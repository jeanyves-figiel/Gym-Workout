import Foundation
import Testing
@testable import WorkoutEngine

private let cal: Calendar = {
    var c = Calendar(identifier: .iso8601)
    c.timeZone = TimeZone(identifier: "Europe/Zurich")!
    return c
}()

/// A day with a logged extra workout is a workout day, not a rest day (#902).
@Suite struct LoggedDaysTests {
    @Test func loggedExtraMarksItsLocalDay() {
        // Wed 28 Oct 2026, 18:00 and 23:30 Zurich; Thu 29 00:15 Zurich is still Wed in UTC.
        let wed = cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 18))!
        let late = cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 23, minute: 30))!
        let thu = cal.date(from: DateComponents(year: 2026, month: 10, day: 29, minute: 15))!
        let days = PlanCalendar.loggedDays([wed, late, thu], cal)
        #expect(days == ["2026-10-28", "2026-10-29"])
        let week = PlanCalendar.dayKeys(weekStart: PlanCalendar.date("2026-10-26", cal)!, cal)
        #expect(week.map { days.contains($0) } == [false, false, true, true, false, false, false])
    }

    @Test func nothingLoggedLeavesRestDays() {
        #expect(PlanCalendar.loggedDays([], cal).isEmpty)
    }
}
