import Foundation
import Testing
@testable import WorkoutEngine

private let utc = Progression.calendar(TimeZone(identifier: "UTC")!)
private let monday = ISO8601DateFormatter().date(from: "2026-09-07T10:00:00Z")! // a Monday

private func day(_ n: Int) -> Date { monday.addingTimeInterval(Double(n) * 86_400) }

/// One workout: (exercise, sets, kg) at 5 reps.
private func workout(_ at: Date, _ lifts: [(String, Int, Double)], deload: Bool = false) -> WorkoutRecord {
    let ex = lifts.enumerated().map { i, l in
        ExerciseRecord(uid: "u\(i)", exerciseId: l.0, category: Exercise.get(l.0).category, setsDone: l.1, setsPlanned: l.1, reps: 5, weightKg: l.2)
    }
    return WorkoutRecord(id: UUID(), startedAt: at, durationSec: 3600, sessionId: "w1s1", week: 1, deload: deload, focus: .fullUpper,
                         title: "Test", exercises: ex, kcal: nil, avgHeartRate: nil, maxHeartRate: nil, muscleLoad: [:])
}

@Suite struct BlockReviewTests {
    let profile = Profile(goal: .strength, sessionsPerWeek: 3, experience: .beginner, climbingDaysPerWeek: 0)

    /// Previous block (weeks −4…−1) and this block (weeks 0…3), 3 workouts a week.
    func history(benchStart: Double, benchStep: Double, row: Double = 50) -> [WorkoutRecord] {
        var out: [WorkoutRecord] = []
        for w in 0..<8 {
            let bench: Double = benchStart + benchStep * Double(w)
            let squat: Double = 80 + Double(w) * 2.5
            for d in [0, 2, 4] {
                out.append(workout(day(7 * (w - 4) + d), [("bench-press", 4, bench), ("barbell-row", 4, row), ("back-squat", 4, squat)]))
            }
        }
        return out
    }

    @Test func strongerConsistentBlockLevelsUp() throws {
        let r = try #require(Growth.review(records: history(benchStart: 60, benchStep: 2.5), blockStart: monday, profile: profile,
                                           level: 2, number: 3, calendar: utc))
        #expect(r.sessionsDone == 12)
        #expect(r.sessionsPlanned == 12)
        #expect((r.strengthChange ?? 0) > 0.02)
        #expect(r.levelUp)
        #expect(r.level == 3)
        // Level 3 crosses into intermediate.
        #expect(r.experience == .intermediate)
        #expect(r.blockKey == "2026-09-07")
    }

    @Test func flatLiftIsAPlateauWithASwap() throws {
        let r = try #require(Growth.review(records: history(benchStart: 60, benchStep: 0), blockStart: monday, profile: profile,
                                           level: 2, number: 1, calendar: utc))
        let bench = try #require(r.plateaus.first { $0.exerciseId == "bench-press" })
        #expect(bench.weeks >= 3)
        #expect(bench.swapTo != nil && bench.swapTo != "bench-press")
        #expect(!r.plateaus.contains { $0.exerciseId == "back-squat" })
    }

    @Test func skippedBlockDoesNotLevelUp() throws {
        let few = history(benchStart: 60, benchStep: 2.5).enumerated().filter { $0.offset < 12 || $0.offset % 3 == 0 }.map(\.element)
        let r = try #require(Growth.review(records: few, blockStart: monday, profile: profile, level: 2, number: 1, calendar: utc))
        #expect(r.sessionsDone == 4)
        #expect(!r.levelUp)
        #expect(r.experience == nil)
    }

    @Test func tooLittleDataGivesNoReview() {
        #expect(Growth.review(records: [workout(day(1), [("bench-press", 3, 60)])], blockStart: monday, profile: profile,
                              level: 1, number: 1, calendar: utc) == nil)
    }

    @Test func laggingGroupAgainstItsCounterpart() throws {
        var recs: [WorkoutRecord] = []
        for w in 0..<4 { for d in [0, 2] { recs.append(workout(day(7 * w + d), [("bench-press", 5, 60), ("barbell-row", 2, 50)])) } }
        let r = try #require(Growth.review(records: recs, blockStart: monday, profile: profile, level: 1, number: 1, calendar: utc))
        #expect(r.lagging == .back)
        #expect(r.laggingVs == .chest)
        let next = profile.growing(r, levelUp: true, focus: true)
        #expect(next.focusMuscles == [.back])
        var focused = profile
        focused.focusMuscles = [.back]
        let again = try #require(Growth.review(records: recs, blockStart: monday, profile: focused, level: 1, number: 1, calendar: utc))
        #expect(again.lagging == nil)
    }

    @Test func experienceBands() {
        #expect(Growth.experience(forLevel: 1) == .beginner)
        #expect(Growth.experience(forLevel: 3) == .intermediate)
        #expect(Growth.experience(forLevel: 6) == .advanced)
        #expect(Growth.startLevel(.intermediate) == 3)
    }
}

@Suite struct GrowthGoalTests {
    /// Bench 60 → 67.5 kg (×5 reps) over 4 weeks, weekly.
    let records = (0..<4).map { w in workout(day(7 * w), [("bench-press", 3, 60 + 2.5 * Double(w))]) }

    @Test func statusPredictsFromTheTrend() {
        let goal = GrowthGoal(exerciseId: "bench-press", targetKg: 90, startKg: 70, startDate: day(0))
        let st = goal.status(records: records, now: day(22), calendar: utc)
        let current = 67.5 * (1 + 5.0 / 30)
        #expect(abs((st.currentKg ?? 0) - current) < 0.01)
        #expect(st.progress > 0.4 && st.progress < 0.6)
        #expect(!st.reached)
        #expect((st.kgPerWeek ?? 0) > 2.5)
        let predicted = st.predicted ?? .distantPast
        #expect(predicted > day(22))
        #expect(st.milestones.map(\.kg) == [70, 80, 90, 100])
        #expect(st.milestones[0].reachedAt != nil)
        #expect(st.milestones.last?.beyond == true)
    }

    @Test func flatTrendHasNoPrediction() {
        let flat = (0..<4).map { w in workout(day(7 * w), [("bench-press", 3, 60)]) }
        let goal = GrowthGoal(exerciseId: "bench-press", targetKg: 90, startKg: 70, startDate: day(0))
        #expect(goal.status(records: flat, now: day(22), calendar: utc).predicted == nil)
    }

    @Test func suggestsTheMostTrainedMainLift() throws {
        let g = try #require(GrowthGoal.suggest(records: records, now: day(22), calendar: utc))
        #expect(g.exerciseId == "bench-press")
        #expect(g.targetKg.truncatingRemainder(dividingBy: 5) == 0)
        #expect(g.targetKg > g.startKg)
        #expect(g.next(now: day(30)).targetKg > g.targetKg)
        #expect(g.next(now: day(30)).startKg == g.targetKg)
    }

    @Test func goalHitIsNoticed() {
        let goal = GrowthGoal(exerciseId: "bench-press", targetKg: 75, startKg: 70, startDate: day(0))
        let ins = Noticed.week(records: records, sets: [], profile: Profile(), goal: goal, now: day(22), calendar: utc)
        #expect(ins.first?.kind == .goalHit)
    }
}

@Suite struct NoticedTests {
    @Test func skippedWeekdayWithAMoveSuggestion() throws {
        var p = Profile(sessionsPerWeek: 3, climbingDaysPerWeek: 0)
        p.gymWeekdays = [1, 3, 5]
        // 5 weeks before day(35): Mon, Wed and Sat trained; Friday never.
        var recs: [WorkoutRecord] = []
        for w in 0..<5 { for d in [0, 2, 5] { recs.append(workout(day(7 * w + d), [("bench-press", 3, 60)])) } }
        let ins = try #require(Noticed.skippedDay(records: recs, profile: p, now: day(36), calendar: utc))
        #expect(ins.weekday == 5)
        #expect(ins.toWeekday == 6)
        #expect(ins.value == "5/5")
    }

    @Test func longRestsFromSetTimes() throws {
        let start = day(20)
        let sets = (0..<8).map { SetLog(date: start.addingTimeInterval(Double($0) * 200), exerciseId: "bench-press", sessionId: "w1s1", kg: 60) }
        let ins = try #require(Noticed.longRests(sets: sets, plannedRest: ["bench-press": 120], now: day(21)))
        #expect(ins.value == "+80s")
        #expect(Noticed.longRests(sets: sets, plannedRest: ["bench-press": 180], now: day(21)) == nil)
    }

    @Test func untrainedGroup() throws {
        let recs: [WorkoutRecord] = (0..<3).map { workout(day(10 + $0), [("bench-press", 3, 60), ("barbell-row", 3, 50)]) }
        let ins = try #require(Noticed.untrained(records: recs, now: day(14), calendar: utc))
        #expect(ins.group == .legs)
    }

    @Test func newBests() throws {
        let recs = [workout(day(0), [("bench-press", 3, 60)]), workout(day(10), [("bench-press", 3, 65)])]
        let ins = try #require(Noticed.bests(records: recs, now: day(11), calendar: utc))
        #expect(ins.value == "1")
    }
}

@Suite struct CoachMemoryTests {
    @Test func factsIncludeGoalAndNotes() {
        let goal = GrowthGoal(exerciseId: "bench-press", targetKg: 80, startKg: 70, startDate: day(0))
        var p = Profile(sessionsPerWeek: 3, climbingDaysPerWeek: 0)
        p.focusMuscles = [.back]
        let facts = CoachMemory.facts(profile: p, goal: goal, goalStatus: nil, level: 4, liked: ["barbell-row"], avoided: [],
                                      notes: ["Left knee: no deep lunges", "  "])
        #expect(facts.first == "Working toward Barbell bench press 80 kg est. 1RM")
        #expect(facts.contains("Growth level 4"))
        #expect(facts.contains("Focus muscles: Back"))
        #expect(facts.contains("Likes Barbell row"))
        #expect(facts.last == "Left knee: no deep lunges")
    }
}
