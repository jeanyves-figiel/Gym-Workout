import Foundation
import HealthKit
import LiftSensor
import Observation
import WatchKit

/// WOD and combat timers on the Watch (#622, design A + B): runs a `WodTimer` inside a workout session (heart rate,
/// calories, saved to Apple Health as boxing or HIIT), rings the bell, claps at 10 seconds, ticks 3-2-1, and counts
/// punches per round with the batched accelerometer (#611 C). Double tap pauses and resumes.
@MainActor @Observable
final class WodTracker: NSObject {
    static let shared = WodTracker()

    private(set) var timer: WodTimer?
    private(set) var paused = false
    /// AMRAP rounds tapped.
    private(set) var amrapRounds = 0
    private(set) var summary: Summary?
    private(set) var heartRate: Double?
    private(set) var kcal: Double = 0
    let impacts = ImpactTracker()

    struct Summary {
        let name: String
        let kind: WodTimer.Kind
        let seconds: Int
        let rounds: Int
        let punches: Int
        let roundPunches: [Int]
        let kcal: Int
    }

    var running: Bool { timer != nil }

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// Seconds run before the current stretch, and when the current stretch started (nil while paused).
    private var banked: TimeInterval = 0
    private var since: Date?
    private var cuedTo: TimeInterval = 0
    private var ticker: Task<Void, Never>?

    func elapsed(_ now: Date = Date()) -> TimeInterval { banked + (since.map { now.timeIntervalSince($0) } ?? 0) }

    func start(_ t: WodTimer) async {
        guard !running, !WorkoutManager.shared.running, !SportTracker.shared.running, !HyroxTracker.shared.running,
              !SwimTracker.shared.running else { return }
        summary = nil
        amrapRounds = 0
        heartRate = nil
        kcal = 0
        banked = 0
        cuedTo = 0
        paused = false
        timer = t
        let now = Date()
        since = now
        if HKHealthStore.isHealthDataAvailable() {
            let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)]
            let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
            try? await store.requestAuthorization(toShare: share, read: read)
            let config = HKWorkoutConfiguration()
            config.activityType = t.punches ? .boxing : .highIntensityIntervalTraining
            config.locationType = .indoor
            if let s = try? HKWorkoutSession(healthStore: store, configuration: config) {
                let b = s.associatedWorkoutBuilder()
                b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
                b.delegate = self
                session = s
                builder = b
                s.startActivity(with: now)
                try? await b.beginCollection(at: now)
                // Same raw values as the iPhone's `Sport`: the sport page reads it back from Health.
                try? await b.addMetadata(["MonkeyWorkoutSport": t.punches ? "boxing" : "crossfit", "MonkeyWorkoutTitle": t.name])
            }
        }
        // Batched sensors need the workout session above.
        if t.punches { impacts.startPunches() }
        if t.prep == 0 { WKInterfaceDevice.current().play(.start) }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let timer, !paused else { return }
        let e = elapsed()
        for cue in timer.cues(from: cuedTo, to: e) { play(cue, timer) }
        cuedTo = e
        if timer.state(at: e).finished {
            ticker?.cancel()
            ticker = nil
            Task { await finish() }
        }
    }

    private func play(_ cue: WodTimer.Cue, _ t: WodTimer) {
        let device = WKInterfaceDevice.current()
        switch cue {
        case .bell:
            device.play(.start)
        case .rest:
            if t.punches { impacts.endRound() }
            device.play(.stop)
        case .clap:
            // Boxing's 10-second clap: two taps.
            device.play(.notification)
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                device.play(.notification)
            }
        case .tick:
            device.play(.click)
        case .done:
            if t.punches { impacts.endRound() }
            device.play(.success)
        }
    }

    /// Double tap, or the pause button.
    func togglePause() {
        guard running else { return }
        if paused {
            since = Date()
            session?.resume()
        } else {
            banked = elapsed()
            since = nil
            session?.pause()
        }
        paused.toggle()
    }

    func addRound() {
        amrapRounds += 1
        WKInterfaceDevice.current().play(.click)
    }

    func finish() async {
        guard let timer else { return }
        let e = Int(elapsed())
        ticker?.cancel()
        impacts.stop()
        let st = timer.state(at: Double(e))
        let worked = timer.kind == .forTime ? max(0, e - timer.prep) : min(e, timer.totalSeconds) - min(e, timer.prep)
        summary = Summary(name: timer.name, kind: timer.kind, seconds: worked,
                          rounds: timer.kind == .amrap ? amrapRounds : (st.finished ? timer.rounds : max(0, (st.phase?.round ?? 1) - 1)),
                          punches: impacts.punches.count, roundPunches: impacts.rounds, kcal: Int(kcal.rounded()))
        session?.end()
        if let builder {
            var meta: [String: Any] = [:]
            if timer.punches { meta["MonkeyWorkoutPunches"] = impacts.punches.count }
            if timer.kind == .amrap { meta["MonkeyWorkoutRounds"] = amrapRounds }
            try? await builder.addMetadata(meta)
            try? await builder.endCollection(at: Date())
            _ = try? await builder.finishWorkout()
        }
        cleanup()
    }

    func discard() {
        ticker?.cancel()
        impacts.stop()
        session?.end()
        builder?.discardWorkout()
        cleanup()
    }

    func closeSummary() { summary = nil }

    private func cleanup() {
        session = nil
        builder = nil
        ticker = nil
        timer = nil
        since = nil
        paused = false
    }

    fileprivate func update(_ stats: HKStatistics) {
        switch stats.quantityType {
        case HKQuantityType(.heartRate):
            heartRate = stats.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) ?? heartRate
        case HKQuantityType(.activeEnergyBurned):
            kcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? kcal
        default:
            break
        }
    }

    #if DEBUG
    /// CI screenshots: round 4 of 6 with 2:14 left.
    func demo(_ t: WodTimer, at seconds: TimeInterval) {
        timer = t
        banked = seconds
        since = nil
        paused = false
        impacts.demo(punches: 112, rate: 71, rounds: [96, 104, 88])
    }
    #endif
}

extension WodTracker: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let stats = collectedTypes.compactMap { $0 as? HKQuantityType }.compactMap { workoutBuilder.statistics(for: $0) }
        Task { @MainActor in stats.forEach(self.update) }
    }
}
