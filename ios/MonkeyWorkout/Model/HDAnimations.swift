import CryptoKit
import Foundation
import Network
import Observation
import UIKit
import WorkoutEngine

/// HD exercise animations (#932, design A + B): the app bundles 3 light frames and a light 60 fps clip (#944) per
/// exercise at half size; every frame and the clip at full size come as a pack downloaded after sign-up (welcome card) or from Settings, on Wi-Fi by default. One file
/// per exercise (`<id>.mwf`, ios/Tools/illustrations/pack.py) listed with its sha256 in `manifest.json`: changed files
/// come again when the manifest changes, so new art needs no app build. An exercise without its HD file, or drawn with
/// other frames than this build expects, keeps the light frames.
@MainActor @Observable
final class HDAnimations {
    static let shared = HDAnimations()

    /// `checking`: reading the manifest, nothing to fetch known yet (#995: Train shows only `downloading`).
    enum Status: Equatable { case off, waitingForWiFi, checking, downloading, ready, failed }

    /// Assets of the `hd-animations` release on the public repo (published by the "HD animations pack" workflow).
    /// The remote value `hdAnimationsURL` moves it without a build.
    static let defaultBase = URL(string: "https://github.com/jeanyves-figiel/Gym-Workout/releases/download/hd-animations/")!
    /// Shown before the manifest is known.
    static let approxBytes: Int64 = 235_000_000

    private(set) var status: Status = .off
    /// Exercises whose HD frames are on this device and match this build.
    private(set) var installed: Set<String> = []
    private(set) var doneBytes: Int64 = 0
    private(set) var totalBytes: Int64 = approxBytes
    /// "HD moves ready" toast, once per finished download.
    var justFinished = false
    /// Exercises fetched by the download running now (#995): "Updating 24 moves" on Train.
    private(set) var fetching = 0

    /// #995: the member sees whether the latest art is on the device. Last manifest read, last time files came,
    /// how many came, and the pack's own version and build time (manifest `version`, `published`).
    private(set) var lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date {
        didSet { UserDefaults.standard.set(lastCheck, forKey: Self.lastCheckKey) }
    }
    private(set) var lastUpdate = UserDefaults.standard.object(forKey: lastUpdateKey) as? Date {
        didSet { UserDefaults.standard.set(lastUpdate, forKey: Self.lastUpdateKey) }
    }
    private(set) var lastUpdateCount = UserDefaults.standard.integer(forKey: lastUpdateCountKey) {
        didSet { UserDefaults.standard.set(lastUpdateCount, forKey: Self.lastUpdateCountKey) }
    }
    private(set) var packVersion = UserDefaults.standard.string(forKey: packVersionKey) {
        didSet { UserDefaults.standard.set(packVersion, forKey: Self.packVersionKey) }
    }
    private(set) var packPublished = UserDefaults.standard.object(forKey: packPublishedKey) as? Date {
        didSet { UserDefaults.standard.set(packPublished, forKey: Self.packPublishedKey) }
    }
    /// Exercises this build animates: `installed.count` of it are HD.
    var catalogCount: Int { ExerciseIllustrations.ids.count }

    private static let enabledKey = "hdAnimations.enabled"
    private static let wifiOnlyKey = "hdAnimations.wifiOnly"
    private static let offeredKey = "hdAnimations.offered"
    private static let lastCheckKey = "hdAnimations.lastCheck"
    private static let lastUpdateKey = "hdAnimations.lastUpdate"
    private static let lastUpdateCountKey = "hdAnimations.lastUpdateCount"
    private static let packVersionKey = "hdAnimations.packVersion"
    private static let packPublishedKey = "hdAnimations.packPublished"

    /// The member asked for HD (welcome card or Settings).
    private(set) var enabled = UserDefaults.standard.bool(forKey: enabledKey)
    /// Download on Wi-Fi only (default), never on mobile data or Low Data Mode.
    var wifiOnly = UserDefaults.standard.object(forKey: wifiOnlyKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(wifiOnly, forKey: Self.wifiOnlyKey)
            if enabled { resume() }
        }
    }
    /// The welcome card was shown on this device (answered either way).
    var offered = UserDefaults.standard.bool(forKey: offeredKey) {
        didSet { UserDefaults.standard.set(offered, forKey: Self.offeredKey) }
    }

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var expensive = false
    /// Exercise id → sha256 of its HD file on this device.
    @ObservationIgnored private var record: [String: Entry] = [:]

    /// `file`: the pack file's name in the bucket (`<id>-<sha>.mwf`, never changes once published).
    struct Entry: Codable, Sendable { let file: String?; let frames: Int; let bytes: Int64; let sha256: String }
    private struct Manifest: Decodable { let format: Int; let version: String?; let published: String?; let exercises: [String: Entry] }

    private static var recordURL: URL { HDFrames.dir.appendingPathComponent("installed.json") }

    private init() {
        if let data = try? Data(contentsOf: Self.recordURL), let r = try? JSONDecoder().decode([String: Entry].self, from: data) {
            record = r
        }
        refreshInstalled()
        if enabled { status = installed.isEmpty ? .off : .ready }
    }

    var base: URL {
        if case .string(let s)? = Remote.shared.value("hdAnimationsURL"), let u = URL(string: s) {
            return s.hasSuffix("/") ? u : u.appendingPathComponent("")
        }
        return Self.defaultBase
    }

    /// HD frames of this exercise are on the device.
    func has(_ exerciseId: String) -> Bool { installed.contains(exerciseId) }

    /// The exercise's HD movement clip (#944) when it is on the device.
    func clipURL(_ exerciseId: String) -> URL? {
        let url = HDFrames.clip(exerciseId)
        return has(exerciseId) && FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var progress: Double { totalBytes > 0 ? min(1, Double(doneBytes) / Double(totalBytes)) : 0 }

    /// Welcome card Download, Settings switch on: downloads now (or on the next Wi-Fi).
    func enable() {
        offered = true
        enabled = true
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        resume()
    }

    /// Settings switch off: the HD files leave the device, the light frames show again.
    func remove() {
        task?.cancel()
        task = nil
        enabled = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        try? FileManager.default.removeItem(at: HDFrames.dir)
        record = [:]
        installed = []
        doneBytes = 0
        fetching = 0
        status = .off
        IllustrationImages.forgetHD()
    }

    /// Settings → Check now (#995): reads the manifest again and fetches changed art.
    func checkNow() { resume() }

    /// App open / back on Wi-Fi: picks up an unfinished download and changed art.
    func resume() {
        guard enabled, task == nil else { return }
        startMonitor()
        if wifiOnly && expensive {
            status = .waitingForWiFi
            return
        }
        task = Task { [weak self] in
            await self?.download()
            self?.task = nil
        }
    }

    private func startMonitor() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        expensive = m.currentPath.isExpensive || m.currentPath.isConstrained
        m.pathUpdateHandler = { [weak self] path in
            let costly = path.isExpensive || path.isConstrained
            Task { @MainActor in
                guard let self else { return }
                self.expensive = costly
                if !costly, self.status == .waitingForWiFi { self.resume() }
            }
        }
        m.start(queue: DispatchQueue(label: "HDAnimations.path", qos: .utility))
        monitor = m
    }

    private func download() async {
        let config = URLSessionConfiguration.default
        config.allowsExpensiveNetworkAccess = !wifiOnly
        config.allowsConstrainedNetworkAccess = !wifiOnly
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let hadAll = !installed.isEmpty && installed.count == ExerciseIllustrations.ids.count
        status = .checking
        do {
            let (data, _) = try await session.data(from: base.appendingPathComponent("manifest.json"))
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            lastCheck = .now
            // Only exercises this build draws with the same frames (motion path and tempo match them).
            let usable = manifest.exercises.filter { ExerciseIllustrations.frameCount(of: $0.key) == $0.value.frames }
            totalBytes = usable.values.reduce(0) { $0 + $1.bytes }
            let wanted = usable.filter { record[$0.key]?.sha256 != $0.value.sha256 }
            doneBytes = totalBytes - wanted.values.reduce(0) { $0 + $1.bytes }
            try FileManager.default.createDirectory(at: HDFrames.dir, withIntermediateDirectories: true)
            var backup = URLResourceValues()
            backup.isExcludedFromBackup = true
            var dir = HDFrames.dir
            try? dir.setResourceValues(backup)
            let root = base
            let jobs = Array(wanted)
            fetching = jobs.count
            if !jobs.isEmpty { status = .downloading }
            defer { fetching = 0 }
            try await withThrowingTaskGroup(of: (String, Entry).self) { group in
                var next = 0
                func add() {
                    guard next < jobs.count else { return }
                    let (id, entry) = jobs[next]
                    next += 1
                    group.addTask { try await Self.fetch(id, entry, base: root, session: session) }
                }
                for _ in 0..<4 { add() }
                while let done = try await group.next() {
                    record[done.0] = done.1
                    installed.insert(done.0)
                    doneBytes += done.1.bytes
                    saveRecord()
                    add()
                }
            }
            status = .ready
            packVersion = manifest.version
            packPublished = manifest.published.flatMap { try? Date($0, strategy: .iso8601) }
            if !wanted.isEmpty {
                lastUpdate = .now
                lastUpdateCount = wanted.count
                if !hadAll { justFinished = true }
            }
        } catch {
            if Task.isCancelled { return }
            status = installed.isEmpty ? .failed : .ready
        }
    }

    /// One exercise's HD file, kept only when it matches the manifest.
    nonisolated private static func fetch(_ id: String, _ entry: Entry, base: URL, session: URLSession) async throws -> (String, Entry) {
        let (data, _) = try await session.data(from: base.appendingPathComponent(entry.file ?? "\(id).mwf"))
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard sha == entry.sha256, HDFrames.frameCount(data) == entry.frames else { throw URLError(.cannotDecodeContentData) }
        try data.write(to: HDFrames.file(id), options: .atomic)
        // The movement clip goes to its own file: video plays from a file.
        if let clip = HDFrames.clip(in: data) {
            try clip.write(to: HDFrames.clip(id), options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: HDFrames.clip(id))
        }
        return (id, entry)
    }

    private func refreshInstalled() {
        installed = Set(record.filter { id, e in
            ExerciseIllustrations.frameCount(of: id) == e.frames && FileManager.default.fileExists(atPath: HDFrames.file(id).path)
        }.keys)
    }

    private func saveRecord() {
        try? JSONEncoder().encode(record).write(to: Self.recordURL, options: .atomic)
    }
}

/// Reads HD frames from the pack files (any thread): `MWF1`, frame count (UInt16 LE), each frame's length (UInt32 LE),
/// then the PNGs; then (#944) `MCLP`, the movement clip's length (UInt32 LE) and the clip.
enum HDFrames {
    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("hd-animations", isDirectory: true)

    static func file(_ exerciseId: String) -> URL { dir.appendingPathComponent("\(exerciseId).mwf") }

    /// The exercise's HD movement clip, taken out of its pack file.
    static func clip(_ exerciseId: String) -> URL { dir.appendingPathComponent("\(exerciseId).mp4") }

    /// The movement clip after a pack file's frames, nil without one.
    static func clip(in data: Data) -> Data? {
        guard let n = frameCount(data) else { return nil }
        let start = (0..<n).reduce(6 + 4 * n) { $0 + int(data, 6 + 4 * $1, 4) }
        guard data.count >= start + 8, data.subdata(in: data.startIndex + start..<data.startIndex + start + 4) == Data("MCLP".utf8) else {
            return nil
        }
        let length = int(data, start + 4, 4)
        guard data.count >= start + 8 + length else { return nil }
        return data.subdata(in: data.startIndex + start + 8..<data.startIndex + start + 8 + length)
    }

    private static func int(_ data: Data, _ at: Int, _ size: Int) -> Int {
        (0..<size).reduce(0) { $0 | Int(data[data.startIndex + at + $1]) << (8 * $1) }
    }

    /// Frames in a pack file, nil when it isn't one.
    static func frameCount(_ data: Data) -> Int? {
        guard data.count >= 6, data.prefix(4) == Data("MWF1".utf8) else { return nil }
        let n = int(data, 4, 2)
        return data.count >= 6 + 4 * n ? n : nil
    }

    /// Frame `frame` of the exercise's HD file.
    static func image(_ exerciseId: String, frame: Int) -> UIImage? {
        guard let data = try? Data(contentsOf: file(exerciseId), options: .alwaysMapped),
              let n = frameCount(data), frame >= 0, frame < n else { return nil }
        var start = 6 + 4 * n
        for i in 0..<frame { start += int(data, 6 + 4 * i, 4) }
        let length = int(data, 6 + 4 * frame, 4)
        guard start + length <= data.count else { return nil }
        return UIImage(data: data.subdata(in: data.startIndex + start..<data.startIndex + start + length))
    }
}
