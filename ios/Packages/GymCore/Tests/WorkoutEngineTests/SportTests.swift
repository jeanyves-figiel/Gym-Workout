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

/// Session page analysis (#416, A + C).
@Suite struct SportTrackTests {
    private func track(_ alts: [Double], speed: Double = 10) -> SportTrack {
        let t0 = Date(timeIntervalSince1970: 0)
        return SportTrack(points: alts.enumerated().map { i, a in
            SportTrack.Point(lat: 46, lon: 9 + Double(i) * 0.001, alt: a, speed: speed, time: t0.addingTimeInterval(Double(i) * 10))
        })
    }

    @Test func runsSplitAtLifts() {
        let up = stride(from: 0.0, through: 300, by: 20).map { $0 }
        let down = stride(from: 300.0, through: 0, by: -20).map { $0 }
        let down2 = stride(from: 300.0, through: 50, by: -25).map { $0 }
        let runs = track(up + down + up + down2).runs()
        #expect(runs.count == 2)
        #expect(runs.map(\.drop) == [300, 250])
        #expect(runs[0].topKmh == 36)
    }

    @Test func verticalIgnoresNoise() {
        let v = track([100, 101, 99, 100, 150, 120]).vertical()
        #expect(v.up == 50)
        #expect(v.down == 30)
        #expect(track([100, 150]).highest == 150)
    }

    @Test func topSpeedIgnoresOneJump() {
        var t = track(Array(repeating: 100, count: 5), speed: 5)
        t.points[2].speed = 60
        #expect(t.topKmh == 18)
    }

    @Test func thinnedKeepsEnds() {
        let t = track((0..<2000).map(Double.init)).thinned(max: 100)
        #expect(t.points.count == 100)
        #expect(t.points.first?.alt == 0 && t.points.last?.alt == 1999)
        #expect(t.index(near: Date(timeIntervalSince1970: 0)) == 0)
    }
}
