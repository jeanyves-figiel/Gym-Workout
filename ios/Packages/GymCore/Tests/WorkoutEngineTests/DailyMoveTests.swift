import Foundation
import Testing
@testable import WorkoutEngine

private let utc = Progression.calendar(TimeZone(identifier: "UTC")!)
private let monday = ISO8601DateFormatter().date(from: "2026-09-14T00:00:00Z")! // a Monday

private func day(_ offset: Int) -> Date { utc.date(byAdding: .day, value: offset, to: monday)! }

@Suite struct DailyMoveTests {
    @Test func xpPerStepsAndFloorsIsCapped() {
        #expect(DailyMove.xp(steps: 999, floors: 0) == 0)
        #expect(DailyMove.xp(steps: 6840, floors: 9) == 80) // 60 + 27, capped
        #expect(DailyMove.xp(steps: 4200, floors: 2) == 46)
        #expect(DailyMove.xp(steps: 30000, floors: 40) == DailyMove.dailyCap)
        #expect(DailyMove.dailyCap < GameProgress.xp(sets: 18)) // walking never beats a workout
    }

    @Test func usualIsMedianOfLastTwoWeeksWithFloor() {
        // Too few days: fallback.
        #expect(DailyMove.usual([DayMove(day: day(-1), steps: 9000)], before: monday, calendar: utc) == DailyMove.fallbackUsual)
        let days = [8000, 6000, 10000, 0, 7000].enumerated().map { DayMove(day: day(-($0.offset + 1)), steps: $0.element) }
        // Zero days are ignored: median of 6000, 7000, 8000, 10000 = 7500.
        #expect(DailyMove.usual(days, before: monday, calendar: utc) == 7500)
        // Older than 14 days doesn't count.
        let old = days + [DayMove(day: day(-20), steps: 50000)]
        #expect(DailyMove.usual(old, before: monday, calendar: utc) == 7500)
        // Never below the floor.
        let lazy = (1...5).map { DayMove(day: day(-$0), steps: 1200) }
        #expect(DailyMove.usual(lazy, before: monday, calendar: utc) == DailyMove.usualFloor)
    }

    @Test func activeWeekAddsBonusAndSinceLimitsXP() {
        // Two weeks at 6000 before, then a week of 7000 every day: all seven are active.
        var days = (1...14).map { DayMove(day: day(-$0), steps: 6000) }
        days += (0..<7).map { DayMove(day: day($0), steps: 7000) }
        #expect(DailyMove.activeDays(days, weekOf: day(3), calendar: utc) == 7)
        let total = DailyMove.totalXP(days, since: monday, calendar: utc)
        #expect(total == 7 * 70 + DailyMove.activeWeekBonus)
        // Without `since` the earlier days earn too.
        #expect(DailyMove.totalXP(days, calendar: utc) > total)
    }

    @Test func usualHourPicksBusiestAfternoonHour() {
        #expect(DailyMove.usualHour([:]) == DailyMove.defaultHour)
        #expect(DailyMove.usualHour([8: 9000, 13: 2000, 18: 4000, 22: 9000]) == 18)
    }

    @Test func nudgeOnlyWhenWellBehindAtTheRightTime() {
        let p = NotificationPrefs()
        func n(steps: Int = 2000, minute: Int = 18 * 60, trained: Bool = false, rest: Bool = false, nudged: Bool = false,
               prefs: NotificationPrefs = p) -> DailyMove.Skip? {
            DailyMove.nudge(steps: steps, usual: 8000, hour: 17, nowMinute: minute, trainedToday: trained,
                            restDay: rest, nudgedToday: nudged, prefs: prefs)
        }
        #expect(n() == nil)
        #expect(n(minute: 16 * 60) == .notYet)
        #expect(n(minute: 21 * 60) == .tooLate)
        #expect(n(trained: true) == .trained)
        #expect(n(rest: true) == .restDay)
        #expect(n(nudged: true) == .alreadyNudged)
        #expect(n(steps: 5000) == .onPace)
        var off = p
        off.moveNudges = false
        #expect(n(prefs: off) == .off)
        var quiet = p
        quiet.quietStart = 17 * 60
        quiet.quietEnd = 19 * 60
        #expect(n(prefs: quiet) == .quiet)
    }

    @Test func messageSaysStepsMinutesAndXP() {
        let m = DailyMove.message(steps: 6800, usual: 8200)
        #expect(m.title.contains("steps to your usual"))
        #expect(m.body.contains("15 min"))
        #expect(m.body.contains("+20 XP"))
    }

    @Test func gameAddsMoveXP() {
        let g = GameProgress.evaluate(records: [], targetPerWeek: 3, moveXP: 520, calendar: utc)
        #expect(g.xp == 520 && g.moveXP == 520 && g.level == 2)
    }

    @Test func oldPrefsDecodeWithMoveNudgesOn() throws {
        let p = try JSONDecoder().decode(NotificationPrefs.self, from: Data(#"{"sessionReminders":false}"#.utf8))
        #expect(p.moveNudges && !p.sessionReminders)
    }
}
