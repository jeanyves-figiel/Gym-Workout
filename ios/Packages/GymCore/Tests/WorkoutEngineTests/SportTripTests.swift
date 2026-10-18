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

/// Dated sport days and trips (#474).
@Suite struct SportTripTests {
    @Test func tripNormalisesAndTitles() {
        let t = SportTrip(sport: .snowboard, start: "2026-10-18", end: "2026-10-14")
        #expect(t.start == "2026-10-14" && t.end == "2026-10-18")
        #expect(t.covers("2026-10-14") && t.covers("2026-10-18") && !t.covers("2026-10-19"))
        #expect(t.isTrip && t.title == "Snowboard trip")
        #expect(SportTrip(sport: .run, start: "2026-10-14", end: "2026-10-14").title == "Run day")
        #expect(SportTrip(sport: .ski, start: "2026-10-14", end: "2026-10-16", name: " Laax week ").title == "Laax week")
    }

    @Test func tripDaysJoinTheWeeksSportDays() {
        var p = Profile(goal: .balanced, sessionsPerWeek: 3)
        p.sports = [SportPlan(sport: .roadBike, weekdays: [3])]
        p.sportTrips = [SportTrip(sport: .snowboard, start: "2026-10-16", end: "2026-10-18")]
        let days = p.sportDays(on: monday, calendar: cal)
        #expect(days.map(\.weekday) == [3, 5, 6, 7])
        #expect(days.filter { $0.sport == .snowboard }.count == 3)
        // Another week: only the weekly bike day.
        #expect(p.sportDays(on: cal.date(byAdding: .day, value: 7, to: monday)!, calendar: cal).map(\.weekday) == [3])
        #expect(p.sportTrip(on: "2026-10-17")?.sport == .snowboard)
        #expect(p.sportTrip(on: "2026-10-19") == nil)
    }

    @Test func pausedSportIsNotPlannedAround() {
        var plan = SportPlan(sport: .roadBike, weekdays: [3, 6])
        #expect(plan.days(on: monday).count == 2)
        plan.paused = true
        #expect(!plan.isOn && plan.days(on: monday).isEmpty)
        #expect(plan.weekdays == [3, 6])
    }

    @Test func noGymOnTripDays() {
        var p = Profile(goal: .balanced, sessionsPerWeek: 3)
        p.sportTrips = [SportTrip(sport: .snowboard, start: "2026-10-15", end: "2026-10-18")]
        let w = PlanCalendar.adapt(p, week: 1, seed: 4, weekStart: monday, away: [], calendar: cal)
        #expect(Set(w.trips.keys) == [4, 5, 6, 7])
        #expect(w.off.isEmpty)
        #expect(w.plan.sessions.allSatisfy { ($0.weekday ?? 0) <= 3 })
        #expect(w.plan.sessions.count + w.dropped == 3)
    }

    @Test func fullTripWeekHasNoGym() {
        var p = Profile(goal: .balanced, sessionsPerWeek: 3)
        p.sportTrips = [SportTrip(sport: .ski, start: "2026-10-10", end: "2026-10-20")]
        let w = PlanCalendar.adapt(p, week: 1, seed: 4, weekStart: monday, away: [], calendar: cal)
        #expect(w.trips.count == 7)
        #expect(w.plan.sessions.isEmpty)
        #expect(PlanCalendar.touches(p.sportTrips ?? [], weekStart: monday, cal))
    }

    @Test func oldProfilesDecodeWithoutTrips() throws {
        let p = Profile(goal: .balanced, sessionsPerWeek: 3)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
        json.removeValue(forKey: "sportTrips")
        let back = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(back.sportTrips == nil)
    }
}
