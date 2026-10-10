import Foundation
import Testing
@testable import WorkoutEngine

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Zurich")!
    return c
}()

private func date(_ s: String) -> Date {
    let f = DateFormatter()
    f.calendar = cal
    f.timeZone = cal.timeZone
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
}

private func session(_ id: String, _ day: String, done: Bool = false) -> PlannedSession {
    PlannedSession(sessionId: id, title: "Push", estMin: 55, day: date("\(day) 00:00"), done: done)
}

@Suite struct ReminderTests {
    @Test func plansReminderAndCheckInForOpenSessions() {
        let r = ReminderPlanner.plan([session("a", "2026-10-12"), session("b", "2026-10-14", done: true)],
                                     prefs: NotificationPrefs(), now: date("2026-10-11 20:00"), calendar: cal)
        #expect(r.map(\.kind) == [.upcoming, .missed])
        #expect(r[0].fireAt == date("2026-10-12 07:30"))
        #expect(r[0].title == "Today: Push")
        #expect(r[1].fireAt == date("2026-10-13 09:00"))
        #expect(r[1].id == "missed|a|2026-10-12")
    }

    @Test func skipsPastTimesButKeepsTomorrowsCheckIn() {
        let r = ReminderPlanner.plan([session("a", "2026-10-12")], prefs: NotificationPrefs(), now: date("2026-10-12 12:00"), calendar: cal)
        #expect(r.map(\.kind) == [.missed])
        #expect(ReminderPlanner.plan([session("a", "2026-10-12")], prefs: NotificationPrefs(), now: date("2026-10-13 10:00"), calendar: cal).isEmpty)
    }

    @Test func honoursToggles() {
        var p = NotificationPrefs()
        p.sessionReminders = false
        #expect(ReminderPlanner.plan([session("a", "2026-10-12")], prefs: p, now: date("2026-10-11 20:00"), calendar: cal).map(\.kind) == [.missed])
        p.missedCheckIn = false
        #expect(ReminderPlanner.plan([session("a", "2026-10-12")], prefs: p, now: date("2026-10-11 20:00"), calendar: cal).isEmpty)
    }

    @Test func movesOutOfQuietHours() {
        var p = NotificationPrefs()
        p.reminderMinutes = 6 * 60 // inside 22:00–07:00 → 07:00
        p.checkInMinutes = 23 * 60 // inside → 21:45
        let r = ReminderPlanner.plan([session("a", "2026-10-12")], prefs: p, now: date("2026-10-11 20:00"), calendar: cal)
        #expect(r[0].fireAt == date("2026-10-12 07:00"))
        #expect(r[1].fireAt == date("2026-10-13 21:45"))
        p.quietHours = false
        #expect(ReminderPlanner.plan([session("a", "2026-10-12")], prefs: p, now: date("2026-10-11 20:00"), calendar: cal)[0].fireAt == date("2026-10-12 06:00"))
    }

    @Test func quietWindowWrapsMidnight() {
        let p = NotificationPrefs()
        #expect(p.isQuiet(23 * 60))
        #expect(p.isQuiet(0))
        #expect(!p.isQuiet(7 * 60))
        #expect(!p.isQuiet(12 * 60))
        var day = NotificationPrefs()
        day.quietStart = 13 * 60
        day.quietEnd = 14 * 60
        #expect(day.isQuiet(13 * 60 + 30))
        #expect(!day.isQuiet(23 * 60))
    }

    @Test func capsPendingCount() {
        let many = (0..<60).map { session("s\($0)", "2026-10-12") }
        #expect(ReminderPlanner.plan(many, prefs: NotificationPrefs(), now: date("2026-10-11 20:00"), calendar: cal).count == ReminderPlanner.maxPending)
    }

    @Test func decodesLeniently() throws {
        let p = try JSONDecoder().decode(NotificationPrefs.self, from: Data(#"{"missedCheckIn":false,"quietStart":5000,"future":1}"#.utf8))
        #expect(!p.missedCheckIn)
        #expect(p.sessionReminders)
        #expect(p.ownAchievements)
        #expect(p.quietStart == 1439)
        #expect(NotificationPrefs.clock(450) == "07:30")
    }

    @Test func laysWeekdaySessionsOnTheCalendarWeek() {
        // Wednesday → Monday 2026-10-12.
        let start = WeekPlan.weekStart(of: date("2026-10-14 15:00"), calendar: cal)
        #expect(start == date("2026-10-12 00:00"))
        #expect(WeekPlan.weekStart(of: date("2026-10-18 23:00"), calendar: cal) == start) // Sunday
        let profile = Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0, gymWeekdays: [1, 3, 5])
        let plan = Generator.generateWeek(profile, week: 1, seed: 1)
        let dated = plan.dated(weekStart: start, calendar: cal)
        #expect(dated.count == plan.sessions.count && !dated.isEmpty)
        for d in dated {
            #expect(d.day == cal.date(byAdding: .day, value: d.session.weekday! - 1, to: start))
            #expect(WeekSchedule.fromCalendar(cal.component(.weekday, from: d.day)) == d.session.weekday)
        }
        let plain = Generator.generateWeek(Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0), week: 1, seed: 1)
        #expect(plain.dated(weekStart: start, calendar: cal).isEmpty)
    }
}
