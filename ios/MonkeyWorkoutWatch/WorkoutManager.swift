import Foundation
import HealthKit
import Observation

/// HealthKit workout session on the Watch: live heart rate and active calories, saved as one
/// Apple Health workout when the session finishes (the phone then skips its own save).
@MainActor @Observable
final class WorkoutManager: NSObject {
    var heartRate: Double?
    var activeKcal: Double = 0
    private(set) var running = false

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var hrSum = 0.0
    private var hrCount = 0
    private(set) var maxHeartRate: Double?

    var averageHeartRate: Double? { hrCount > 0 ? hrSum / Double(hrCount) : nil }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType()]
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    func start(title: String) async {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }
        await requestAuthorization()
        let config = HKWorkoutConfiguration()
        config.activityType = .functionalStrengthTraining
        config.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            s.delegate = self
            b.delegate = self
            session = s
            builder = b
            heartRate = nil
            activeKcal = 0
            hrSum = 0
            hrCount = 0
            maxHeartRate = nil
            let start = Date()
            s.startActivity(with: start)
            try await b.beginCollection(at: start)
            try? await b.addMetadata(["MonkeyWorkoutTitle": title])
            running = true
        } catch {
            session = nil
            builder = nil
        }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    /// Ends and saves the Health workout. Returns false when no session ran (the phone saves it then).
    func finish(sets: Int) async -> Bool {
        guard let session, let builder else { return false }
        session.end()
        defer { self.session = nil; self.builder = nil; running = false }
        do {
            try? await builder.addMetadata([HKMetadataKeyIndoorWorkout: true, "MonkeyWorkoutSets": sets])
            try await builder.endCollection(at: Date())
            _ = try await builder.finishWorkout()
            return true
        } catch {
            return false
        }
    }

    /// Discards the session without saving anything.
    func discard() {
        session?.end()
        builder?.discardWorkout()
        session = nil
        builder = nil
        running = false
    }

    fileprivate func update(_ stats: HKStatistics) {
        switch stats.quantityType {
        case HKQuantityType(.heartRate):
            let unit = HKUnit.count().unitDivided(by: .minute())
            guard let v = stats.mostRecentQuantity()?.doubleValue(for: unit) else { return }
            heartRate = v
            hrSum += v
            hrCount += 1
            maxHeartRate = max(maxHeartRate ?? 0, v)
        case HKQuantityType(.activeEnergyBurned):
            activeKcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? activeKcal
        default:
            break
        }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let stats = collectedTypes.compactMap { $0 as? HKQuantityType }.compactMap { workoutBuilder.statistics(for: $0) }
        Task { @MainActor in stats.forEach(self.update) }
    }
}
