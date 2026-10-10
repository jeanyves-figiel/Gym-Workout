import Foundation

/// Notification settings (#69). Times are minutes after local midnight. Mirrors the server's
/// `NotificationPrefs` (backend/src/push/prefs.ts), which uses the same keys and defaults.
public struct NotificationPrefs: Codable, Hashable, Sendable {
    /// Reminder on the morning of a planned gym session.
    public var sessionReminders = true
    public var reminderMinutes = 7 * 60 + 30
    /// Check-in the day after a planned session that was not done: train today or pick another day.
    public var missedCheckIn = true
    public var checkInMinutes = 9 * 60
    /// Remote push when someone you follow sets a PR or hits a milestone.
    public var followAchievements = true
    /// Local reminders are moved out of the window; remote pushes arrive silently inside it.
    public var quietHours = true
    public var quietStart = 22 * 60
    public var quietEnd = 7 * 60

    public init() {}

    /// Lenient: missing keys keep their defaults, so newer settings never break older stored prefs.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NotificationPrefs()
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? fallback }
        sessionReminders = v(.sessionReminders, d.sessionReminders)
        reminderMinutes = NotificationPrefs.clamp(v(.reminderMinutes, d.reminderMinutes))
        missedCheckIn = v(.missedCheckIn, d.missedCheckIn)
        checkInMinutes = NotificationPrefs.clamp(v(.checkInMinutes, d.checkInMinutes))
        followAchievements = v(.followAchievements, d.followAchievements)
        quietHours = v(.quietHours, d.quietHours)
        quietStart = NotificationPrefs.clamp(v(.quietStart, d.quietStart))
        quietEnd = NotificationPrefs.clamp(v(.quietEnd, d.quietEnd))
    }

    static func clamp(_ m: Int) -> Int { min(max(m, 0), 1439) }

    /// Whether minute-of-day `m` falls inside [quietStart, quietEnd), wrapping midnight.
    public func isQuiet(_ m: Int) -> Bool {
        guard quietHours, quietStart != quietEnd else { return false }
        return quietStart < quietEnd ? (m >= quietStart && m < quietEnd) : (m >= quietStart || m < quietEnd)
    }

    /// "07:30" for a minute-of-day value.
    public static func clock(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }
}

/// A gym session placed on a calendar day. Today the week plan's weekdays supply these; the training
/// calendar (#68) can supply dated sessions directly by conforming to `PlannedSessionSource`.
public struct PlannedSession: Hashable, Sendable {
    public var sessionId: String
    public var title: String
    public var estMin: Int
    /// Start of the calendar day the session is planned on.
    public var day: Date
    public var done: Bool

    public init(sessionId: String, title: String, estMin: Int, day: Date, done: Bool) {
        self.sessionId = sessionId
        self.title = title
        self.estMin = estMin
        self.day = day
        self.done = done
    }
}

/// Anything that can list planned gym sessions by date.
public protocol PlannedSessionSource {
    func plannedSessions(from: Date, through: Date, calendar: Calendar) -> [PlannedSession]
}

/// One local notification to schedule.
public struct LocalReminder: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case upcoming, missed }
    public var id: String
    public var kind: Kind
    public var sessionId: String
    public var day: Date
    public var fireAt: Date
    public var title: String
    public var body: String
}

public enum ReminderPlanner {
    /// iOS keeps at most 64 pending local notifications per app; stay well below.
    public static let maxPending = 40

    /// Reminders and missed-session check-ins still ahead of `now`, soonest first.
    public static func plan(_ sessions: [PlannedSession], prefs: NotificationPrefs, now: Date, calendar: Calendar) -> [LocalReminder] {
        var out: [LocalReminder] = []
        for s in sessions where !s.done {
            let day = calendar.startOfDay(for: s.day)
            let key = dayKey(day, calendar: calendar)
            if prefs.sessionReminders, let at = fireDate(day: day, minutes: prefs.reminderMinutes, prefs: prefs, calendar: calendar), at > now {
                out.append(LocalReminder(
                    id: "upcoming|\(s.sessionId)|\(key)", kind: .upcoming, sessionId: s.sessionId, day: day, fireAt: at,
                    title: "Today: \(s.title)", body: "\(s.estMin) min. Tap to see your session."))
            }
            if prefs.missedCheckIn, let next = calendar.date(byAdding: .day, value: 1, to: day),
               let at = fireDate(day: next, minutes: prefs.checkInMinutes, prefs: prefs, calendar: calendar), at > now {
                out.append(LocalReminder(
                    id: "missed|\(s.sessionId)|\(key)", kind: .missed, sessionId: s.sessionId, day: day, fireAt: at,
                    title: "Missed \(s.title)?", body: "No worries. Train today or pick another day."))
            }
        }
        return Array(out.sorted { $0.fireAt < $1.fireAt }.prefix(maxPending))
    }

    /// `day` at `minutes`, moved out of quiet hours: forward to the end of the window when that is still
    /// the same day (early morning), otherwise back to 15 min before it starts (late evening).
    static func fireDate(day: Date, minutes: Int, prefs: NotificationPrefs, calendar: Calendar) -> Date? {
        var m = NotificationPrefs.clamp(minutes)
        if prefs.isQuiet(m) {
            if m < prefs.quietEnd, !prefs.isQuiet(prefs.quietEnd) { m = prefs.quietEnd }
            else { m = max(0, prefs.quietStart - 15) }
            if prefs.isQuiet(m) { return nil }
        }
        return calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day)
    }

    /// "2026-10-12" in `calendar`'s zone.
    public static func dayKey(_ day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

extension WeekPlan {
    /// Monday 00:00 of the ISO week containing `date`.
    public static func weekStart(of date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let wd = WeekSchedule.fromCalendar(calendar.component(.weekday, from: day))
        return calendar.date(byAdding: .day, value: 1 - wd, to: day) ?? day
    }

    /// Weekday-scheduled sessions laid on the calendar week starting `weekStart` (Monday).
    /// Sessions without a weekday (no gym/climbing days picked) have no date and are skipped.
    public func dated(weekStart: Date, calendar: Calendar) -> [(session: Session, day: Date)] {
        sessions.compactMap { s in
            guard let wd = s.weekday, let day = calendar.date(byAdding: .day, value: wd - 1, to: weekStart) else { return nil }
            return (s, day)
        }
    }
}
