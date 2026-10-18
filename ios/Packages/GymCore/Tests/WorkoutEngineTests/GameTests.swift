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

    @Test func recentWeeksShowEachChestAndItsXP() {
        let a = record(plan.sessions[0], at: monday)
        let b = record(plan.sessions[1], at: monday.addingTimeInterval(2 * 86_400))
        let c = record(plan.sessions[0], at: monday.addingTimeInterval(7 * 86_400))
        let now = monday.addingTimeInterval(8 * 86_400)
        let weeks = GameWeek.recent(records: [a, b, c], targetPerWeek: 2, count: 8, now: now, calendar: utc)
        #expect(weeks.count == 8)
        #expect(weeks.last?.weekStart == Progression.weekStart(now, utc))
        #expect(weeks[6].chestOpen && weeks[6].sessions == 2)
        #expect(weeks[6].workoutXP == GameProgress.xp(sets: a.totalSets) + GameProgress.xp(sets: b.totalSets))
        #expect(weeks[6].chestXP == GameProgress.weekBonus)
        #expect(!weeks[7].chestOpen && weeks[7].sessions == 1 && weeks[7].chestXP == 0)
        #expect(weeks.prefix(6).allSatisfy { $0.sessions == 0 && !$0.chestOpen })
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

    @Test func ladderRanksStartAtTheirLevels() {
        let at = { (level: Int) in GameProgress(xp: (level - 1) * GameProgress.perLevel).rank }
        #expect(at(1) == "Rookie")
        #expect(at(2) == "Rookie")
        #expect(at(3) == "Regular")
        #expect(at(7) == "Regular")
        #expect(at(8) == "Iron")
        #expect(at(15) == "Steel")
        #expect(at(24) == "Steel")
        #expect(at(25) == "Titan")
        #expect(at(40) == "Legend")
    }
}
