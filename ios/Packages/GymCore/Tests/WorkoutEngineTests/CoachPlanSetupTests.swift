import Foundation
import Testing
@testable import WorkoutEngine

/// Set up the plan with Coach (#873): Coach's draft lands on the form's values, out-of-range answers fall back.
@Suite struct CoachPlanSetupTests {
    @Test func draftFillsTheForm() {
        var base = Profile()
        base.equipment = [.dumbbells, .bench]
        let d = CoachPlanDraft(goal: "build", experience: "beginner", sessions: 4, weekdays: [6, 2, 4, 1, 2], minutes: 60,
                               protect: .init(area: "knee", side: "right", level: "loaded"), summary: "Muscle and fat loss, 4 days.")
        let p = d.applied(to: base)
        #expect(p.goal == .build)
        #expect(p.experience == .beginner)
        #expect(p.sessionsPerWeek == 4)
        #expect(p.gymWeekdays == [1, 2, 4, 6])
        #expect(p.maxSessionMinutes == 60)
        #expect(p.equipment == [.dumbbells, .bench])
        #expect(!p.climbs)
        #expect(d.pain()?.spot == "right knee")
        #expect(d.pain()?.level == .loaded)
    }

    @Test func unknownValuesFallBack() {
        let d = CoachPlanDraft(goal: "yoga", experience: "pro", sessions: 9, weekdays: [0, 8], minutes: 50, climbs: true, climbDays: 7, protect: .init(area: "toe"))
        let p = d.applied(to: Profile())
        #expect(p.goal == .balanced)
        #expect(p.experience == .beginner)
        #expect(p.sessionsPerWeek == 6)
        #expect(p.gymWeekdays == nil)
        #expect(p.maxSessionMinutes == nil)
        #expect(p.climbingDaysPerWeek == 4)
        #expect(d.pain() == nil)
        #expect(CoachPlanDraft(goal: "build", experience: "beginner", sessions: 3, protect: .init(area: "lower-back", side: "left", level: "x")).pain()?.spot == "lower back")
    }

    @Test func helpPickOnlyFromOptions() {
        let ask = CoachPlanHelpAsk(step: "Goal", options: [.init(id: "strength", label: "Strength"), .init(id: "build", label: "Muscle")],
                                   so: CoachPlanHelpAsk.soFar(Profile()))
        #expect(CoachPlanHelp(answer: "Strength.", pick: "strength").pick(in: ask)?.label == "Strength")
        #expect(CoachPlanHelp(answer: "Hmm.", pick: "endurance").pick(in: ask) == nil)
        #expect(ask.so.contains("3 gym days a week"))
    }
}
