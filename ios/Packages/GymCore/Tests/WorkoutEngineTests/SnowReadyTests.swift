import Foundation
import Testing
@testable import WorkoutEngine

/// Snow ready pre-season programme (#428): variants, length fitted to the first day on snow, season nudge.
@Suite struct SnowReadyTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)!
    }

    @Test func variantsAreFoundAndShareTheShape() {
        for r in SnowRide.allCases {
            let p = Programme.snowReady(r)
            #expect(Programme.find(r.programmeId) == p)
            #expect(p.snowRide == r)
            #expect(p.weeks == 8 && p.phases.map(\.kind) == [.base, .build, .peak, .test, .ease])
            for s in p.signatures { for it in s.items { #expect(Exercise.find(it.exerciseId) != nil, "\(p.id) \(it.exerciseId)") } }
            #expect(p.lengths.count >= 3)
        }
        // Only the "both" card is in the catalog list.
        #expect(Programme.all.filter { $0.snowRide != nil }.map(\.id) == ["snow-ready"])
        #expect(Programme.strengthFoundation.snowRide == nil)
    }

    @Test func rideComesFromMySports() {
        #expect(SnowRide.from(nil) == nil)
        #expect(SnowRide.from([SportPlan(sport: .run)]) == nil)
        #expect(SnowRide.from([SportPlan(sport: .ski)]) == .ski)
        #expect(SnowRide.from([SportPlan(sport: .snowboard), SportPlan(sport: .run)]) == .snowboard)
        #expect(SnowRide.from([SportPlan(sport: .ski), SportPlan(sport: .snowboard)]) == .both)
    }

    @Test func lengthEndsTheWeekBeforeTheFirstDay() {
        let now = day("2026-10-17") // Saturday; programme week 1 starts Monday 12 Oct
        #expect(Programme.snowWeeks(until: day("2026-12-12"), now: now, calendar: cal) == 8) // week of 7 Dec
        #expect(Programme.snowWeeks(until: day("2026-12-26"), now: now, calendar: cal) == 10)
        // Clamped: too close keeps the shortest, far away the longest.
        #expect(Programme.snowWeeks(until: day("2026-10-30"), now: now, calendar: cal) == Programme.snowMinWeeks)
        #expect(Programme.snowWeeks(until: day("2027-06-01"), now: now, calendar: cal) == Programme.snowMaxWeeks)
        let ten = Programme.snowReady(.ski).resized(to: 10)
        #expect(ten.weeks == 10 && ten.phases.last?.kind == .ease)
        let five = Programme.snowReady(.both).resized(to: Programme.snowMinWeeks)
        #expect(five.weeks == 5 && five.phases.allSatisfy { $0.weeks >= 1 })
    }

    @Test func defaultFirstDayFollowsTheSeason() {
        let now = day("2026-10-17")
        // Season December to April: 1 December, not 1 January.
        let winter = [SportPlan(sport: .snowboard, seasonMonths: [12, 1, 2, 3, 4])]
        #expect(Programme.defaultSnowDay(sports: winter, now: now, calendar: cal) == day("2026-12-01"))
        // No season: the Saturday 8 weeks out.
        let d = Programme.defaultSnowDay(sports: [SportPlan(sport: .ski)], now: now, calendar: cal)
        #expect(cal.component(.weekday, from: d) == 7)
        #expect(d >= day("2026-12-12") && d < day("2026-12-19"))
    }

    @Test func nudgeOnlyInAutumnForRidersWithoutAProgramme() {
        let ski = [SportPlan(sport: .ski)]
        let oct = day("2026-10-17")
        #expect(Programme.snowNudge(sports: ski, running: false, seenSeason: nil, now: oct, calendar: cal) == .ski)
        #expect(Programme.snowNudge(sports: ski, running: true, seenSeason: nil, now: oct, calendar: cal) == nil)
        #expect(Programme.snowNudge(sports: ski, running: false, seenSeason: 2026, now: oct, calendar: cal) == nil)
        #expect(Programme.snowNudge(sports: ski, running: false, seenSeason: 2025, now: oct, calendar: cal) == .ski)
        #expect(Programme.snowNudge(sports: ski, running: false, seenSeason: nil, now: day("2027-02-10"), calendar: cal) == nil)
        #expect(Programme.snowNudge(sports: [SportPlan(sport: .run)], running: false, seenSeason: nil, now: oct, calendar: cal) == nil)
    }

    @Test func firstDayIsKeptAndOlderProgrammesDecode() throws {
        let saved = ActiveProgramme.SavedPlan(profile: Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate), seed: 1, week: 1)
        var a = ActiveProgramme(programmeId: "snow-ready-board", start: day("2026-10-12"), seed: 3, saved: saved, length: 9)
        a.firstDay = day("2026-12-19")
        let back = try JSONDecoder().decode(ActiveProgramme.self, from: JSONEncoder().encode(a))
        #expect(back.firstDay == a.firstDay && back.programme?.weeks == 9 && back.programme?.snowRide == .snowboard)
    }
}
