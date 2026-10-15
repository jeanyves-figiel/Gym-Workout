import Foundation
import HealthKit
import Observation

/// HealthKit workout session on the Watch: live heart rate and active calories, saved as one
/// Apple Health workout when the session finishes (the phone then skips its own save).
@MainActor @Observable
final class WorkoutManager: NSObject {
    /// One per app: the iPhone can wake the Watch with a workout configuration (#347).
    static let shared = WorkoutManager()

    var heartRate: Double?
    /// iPhone workout this session tracks (#347); nil for a workout run on the Watch.
    private(set) var phoneSessionId: String?
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

    /// Woken by the iPhone (#347): warm up the sensors while the member decides on the start prompt.
    func prepare() async {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }
        await requestAuthorization()
        guard session == nil, makeSession() else { return }
        session?.prepare()
    }

    /// Starts the Health session; `phoneSessionId` marks it as tracking a workout run on the iPhone (#347).
    func start(title: String, phoneSessionId: String? = nil) async {
        guard HKHealthStore.isHealthDataAvailable(), !running else { return }
        if session == nil {
            await requestAuthorization()
            guard session == nil, makeSession() else { return }
        }
        guard let s = session, let b = builder else { return }
        self.phoneSessionId = phoneSessionId
        heartRate = nil
        activeKcal = 0
        hrSum = 0
        hrCount = 0
        maxHeartRate = nil
        let start = Date()
        s.startActivity(with: start)
        do {
            try await b.beginCollection(at: start)
            try? await b.addMetadata(["MonkeyWorkoutTitle": title])
            running = true
        } catch {
            discard()
        }
    }

    private func makeSession() -> Bool {
        let config = HKWorkoutConfiguration()
        config.activityType = .functionalStrengthTraining
        config.locationType = .indoor
        guard let s = try? HKWorkoutSession(healthStore: store, configuration: config) else { return false }
        let b = s.associatedWorkoutBuilder()
        b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        s.delegate = self
        b.delegate = self
        session = s
        builder = b
        return true
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    /// Ends and saves the Health workout. Returns false when no session ran (the phone saves it then).
    func finish(sets: Int?) async -> Bool {
        guard let session, let builder, running else { discard(); return false }
        session.end()
        defer { self.session = nil; self.builder = nil; running = false; phoneSessionId = nil }
        do {
            var meta: [String: Any] = [HKMetadataKeyIndoorWorkout: true]
            if let sets { meta["MonkeyWorkoutSets"] = sets }
            try? await builder.addMetadata(meta)
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
        phoneSessionId = nil
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
