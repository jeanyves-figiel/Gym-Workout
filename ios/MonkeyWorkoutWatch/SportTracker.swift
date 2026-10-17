import CoreLocation
import Foundation
import HealthKit
import Observation
import WatchKit

/// Sports the Watch tracks (#418, design B + C). Raw values match the iPhone's `Sport`, so the session page and the
/// plan read the exact sport from the workout's metadata. Diving is left to dive apps (user, 2026-10-17).
enum TrackedSport: String, CaseIterable, Identifiable {
    case snowboard, ski, crossCountrySki, mountainBike, roadBike, run, trailRun, hike, mountaineering
    case hyrox, crossfit, rowing, football, tennis, padel, surf, skate, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .snowboard: "Snowboard"
        case .ski: "Ski"
        case .crossCountrySki: "XC ski"
        case .mountainBike: "MTB"
        case .roadBike: "Road bike"
        case .run: "Run"
        case .trailRun: "Trail run"
        case .hike: "Hike"
        case .mountaineering: "Mountaineering"
        case .hyrox: "Hyrox"
        case .crossfit: "CrossFit"
        case .rowing: "Rowing"
        case .football: "Football"
        case .tennis: "Tennis"
        case .padel: "Padel"
        case .surf: "Surf"
        case .skate: "Skate"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .snowboard: "figure.snowboarding"
        case .ski: "figure.skiing.downhill"
        case .crossCountrySki: "figure.skiing.crosscountry"
        case .mountainBike: "figure.outdoor.cycle"
        case .roadBike: "bicycle"
        case .run, .trailRun: "figure.run"
        case .hike: "figure.hiking"
        case .mountaineering: "mountain.2.fill"
        case .hyrox: "figure.cross.training"
        case .crossfit: "figure.highintensity.intervaltraining"
        case .rowing: "figure.rower"
        case .football: "figure.soccer"
        case .tennis: "figure.tennis"
        case .padel: "figure.racquetball"
        case .surf: "figure.surfing"
        case .skate: "figure.skating"
        case .other: "figure.mixed.cardio"
        }
    }

    var tint: (UInt32, UInt32) {
        switch self {
        case .snowboard, .ski, .crossCountrySki: (0x00A3C4, 0x7DF9FF)
        case .mountainBike, .hike, .trailRun, .mountaineering: (0x00B86B, 0x7DFFB0)
        case .hyrox, .crossfit: (0xFF3D8B, 0xFF9A5E)
        case .roadBike, .run, .rowing: (0x3D59FF, 0x00C7FF)
        default: (0x7D4DFF, 0xE040FB)
        }
    }

    var activityType: HKWorkoutActivityType {
        switch self {
        case .snowboard: .snowboarding
        case .ski: .downhillSkiing
        case .crossCountrySki: .crossCountrySkiing
        case .mountainBike, .roadBike: .cycling
        case .run, .trailRun: .running
        case .hike, .mountaineering: .hiking
        case .hyrox, .crossfit: .crossTraining
        case .rowing: .rowing
        case .football: .soccer
        case .tennis: .tennis
        case .padel: .pickleball
        case .surf: .surfingSports
        case .skate: .skatingSports
        case .other: .other
        }
    }

    /// GPS is worth its battery: outdoor sports that move.
    var usesGPS: Bool { ![TrackedSport.hyrox, .crossfit, .rowing, .tennis, .padel, .football].contains(self) }
    /// Downhill: runs split at lifts, vertical counted down.
    var downhill: Bool { self == .snowboard || self == .ski }
    /// Laps or stations with a big LAP button.
    var laps: Bool { [TrackedSport.hyrox, .crossfit, .run, .rowing].contains(self) }

    var locationActivity: CLActivityType {
        switch self {
        case .mountainBike, .roadBike: .otherNavigation
        case .snowboard, .ski: .otherNavigation
        default: .fitness
        }
    }

    /// Hyrox: 8 × 1 km run, each followed by a station.
    static let hyroxStations = ["SkiErg", "Sled push", "Sled pull", "Burpee broad jumps", "Rowing", "Farmers carry", "Sandbag lunges", "Wall balls"]
}

/// Battery mode picked before the start (design C).
enum TrackPower: String, CaseIterable, Identifiable {
    /// GPS every few metres: best map and speed.
    case full
    /// GPS fix about once a minute, coarse accuracy: long days on one charge.
    case saver

    var id: String { rawValue }
    var label: String { self == .full ? "Full" : "Saver" }
    var detail: String { self == .full ? "GPS every few m · ~6 h" : "GPS once a min · ~14 h" }
}

/// A sport session on the Watch (#418): system workout session in the background (HR, energy, motion from watchOS),
/// GPS route batched into Apple Health, live speed / distance / vertical / runs, laps as workout segments.
/// Battery: no timers except the 1-minute fix in Saver, GPS filtered per sport, nothing sent live to the iPhone.
@MainActor @Observable
final class SportTracker: NSObject {
    static let shared = SportTracker()

    private(set) var sport: TrackedSport?
    private(set) var power: TrackPower = .full
    private(set) var started: Date?
    private(set) var paused = false
    var heartRate: Double?
    private(set) var maxHeartRate: Double?
    private(set) var kcal: Double = 0
    /// km/h, smoothed over the last fixes.
    private(set) var speed: Double = 0
    private(set) var topSpeed: Double = 0
    private(set) var meters: Double = 0
    private(set) var up: Double = 0
    private(set) var down: Double = 0
    private(set) var altitude: Double?
    private(set) var highest: Double?
    private(set) var runs = 0
    /// Lap / station index (0-based) and when it started.
    private(set) var lap = 0
    private(set) var lapStart: Date?
    private(set) var lastLapMinutes: Double?
    /// Battery % at start and at finish (summary).
    private(set) var batteryStart: Float?
    private(set) var summary: Summary?

    struct Summary {
        let sport: TrackedSport
        let minutes: Int
        let km: Double
        let vertical: Double
        let runs: Int
        let topKmh: Double
        let batteryUsed: Int?
    }

    var running: Bool { sport != nil }

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let location = CLLocationManager()
    private var pending: [CLLocation] = []
    private var last: CLLocation?
    private var altRef: Double?
    private var runTop: Double?
    private var runLow: Double?
    private var saverTimer: Timer?

    func start(_ sport: TrackedSport, power: TrackPower) async {
        guard HKHealthStore.isHealthDataAvailable(), !running, !WorkoutManager.shared.running else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), HKQuantityType(.activeEnergyBurned),
                                        HKQuantityType(.heartRate)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType()]
        try? await store.requestAuthorization(toShare: share, read: read)
        let config = HKWorkoutConfiguration()
        config.activityType = sport.activityType
        config.locationType = sport.usesGPS ? .outdoor : .indoor
        guard let s = try? HKWorkoutSession(healthStore: store, configuration: config) else { return }
        let b = s.associatedWorkoutBuilder()
        b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        s.delegate = self
        b.delegate = self
        session = s
        builder = b
        reset()
        self.sport = sport
        self.power = power
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        batteryStart = WKInterfaceDevice.current().batteryLevel >= 0 ? WKInterfaceDevice.current().batteryLevel : nil
        let now = Date()
        started = now
        lapStart = now
        s.startActivity(with: now)
        do {
            try await b.beginCollection(at: now)
            try? await b.addMetadata(["MonkeyWorkoutSport": sport.rawValue, "MonkeyWorkoutPower": power.rawValue])
        } catch {
            discard()
            return
        }
        if sport.usesGPS { startLocation() }
    }

    private func reset() {
        summary = nil
        paused = false
        heartRate = nil
        maxHeartRate = nil
        kcal = 0
        speed = 0
        topSpeed = 0
        meters = 0
        up = 0
        down = 0
        altitude = nil
        highest = nil
        runs = 0
        lap = 0
        lastLapMinutes = nil
        pending = []
        last = nil
        altRef = nil
        runTop = nil
        runLow = nil
    }

    private func startLocation() {
        guard let sport else { return }
        routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        location.delegate = self
        location.activityType = sport.locationActivity
        location.requestWhenInUseAuthorization()
        if power == .full {
            location.desiredAccuracy = kCLLocationAccuracyBest
            // Fast sports need fewer points per metre.
            location.distanceFilter = sport.downhill || sport == .roadBike ? 15 : 8
            location.startUpdatingLocation()
        } else {
            location.desiredAccuracy = kCLLocationAccuracyHundredMeters
            location.requestLocation()
            saverTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.location.requestLocation() }
            }
        }
    }

    private func stopLocation() {
        saverTimer?.invalidate()
        saverTimer = nil
        location.stopUpdatingLocation()
    }

    func pause() {
        session?.pause()
        paused = true
        stopLocation()
    }

    func resume() {
        session?.resume()
        paused = false
        if sport?.usesGPS == true { startLocation() }
    }

    /// LAP: closes the current lap / station as a workout segment (the iPhone shows them as splits).
    func markLap() {
        guard let builder, let s = lapStart else { return }
        let now = Date()
        let event = HKWorkoutEvent(type: .segment, dateInterval: DateInterval(start: s, end: now), metadata: nil)
        Task { try? await builder.addWorkoutEvents([event]) }
        lastLapMinutes = now.timeIntervalSince(s) / 60
        lap += 1
        lapStart = now
        WKInterfaceDevice.current().play(.click)
    }

    /// Current Hyrox step: "Run 3" or the station after it.
    var hyroxStep: String {
        let i = lap
        guard i < 16 else { return "Finish" }
        return i % 2 == 0 ? "Run \(i / 2 + 1)" : TrackedSport.hyroxStations[i / 2]
    }

    func finish() async {
        guard let session, let builder, let sport else { discard(); return }
        stopLocation()
        flushRoute()
        session.end()
        let end = Date()
        let used = batteryStart.map { start -> Int in
            let now = WKInterfaceDevice.current().batteryLevel
            return now >= 0 ? max(0, Int(((start - now) * 100).rounded())) : 0
        }
        summary = Summary(sport: sport, minutes: Int(end.timeIntervalSince(started ?? end) / 60), km: meters / 1000,
                          vertical: sport.downhill ? down : up, runs: runs, topKmh: topSpeed, batteryUsed: used)
        do {
            var meta: [String: Any] = [HKMetadataKeyIndoorWorkout: !sport.usesGPS]
            if up > 0 { meta[HKMetadataKeyElevationAscended] = HKQuantity(unit: .meter(), doubleValue: up) }
            try? await builder.addMetadata(meta)
            try await builder.endCollection(at: end)
            if let workout = try await builder.finishWorkout(), let routeBuilder {
                _ = try? await routeBuilder.finishRoute(with: workout, metadata: nil)
            }
        } catch {}
        cleanup()
    }

    func discard() {
        stopLocation()
        session?.end()
        builder?.discardWorkout()
        routeBuilder?.discard()
        cleanup()
    }

    func closeSummary() { summary = nil }

    private func cleanup() {
        session = nil
        builder = nil
        routeBuilder = nil
        sport = nil
        paused = false
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = false
    }

    /// Route points go to Health in batches of 30, never one by one.
    private func flushRoute() {
        guard !pending.isEmpty, let routeBuilder else { return }
        let batch = pending
        pending = []
        Task { try? await routeBuilder.insertRouteData(batch) }
    }

    fileprivate func add(_ locations: [CLLocation]) {
        guard !paused, let sport else { return }
        for l in locations where l.horizontalAccuracy >= 0 && l.horizontalAccuracy <= (power == .full ? 50 : 200) {
            if let prev = last {
                let d = l.distance(from: prev)
                let dt = l.timestamp.timeIntervalSince(prev.timestamp)
                guard dt > 0 else { continue }
                meters += d
                let kmh = (l.speed >= 0 ? l.speed : d / dt) * 3.6
                // Smoothed live speed; top speed only from a believable fix.
                speed = speed * 0.5 + kmh * 0.5
                if l.horizontalAccuracy <= 20, kmh < 150 { topSpeed = max(topSpeed, speed) }
            }
            last = l
            pending.append(l)
            if l.verticalAccuracy >= 0 { climb(l.altitude, downhill: sport.downhill) }
        }
        if pending.count >= 30 { flushRoute() }
    }

    /// Vertical up/down ignoring < 3 m wobble; a downhill run counts once it dropped 40 m and the lift climbs 25 m.
    private func climb(_ alt: Double, downhill: Bool) {
        altitude = alt
        highest = max(highest ?? alt, alt)
        guard let ref = altRef else { altRef = alt; runTop = alt; runLow = alt; return }
        let d = alt - ref
        if abs(d) >= 3 {
            if d > 0 { up += d } else { down -= d }
            altRef = alt
        }
        guard downhill, let top = runTop, let low = runLow else { return }
        if alt < low { runLow = alt }
        if alt - (runLow ?? alt) >= 25 {
            if top - (runLow ?? top) >= 40 { runs += 1 }
            runTop = alt
            runLow = alt
        } else if alt > top && runLow == top {
            runTop = alt
            runLow = alt
        }
    }

    fileprivate func update(_ stats: HKStatistics) {
        switch stats.quantityType {
        case HKQuantityType(.heartRate):
            guard let v = stats.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) else { return }
            heartRate = v
            maxHeartRate = max(maxHeartRate ?? 0, v)
        case HKQuantityType(.activeEnergyBurned):
            kcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? kcal
        default:
            break
        }
    }
}

extension SportTracker: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.add(locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension SportTracker: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension SportTracker: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let stats = collectedTypes.compactMap { $0 as? HKQuantityType }.compactMap { workoutBuilder.statistics(for: $0) }
        Task { @MainActor in stats.forEach(self.update) }
    }
}
