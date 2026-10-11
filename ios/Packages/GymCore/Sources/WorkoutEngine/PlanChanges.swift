import Foundation

// MARK: - One-off moves (#113)

/// A session of one calendar week put on another day, that week only. Next week the plan is back to normal.
public struct SessionMove: Codable, Hashable, Sendable {
    /// Monday of the week ("yyyy-MM-dd").
    public var weekOf: String
    public var sessionId: String
    /// 1 = Monday … 7 = Sunday.
    public var weekday: Int

    public init(weekOf: String, sessionId: String, weekday: Int) {
        self.weekOf = weekOf
        self.sessionId = sessionId
        self.weekday = max(1, min(7, weekday))
    }
}

extension WeekPlan {
    /// The plan with `fixed` sessions (id → weekday) put on their day; order is kept.
    public func pinning(_ fixed: [String: Int]) -> WeekPlan {
        guard !fixed.isEmpty else { return self }
        var p = self
        for i in p.sessions.indices {
            if let wd = fixed[p.sessions[i].id] { p.sessions[i].weekday = wd }
        }
        return p
    }
}

extension PlanCalendar {
    /// Days to record for moving `sessionId` to `weekday` in a week as shown: sessions already on that day
    /// (not done) swap to the moved session's day. Empty when the session is unknown, done or already there.
    public static func moving(_ sessionId: String, to weekday: Int, in plan: WeekPlan, done: Set<String>) -> [String: Int] {
        guard let s = plan.sessions.first(where: { $0.id == sessionId }), !done.contains(sessionId), s.weekday != weekday else { return [:] }
        var out = [sessionId: weekday]
        if let from = s.weekday {
            for other in plan.sessions where other.weekday == weekday && other.id != sessionId && !done.contains(other.id) {
                out[other.id] = from
            }
        }
        return out
    }
}

// MARK: - Quick extra session (#113)

extension Generator {
    /// Foci offered for a quick extra session.
    public static let quickFoci: [Focus] = [.fullUpper, .fullLower, .fullPower, .push, .pull, .legs, .conditioning]

    /// One generated session of `focus` for this profile and cycle week (equipment, goal and style kept), unscheduled.
    public static func quickSession(_ profile: Profile, focus: Focus, week: Int, seed: UInt32) -> Session? {
        guard let n = Rules.splits.keys.sorted().first(where: { Rules.splits[$0]!.contains(focus) }) else { return nil }
        var p = profile
        p.sessionsPerWeek = n
        p.climbingWeekdays = nil
        p.gymWeekdays = nil
        p.climbingDaysPerWeek = 0
        guard var s = generateWeek(p, week: week, seed: seed).sessions.first(where: { $0.focus == focus }) else { return nil }
        s.weekday = nil
        return s
    }
}
