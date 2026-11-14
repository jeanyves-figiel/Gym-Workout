import APIClient
import CoreLocation
import Foundation
import Photos
import UIKit
import UserNotifications
import Vision
import WorkoutEngine

/// Invisible Monkey (#1087): water, meals and gym arrivals found without typing. The Watch sends sips and meal windows,
/// the photo inbox looks at new photos on the device, the home gym's region notices arrival. The ladder in
/// `AutoTrack` logs sure finds at once (Undo on the card) and asks one tap for the rest.
///
/// Stays on the device (Application Support), never synced, never in Social or Coach.
@MainActor @Observable
final class AutoTrackStore {
    static let shared = AutoTrackStore()

    struct Saved: Codable {
        var prefs = AutoTrackPrefs()
        var events: [AutoEvent] = []
        /// Photos newer than this are still to look at.
        var photosSince: Date?
        /// Glasses already added to Fuel from auto water, per Fuel day key (so the rest of a glass waits).
        var glasses: [String: Int] = [:]
        /// The "Track without typing" invite was put away.
        var inviteHidden = false
    }

    private(set) var saved = Saved()
    @ObservationIgnored weak var model: AppModel?
    private var scanningPhotos = false

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("autotrack.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.url), let s = try? JSONDecoder().decode(Saved.self, from: data) { saved = s }
    }

    var prefs: AutoTrackPrefs { saved.prefs }

    private var cal: Calendar { model?.planCalendar ?? Progression.calendar() }

    /// Today's finds for the card.
    var today: [AutoEvent] { AutoTrack.today(saved.events, calendar: cal) }

    // MARK: Settings

    func setPrefs(_ p: AutoTrackPrefs) {
        let was = saved.prefs
        var s = saved
        s.prefs = p
        if p.photos, !was.photos { s.photosSince = Date() }
        save(s)
        if p.watchOn != was.watchOn { WatchSync.shared.schedulePush() }
        if p.gym != was.gym { Task { await GymArrival.shared.follow() } }
    }

    // MARK: Finds

    /// Sips and meal windows from the Watch. Movement during a workout is lifting, not eating.
    func ingest(_ batch: WIntakeBatch) {
        let p = saved.prefs
        var new: [AutoEvent] = []
        if p.sips {
            new += AutoTrack.drinks(batch.sips.map { AutoTrack.Sip(date: $0.date, confidence: $0.confidence) }, mlPerSip: p.mlPerSip)
        }
        if p.bites {
            new += batch.meals.map { AutoTrack.meal(start: $0.start, end: $0.end, bites: $0.bites, confidence: $0.confidence) }
        }
        let workouts = (model?.state.history ?? []).filter { $0.startedAt > batch.from.addingTimeInterval(-6 * 3600) }
            .map { DateInterval(start: $0.startedAt, duration: TimeInterval(max(60, $0.durationSec))) }
        add(new.filter { AutoTrack.outside($0, workouts: workouts) })
    }

    func add(_ new: [AutoEvent]) {
        guard !new.isEmpty else { return }
        var s = saved
        s.events = AutoTrack.merge(s.events, new: new, calendar: cal)
        save(s)
        syncWater()
    }

    /// Fuel counts glasses: add the whole glasses the auto water is worth, per day, once.
    private func syncWater() {
        let fuel = FuelStore.shared
        let glassMl = fuel.prefs.glassMl
        let days = Set(saved.events.filter { $0.kind == .water }.map { cal.startOfDay(for: $0.start) })
        var s = saved
        for day in days {
            let key = fuel.key(day)
            let want = AutoTrack.glasses(ml: AutoTrack.loggedMl(s.events, on: day, calendar: cal), glassMl: glassMl)
            let have = s.glasses[key] ?? 0
            if want > have {
                fuel.addGlasses(want - have, on: day)
            } else if want < have, let plan = fuel.planFor?(day) {
                fuel.update(day, plan: plan) { $0.glasses = max(0, $0.glasses - (have - want)) }
            }
            s.glasses[key] = want
        }
        save(s)
    }

    func hideInvite() {
        var s = saved
        s.inviteHidden = true
        save(s)
    }

    func keep(_ id: String) { set(id, .kept) }

    /// Bin a card, or undo something logged by itself.
    func dismiss(_ id: String) { set(id, .dismissed) }

    private func set(_ id: String, _ state: AutoState) {
        var s = saved
        guard let i = s.events.firstIndex(where: { $0.id == id }) else { return }
        s.events[i].state = state
        save(s)
        if s.events[i].kind == .water { syncWater() }
    }

    // MARK: Photo inbox

    /// Looks at photos taken since last time (on the device), at most once a minute.
    func scanPhotos() async {
        guard saved.prefs.photos, !scanningPhotos, PhotoInbox.allowed else { return }
        scanningPhotos = true
        defer { scanningPhotos = false }
        let since = saved.photosSince ?? Date().addingTimeInterval(-6 * 3600)
        let now = Date()
        let found = await PhotoInbox.foods(since: since)
        var s = saved
        s.photosSince = now
        save(s)
        add(found.map { AutoTrack.photo(id: $0.id, date: $0.date, title: $0.title, confidence: $0.confidence) })
    }

    // MARK: Gym arrival

    func arrivedAtGym(now: Date = Date()) async {
        guard saved.prefs.gym else { return }
        let e = AutoTrack.gym(at: now, calendar: cal)
        guard !saved.events.contains(where: { $0.id == e.id }) else { return }
        add([e])
        let content = UNMutableNotificationContent()
        let gym = model?.homePlace?.name ?? "your gym"
        content.title = "At \(gym) 🦍"
        if let session = model?.todaySession {
            content.body = "\(session.title) is ready. Tap to start."
            content.userInfo = ["kind": "upcoming", "sessionId": session.id]
        } else {
            content.body = "No workout planned today. Tap for a quick one."
            content.userInfo = ["kind": "gym_arrival"]
        }
        content.sound = .default
        content.threadIdentifier = "gym"
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: e.id, content: content, trigger: nil))
    }

    #if DEBUG
    /// Demo screens: a morning of sips, a photo breakfast to check, a meal to name, the gym. Not saved.
    func demo(now: Date = Date()) {
        let day = Calendar.current.startOfDay(for: now)
        let h = { (x: Double) in day.addingTimeInterval(x * 3600) }
        var p = AutoTrackPrefs()
        p.sips = true
        p.bites = true
        p.photos = true
        p.gym = true
        saved = Saved(prefs: p, events: [
            AutoEvent(id: "gym|d", kind: .gym, source: .place, start: h(18.1), end: h(18.1), confidence: 0.9, state: .logged),
            AutoEvent(id: "meal|d", kind: .meal, source: .bites, start: h(12.5), end: h(12.8), confidence: 0.72, state: .pending, count: 18),
            AutoEvent(id: "photo|d", kind: .meal, source: .photo, start: h(7.7), end: h(7.7), confidence: 0.81, state: .pending, title: "Croissant"),
            AutoEvent(id: "water|d", kind: .water, source: .sips, start: h(8), end: h(11), confidence: 0.94, state: .logged, ml: 1350, count: 45),
        ])
    }
    #endif

    func signOut() {
        saved = Saved()
        try? FileManager.default.removeItem(at: Self.url)
        Task { await GymArrival.shared.follow() }
    }

    private func save(_ s: Saved) {
        saved = s
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: Self.url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

// MARK: - Photo inbox

/// New photos in the library checked for food with Apple's on-device classifier (the same one Scan live uses, #1012).
/// Nothing is copied or uploaded; a card keeps the photo's local id and loads it only when tapped.
enum PhotoInbox {
    struct Found {
        var id: String
        var date: Date
        var title: String
        var confidence: Double
    }

    static var allowed: Bool {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return s == .authorized || s == .limited
    }

    static func ask() async -> Bool {
        let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return s == .authorized || s == .limited
    }

    /// Labels that mean "a meal" without naming a food.
    static let mealWords: Set<String> = ["food", "meal", "dish", "dessert", "baked goods", "breakfast", "lunch", "dinner", "salad", "soup", "sandwich"]

    static func foods(since: Date, limit: Int = 25) async -> [Found] {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "creationDate > %@ AND mediaType == %d", since as NSDate, PHAssetMediaType.image.rawValue)
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = limit
        let result = PHAsset.fetchAssets(with: opts)
        var assets: [PHAsset] = []
        result.enumerateObjects { a, _, _ in
            if !a.mediaSubtypes.contains(.photoScreenshot) { assets.append(a) }
        }
        var out: [Found] = []
        for a in assets {
            guard let image = await image(a, side: 384)?.cgImage else { continue }
            let guess = await Task.detached(priority: .utility) { classify(image) }.value
            if let g = guess { out.append(Found(id: a.localIdentifier, date: a.creationDate ?? Date(), title: g.0, confidence: g.1)) }
        }
        return out
    }

    /// A food name (or "Meal") and how sure, nil when the photo isn't food.
    static func classify(_ image: CGImage) -> (String, Double)? {
        let req = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: image).perform([req])
        let results = (req.results ?? []).filter { $0.confidence >= 0.3 }
        for r in results {
            if let f = SeenFood.food(label: r.identifier) { return (f.name, Double(r.confidence)) }
        }
        let words = Set(results.filter { $0.confidence >= 0.5 }.map { $0.identifier.replacingOccurrences(of: "_", with: " ").lowercased() })
        if let w = words.intersection(mealWords).first, let c = results.first(where: { $0.identifier.replacingOccurrences(of: "_", with: " ").lowercased() == w })?.confidence {
            return ("Meal", Double(c))
        }
        return nil
    }

    /// The photo at about `side` points (local only, never from iCloud).
    static func image(_ asset: PHAsset, side: CGFloat, network: Bool = false) async -> UIImage? {
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = network
        opts.resizeMode = .fast
        return await withCheckedContinuation { cont in
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFit,
                                                  options: opts) { img, _ in cont.resume(returning: img) }
        }
    }

    /// A card's photo, bigger, for the plate scan.
    static func image(id: String) async -> UIImage? {
        guard let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        return await image(a, side: 1600, network: true)
    }
}

// MARK: - Gym arrival

/// The home gym's region (150 m) with Core Location's monitor: arriving posts one "start today's workout" a day.
/// Needs Always location; asked only when the member turns gym arrival on.
@MainActor
final class GymArrival {
    static let shared = GymArrival()
    private var monitor: CLMonitor?
    private var listening: Task<Void, Never>?
    private let manager = CLLocationManager()
    private static let name = "monkey-gym"
    private static let condition = "home-gym"

    func askAlways() { manager.requestAlwaysAuthorization() }

    /// Starts or stops following the home gym to match the setting. Called at launch too: a relaunch for an
    /// arrival delivers its event only once the monitor is opened again.
    func follow() async {
        let store = AutoTrackStore.shared
        let monitor = await current()
        guard store.prefs.gym else {
            await monitor.remove(Self.condition)
            return
        }
        // Home gym not loaded yet (early at launch): keep what the monitor already follows.
        guard let g = store.model?.homePlace, let lat = g.latitude, let lng = g.longitude else { return }
        let region = CLMonitor.CircularGeographicCondition(center: CLLocationCoordinate2D(latitude: lat, longitude: lng), radius: 150)
        await monitor.add(region, identifier: Self.condition, assuming: .unsatisfied)
    }

    private func current() async -> CLMonitor {
        if let monitor { return monitor }
        let m = await CLMonitor(Self.name)
        monitor = m
        listening = Task {
            do {
                for try await event in await m.events where event.state == .satisfied {
                    await AutoTrackStore.shared.arrivedAtGym(now: event.date)
                }
            } catch {}
        }
        return m
    }
}
