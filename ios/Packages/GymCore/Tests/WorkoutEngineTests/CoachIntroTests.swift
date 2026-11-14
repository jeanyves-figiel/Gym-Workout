import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct CoachIntroTests {
    @Test func asksInOrderAndSkipsDietWithoutFuel() {
        var a = CoachIntroAnswers()
        #expect(a.next == .goal)
        a.goal = .strength; a.answer(.goal)
        a.days = 4; a.answer(.days)
        a.minutes = 45; a.answer(.minutes)
        a.experience = .beginner; a.answer(.experience)
        #expect(a.next == .level)
        a.level = .workouts; a.answer(.level)
        #expect(a.next == nil)
        #expect(a.fraction == 1)
        a.level = .everything
        #expect(a.next == .diet)
    }

    @Test func undoClearsLastAnswer() {
        var a = CoachIntroAnswers()
        a.goal = .build; a.answer(.goal)
        a.days = 5; a.answer(.days)
        a.undoLast()
        #expect(a.days == nil)
        #expect(a.next == .days)
        #expect(a.goal == .build)
    }

    @Test func appliesToProfile() {
        var a = CoachIntroAnswers()
        a.goal = .strength; a.answer(.goal)
        a.days = 5; a.answer(.days)
        a.minutes = nil; a.answer(.minutes)
        a.experience = .advanced; a.answer(.experience)
        var p = Profile()
        p.maxSessionMinutes = 40
        a.apply(to: &p)
        #expect(p.goal == .strength)
        #expect(p.sessionsPerWeek == 5)
        #expect(p.maxSessionMinutes == nil)
        #expect(p.experience == .advanced)
    }

    @Test func buildStepsFollowLevel() {
        var a = CoachIntroAnswers()
        a.goal = .build; a.days = 4; a.minutes = 60; a.level = .workouts
        let s = CoachIntro.buildSteps(a, gymName: "Puls 5", machines: 62)
        #expect(s.contains("4 days × 60 min"))
        #expect(s.contains("62 machines at Puls 5"))
        #expect(!s.contains { $0.hasPrefix("Fuel") })
        a.level = .everything
        let all = CoachIntro.buildSteps(a, gymName: nil, machines: 0)
        #expect(all.contains { $0.hasPrefix("Fuel") })
        #expect(all.contains("Mind: daily check-in"))
    }

    @Test func everyAnswerGetsAReaction() {
        var a = CoachIntroAnswers()
        for q in CoachIntroQuestion.allCases {
            #expect(!CoachIntro.question(q).isEmpty)
            #expect(!CoachIntro.reaction(q, a).isEmpty)
        }
        a.days = 2
        #expect(CoachIntro.reaction(.days, a).hasPrefix("2 days"))
    }
}
