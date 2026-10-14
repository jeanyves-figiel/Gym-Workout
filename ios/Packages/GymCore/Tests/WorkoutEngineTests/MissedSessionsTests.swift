import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct MissedSessionsTests {
    private func s(_ id: String, _ day: Int?, _ focus: Focus = .push) -> Session {
        Session(id: id, index: 0, focus: focus, title: id, targetMin: 60, estMin: 60, blocks: [], weekday: day)
    }
    private func plan(_ sessions: [Session]) -> WeekPlan {
        WeekPlan(week: 1, deload: false, seed: 1, sessionMinutes: 60, sessions: sessions)
    }

    @Test func pastUndoneSessionsAreMissedAndNextUpIsFromToday() {
        // Mon push, Wed pull, Fri legs; today is Wednesday.
        let p = plan([s("fri", 5, .legs), s("mon", 1), s("wed", 3, .pull)])
        #expect(WeekProgress.missed(p, today: 3, done: []).map(\.id) == ["mon"])
        #expect(WeekProgress.next(p, today: 3, done: [])?.id == "wed")
        #expect(WeekProgress.remaining(p, today: 3, done: []) == 2)
        // Wednesday done: Friday is next.
        #expect(WeekProgress.next(p, today: 3, done: ["wed"])?.id == "fri")
        // Monday logged later: nothing missed.
        #expect(WeekProgress.missed(p, today: 3, done: ["mon"]).isEmpty)
    }

    @Test func nothingLeftThisWeek() {
        let p = plan([s("mon", 1), s("tue", 2)])
        #expect(WeekProgress.next(p, today: 4, done: []) == nil)
        #expect(WeekProgress.missed(p, today: 4, done: ["tue"]).map(\.id) == ["mon"])
        #expect(WeekProgress.remaining(p, today: 4, done: []) == 0)
    }

    @Test func unscheduledSessionsAreNeverMissed() {
        let p = plan([s("a", nil), s("b", nil)])
        #expect(WeekProgress.missed(p, today: 7, done: []).isEmpty)
        #expect(WeekProgress.next(p, today: 7, done: ["a"])?.id == "b")
    }

    @Test func weeksBetweenMondays() {
        let cal = Progression.calendar(TimeZone(identifier: "Europe/Zurich")!)
        let wed = cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 6))!
        let mon = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 22))!
        #expect(WeekProgress.weeksBetween(mon, wed, cal) == 1)
        #expect(WeekProgress.weeksBetween(wed, wed, cal) == 0)
        // Across the end of summer time (25 Oct).
        let nov = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 0, minute: 30))!
        #expect(WeekProgress.weeksBetween(wed, nov, cal) == 3)
    }
}
