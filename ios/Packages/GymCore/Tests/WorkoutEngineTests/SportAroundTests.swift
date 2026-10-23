import Foundation
import Testing
@testable import WorkoutEngine

/// Around sport days (#658): choices worded from each sport's load; the day's sport puts dated days first.
@Suite struct SportAroundTests {
    @Test func climbingKeepsItsWords() {
        #expect(Sport.climbing.aroundLabel(.strong) == "Strong push or legs")
        #expect(Sport.climbing.aroundBlurb(.light, before: true) == "No heavy pulling, grip or jumps. Push and legs preferred.")
        #expect(Sport.climbing.sameDayLabel(.avoid) == "Climb only")
    }

    @Test func legSportsSpareLegs() {
        #expect(Sport.run.aroundLabel(.strong) == "Strong upper body")
        #expect(Sport.run.aroundBlurb(.light, before: true) == "No heavy legs or jumps. Upper body preferred.")
        #expect(Sport.run.aroundBlurb(.strong, before: true) == "Hard upper body day welcome. Only legs kept light.")
        #expect(Sport.snowboard.aroundBlurb(.light, before: false) == "Light on legs while you recover.")
        #expect(Sport.run.aroundBlurb(.any, before: true) == "Plan the gym session as if there were no running.")
        #expect(Sport.run.sameDayLabel(.avoid) == "Run only")
    }

    @Test func otherLoads() {
        #expect(Sport.boxing.aroundLabel(.strong) == "Strong legs or pull")
        #expect(Sport.rowing.aroundLabel(.strong) == "Strong push")
        #expect(Sport.hyrox.aroundLabel(.strong) == "Strong session")
        #expect(Sport.hyrox.aroundBlurb(.strong, before: true) == "Hard gym day welcome, volume kept moderate.")
        #expect(Sport.yoga.isLightLoad)
        #expect(Sport.yoga.aroundBlurb(.light, before: true) == "Moderate session, nothing to failure.")
        for s in Sport.allCases {
            for o in ClimbNeighbour.allCases {
                #expect(!s.aroundLabel(o).isEmpty && !s.aroundBlurb(o, before: true).contains("  "))
            }
        }
    }

    @Test func datedDayBeatsWeeklyClimbing() {
        var p = Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 1, climbingWeekdays: [5])
        p.sports = [SportPlan(sport: .run, weekdays: [2])]
        #expect(p.sport(onWeekday: 5, key: "2026-10-23") == .climbing)
        #expect(p.sport(onWeekday: 2, key: "2026-10-20") == .run)
        #expect(p.sport(onWeekday: 3, key: "2026-10-21") == nil)
        p.sportTrips = [SportTrip(sport: .snowboard, start: "2026-10-23", end: "2026-10-23")]
        #expect(p.sport(onWeekday: 5, key: "2026-10-23") == .snowboard)
    }
}
