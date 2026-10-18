import Foundation

/// Steps and floors of one day, from Apple Health (#454). Stays on the device.
public struct DayMove: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Start of the day.
    public var day: Date
    public var steps: Int
    public var floors: Int

    public init(day: Date, steps: Int, floors: Int = 0) {
        self.day = day
        self.steps = max(0, steps)
        self.floors = max(0, floors)
    }

    public var id: Date { day }
}

/// Daily Move (#454, design B + C timing): walking and stairs earn XP for the level, measured against the
/// member's own usual, and one quiet nudge on a slow day. Nothing to set up.
public enum DailyMove {
    public static let xpPerThousandSteps = 10
    public static let xpPerFloor = 3
    /// So walking never outweighs a workout (50 + 5 per set, ~150–250 XP).
    public static let dailyCap = 80
    /// Five days at your usual in one week.
    public static let activeWeekDays = 5
    public static let activeWeekBonus = 50
    /// Usual = median of the last 14 days with steps, needs 3 of them; never below the floor.
    public static let usualWindow = 14
    public static let usualFloor = 3000
    public static let fallbackUsual = 6000
    /// Nudge only when below this share of your usual at nudge time, and at least this many steps short.
    public static let behindShare = 0.6
    public static let minGap = 1000
    /// Hour the nudge goes out when no walking pattern is known yet.
    public static let defaultHour = 17
    public static let earliestHour = 12
    public static let latestHour = 20
    /// Roughly 100 steps a minute at an easy walk.
    public static let stepsPerMinute = 100

    public static func xp(steps: Int, floors: Int) -> Int {
        min(dailyCap, (max(0, steps) / 1000) * xpPerThousandSteps + max(0, floors) * xpPerFloor)
    }

    public static func xp(_ d: DayMove) -> Int { xp(steps: d.steps, floors: d.floors) }

    /// The member's usual steps before `day`: median of the last 14 days that have steps.
    public static func usual(_ days: [DayMove], before day: Date, calendar cal: Calendar = Progression.calendar()) -> Int {
        let start = cal.startOfDay(for: day)
        guard let from = cal.date(byAdding: .day, value: -usualWindow, to: start) else { return fallbackUsual }
        let steps = days.filter { $0.day >= from && $0.day < start && $0.steps > 0 }.map(\.steps).sorted()
        guard steps.count >= 3 else { return fallbackUsual }
        let mid = steps.count / 2
        let median = steps.count % 2 == 0 ? (steps[mid - 1] + steps[mid]) / 2 : steps[mid]
        return max(usualFloor, median)
    }

    /// A day at or above the usual of the two weeks before it.
    public static func isActive(_ d: DayMove, in days: [DayMove], calendar cal: Calendar = Progression.calendar()) -> Bool {
        d.steps > 0 && d.steps >= usual(days, before: d.day, calendar: cal)
    }

    /// All XP walking and stairs earned: per-day XP plus the active-week bonus. Only days from `since` count;
    /// earlier ones still set the usual.
    public static func totalXP(_ days: [DayMove], since: Date? = nil, calendar cal: Calendar = Progression.calendar()) -> Int {
        var xp = 0
        var activePerWeek: [Date: Int] = [:]
        for d in days where since.map({ d.day >= cal.startOfDay(for: $0) }) ?? true {
            xp += self.xp(d)
            if isActive(d, in: days, calendar: cal) { activePerWeek[Progression.weekStart(d.day, cal), default: 0] += 1 }
        }
        return xp + activeWeekBonus * activePerWeek.values.filter { $0 >= activeWeekDays }.count
    }

    /// Active days so far in the week of `now`.
    public static func activeDays(_ days: [DayMove], weekOf now: Date, calendar cal: Calendar = Progression.calendar()) -> Int {
        let week = Progression.weekStart(now, cal)
        return days.filter { Progression.weekStart($0.day, cal) == week && isActive($0, in: days, calendar: cal) }.count
    }

    /// Hour the member usually walks (C): the afternoon / evening hour with the most steps on average,
    /// from per-hour step totals of the last two weeks (`hourly[h]` = steps in hour h). Nil data → 17:00.
    public static func usualHour(_ hourly: [Int: Int]) -> Int {
        let window = hourly.filter { (earliestHour...latestHour).contains($0.key) && $0.value > 0 }
        guard let best = window.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }) else { return defaultHour }
        return best.key
    }

    public enum Skip: String, Sendable, Equatable {
        case trained, off, restDay, alreadyNudged, notYet, tooLate, quiet, onPace
    }

    /// Why not to nudge now, nil = nudge. One a day max, from the member's walking hour until 21:00, only when
    /// well behind. `trainedToday`: a workout or sport today (this app's, or any app's in Health).
    public static func nudge(steps: Int, usual: Int, hour: Int, nowMinute: Int, trainedToday: Bool,
                             restDay: Bool, nudgedToday: Bool, prefs: NotificationPrefs) -> Skip? {
        if !prefs.moveNudges { return .off }
        if trainedToday { return .trained }
        if restDay { return .restDay }
        if nudgedToday { return .alreadyNudged }
        if nowMinute < hour * 60 { return .notYet }
        if nowMinute >= 21 * 60 { return .tooLate }
        if prefs.isQuiet(nowMinute) { return .quiet }
        if Double(steps) >= Double(usual) * behindShare || usual - steps < minGap { return .onPace }
        return nil
    }

    /// Nudge text: steps to the usual, minutes of walking, XP it adds.
    public static func message(steps: Int, usual: Int) -> (title: String, body: String) {
        let gap = max(0, usual - steps)
        let minutes = max(5, Int((Double(gap) / Double(stepsPerMinute) / 5).rounded(.up)) * 5)
        let gain = xp(steps: usual, floors: 0) - xp(steps: steps, floors: 0)
        let title = "\(gap.formatted()) steps to your usual 👣"
        let body = minutes <= 20
            ? "A \(minutes) min walk or the stairs gets you there\(gain > 0 ? ". +\(gain) XP" : "")."
            : "Quiet day so far. A short walk now counts\(gain > 0 ? ", up to +\(gain) XP" : "")."
        return (title, body)
    }
}
