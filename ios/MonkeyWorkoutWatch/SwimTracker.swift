import CoreLocation
import CoreMotion
import Foundation
import HealthKit
import LiftSensor
import Observation
import WatchKit

/// Swimming on the Watch (#615 T13, #624 X7): one flow for pool laps, open water and snorkel depth.
/// Water Lock goes on at the start (turn the Digital Crown to unlock). Pool: laps, stroke, pace per 100 m and SWOLF
/// from Apple Health's swim tracking; with a swim workout the send-off clock buzzes each start (A).
/// Open water: distance, route and water temperature, and the iPhone on the shore alerts if the swim runs long (B).
/// Depth (C): live depth, max depth and time under water on Apple Watch Ultra, once the app has Apple's shallow-depth
/// entitlement (`MWDepth` in the Watch Info.plist).
@MainActor @Observable
final class SwimTracker: NSObject {
    static let shared = SwimTracker()

    enum Mode: Equatable {
        case pool(Int)
        case openWater
        case snorkel

        var isPool: Bool {
            if case .pool = self { true } else { false }
        }

        var title: String {
            switch self {
            case let .pool(m): "POOL \(m) M"
            case .openWater: "OPEN WATER"
            case .snorkel: "SNORKEL"
            }
        }
    }

    private(set) var mode: Mode?
    private(set) var workout: SwimWorkout?
    private(set) var started: Date?
    private(set) var laps = 0
    private(set) var meters: Double = 0
    private(set) var strokes: Double = 0
    private(set) var stroke: String?
    private(set) var heartRate: Double?
    private(set) var kcal: Double = 0
    /// °C, from the depth sensor or Apple Health.
    private(set) var waterTemp: Double?
    private(set) var depth: Double?
    private(set) var maxDepth: Double = 0
    private(set) var underSeconds: TimeInterval = 0
    private(set) var summary: Summary?

    struct Summary {
        let mode: Mode
        let minutes: Int
        let meters: Int
        let laps: Int
        let pace: Int?
        let swolf: Int?
        let maxDepth: Double
        let waterTemp: Double?
        let workout: String?
    }

    var running: Bool { mode != nil }

    /// Depth needs Apple Watch Ultra and the shallow-depth entitlement (flag set when it is added).
    static var depthAvailable: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "MWDepth") as? Bool ?? false) && CMWaterSubmersionManager.waterSubmersionAvailable
    }

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let location = CLLocationManager()
    private var pending: [CLLocation] = []
    private var submersion: CMWaterSubmersionManager?
    private var underSince: Date?
    private var ticker: Task<Void, Never>?
    private var buzzedTo: TimeInterval = 0
    private var buddyMinutes = 60

    func elapsed(_ now: Date = Date()) -> TimeInterval { now.timeIntervalSince(started ?? now) }

    /// Seconds per 100 m so far.
    var pace: Int? { meters >= 25 ? Int(elapsed() / meters * 100) : nil }

    /// SWOLF per length: seconds plus strokes.
    var swolf: Int? {
        guard laps > 0 else { return nil }
        return Int((elapsed() / Double(laps) + strokes / Double(laps)).rounded())
    }

    func start(_ mode: Mode, workout: SwimWorkout? = nil, buddyMinutes: Int = 60) async {
        guard HKHealthStore.isHealthDataAvailable(), !running, !WorkoutManager.shared.running, !SportTracker.shared.running,
              !HyroxTracker.shared.running, !WodTracker.shared.running else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), HKQuantityType(.activeEnergyBurned),
                                        HKQuantityType(.heartRate), HKQuantityType(.distanceSwimming), HKQuantityType(.swimmingStrokeCount)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceSwimming),
                                       HKQuantityType(.swimmingStrokeCount), HKQuantityType(.waterTemperature)]
        try? await store.requestAuthorization(toShare: share, read: read)
        let config = HKWorkoutConfiguration()
        config.activityType = .swimming
        switch mode {
        case let .pool(m):
            config.swimmingLocationType = .pool
            config.lapLength = HKQuantity(unit: .meter(), doubleValue: Double(m))
            config.locationType = .indoor
        case .openWater, .snorkel:
            config.swimmingLocationType = .openWater
            config.locationType = .outdoor
        }
        guard let s = try? HKWorkoutSession(healthStore: store, configuration: config) else { return }
        let b = s.associatedWorkoutBuilder()
        let source = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        source.enableCollection(for: HKQuantityType(.waterTemperature), predicate: nil)
        b.dataSource = source
        b.delegate = self
        session = s
        builder = b
        reset()
        self.mode = mode
        self.workout = workout
        self.buddyMinutes = buddyMinutes
        let now = Date()
        started = now
        s.startActivity(with: now)
        do {
            try await b.beginCollection(at: now)
            var meta: [String: Any] = ["MonkeyWorkoutSport": "swim"]
            if let workout { meta["MonkeyWorkoutTitle"] = workout.name }
            try? await b.addMetadata(meta)
        } catch {
            discard()
            return
        }
        if mode == .openWater || mode == .snorkel {
            startLocation()
            WatchStore.current?.sendBuddy(WSwimBuddy(start: now, minutes: buddyMinutes, ended: false))
        }
        if Self.depthAvailable { startDepth() }
        WKInterfaceDevice.current().play(.start)
        // Water Lock: the screen ignores water; turning the Digital Crown unlocks it.
        WKInterfaceDevice.current().enableWaterLock()
        if workout != nil {
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    self?.tick()
                }
            }
        }
    }

    private func reset() {
        summary = nil
        laps = 0
        meters = 0
        strokes = 0
        stroke = nil
        heartRate = nil
        kcal = 0
        waterTemp = nil
        depth = nil
        maxDepth = 0
        underSeconds = 0
        underSince = nil
        buzzedTo = 0
        pending = []
    }

    /// Swim sets (A): a strong buzz at every send-off, three at the end of the workout.
    private func tick() {
        guard let workout else { return }
        let e = elapsed()
        let n = workout.sendOffs(from: buzzedTo, to: e)
        buzzedTo = e
        guard n > 0 else { return }
        let device = WKInterfaceDevice.current()
        if workout.clock(at: e).finished {
            ticker?.cancel()
            Task {
                for _ in 0..<3 {
                    device.play(.success)
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        } else {
            device.play(.start)
        }
    }

    private func startLocation() {
        if routeBuilder == nil { routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil) }
        location.delegate = self
        location.activityType = .fitness
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.distanceFilter = 10
        location.requestWhenInUseAuthorization()
        location.startUpdatingLocation()
    }

    private func startDepth() {
        let m = CMWaterSubmersionManager()
        m.delegate = self
        submersion = m
    }

    func finish() async {
        guard let mode, let session, let builder else { discard(); return }
        ticker?.cancel()
        location.stopUpdatingLocation()
        flushRoute()
        let end = Date()
        if let u = underSince { underSeconds += end.timeIntervalSince(u) }
        summary = Summary(mode: mode, minutes: Int(end.timeIntervalSince(started ?? end) / 60), meters: Int(meters.rounded()), laps: laps,
                          pace: pace, swolf: swolf, maxDepth: maxDepth, waterTemp: waterTemp, workout: workout?.name)
        if mode == .openWater || mode == .snorkel {
            WatchStore.current?.sendBuddy(WSwimBuddy(start: started ?? end, minutes: buddyMinutes, ended: true))
        }
        session.end()
        do {
            var meta: [String: Any] = [:]
            if maxDepth > 0 { meta["MonkeyWorkoutMaxDepth"] = maxDepth }
            if let waterTemp { meta["MonkeyWorkoutWaterTemp"] = waterTemp }
            try? await builder.addMetadata(meta)
            try await builder.endCollection(at: end)
            if let workout = try await builder.finishWorkout(), let routeBuilder {
                _ = try? await routeBuilder.finishRoute(with: workout, metadata: nil)
            }
        } catch {}
        cleanup()
    }

    func discard() {
        ticker?.cancel()
        location.stopUpdatingLocation()
        if let started, mode == .openWater || mode == .snorkel {
            WatchStore.current?.sendBuddy(WSwimBuddy(start: started, minutes: buddyMinutes, ended: true))
        }
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
        submersion = nil
        ticker = nil
        mode = nil
        workout = nil
    }

    private func flushRoute() {
        guard !pending.isEmpty, let routeBuilder else { return }
        let batch = pending
        pending = []
        Task { try? await routeBuilder.insertRouteData(batch) }
    }

    fileprivate func add(_ locations: [CLLocation]) {
        guard running else { return }
        pending.append(contentsOf: locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 })
        if pending.count >= 30 { flushRoute() }
    }

    fileprivate func update(_ stats: HKStatistics) {
        switch stats.quantityType {
        case HKQuantityType(.heartRate):
            heartRate = stats.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? heartRate
        case HKQuantityType(.activeEnergyBurned):
            kcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? kcal
        case HKQuantityType(.distanceSwimming):
            meters = stats.sumQuantity()?.doubleValue(for: .meter()) ?? meters
        case HKQuantityType(.swimmingStrokeCount):
            strokes = stats.sumQuantity()?.doubleValue(for: .count()) ?? strokes
        case HKQuantityType(.waterTemperature):
            if waterTemp == nil || submersion == nil {
                waterTemp = stats.mostRecentQuantity()?.doubleValue(for: .degreeCelsius()) ?? waterTemp
            }
        default:
            break
        }
    }

    fileprivate func lapsChanged(_ events: [HKWorkoutEvent]) {
        let lapEvents = events.filter { $0.type == .lap }
        if lapEvents.count > laps { WKInterfaceDevice.current().play(.click) }
        laps = lapEvents.count
        if let raw = lapEvents.last?.metadata?[HKMetadataKeySwimmingStrokeStyle] as? NSNumber,
           let style = HKSwimmingStrokeStyle(rawValue: raw.intValue) {
            stroke = Self.label(style)
        }
    }

    fileprivate func submerged(depth d: Double?, temp: Double?) {
        if let temp { waterTemp = temp }
        guard let d else { return }
        depth = d
        maxDepth = max(maxDepth, d)
        if d >= 0.5, underSince == nil { underSince = Date() }
        if d < 0.5, let u = underSince {
            underSeconds += Date().timeIntervalSince(u)
            underSince = nil
        }
    }

    /// Time under water so far, the current dive included.
    func under(_ now: Date = Date()) -> TimeInterval { underSeconds + (underSince.map { now.timeIntervalSince($0) } ?? 0) }

    static func label(_ s: HKSwimmingStrokeStyle) -> String {
        switch s {
        case .freestyle: "Free"
        case .backstroke: "Back"
        case .breaststroke: "Breast"
        case .butterfly: "Fly"
        case .kickboard: "Kick"
        case .mixed: "Mixed"
        default: "Swim"
        }
    }

    #if DEBUG
    /// CI screenshots.
    func demo(_ mode: Mode, workout: SwimWorkout? = nil, minutes: Double) {
        self.mode = mode
        self.workout = workout
        started = Date().addingTimeInterval(-minutes * 60)
        switch mode {
        case .pool:
            laps = 32
            meters = 800
            strokes = 32 * 16
            stroke = "Free"
        case .openWater:
            meters = 1420
            waterTemp = 17.4
        case .snorkel:
            depth = 4.8
            maxDepth = 5.6
            underSeconds = 42
            waterTemp = 19.2
        }
    }
    #endif
}

extension SwimTracker: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.add(locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension SwimTracker: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        let events = workoutBuilder.workoutEvents
        Task { @MainActor in self.lapsChanged(events) }
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let stats = collectedTypes.compactMap { $0 as? HKQuantityType }.compactMap { workoutBuilder.statistics(for: $0) }
        Task { @MainActor in stats.forEach(self.update) }
    }
}

extension SwimTracker: CMWaterSubmersionManagerDelegate {
    nonisolated func manager(_ manager: CMWaterSubmersionManager, didUpdate event: CMWaterSubmersionEvent) {}

    nonisolated func manager(_ manager: CMWaterSubmersionManager, didUpdate measurement: CMWaterSubmersionMeasurement) {
        let d = measurement.depth?.converted(to: .meters).value
        Task { @MainActor in self.submerged(depth: d, temp: nil) }
    }

    nonisolated func manager(_ manager: CMWaterSubmersionManager, didUpdate measurement: CMWaterTemperature) {
        let t = measurement.temperature.converted(to: .celsius).value
        Task { @MainActor in self.submerged(depth: nil, temp: t) }
    }

    nonisolated func manager(_ manager: CMWaterSubmersionManager, errorOccurred error: Error) {}
}
