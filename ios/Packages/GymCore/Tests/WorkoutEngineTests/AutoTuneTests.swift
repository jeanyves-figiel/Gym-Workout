import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct AutoTuneTests {
    let profile = Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0)
    var session: Session { Generator.generateWeek(profile, week: 2, seed: 3).sessions[0] }

    @Test func shortSleepAndLowHRVGoMediumOrLight() {
        let v = AutoTune.assess(TuneInputs(hrv: 41, hrvBaseline: 54, sleepHours: 5.7))
        // 80 − 24 (HRV) − 13 (sleep) = 43.
        #expect(v.score == 43)
        #expect(v.level == .light)
        #expect(v.reason.hasPrefix("HRV low"))
        let ok = AutoTune.assess(TuneInputs(hrv: 52, hrvBaseline: 54, sleepHours: 6.5))
        #expect(ok.level == .medium)
    }

    @Test func freshMemberPushesOnlyWithHealthData() {
        let fresh = AutoTune.assess(TuneInputs(hrv: 62, hrvBaseline: 54, restingHR: 50, restingHRBaseline: 52, sleepHours: 8.2))
        #expect(fresh.level == .push)
        #expect(AutoTune.assess(TuneInputs(lastRIR: 3)).level == .medium)
        #expect(AutoTune.assess(TuneInputs()).score == 80)
    }

    @Test func soreGroupsLowerTheScore() {
        let v = AutoTune.assess(TuneInputs(daysInARow: 3, sore: [.legs, .hips]))
        #expect(v.score == 80 - 12 - 12)
        #expect(v.factors.contains { $0.id == "sore" && $0.detail == "Hips & glutes, Legs" })
    }

    @Test func lightDropsAccessorySetsAndEasesTheMainLift() {
        let s = session
        let t = s.autoTuned(.light, sore: [], profile: profile)
        #expect(!t.changes.isEmpty)
        #expect(t.changes.contains { $0.kind == .dropSet })
        #expect(t.session.blocks.flatMap(\.items).map(\.prescription.sets).reduce(0, +)
                < s.blocks.flatMap(\.items).map(\.prescription.sets).reduce(0, +))
        #expect(t.session.estMin <= s.estMin)
    }

    @Test func pushAddsAMainSetButNotInDeload() throws {
        let s = session
        let t = s.autoTuned(.push, sore: [], profile: profile)
        let add = try #require(t.changes.first)
        #expect(t.changes.count == 1)
        #expect(add.kind == .addSet)
        #expect(add.toSets == (add.fromSets ?? 0) + 1)
        #expect(s.autoTuned(.push, sore: [], profile: profile, deload: true).changes.isEmpty)
        #expect(s.autoTuned(.medium, sore: [], profile: profile).changes.isEmpty)
    }

    @Test func soreMusclesSwapAway() throws {
        let s = session
        let sore: Set<MuscleGroup> = [.chest, .legs, .back, .hips]
        let t = s.autoTuned(.medium, sore: sore, profile: profile)
        #expect(!t.changes.isEmpty)
        for c in t.changes where c.kind == .swap {
            let to = try #require(c.to.flatMap { Exercise.find($0) })
            #expect(Set(to.primary.map(\.group)).isDisjoint(with: sore))
        }
    }

    @Test func undoneChangesStayOut() throws {
        let s = session
        let all = s.autoTuned(.light, sore: [], profile: profile).changes
        let first = try #require(all.first)
        let again = s.autoTuned(.light, sore: [], profile: profile, undone: [first.id])
        #expect(again.changes.count == all.count - 1)
        #expect(!again.changes.contains(first))
    }

    @Test func planTunesOnlyTheGivenSessions() {
        let plan = Generator.generateWeek(profile, week: 2, seed: 3)
        let t = plan.autoTuned([plan.sessions[1].id], level: .light, sore: [], profile: profile)
        #expect(t.plan.sessions[0] == plan.sessions[0])
        #expect(t.plan.sessions[1] != plan.sessions[1])
    }
}
