import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct AutoTuneTests {
    let profile = Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0)
    var session: Session { Generator.generateWeek(profile, week: 2, seed: 3).sessions[0] }

    func totalSets(_ s: Session) -> Int {
        var n = 0
        for b in s.blocks { for it in b.items { n += it.prescription.sets } }
        return n
    }

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
        let tunedSets: Int = totalSets(t.session)
        let plannedSets: Int = totalSets(s)
        #expect(tunedSets < plannedSets)
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

    /// HRV flag follows each member's own day-to-day swing (#978, Plews 2012): a steady HRV flags a small drop, a
    /// noisy one needs a bigger drop; the 85 % floor stands in until a week of readings.
    @Test func hrvFlagUsesTheSmallestWorthwhileChange() throws {
        let steady = try #require(HRVFlag.lnSD(daily: [60, 62, 58, 61, 59, 60, 60]))
        #expect(abs(steady - 0.0215) < 0.001)
        #expect(HRVFlag.isLow(week: 57, baseline: 60, lnSD: steady))
        #expect(!HRVFlag.isLow(week: 59.8, baseline: 60, lnSD: steady))
        let noisy = try #require(HRVFlag.lnSD(daily: [40, 80, 45, 75, 50, 70, 60]))
        #expect(abs(HRVFlag.threshold(lnSD: noisy) - 0.875) < 0.001)
        #expect(!HRVFlag.isLow(week: 54, baseline: 60, lnSD: noisy))
        #expect(HRVFlag.isLow(week: 50, baseline: 60, lnSD: noisy))
        #expect(HRVFlag.lnSD(daily: [60, 62, 58, 61, 59, 60]) == nil)
        #expect(HRVFlag.threshold(lnSD: nil) == HRVFlag.fallbackFloor)
        #expect(HRVFlag.isLow(week: 50, baseline: 60, lnSD: nil) && !HRVFlag.isLow(week: 52, baseline: 60, lnSD: nil))
        #expect(!HRVFlag.isLow(week: 50, baseline: 0, lnSD: nil))
    }

    @Test func hrvDailyValuesAverageEachDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d0 = Date(timeIntervalSince1970: 1_700_000_000)
        let readings: [(date: Date, value: Double)] = [(d0, 50), (d0.addingTimeInterval(3_600), 70),
                                                      (d0.addingTimeInterval(86_400), 40), (d0.addingTimeInterval(-86_400), 0)]
        #expect(HRVFlag.dailyValues(readings, calendar: cal) == [60, 40])
    }
}
