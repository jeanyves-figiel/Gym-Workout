import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct CoachIntroTests {
    @Test func asksInOrderAndSkipsWhatDoesNotApply() {
        var a = CoachIntroAnswers()
        #expect(a.next == .goal)
        a.goal = .strength; a.answer(.goal)
        a.days = 4; a.answer(.days)
        a.answer(.weekdays)
        a.minutes = 45; a.answer(.minutes)
        a.experience = .beginner; a.answer(.experience)
        #expect(a.next == .sports)
        a.answer(.sports)
        #expect(a.next == .focus)
        a.answer(.focus)
        a.answer(.pain)
        a.level = .workouts; a.answer(.level)
        #expect(a.next == .figure)
        a.answer(.figure); a.answer(.pronouns); a.answer(.health); a.answer(.reminder)
        #expect(a.next == nil)
        #expect(a.fraction == 1)
        a.level = .everything
        #expect(a.next == .diet)
        a.sports = [.run]
        #expect(a.questions.contains(.sportDays))
    }

    @Test func appliesWeekdaysSportsAndFocus() {
        var a = CoachIntroAnswers()
        a.goal = .build; a.answer(.goal)
        a.days = 4; a.answer(.days)
        a.weekdays = [5, 1, 3]; a.answer(.weekdays)
        a.sports = [.climbing, .run]; a.answer(.sports)
        a.sportDays = [6, 2]; a.answer(.sportDays)
        a.focus = [.chest]; a.answer(.focus)
        var p = Profile()
        p.climbs = false
        a.apply(to: &p)
        #expect(p.gymWeekdays == [1, 3, 5])
        #expect(p.sessionsPerWeek == 3)
        #expect(p.climbingWeekdays == [2, 6])
        #expect(p.climbingDaysPerWeek == 2)
        #expect(p.sports?.map(\.sport) == [.run])
        #expect(p.sports?.first?.weekdays == [2, 6])
        #expect(p.focusMuscles == [.chest])
        #expect(CoachIntro.toggled([1, 3], 3) == [1])
        #expect(CoachIntro.toggled([3], 1) == [1, 3])
        #expect(CoachIntro.dayList([3, 1]) == "Mon, Wed")
        #expect(CoachIntro.clock(17 * 60 + 30) == "17:30")
    }

    @Test func undoClearsMultiPicks() {
        var a = CoachIntroAnswers()
        a.sports = [.swim]; a.answer(.sports)
        a.sportDays = [2]; a.answer(.sportDays)
        a.undoLast()
        #expect(a.sportDays.isEmpty)
        #expect(a.sports == [.swim])
        a.undoLast()
        #expect(a.sports.isEmpty)
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
        a.sports = [.run]
        a.pain = .knee
        a.reminder = 7 * 60
        a.allergies = [.nuts]
        for q in CoachIntroQuestion.allCases {
            #expect(!CoachIntro.question(q, a).isEmpty)
            #expect(!CoachIntro.reaction(q, a).isEmpty)
        }
        a.days = 2
        #expect(CoachIntro.reaction(.days, a).hasPrefix("2 days"))
        #expect(CoachIntro.reaction(.reminder, a).contains("7:00"))
        #expect(CoachIntro.reaction(.allergies, a) == "No nuts in any recipe.")
    }
}
