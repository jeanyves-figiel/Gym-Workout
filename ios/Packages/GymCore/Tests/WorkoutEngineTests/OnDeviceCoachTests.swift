import Foundation
import Testing
@testable import WorkoutEngine

/// On-device Coach routing and the instant recap (#608).
@Suite struct OnDeviceCoachTests {
    @Test func shortQuestionsStayOnDevice() {
        #expect(CoachRoute.onDevice("How long rest for 5×5 squat?"))
        #expect(CoachRoute.onDevice("Is it ok to train when sore?"))
        #expect(!CoachRoute.onDevice("45 min full body"))
        #expect(!CoachRoute.onDevice("Make me a legs workout"))
        #expect(!CoachRoute.onDevice("hi"))
    }

    private func record(_ day: Int, bench: Double, setsDone: Int = 3, dips: Int = 3) -> WorkoutRecord {
        WorkoutRecord(
            id: UUID(), startedAt: Date(timeIntervalSince1970: Double(day) * 86_400), durationSec: 48 * 60, sessionId: "push",
            week: 1, deload: false, focus: .fullUpper, title: "Push day",
            exercises: [
                ExerciseRecord(uid: "a", exerciseId: "bench-press", category: .strength, setsDone: setsDone, setsPlanned: 3, reps: 8, weightKg: bench),
                ExerciseRecord(uid: "b", exerciseId: "db-bench", category: .strength, setsDone: dips, setsPlanned: 3, reps: 10, weightKg: 20),
            ],
            kcal: nil, avgHeartRate: nil, maxHeartRate: nil, muscleLoad: [:])
    }

    @Test func recapComparesWithLastTime() throws {
        let before = record(1, bench: 80)
        let now = record(8, bench: 82.5)
        let r = try #require(WorkoutRecap.build(now, history: [before, now]))
        #expect(r.title == "PUSH DAY · 48′")
        #expect(r.recap.hasPrefix("Barbell bench press +2.5 kg vs last time."))
        #expect(r.tip == "Try 85 kg on Barbell bench press × 8.")
        #expect(r.facts.contains { $0.contains("last time 80 kg") })
    }

    @Test func recapTipsToFinishMissedSets() throws {
        let r = try #require(WorkoutRecap.build(record(8, bench: 80, dips: 2), history: []))
        #expect(r.tip.hasPrefix("Finish all 3 sets of"))
        #expect(r.recap.contains("stopped at 2 of 3 sets"))
    }

    @Test func noRecapWithoutSets() {
        #expect(WorkoutRecap.build(record(8, bench: 80, setsDone: 0, dips: 0), history: []) == nil)
    }
}
