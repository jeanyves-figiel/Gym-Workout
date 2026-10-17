import Foundation
import Testing
@testable import WorkoutEngine

/// Other sports planned around like climbing days (#416).
@Suite struct SportTests {
    private func profile(_ sessions: Int, _ sports: [SportPlan]) -> Profile {
        var p = Profile(goal: .balanced, sessionsPerWeek: sessions, experience: .intermediate, climbingDaysPerWeek: 0)
        p.sports = sports
        return p
    }

    @Test func noSportsPlansAsBefore() {
        var p = profile(3, [])
        let none = Generator.generateWeek(p, seed: 4)
        p.sports = nil
        #expect(Generator.generateWeek(p, seed: 4) == none)
        #expect(p.climbPrefs == ClimbPrefs())
    }

    @Test func legDaysKeptAwayFromSnowboardDays() {
        let p = profile(3, [SportPlan(sport: .snowboard, weekdays: [6, 7])])
        let plan = Generator.generateWeek(p, seed: 9)
        #expect(plan.sessions.allSatisfy { $0.weekday != nil })
        for s in plan.sessions {
            let day = s.weekday!
            #expect(day != 6 && day != 7)
            if day == 5 { #expect(WeekSchedule.legDemand(s.focus) < 3) }
        }
    }

    @Test func divingKeepsTheDayAfterFree() {
        let sp = SportPlan(sport: .scubaDiving, weekdays: [6], sameDay: .allow)
        let day = sp.days(on: Date()).first!
        #expect(day.after == .rest && day.sameDay == .avoid)
        let plan = Generator.generateWeek(profile(3, [sp]), seed: 2)
        #expect(plan.sessions.allSatisfy { $0.weekday != 6 && $0.weekday != 7 })
    }

    @Test func outOfSeasonIgnored() {
        let months = [12, 1, 2, 3]
        let sp = SportPlan(sport: .ski, weekdays: [6], seasonMonths: months)
        let cal = Calendar(identifier: .gregorian)
        let july = cal.date(from: DateComponents(year: 2026, month: 7, day: 10))!
        let jan = cal.date(from: DateComponents(year: 2027, month: 1, day: 10))!
        #expect(sp.days(on: july).isEmpty)
        #expect(sp.days(on: jan).map(\.weekday) == [6])
    }

    @Test func notesAndWarnings() {
        let days = [SportDay(weekday: 6, sport: .mountainBike)]
        #expect(WeekSchedule.note(weekday: 5, climbing: [], prefs: ClimbPrefs(sports: days)) == "MTB tomorrow · legs kept light")
        #expect(WeekSchedule.note(weekday: 7, climbing: [], prefs: ClimbPrefs(sports: days)) == "Day after MTB")
        #expect(WeekSchedule.climbWarning(.legs, on: 5, climbing: [], prefs: ClimbPrefs(sports: days)) != nil)
        #expect(WeekSchedule.climbWarning(.push, on: 5, climbing: [], prefs: ClimbPrefs(sports: days)) == nil)
    }

    @Test func roundTripAndEvent() throws {
        let p = profile(3, [SportPlan(sport: .hyrox, weekdays: [3], eventDate: "2027-03-14", before: .strong)])
        #expect(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p)) == p)
        #expect(p.sports?.first?.event != nil)
        #expect(Sport.climbing.loadLabel == "grip · pull")
        #expect(Sport.snowboard.loadLabel == "legs")
    }
}
