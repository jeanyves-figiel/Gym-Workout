import Foundation
import Testing
@testable import WorkoutEngine

/// Changing one planned workout's focus (#342): this workout only, or every week.
@Suite struct SessionFocusTests {
    private func profile(sessions: Int = 4, climbing: [Int]? = nil) -> Profile {
        var p = Profile(experience: .intermediate, climbingDaysPerWeek: 0)
        p.applyGoal(.build)
        p.sessionsPerWeek = sessions
        p.climbingWeekdays = climbing
        return p
    }

    @Test func thisWorkoutOnlyChangesThatSession() {
        for week in 1...4 {
            let p = profile(climbing: [2, 5])
            let plan = Generator.generateWeek(p, week: week, seed: 11)
            let target = plan.sessions[1]
            let other: Focus = target.focus == .push ? .pull : .push
            var q = p
            q.sessionFoci = [target.id: other]
            let changed = Generator.generateWeek(q, week: week, seed: 11)
            #expect(changed.sessions[1].focus == other)
            #expect(changed.sessions[1].weekday == target.weekday)
            #expect(changed.sessions[1].id == target.id)
            for i in plan.sessions.indices where i != 1 {
                #expect(changed.sessions[i] == plan.sessions[i], "week \(week) session \(i)")
            }
        }
    }

    @Test func otherWeeksIgnoreTheOverride() {
        let p = profile()
        var q = p
        q.sessionFoci = ["w1s1": .conditioning]
        #expect(Generator.generateWeek(q, week: 2, seed: 4) == Generator.generateWeek(p, week: 2, seed: 4))
    }

    @Test func overrideWithStyleKeepsBoth() {
        var p = profile()
        p.sessionFoci = ["w1s2": .backBi]
        p.sessionStyles = ["w1s2": SessionStyle(rest: .short)]
        let s = Generator.generateWeek(p, week: 1, seed: 9).sessions[1]
        #expect(s.focus == .backBi)
    }

    @Test func weekOrderMatchesThePlan() {
        for climbing in [nil, [2, 5], [6]] as [[Int]?] {
            for n in 2...6 {
                for week in 1...4 {
                    var p = profile(sessions: n, climbing: climbing)
                    for v in [PlanVariety.fresh, .rotate] {
                        p.variety = v
                        let plan = Generator.generateWeek(p, week: week, seed: 5)
                        #expect(Generator.weekOrder(p, week: week) == plan.sessions.map(\.focus), "\(n) \(week) \(v)")
                    }
                }
            }
        }
    }

    @Test func everyWeekChangesOnlyThatDay() {
        let p = profile(climbing: [2, 5])
        let plan = Generator.generateWeek(p, week: 1, seed: 3)
        var q = p
        let other: Focus = plan.sessions[2].focus == .posterior ? .chestTri : .posterior
        q.setPlanDay(2, to: other, week: 1)
        #expect(q.customSplit)
        var expected = plan.sessions.map(\.focus)
        expected[2] = other
        for week in 1...4 {
            #expect(Generator.generateWeek(q, week: week, seed: 3).sessions.map(\.focus) == expected)
        }
    }

    @Test func climbWarningOnlyForPullingNextToClimbing() {
        let prefs = ClimbPrefs()
        #expect(WeekSchedule.climbWarning(.pull, on: 4, climbing: [5], prefs: prefs) != nil)
        #expect(WeekSchedule.climbWarning(.backBi, on: 6, climbing: [5], prefs: prefs) != nil)
        #expect(WeekSchedule.climbWarning(.push, on: 4, climbing: [5], prefs: prefs) == nil)
        #expect(WeekSchedule.climbWarning(.pull, on: 2, climbing: [5], prefs: prefs) == nil)
        #expect(WeekSchedule.climbWarning(.pull, on: 4, climbing: [5], prefs: ClimbPrefs(before: .any)) == nil)
    }
}
