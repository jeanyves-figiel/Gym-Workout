import Foundation

/// Missed sessions and what comes next this week (#266): a session planned on a day before today that wasn't
/// done is missed; Next up is the first not-done session from today on.
public enum WeekProgress {
    /// Plan sessions in day order (unscheduled ones last, plan order within a day).
    public static func ordered(_ plan: WeekPlan) -> [Session] {
        plan.sessions.enumerated().sorted { ($0.element.weekday ?? 8, $0.offset) < ($1.element.weekday ?? 8, $1.offset) }.map(\.element)
    }

    /// Sessions planned before `today` (1 = Monday … 7 = Sunday) and not done, in day order.
    /// Sessions without a weekday are never missed.
    public static func missed(_ plan: WeekPlan, today: Int, done: Set<String>) -> [Session] {
        ordered(plan).filter { s in
            guard let wd = s.weekday else { return false }
            return wd < today && !done.contains(s.id)
        }
    }

    /// First not-done session planned today or later this week (unscheduled sessions count as any day).
    public static func next(_ plan: WeekPlan, today: Int, done: Set<String>) -> Session? {
        ordered(plan).first { !done.contains($0.id) && ($0.weekday ?? 8) >= today }
    }

    /// Sessions still to do this week: not done and not missed.
    public static func remaining(_ plan: WeekPlan, today: Int, done: Set<String>) -> Int {
        plan.sessions.filter { !done.contains($0.id) && ($0.weekday ?? 8) >= today }.count
    }

    /// Calendar weeks between two Monday-start dates (negative when `to` is earlier).
    public static func weeksBetween(_ from: Date, _ to: Date, _ cal: Calendar) -> Int {
        let a = Progression.weekStart(from, cal), b = Progression.weekStart(to, cal)
        return Int((b.timeIntervalSince(a) / (7 * 86_400)).rounded())
    }
}
