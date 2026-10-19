import Foundation
import Testing
@testable import WorkoutEngine

private let utc = Progression.calendar(TimeZone(identifier: "UTC")!)
private let monday = ISO8601DateFormatter().date(from: "2026-09-07T10:00:00Z")! // a Monday
private let day = 86_400.0

private func record(_ s: Session, at date: Date, all: Bool = true, minutes: Double = 60) -> WorkoutRecord {
    var done: [String: Int] = [:]
    for b in s.blocks { for it in b.items { done[it.uid] = all ? it.prescription.sets : (b.kind == .strength ? 1 : 0) } }
    return WorkoutRecord.build(session: s, week: 1, deload: false, setsDone: done, weights: [:],
                               startedAt: date, endedAt: date.addingTimeInterval(minutes * 60), bodyMassKg: 70)
}

private func week(_ i: Int) -> Date { utc.date(byAdding: .weekOfYear, value: i, to: Progression.weekStart(monday, utc))! }

@Suite struct StreakShieldTests {
    @Test func fourGoalWeeksEarnAShieldThatSavesAMissedWeek() {
        // 4 goal weeks, a missed week, then a goal week: the shield keeps the streak (5, not 1).
        let counts: [Date: Int] = [week(0): 2, week(1): 2, week(2): 2, week(3): 2, week(4): 0, week(5): 2]
        let r = StreakRun.evaluate(counts: counts, target: 2, through: week(5), calendar: utc)
        #expect(r.current == 5)
        #expect(r.shields == 0)
        #expect(r.shielded == [week(4)])
        #expect(r.savedWeekBefore(week(5), calendar: utc))
    }

    @Test func withoutAShieldAMissedWeekResets() {
        let counts: [Date: Int] = [week(0): 2, week(1): 2, week(2): 1, week(3): 2]
        let r = StreakRun.evaluate(counts: counts, target: 2, through: week(3), calendar: utc)
        #expect(r.current == 1 && r.best == 2 && r.shielded.isEmpty)
    }

    @Test func thisWeekNeverBreaksTheStreakAndShieldsCapAtTwo() {
        var counts: [Date: Int] = [:]
        for i in 0..<12 { counts[week(i)] = 3 }
        let r = StreakRun.evaluate(counts: counts, target: 3, through: week(12), calendar: utc)
        #expect(r.current == 12 && r.shields == StreakRun.maxShields)
    }

    @Test func statsUseShields() {
        let plan = Generator.generateWeek(Profile(sessionsPerWeek: 1), seed: 2)
        var recs = (0..<4).map { record(plan.sessions[0], at: week($0).addingTimeInterval(3600)) }
        recs.append(record(plan.sessions[0], at: week(5).addingTimeInterval(3600)))
        let s = Progression.stats(records: recs, weights: [], targetPerWeek: 1, now: week(5).addingTimeInterval(7200), calendar: utc)
        #expect(s.currentStreakWeeks == 5)
        #expect(s.streakShields == 0 && s.shieldSavedLastWeek)
    }
}

@Suite struct ComebackTests {
    let plan = Generator.generateWeek(Profile(sessionsPerWeek: 2), seed: 4)

    @Test func tenDaysAwayStartsAQuestOfThreeSessions() {
        let a = record(plan.sessions[0], at: monday)
        let now = monday.addingTimeInterval(12 * day)
        #expect(Comeback.current(records: [a], now: now) == Comeback(daysAway: 12, done: 0))
        let b = record(plan.sessions[0], at: now)
        let c = record(plan.sessions[1], at: now.addingTimeInterval(2 * day))
        let d = record(plan.sessions[0], at: now.addingTimeInterval(4 * day))
        let e = record(plan.sessions[1], at: now.addingTimeInterval(6 * day))
        #expect(Comeback.current(records: [a, b, c], now: now.addingTimeInterval(3 * day))?.done == 2)
        #expect(Comeback.questIds([a, b, c, d, e]) == [b.id, c.id, d.id])
        #expect(Comeback.current(records: [a, b, c, d], now: now.addingTimeInterval(5 * day)) == nil)
        let g = GameProgress.evaluate(records: [a, b, c, d, e], targetPerWeek: 2, calendar: utc)
        #expect(g.comebackXP == 3 * Comeback.xpPerSession)
    }

    @Test func firstSessionEverIsNoComeback() {
        let a = record(plan.sessions[0], at: monday)
        #expect(Comeback.questIds([a]).isEmpty)
        #expect(Comeback.current(records: [], now: monday) == nil)
        #expect(Comeback.current(records: [a], now: monday.addingTimeInterval(3 * day)) == nil)
    }

    @Test func awayAgainAfterAQuestShowsTheWelcomeBack() {
        let a = record(plan.sessions[0], at: monday)
        let b = record(plan.sessions[0], at: monday.addingTimeInterval(15 * day))
        let late = record(plan.sessions[1], at: monday.addingTimeInterval(15 * day + 9 * day))
        #expect(Comeback.questIds([a, b, late]) == [b.id, late.id])
        #expect(Comeback.current(records: [a, b, late], now: monday.addingTimeInterval(40 * day)) == Comeback(daysAway: 16, done: 0))
    }
}

@Suite struct WinsTests {
    let plan = Generator.generateWeek(Profile(sessionsPerWeek: 3), seed: 7)

    @Test func alwaysThreeWinsEvenOnAWeakFirstDay() {
        let r = record(plan.sessions[0], at: monday, all: false, minutes: 18)
        let wins = Wins.find(record: r, history: [r], weights: [], targetPerWeek: 3, calendar: utc)
        #expect(wins.count == 3)
        #expect(Set(wins.map(\.id)).count == 3)
        #expect(wins[0].kind == .sessionCount && wins[0].value == "#1")
        #expect(wins[1].kind == .minutes && wins[1].value == "18")
    }

    @Test func comebackHeavierAndWeekGoalComeFirst() {
        let s = plan.sessions[0]
        let a = record(s, at: monday)
        let b = record(s, at: monday.addingTimeInterval(14 * day))
        let lift = b.exercises.first { $0.category == .strength }!.exerciseId
        let weights = [WeightEntry(exerciseId: lift, date: monday.addingTimeInterval(600), kg: 60, reps: 8),
                       WeightEntry(exerciseId: lift, date: b.startedAt.addingTimeInterval(600), kg: 62.5, reps: 8)]
        let wins = Wins.find(record: b, history: [a, b], weights: weights, targetPerWeek: 1, calendar: utc)
        #expect(wins.map(\.kind) == [.comeback, .heavier, .weekGoal])
        #expect(wins[0].title == "Back after 14 days")
        #expect(wins[1].value == "+2.5" && wins[1].detail.hasPrefix("New best"))
    }

    @Test func moreRepsAtTheSameLoadAndFeelings() {
        let s = plan.sessions[0]
        let a = record(s, at: monday)
        let b = record(s, at: monday.addingTimeInterval(2 * day))
        let lift = b.exercises.first { $0.category == .strength }!.exerciseId
        let weights = [WeightEntry(exerciseId: lift, date: monday.addingTimeInterval(600), kg: 40, reps: 8),
                       WeightEntry(exerciseId: lift, date: b.startedAt.addingTimeInterval(600), kg: 40, reps: 10)]
        let wins = Wins.find(record: b, history: [a, b], weights: weights, targetPerWeek: 3,
                             feels: [.good, .meh, .great, .good], calendar: utc)
        let heavier = wins.first { $0.kind == .heavier }
        #expect(heavier?.value == "+2" && heavier?.unit == "reps")
        #expect(wins.count == 3)
        let feel = Wins.find(record: b, history: [a, b], weights: [], targetPerWeek: 3, feels: [.good, .meh, .great, .good], calendar: utc)
        #expect(feel.contains { $0.kind == .feel && $0.value == "3/4" })
    }
}
