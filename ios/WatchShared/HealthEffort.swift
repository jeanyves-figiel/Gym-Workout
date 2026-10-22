import Foundation
import HealthKit

/// Effort and mood to Apple Health (#614): the effort score on the workout counts gym sessions in Apple's Training
/// Load; the finish mood is saved as a State of Mind. Shared by the iPhone and the Watch.
enum HealthEffort {
    static var shareTypes: Set<HKSampleType> { [HKQuantityType(.workoutEffortScore), HKSampleType.stateOfMindType()] }

    /// Asks once for the two types (members connected before #614 never allowed them). No sheet when already asked.
    static func authorize(_ store: HKHealthStore) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(toShare: shareTypes, read: [])
    }

    /// Effort 1–10 related to `workout`.
    static func saveEffort(_ score: Int, workout: HKWorkout, store: HKHealthStore) async throws {
        let v = Double(min(10, max(1, score)))
        let sample = HKQuantitySample(type: HKQuantityType(.workoutEffortScore), quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: v),
                                      start: workout.startDate, end: workout.endDate)
        _ = try await store.relateWorkoutEffortSample(sample, with: workout, activity: nil)
    }

    /// Mood level 1–5 (`Feel` raw values on the iPhone: drained, meh, good, great, amazing).
    static func saveMood(_ level: Int, at date: Date, store: HKHealthStore) async throws {
        let mood = HKStateOfMind(date: date, kind: .momentaryEmotion, valence: valence(level), labels: [label(level)], associations: [.fitness])
        _ = try await store.save(mood)
    }

    static func valence(_ level: Int) -> Double {
        switch level {
        case ...1: -0.8
        case 2: -0.2
        case 3: 0.4
        case 4: 0.7
        default: 1
        }
    }

    static func label(_ level: Int) -> HKStateOfMind.Label {
        switch level {
        case ...1: .drained
        case 2: .indifferent
        case 3: .content
        case 4: .happy
        default: .excited
        }
    }

    /// The Health workout saved for a session between `start` and `end` (by this app or its Watch).
    static func workout(from start: Date, to end: Date, store: HKHealthStore) async -> HKWorkout? {
        let pred = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-180), end: end.addingTimeInterval(180))
        let d = HKSampleQueryDescriptor(predicates: [.workout(pred)], sortDescriptors: [SortDescriptor<HKWorkout>(\.startDate)], limit: 5)
        let found = (try? await d.result(for: store)) ?? []
        return found.min { abs($0.startDate.timeIntervalSince(start)) < abs($1.startDate.timeIntervalSince(start)) }
    }
}
