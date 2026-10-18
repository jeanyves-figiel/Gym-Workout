import Foundation
import HealthKit
import Observation
import WatchConnectivity

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
    /// Paused from the controls or with Action + side button (#349).
    private(set) var paused = false

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var hrSum = 0.0
    private var hrCount = 0
    private(set) var maxHeartRate: Double?
    /// Last heart rate sent to the iPhone for its Live Activity (#371).
    private var hrSentAt = Date.distantPast

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
        UserDefaults.standard.set(phoneSessionId, forKey: Self.phoneSessionKey)
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
            paused = false
            ActionButton.sessionStarted()
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

    func pause() {
        session?.pause()
        paused = session != nil
    }

    func resume() {
        session?.resume()
        paused = false
    }

    /// Ends and saves the Health workout. Returns false when no session ran (the phone saves it then).
    func finish(sets: Int?) async -> Bool {
        guard let session, let builder, running else { discard(); return false }
        session.end()
        defer {
            self.session = nil
            self.builder = nil
            running = false
            paused = false
            phoneSessionId = nil
            UserDefaults.standard.removeObject(forKey: Self.phoneSessionKey)
        }
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
        paused = false
        phoneSessionId = nil
        UserDefaults.standard.removeObject(forKey: Self.phoneSessionKey)
    }

    // MARK: Recovery

    /// iPhone workout being tracked, kept on disk so a relaunch after a crash can pick the session back up.
    private static let phoneSessionKey = "workout.phoneSessionId"

    /// watchOS relaunched the app after it quit mid-workout. An iPhone workout's tracking carries on (the iPhone
    /// ends it); anything else (Watch player, sport, Hyrox) lost its screen state, so what Health recorded is saved.
    func recoverActiveWorkout() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        store.recoverActiveWorkoutSession { [weak self] session, _ in
            guard let session else { return }
            Task { @MainActor in self?.recovered(session) }
        }
    }

    private func recovered(_ s: HKWorkoutSession) {
        let b = s.associatedWorkoutBuilder()
        let phoneId = UserDefaults.standard.string(forKey: Self.phoneSessionKey)
        guard s.workoutConfiguration.activityType == .functionalStrengthTraining, let phoneId, !running else {
            UserDefaults.standard.removeObject(forKey: Self.phoneSessionKey)
            s.end()
            Task {
                try? await b.endCollection(at: Date())
                _ = try? await b.finishWorkout()
            }
            return
        }
        if session != nil { discard() } // only ever a prepared, not started one here
        b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: s.workoutConfiguration)
        s.delegate = self
        b.delegate = self
        session = s
        builder = b
        phoneSessionId = phoneId
        UserDefaults.standard.set(phoneId, forKey: Self.phoneSessionKey)
        heartRate = nil
        activeKcal = 0
        hrSum = 0
        hrCount = 0
        maxHeartRate = nil
        running = true
        paused = s.state == .paused
    }

    /// The Health session failed: drop it. The Watch player and the iPhone save the workout without it
    /// (`finish` returns false), and a tracked iPhone workout is told tracking stopped.
    private func failed(_ s: HKWorkoutSession) {
        guard s === session else { return }
        if phoneSessionId != nil, let store = WatchStore.current { store.stopTracking() } else { discard() }
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
            // iPhone workout (#371): its lock screen shows the heart rate, every 10 s at most.
            if phoneSessionId != nil, Date().timeIntervalSince(hrSentAt) >= 10, WCSession.default.isReachable {
                hrSentAt = Date()
                WCSession.default.sendMessage([WatchKeys.heartRate: Int(v.rounded())], replyHandler: nil, errorHandler: nil)
            }
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

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.failed(workoutSession) }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let stats = collectedTypes.compactMap { $0 as? HKQuantityType }.compactMap { workoutBuilder.statistics(for: $0) }
        Task { @MainActor in stats.forEach(self.update) }
    }
}
