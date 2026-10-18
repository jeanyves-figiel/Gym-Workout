import CoreMotion
import Foundation
import HealthKit
import LiftSensor
import Observation
import WatchConnectivity
import WatchKit

/// Hyrox race mode (#426, design A): records a race or sim on the Watch alone. An Apple workout session keeps it
/// running in the background (HR, energy); the pedometer gives cadence and distance, 25 Hz wrist motion tells the
/// stations apart (`HyroxDetector`) and counts strokes, jumps and throws. Double tap, the Action button or the
/// big button move on by hand. The finished race goes to Apple Health, is queued for the iPhone, and is uploaded
/// straight away when the Watch has a network.
@MainActor @Observable
final class HyroxTracker: NSObject {
    static let shared = HyroxTracker()

    private(set) var format: HyroxFormat = .full
    private(set) var division = HyroxDivision()
    private(set) var goal: Double?
    private(set) var pacing: HyroxPacing?
    /// 3-2-1 before the gun; nil once racing.
    private(set) var countdown: Int?
    private(set) var started: Date?
    private(set) var index = 0
    private(set) var between = false
    private(set) var stepStart: Date?
    private(set) var splits: [HyroxSplit] = []
    private(set) var reps = 0
    /// Asking to confirm the next step (detection unsure).
    private(set) var asking = false
    private(set) var heartRate: Double?
    /// Metres from the pedometer in the current run.
    private(set) var runMeters: Double = 0
    private(set) var result: HyroxRace?
    /// Faster than the last comparable race (finish screen).
    private(set) var pb: Double?

    var running: Bool { started != nil || countdown != nil }
    var steps: [HyroxStep] { format.steps }
    var current: HyroxStep? { index < steps.count ? steps[index] : nil }
    var next: HyroxStep? { index + 1 < steps.count ? steps[index + 1] : nil }
    var target: Double? { pacing.flatMap { index < $0.targets.count ? $0.targets[index] : nil } }

    /// Seconds ahead (−) or behind (+) the plan at `now`, counting finished splits and the current step.
    func delta(now: Date) -> Double? {
        guard let pacing, let started else { return nil }
        let planned = pacing.targets.prefix(index).reduce(0, +) + pacing.roxzone * Double(index) / Double(max(1, steps.count))
        return now.timeIntervalSince(started) - planned - (between ? 0 : min(target ?? 0, now.timeIntervalSince(stepStart ?? now)))
    }

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var detector: HyroxDetector?
    private let motion = CMMotionManager()
    private let pedometer = CMPedometer()
    private let buffer = HyroxBuffer()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()
    private var tick: Timer?
    private var cadence: Double = 0
    private var meters: Double = 0
    private var runStartMeters: Double = 0
    private var hrSum = 0.0
    private var hrCount = 0
    private var maxHR: Double?
    private var lastRace: HyroxRace?
    /// Between the finish line and the saved race: the detector's finish and End can both call `finish`.
    private var finishing = false

    /// Gets ready: settings from the iPhone, Health session prepared, then 3-2-1 and go.
    func start(_ format: HyroxFormat, settings: WHyrox?) async {
        guard !running, HKHealthStore.isHealthDataAvailable(), !WorkoutManager.shared.running, !SportTracker.shared.running else { return }
        self.format = format
        division = settings?.division ?? HyroxDivision()
        goal = format == .full ? settings?.goalSeconds : nil
        pacing = goal.map { HyroxPacing(goalSeconds: $0, steps: format.steps) }
        lastRace = settings?.lastRace.flatMap { $0.format == format ? $0 : nil }
        result = nil
        pb = nil
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate),
                                        HKQuantityType(.distanceWalkingRunning)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType()]
        try? await store.requestAuthorization(toShare: share, read: read)
        let config = HKWorkoutConfiguration()
        config.activityType = .crossTraining
        config.locationType = .indoor
        guard let s = try? HKWorkoutSession(healthStore: store, configuration: config) else { return }
        let b = s.associatedWorkoutBuilder()
        b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        b.delegate = self
        session = s
        builder = b
        s.prepare()
        countdown = 3
        for n in [3, 2, 1] {
            countdown = n
            WKInterfaceDevice.current().play(.click)
            try? await Task.sleep(for: .seconds(1))
        }
        countdown = nil
        await go()
    }

    private func go() async {
        guard let session, let builder else { return }
        let now = Date()
        WKInterfaceDevice.current().play(.start)
        session.startActivity(with: now)
        do {
            try await builder.beginCollection(at: now)
            try? await builder.addMetadata(["MonkeyWorkoutSport": "hyrox", "MonkeyWorkoutHyrox": format.label])
        } catch {
            discard()
            return
        }
        started = now
        stepStart = now
        index = 0
        between = false
        splits = []
        detector = HyroxDetector(steps: format.steps, start: now)
        buffer.reset(station: nil)
        startSensors(from: now)
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.second() }
        }
    }

    private func startSensors(from date: Date) {
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: date) { [weak self] data, _ in
                guard let data else { return }
                let c = data.currentCadence?.doubleValue ?? 0
                let d = data.distance?.doubleValue ?? 0
                Task { @MainActor in
                    self?.cadence = c
                    self?.meters = d
                }
            }
        }
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / HyroxBuffer.hz
        let buffer = buffer
        motion.startDeviceMotionUpdates(to: queue) { m, _ in
            guard let m else { return }
            let u = m.userAcceleration, g = m.gravity, r = m.rotationRate
            buffer.add(MotionSample(userAcceleration: Vec3(u.x, u.y, u.z), gravity: Vec3(g.x, g.y, g.z),
                                    rotationRate: (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()), at: m.timestamp)
        }
    }

    private func stopSensors() {
        tick?.invalidate()
        tick = nil
        motion.stopDeviceMotionUpdates()
        pedometer.stopUpdates()
    }

    /// Once a second: features → detector; counted reps.
    private func second() {
        guard let detector, started != nil else { return }
        let (f, newReps) = buffer.features(cadence: cadence)
        for _ in 0..<newReps { detector.rep() }
        apply(detector.feed(f, at: Date()))
        reps = detector.reps
        if current?.isRun == true, !between { runMeters = max(0, meters - runStartMeters) }
    }

    /// Double tap, Action button, big button.
    func advance() {
        guard let detector, started != nil else { return }
        if asking { asking = false }
        apply(detector.advance(at: Date()))
    }

    private func apply(_ events: [HyroxDetector.Event]) {
        guard let detector else { return }
        for e in events {
            switch e {
            case let .started(i, t):
                index = i
                between = false
                stepStart = t
                asking = false
                if steps[i].isRun { runStartMeters = meters }
                buffer.reset(station: steps[i].station)
                // Strong double buzz: new step.
                WKInterfaceDevice.current().play(.directionUp)
            case let .ended(i, _):
                index = min(i + 1, steps.count - 1)
                between = true
                buffer.reset(station: nil)
                WKInterfaceDevice.current().play(.success)
            case .unsure:
                asking = true
                WKInterfaceDevice.current().play(.retry)
            case let .finished(t):
                splits = detector.splits
                Task { await finish(at: t) }
                return
            }
        }
        splits = detector.splits
    }

    /// The finish line (or End): saves to Health, then queues and uploads the race.
    func finish(at end: Date = Date()) async {
        guard !finishing else { return }
        guard let session, let builder, let started else { discard(); return }
        finishing = true
        defer { finishing = false }
        if let detector, detector.phase != .done {
            _ = detector.finish(at: end)
            splits = detector.splits
        }
        stopSensors()
        session.end()
        WKInterfaceDevice.current().play(.notification)
        var race = HyroxRace(format: format, division: division, start: started, end: splits.last?.end ?? end,
                             goalSeconds: goal, splits: splits, avgHR: hrCount > 0 ? hrSum / Double(hrCount) : nil, maxHR: maxHR)
        do {
            try await builder.endCollection(at: end)
            if let workout = try await builder.finishWorkout() { race.id = workout.uuid }
        } catch {}
        if let lastRace, lastRace.complete, race.complete { pb = race.total - lastRace.total }
        result = race
        self.session = nil
        self.builder = nil
        detector = nil
        self.started = nil
        HyroxSync.send(race)
    }

    func discard() {
        stopSensors()
        session?.end()
        builder?.discardWorkout()
        session = nil
        builder = nil
        detector = nil
        started = nil
        countdown = nil
    }

    func closeResult() { result = nil }

    fileprivate func heart(_ stats: HKStatistics) {
        guard stats.quantityType == HKQuantityType(.heartRate),
              let v = stats.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) else { return }
        heartRate = v
        hrSum += v
        hrCount += 1
        maxHR = max(maxHR ?? 0, v)
    }
}

extension HyroxTracker: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let stats = workoutBuilder.statistics(for: HKQuantityType(.heartRate)) else { return }
        Task { @MainActor in self.heart(stats) }
    }
}

/// Wrist motion of the last 8 s and the reps counted in it, filled from the motion queue.
final class HyroxBuffer: @unchecked Sendable {
    static let hz = 25.0
    private let lock = NSLock()
    private var samples: [MotionSample] = []
    private var counter: HyroxRepCounter?
    private var reps = 0

    func reset(station: HyroxStation?) {
        lock.lock()
        defer { lock.unlock() }
        counter = station.flatMap { $0.counts ? HyroxRepCounter(for: $0) : nil }
        reps = 0
    }

    func add(_ s: MotionSample, at t: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(s)
        if samples.count > Int(Self.hz * 8) { samples.removeFirst(samples.count - Int(Self.hz * 8)) }
        if counter?.add(s.verticalUp, at: t) == true { reps += 1 }
    }

    /// Features of the window and the reps counted since the last call.
    func features(cadence: Double) -> (HyroxFeatures, Int) {
        lock.lock()
        let window = samples
        let n = reps
        reps = 0
        lock.unlock()
        return (HyroxMotion.features(window, hz: Self.hz, cadence: cadence), n)
    }
}

/// Getting the race to the iPhone and the server (#426): queued to the iPhone (delivered when it is back in range)
/// and, when the Watch has Wi-Fi or cellular and an upload key from the iPhone, posted straight to MonkeyWorkout.
enum HyroxSync {
    @MainActor static func send(_ race: HyroxRace) {
        WatchStore.current?.send(.hyroxRace(race))
        guard let h = WatchStore.current?.snapshot.hyrox, let key = h.uploadKey, let base = h.apiBase,
              let url = URL(string: "/v1/watch/sports", relativeTo: URL(string: base)) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        struct Log: Encodable {
            var id: UUID
            var start: Date
            var minutes: Int
            var effort: Int
            var sport = "hyrox"
            var hyrox: HyroxRace
        }
        let log = Log(id: race.id, start: race.start, minutes: max(1, Int((race.total / 60).rounded())),
                      effort: race.format == .full ? 9 : 8, hyrox: race)
        guard let body = try? encoder.encode(["sports": [log]]) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "X-Watch-Key")
        req.httpBody = body
        req.timeoutInterval = 20
        // Best effort: the queued copy reaches the iPhone anyway, which syncs it.
        URLSession.shared.dataTask(with: req).resume()
    }
}
