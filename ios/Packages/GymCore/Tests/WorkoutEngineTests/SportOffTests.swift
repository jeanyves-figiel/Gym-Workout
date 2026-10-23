import Foundation
import Testing
@testable import WorkoutEngine

private let cal: Calendar = {
    var c = Calendar(identifier: .iso8601)
    c.timeZone = TimeZone(identifier: "Europe/Zurich")!
    return c
}()

/// Monday 12 Oct 2026.
private let monday = PlanCalendar.date("2026-10-12", cal)!

/// A sport day turned into a rest day, and moves in later weeks (#671).
@Suite struct SportOffTests {
    @Test func restDayDropsWeeklySportAndTripThatDayOnly() {
        var p = Profile(goal: .balanced, sessionsPerWeek: 3)
        p.sports = [SportPlan(sport: .roadBike, weekdays: [3])]
        p.sportTrips = [SportTrip(sport: .snowboard, start: "2026-10-16", end: "2026-10-18")]
        p.sportOff = ["2026-10-14", "2026-10-17"]
        #expect(p.sportDays(on: monday, calendar: cal).map(\.weekday) == [5, 7])
        #expect(p.sport(onWeekday: 3, key: "2026-10-14") == nil)
        #expect(p.sport(onWeekday: 3, key: "2026-10-21") == .roadBike)
        #expect(p.sportTrip(on: "2026-10-17") == nil)
        #expect(p.sportTrip(on: "2026-10-18")?.sport == .snowboard)
        let w = PlanCalendar.adapt(p, week: 1, seed: 4, weekStart: monday, away: [], calendar: cal)
        #expect(Set(w.trips.keys) == [5, 7])
    }

    @Test func restDayDropsClimbing() {
        var p = Profile(goal: .climbing, sessionsPerWeek: 3, climbingDaysPerWeek: 2, climbingWeekdays: [2, 5])
        #expect(p.sport(onWeekday: 2, key: "2026-10-13") == .climbing)
        p.sportOff = ["2026-10-13"]
        #expect(p.sport(onWeekday: 2, key: "2026-10-13") == nil)
        let w = PlanCalendar.adapt(p, week: 1, seed: 4, weekStart: monday, away: [], calendar: cal)
        #expect(w.climbing == [5])
    }

    @Test func laterWeekMovesKeepTheirDay() throws {
        let p = Profile(goal: .balanced, sessionsPerWeek: 3, gymWeekdays: [1, 3, 5])
        let plain = PlanCalendar.weeks(p, seed: 4, currentWeek: 1, current: nil, done: [], away: [], now: monday, count: 2, calendar: cal)
        let s = try #require(plain[1].plan.sessions.first { $0.weekday != nil })
        let from = try #require(s.weekday)
        let to = from == 7 ? 6 : from + 1
        let nextMonday = PlanCalendar.key(plain[1].start, cal)
        let moved = PlanCalendar.weeks(p, seed: 4, currentWeek: 1, current: nil, done: [], away: [], now: monday, count: 2, calendar: cal,
                                       laterFixed: [nextMonday: [s.id: to]])
        #expect(moved[1].plan.sessions.first { $0.id == s.id }?.weekday == to)
        // This week is left alone.
        #expect(moved[0].plan.sessions.map(\.weekday) == plain[0].plan.sessions.map(\.weekday))
    }
}
