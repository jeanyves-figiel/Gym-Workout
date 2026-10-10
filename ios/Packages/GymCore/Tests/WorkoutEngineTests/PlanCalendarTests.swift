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

private func off(_ a: String, _ b: String) -> AwayPeriod { AwayPeriod(kind: .off, start: a, end: b, note: "Busy") }

@Suite struct PlanCalendarTests {
    let climber = Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 2,
                          climbingWeekdays: [2, 5], gymWeekdays: nil)

    @Test func dayKeysRoundTrip() {
        #expect(PlanCalendar.key(monday, cal) == "2026-10-12")
        #expect(PlanCalendar.dayKeys(weekStart: monday, cal) == (12...18).map { "2026-10-\($0)" })
        #expect(PlanCalendar.date("nope", cal) == nil)
        #expect(PlanCalendar.cycleWeek(current: 3, offset: 0) == 3)
        #expect(PlanCalendar.cycleWeek(current: 3, offset: 2) == 1)
        #expect(PlanCalendar.cycleWeek(current: 4, offset: 5) == 1)
    }

    @Test func periodNormalisesAndCovers() {
        let p = AwayPeriod(kind: .off, start: "2026-10-20", end: "2026-10-15")
        #expect(p.start == "2026-10-15" && p.end == "2026-10-20")
        #expect(p.covers("2026-10-15") && p.covers("2026-10-20") && !p.covers("2026-10-21"))
        #expect(PlanCalendar.touches([p], weekStart: monday, cal))
        #expect(!PlanCalendar.touches([p], weekStart: cal.date(byAdding: .day, value: 14, to: monday)!, cal))
    }

    @Test func untouchedWeekIsTheRegularPlan() {
        let regular = Generator.generateWeek(climber, week: 2, seed: 9)
        let w = PlanCalendar.adapt(climber, week: 2, seed: 9, weekStart: monday, away: [], calendar: cal)
        #expect(w.plan == regular)
        #expect(!w.adapted)
        #expect(w.climbing == [2, 5])
    }

    @Test func offDaysMoveSessionsToFreeDays() {
        let regular = Generator.generateWeek(climber, week: 1, seed: 3)
        let busy = Set(regular.sessions.compactMap(\.weekday))
        let away = busy.map { wd in off(PlanCalendar.dayKeys(weekStart: monday, cal)[wd - 1], PlanCalendar.dayKeys(weekStart: monday, cal)[wd - 1]) }
        let w = PlanCalendar.adapt(climber, week: 1, seed: 3, weekStart: monday, away: away, calendar: cal)
        #expect(w.plan.sessions.count == 3)
        #expect(w.plan.sessions.allSatisfy { $0.weekday != nil && !busy.contains($0.weekday!) })
        #expect(Set(w.off.keys) == busy)
        #expect(w.adapted)
        #expect(w.dropped == 0)
    }

    @Test func fewFreeDaysUseTheSmallerSplit() {
        let p = Profile(goal: .balanced, sessionsPerWeek: 4)
        // Only Saturday and Sunday free.
        let w = PlanCalendar.adapt(p, week: 1, seed: 5, weekStart: monday, away: [off("2026-10-12", "2026-10-16")], calendar: cal)
        #expect(w.plan.sessions.map(\.focus) .sorted { $0.rawValue < $1.rawValue } == Rules.splits[2]!.sorted { $0.rawValue < $1.rawValue })
        #expect(Set(w.plan.sessions.compactMap(\.weekday)) == [6, 7])
        #expect(w.adapted)
    }

    @Test func fullyBlockedWeekHasNoSessions() {
        let w = PlanCalendar.adapt(climber, week: 1, seed: 1, weekStart: monday, away: [off("2026-10-10", "2026-10-25")], calendar: cal)
        #expect(w.plan.sessions.isEmpty)
        #expect(w.dropped == 3)
        #expect(w.climbing.isEmpty)
    }

    @Test func oneFreeDayKeepsOneSession() {
        let w = PlanCalendar.adapt(climber, week: 1, seed: 1, weekStart: monday, away: [off("2026-10-12", "2026-10-17")], calendar: cal)
        #expect(w.plan.sessions.count == 1)
        #expect(w.plan.sessions.first?.weekday == 7)
        #expect(w.dropped == 1)
    }

    @Test func travelDaysUseTheTripEquipment() {
        let trip = AwayPeriod(kind: .travel, start: "2026-10-12", end: "2026-10-18", note: "Berlin", setup: .bodyweight)
        let w = PlanCalendar.adapt(climber, week: 1, seed: 2, weekStart: monday, away: [trip], calendar: cal)
        #expect(w.plan.sessions.count == 3)
        #expect(w.climbing.isEmpty)
        for s in w.plan.sessions {
            #expect(s.title.hasSuffix("Bodyweight only"))
            let items = s.blocks.flatMap(\.items)
            #expect(items.allSatisfy { Exercise.get($0.exerciseId).equipment.allSatisfy { [.mat].contains($0) } })
            #expect(s.blocks.contains { $0.kind == .strength && !$0.items.isEmpty })
        }
    }

    @Test(arguments: TravelSetup.allCases)
    func everyTravelSetupBuildsStrengthWork(_ setup: TravelSetup) {
        let trip = AwayPeriod(kind: .travel, start: "2026-10-12", end: "2026-10-18", setup: setup)
        for n in 2...6 {
            let p = Profile(goal: .balanced, sessionsPerWeek: n, experience: .intermediate, climbingDaysPerWeek: 0)
            let w = PlanCalendar.adapt(p, week: 1, seed: 11, weekStart: monday, away: [trip], calendar: cal)
            #expect(w.plan.sessions.count == n)
            #expect(w.plan.sessions.allSatisfy { s in s.blocks.contains { $0.kind == .strength && $0.items.count >= 2 } })
        }
    }

    @Test func doneSessionsStayAndPastDaysAreSkipped() {
        let regular = Generator.generateWeek(climber, week: 1, seed: 4)
        let first = regular.sessions[0]
        // Thursday, first session done; Saturday off.
        let w = PlanCalendar.adapt(climber, week: 1, seed: 4, weekStart: monday, away: [off("2026-10-17", "2026-10-17")],
                                   base: regular, done: [first.id], firstDay: 4, calendar: cal)
        #expect(w.plan.sessions.first { $0.id == first.id } == first)
        let rest = w.plan.sessions.filter { $0.id != first.id }
        #expect(rest.count == 2)
        #expect(rest.allSatisfy { $0.weekday! >= 4 && $0.weekday != 6 })
    }

    @Test func weeksCoverTheHorizonAndAdvanceTheCycle() {
        let now = cal.date(byAdding: .hour, value: 10, to: monday)!
        let current = Generator.generateWeek(climber, week: 3, seed: 8)
        let weeks = PlanCalendar.weeks(climber, seed: 8, currentWeek: 3, current: current, done: [], away: [], now: now, calendar: cal)
        #expect(weeks.count == PlanCalendar.horizonWeeks)
        #expect(weeks.map(\.plan.week) == [3, 4, 1, 2, 3, 4])
        #expect(weeks[0].plan == current)
        #expect(weeks[1].days[0] == "2026-10-19")
        let planned = PlanCalendar.planned(in: weeks, from: monday, to: cal.date(byAdding: .day, value: 13, to: monday)!, done: [], calendar: cal)
        #expect(planned.count == 6)
        #expect(planned.allSatisfy { $0.date >= monday })
    }
}
