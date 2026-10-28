import Foundation
import Testing
@testable import WorkoutEngine

private let utc = Progression.calendar(TimeZone(identifier: "UTC")!)
private let monday = ISO8601DateFormatter().date(from: "2026-09-07T10:00:00Z")! // a Monday

private func day(_ n: Int) -> Date { monday.addingTimeInterval(Double(n) * 86_400) }

/// One workout of bench press: `sets` × 5 at `kg`; `kg` nil = a workout without lifting.
private func workout(_ at: Date, sets: Int = 4, kg: Double?) -> WorkoutRecord {
    let ex = kg.map { [ExerciseRecord(uid: "u0", exerciseId: "bench-press", category: .strength, setsDone: sets, setsPlanned: sets, reps: 5, weightKg: $0)] }
        ?? [ExerciseRecord(uid: "u0", exerciseId: "rowing-machine", category: .cardio, setsDone: 1, setsPlanned: 1, reps: nil, weightKg: nil)]
    return WorkoutRecord(id: UUID(), startedAt: at, durationSec: 3600, sessionId: "w1s1", week: 1, deload: false, focus: .fullUpper,
                         title: "Test", exercises: ex, kcal: nil, avgHeartRate: nil, maxHeartRate: nil, muscleLoad: [:])
}

/// 8 weeks, 3 workouts a week; `kg(week)` and `sets(week)` per week.
private func history(kg: (Int) -> Double, sets: (Int) -> Int = { _ in 4 }) -> [WorkoutRecord] {
    (0..<8).flatMap { w in [0, 2, 4].map { workout(day(7 * w + $0), sets: sets(w), kg: kg(w)) } }
}

private let afterLast = day(7 * 7 + 5)

@Suite struct PlateauExplainTests {
    @Test func flatLiftWithNothingElseIsSameScheme() throws {
        let s = try #require(Plateaus.stalled("bench-press", records: history { _ in 60 }, sessionsPerWeek: 3, now: afterLast, calendar: utc))
        #expect(s.weeks >= 3)
        #expect(s.causes == [.sameScheme])
        #expect(s.fix == .cluster)
        #expect(abs(s.kg - 70) < 0.5)
    }

    @Test func risingLiftIsNotStalled() {
        #expect(Plateaus.stalled("bench-press", records: history { 60 + 2.5 * Double($0) }, sessionsPerWeek: 3, now: afterLast, calendar: utc) == nil)
    }

    @Test func fewerSetsIsLessVolumeAndBackOffs() throws {
        let rs = history(kg: { 60 + 2.5 * Double(min($0, 3)) }, sets: { $0 < 4 ? 4 : 2 })
        let s = try #require(Plateaus.stalled("bench-press", records: rs, sessionsPerWeek: 3, now: afterLast, calendar: utc))
        #expect(s.weeks == 4)
        #expect(s.causes.contains(.volumeDrop(percent: 50)))
        #expect(s.fix == .topBackoff)
        #expect(s.since == utc.startOfDay(for: day(28)))
    }

    @Test func skippedSessionsSleepAndOtherTraining() throws {
        // Weeks 4-7: one bench day and two rowing days instead of three bench days.
        var rs = (0..<4).flatMap { w in [0, 2, 4].map { workout(day(7 * w + $0), kg: 60 + 2.5 * Double(w)) } }
        rs += (4..<8).flatMap { w in [workout(day(7 * w), kg: 67.5), workout(day(7 * w + 2), kg: nil), workout(day(7 * w + 4), kg: nil)] }
        let s = try #require(Plateaus.stalled("bench-press", records: rs, sessionsPerWeek: 3, sleepHours: 5.2, style: .cluster,
                                              now: afterLast, calendar: utc))
        #expect(s.causes.contains(.skipped(done: 4, planned: 12)))
        #expect(s.causes.contains(.otherTraining(extra: 8)))
        #expect(s.causes.contains(.shortSleep(hours: 5.2)))
        #expect(s.fix == .topBackoff)
    }

    @Test func liftNotDoneLatelyIsNotStalled() {
        #expect(Plateaus.stalled("bench-press", records: history { _ in 60 }, sessionsPerWeek: 3, now: day(7 * 7 + 30), calendar: utc) == nil)
    }

    @Test func workoutListsItsStalledLifts() {
        let rs = history { _ in 60 }
        let out = Plateaus.stalled(in: rs.last!, records: rs, sessionsPerWeek: 3, now: afterLast, calendar: utc)
        #expect(out.map(\.exerciseId) == ["bench-press"])
    }
}
