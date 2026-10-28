import Foundation
import HealthKit
import Observation
import WatchKit

/// Breathing on the Watch (#834 A + C): plays a `WBreath` with a tap on the wrist for each phase (a stronger one on the
/// breath in, so it works with eyes closed), and runs a mind & body workout session only for live heart rate and to
/// keep the screen up; that workout is thrown away at the end (the iPhone saves mindful minutes). The summary shows
/// how far the heart rate dropped.
@MainActor @Observable
final class CalmTracker: NSObject {
    static let shared = CalmTracker()

    private(set) var breath: WBreath?
    private(set) var minutes = 3
    private(set) var paused = false
    private(set) var heartRate: Double?
    private(set) var summary: Summary?

    struct Summary {
        let breath: WBreath
        let seconds: Int
        let hrStart: Int?
        let hrEnd: Int?
    }

    var running: Bool { breath != nil }

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var start: Date?
    private var banked: TimeInterval = 0
    private var since: Date?
    private var lastStep = -1
    private var hrStart: Double?
    private var ticker: Task<Void, Never>?

    func elapsed(_ now: Date = Date()) -> TimeInterval { banked + (since.map { now.timeIntervalSince($0) } ?? 0) }

    func begin(_ b: WBreath, minutes m: Int) async {
        guard !running, !WorkoutManager.shared.running, !SportTracker.shared.running, !HyroxTracker.shared.running,
              !SwimTracker.shared.running, !WodTracker.shared.running else { return }
        summary = nil
        heartRate = nil
        hrStart = nil
        banked = 0
        lastStep = -1
        paused = false
        minutes = m
        breath = b
        let now = Date()
        start = now
        since = now
        if HKHealthStore.isHealthDataAvailable() {
            let share: Set<HKSampleType> = [HKObjectType.workoutType()]
            let read: Set<HKObjectType> = [HKQuantityType(.heartRate)]
            try? await store.requestAuthorization(toShare: share, read: read)
            let config = HKWorkoutConfiguration()
            config.activityType = .mindAndBody
            config.locationType = .indoor
            if let s = try? HKWorkoutSession(healthStore: store, configuration: config) {
                let builder = s.associatedWorkoutBuilder()
                builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
                builder.delegate = self
                session = s
                self.builder = builder
                s.startActivity(with: now)
                try? await builder.beginCollection(at: now)
            }
        }
        WKInterfaceDevice.current().play(.start)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let breath, !paused else { return }
        let e = elapsed()
        let at = breath.at(e, minutes: minutes)
        let step = at.cycle * breath.phases.count + at.index
        if step != lastStep {
            lastStep = step
            // Breath in: a rising tap; hold and out: a soft click.
            WKInterfaceDevice.current().play(breath.phases[at.index].inhale ? .directionUp : .click)
        }
        if e >= breath.totalSeconds(minutes: minutes) {
            ticker?.cancel()
            ticker = nil
            WKInterfaceDevice.current().play(.success)
            finish()
        }
    }

    /// Tap on the screen or double tap.
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

    /// End now (✕) or at the end: a minute or more counts as mindful minutes.
    func finish() {
        guard let breath, let start else { return }
        let seconds = Int(min(elapsed(), breath.totalSeconds(minutes: minutes)))
        ticker?.cancel()
        session?.end()
        builder?.discardWorkout()
        WatchStore.current?.calmDone(breath: breath.id, start: start, seconds: seconds)
        summary = seconds >= 60
            ? Summary(breath: breath, seconds: seconds, hrStart: hrStart.map { Int($0.rounded()) }, hrEnd: heartRate.map { Int($0.rounded()) })
            : nil
        session = nil
        builder = nil
        ticker = nil
        self.breath = nil
        self.start = nil
        since = nil
        paused = false
    }

    func closeSummary() { summary = nil }

    fileprivate func update(_ stats: HKStatistics) {
        guard stats.quantityType == HKQuantityType(.heartRate),
              let v = stats.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) else { return }
        heartRate = v
        if hrStart == nil { hrStart = v }
    }

    #if DEBUG
    /// CI screenshots: box breathing, 2:14 left, or its summary.
    func demo(_ b: WBreath, at seconds: TimeInterval, done: Bool = false) {
        if done {
            summary = Summary(breath: b, seconds: 240, hrStart: 72, hrEnd: 61)
            return
        }
        breath = b
        minutes = b.lengths.first ?? 3
        banked = seconds
        since = nil
        paused = false
        heartRate = 68
    }
    #endif
}

extension CalmTracker: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let stats = collectedTypes.compactMap { $0 as? HKQuantityType }.compactMap { workoutBuilder.statistics(for: $0) }
        Task { @MainActor in stats.forEach(self.update) }
    }
}
