import APIClient
import Foundation
import WorkoutEngine

/// Garmin watches (#550). The Connect IQ app has no WatchConnectivity: it reads what to show from the server and sends
/// sets, finished workouts and water back there. The phone publishes the snapshot (the plan is built here) and picks
/// up the watch's events when it is active.
@MainActor @Observable
final class GarminSync {
    static let shared = GarminSync()
    private static let pairedKey = "garmin.paired"

    private(set) var devices: [GarminDevice] = []
    /// At least one Garmin watch paired: only then is anything published or pulled.
    private(set) var paired = UserDefaults.standard.bool(forKey: GarminSync.pairedKey)
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var lastPublished: Data?
    @ObservationIgnored private var publishTask: Task<Void, Never>?
    @ObservationIgnored private var pulling = false

    private init() {}

    func attach(_ model: AppModel) { self.model = model }

    // MARK: Pairing

    func refreshDevices() async {
        guard let model, model.user != nil, let list = try? await model.api.garminDevices() else { return }
        devices = list
        setPaired(!list.isEmpty)
    }

    func claim(_ code: String) async throws {
        guard let model else { return }
        let d = try await model.api.garminClaim(code: code)
        devices.removeAll { $0.id == d.id }
        devices.append(d)
        setPaired(true)
        lastPublished = nil
        publish()
    }

    func remove(_ d: GarminDevice) async throws {
        guard let model else { return }
        try await model.api.garminRemove(d.id)
        devices.removeAll { $0.id == d.id }
        setPaired(!devices.isEmpty)
    }

    private func setPaired(_ on: Bool) {
        paired = on
        UserDefaults.standard.set(on, forKey: Self.pairedKey)
    }

    // MARK: Phone → watch

    /// Publishes the snapshot a moment later (changes come in bursts), only when it changed.
    func publish() {
        guard paired else { return }
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, let model = self.model, model.user != nil else { return }
            let snap = GarminSnapshot(WatchSync.snapshot(model, readiness: nil))
            guard let data = try? JSONEncoder().encode(snap), data != self.lastPublished else { return }
            do {
                try await model.api.garminPublish(snap)
                self.lastPublished = data
            } catch {}
        }
    }

    // MARK: Watch → phone

    /// Sets, finished workouts and water from the watch, applied like the Apple Watch's, then acknowledged.
    func pull() async {
        guard paired, !pulling, let model, model.user != nil else { return }
        pulling = true
        defer { pulling = false }
        guard let events = try? await model.api.garminInbox(GarminEvent.self), !events.isEmpty else { return }
        for e in events { apply(e, model: model) }
        try? await model.api.garminAck(events.map(\.id))
        publish()
    }

    private func apply(_ e: GarminEvent, model: AppModel) {
        switch e.type {
        case "set":
            guard let sid = e.sid, let ex = e.ex, let i = e.i, let reps = e.reps else { return }
            WatchSync.shared.receive(.setLogged(sessionId: sid, exerciseId: ex, setIndex: i, kg: e.kg ?? 0, reps: reps, rir: e.rir))
        case "done":
            guard let uid = e.uid else { return }
            WatchSync.shared.receive(.itemDone(uid: uid))
        case "finished":
            guard let sid = e.sid, let start = e.start, let end = e.end, end > start else { return }
            // Garmin Connect writes the activity to Apple Health itself: the phone must not save another.
            WatchSync.shared.receive(.finished(WFinished(
                id: Self.uuid(e.id), sessionId: sid, setsDone: e.sets ?? [:],
                start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end),
                avgHeartRate: e.hr, maxHeartRate: e.hrMax, kcal: e.kcal, savedToHealth: true, title: e.title)))
        case "water":
            let day = e.day ?? WWater.key(Date())
            guard let date = PlanCalendar.date(day, Progression.calendar()) else { return }
            FuelStore.shared.addGlass(dayKey: day, plan: model.fuelPlan(on: date))
        default:
            return
        }
    }

    /// Same event, same id: a resent finish is recorded once (`WatchSync` keeps the handled ids).
    private static func uuid(_ s: String) -> UUID {
        if let u = UUID(uuidString: s) { return u }
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, b) in s.utf8.enumerated() { bytes[i % 16] = bytes[i % 16] &* 31 &+ b }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// One event from the Garmin watch, as the Connect IQ app sends it (short keys, dates in Unix seconds).
struct GarminEvent: Decodable, Sendable {
    var id: String
    var type: String
    var sid: String?
    var ex: String?
    var i: Int?
    var kg: Double?
    var reps: Int?
    var rir: Int?
    var uid: String?
    var title: String?
    var start: Double?
    var end: Double?
    var sets: [String: Int]?
    var hr: Double?
    var hrMax: Double?
    var kcal: Double?
    var day: String?
}

/// What the Garmin watch shows (#550): this week's sessions, next up in full, water. Short keys: a Connect IQ app
/// has little memory.
struct GarminSnapshot: Encodable, Sendable {
    struct Day: Encodable, Sendable {
        var id: String
        var t: String
        var d: String
        var m: Int
        var done: Bool
        var c: UInt32
    }

    struct Item: Encodable, Sendable {
        var u: String
        var e: String
        var n: String
        var s: Int
        var r: String
        var rest: Int
        var kg: Double?
        var st: Double
        var tr: Int?
        var l: Bool
        var ts: Int?
        var c: UInt32
    }

    struct Next: Encodable, Sendable {
        var id: String
        var t: String
        var d: String
        var m: Int
        var c: UInt32
        var items: [Item]
    }

    struct Water: Encodable, Sendable {
        var d: String
        var g: Int
        var t: Int
    }

    var v = 1
    var at: Int
    var wk: Int
    var pro: Bool
    var days: [Day]
    var next: Next?
    var water: Water?

    init(_ w: WatchSnapshot) {
        at = Int(w.generatedAt.timeIntervalSince1970)
        wk = w.week
        pro = w.pro ?? true
        days = w.sessions.map { Day(id: $0.id, t: $0.title, d: $0.dayLabel, m: $0.estMin, done: $0.done, c: $0.tint) }
        next = w.nextSessionId.flatMap(w.session).map { s in
            Next(id: s.id, t: s.title, d: s.dayLabel, m: s.estMin, c: s.tint, items: s.blocks.flatMap { b in
                b.items.map { it in
                    Item(u: it.uid, e: it.exerciseId, n: it.name, s: it.sets, r: it.reps, rest: it.restSec, kg: it.kg, st: it.kgStep,
                         tr: it.targetReps, l: it.loggable, ts: it.timedSec, c: b.tint)
                }
            })
        }
        water = w.water.map { Water(d: $0.day, g: $0.glasses, t: $0.target) }
    }
}
