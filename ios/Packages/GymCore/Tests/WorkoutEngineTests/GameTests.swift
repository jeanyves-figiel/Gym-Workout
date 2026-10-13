import Foundation
import Testing
@testable import WorkoutEngine

private let utc = Progression.calendar(TimeZone(identifier: "UTC")!)
private let monday = ISO8601DateFormatter().date(from: "2026-09-07T10:00:00Z")! // a Monday

private func record(_ s: Session, at date: Date) -> WorkoutRecord {
    var done: [String: Int] = [:]
    for b in s.blocks { for it in b.items { done[it.uid] = it.prescription.sets } }
    return WorkoutRecord.build(session: s, week: 1, deload: false, setsDone: done, weights: [:],
                               startedAt: date, endedAt: date.addingTimeInterval(3600), bodyMassKg: 70)
}

@Suite struct GameTests {
    let plan = Generator.generateWeek(Profile(sessionsPerWeek: 2), seed: 3)

    @Test func emptyHistoryIsLevelOne() {
        let g = GameProgress.evaluate(records: [], targetPerWeek: 2, calendar: utc)
        #expect(g.xp == 0)
        #expect(g.level == 1)
        #expect(g.xpToNext == GameProgress.perLevel)
    }

    @Test func workoutXPIsFiftyPlusFivePerSet() {
        #expect(GameProgress.xp(sets: 0) == 50)
        #expect(GameProgress.xp(sets: 18) == 140)
        let r = record(plan.sessions[0], at: monday)
        let g = GameProgress.evaluate(records: [r], targetPerWeek: 2, calendar: utc)
        #expect(g.xp == GameProgress.xp(sets: r.totalSets))
        #expect(g.weeksCleared == 0)
    }

    @Test func meetingTheWeekGoalAddsTheChestBonus() {
        let a = record(plan.sessions[0], at: monday)
        let b = record(plan.sessions[1], at: monday.addingTimeInterval(2 * 86_400))
        let before = GameProgress.evaluate(records: [a], targetPerWeek: 2, calendar: utc)
        let after = GameProgress.evaluate(records: [a, b], targetPerWeek: 2, calendar: utc)
        #expect(after.weeksCleared == 1)
        #expect(after.xp == before.xp + GameProgress.xp(sets: b.totalSets) + GameProgress.weekBonus)
        let reward = GameReward(before: before, after: after, badgesBefore: [], badgesAfter: [])
        #expect(reward.weekCleared)
        #expect(reward.xp == GameProgress.xp(sets: b.totalSets) + GameProgress.weekBonus)
    }

    @Test func levelUpAndNewBadgesAreReported() {
        let before = GameProgress(xp: 480)
        let after = GameProgress(xp: 620)
        let first = Achievements.evaluate(records: [record(plan.sessions[0], at: monday)], weights: [], targetPerWeek: 2, calendar: utc)
        let reward = GameReward(before: before, after: after, badgesBefore: [], badgesAfter: first)
        #expect(reward.levelUp == 2)
        #expect(reward.badges.contains { $0.id == "first" })
        #expect(GameReward(before: after, after: after, badgesBefore: first, badgesAfter: first).badges.isEmpty)
    }
}
