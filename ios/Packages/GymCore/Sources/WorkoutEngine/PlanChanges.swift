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

    /// The plan with `ids` sessions (done, in progress) taken from `old` as they were (#194): a re-plan after a
    /// profile edit leaves them alone. One the new plan no longer has is added back in day order. `old` must be
    /// the same cycle week.
    public func keeping(_ ids: Set<String>, from old: WeekPlan?) -> WeekPlan {
        guard let old, old.week == week, !ids.isEmpty else { return self }
        var p = self
        var added = false
        for s in old.sessions where ids.contains(s.id) {
            if let i = p.sessions.firstIndex(where: { $0.id == s.id }) {
                p.sessions[i] = s
            } else {
                p.sessions.append(s)
                added = true
            }
        }
        if added { p.sessions.sort { $0.index < $1.index } }
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

    /// Durations offered for a quick extra session (#178), and the default (extra sessions are usually short).
    public static let quickDurations = [15, 20, 30, 45, 60]
    public static let quickDefaultMinutes = 30

    /// One generated session of `focus` for this profile and cycle week (equipment, goal and style kept), unscheduled.
    /// `minutes` sets its length (#178); nil = the plan's session length. `tweaks`: warm-up / cool-down choices (#293).
    public static func quickSession(_ profile: Profile, focus: Focus, week: Int, seed: UInt32, minutes: Int? = nil,
                                    tweaks: FlowTweaks? = nil) -> Session? {
        // The goal's own week when it has this focus (#194), else the default split that does.
        let sizes = Rules.splits.keys.sorted()
        let own = sizes.first { Rules.split(profile.goal, $0).contains(focus) }
        // Body-part days (#200) are in no goal's split: a 3-session week of that day type.
        let n = own ?? sizes.first(where: { Rules.splits[$0]!.contains(focus) }) ?? 3
        // Always explicit: the profile's own split style or per-day picks must not change which week is used.
        let split = own.map { Rules.split(profile.goal, $0) } ?? Rules.splits[n].flatMap { $0.contains(focus) ? $0 : nil }
            ?? Array(repeating: focus, count: n)
        var p = profile.applying(tweaks)
        p.sessionsPerWeek = n
        p.climbingWeekdays = nil
        p.gymWeekdays = nil
        p.climbingDaysPerWeek = 0
        let plan: WeekPlan
        if let minutes {
            p.syncClimbingDays()
            let ctx = Ctx(profile: p, week: min(mesocycleWeeks, max(1, week)), seed: seed)
            ctx.minutes = minutes
            ctx.split = split
            plan = generateWeek(ctx)
        } else {
            plan = generateWeek(p, week: week, seed: seed, split: split)
        }
        guard var s = plan.sessions.first(where: { $0.focus == focus }) else { return nil }
        s.weekday = nil
        return s
    }

    /// A quick extra session for chosen muscle groups (#178): the muscle generator's workout sized to `minutes`,
    /// with the profile's rest and grouping. Empty when no group is chosen or nothing fits the equipment.
    public static func quickWorkout(_ profile: Profile, groups: Set<MuscleGroup>, minutes: Int, seed: UInt32) -> CustomWorkout {
        var options = MuscleWorkoutOptions(profile: profile, groups: groups)
        options.minutes = minutes
        return CustomWorkout.generate(options, profile: profile, seed: seed)
    }
}

extension Focus {
    /// Muscle groups a quick session of this focus works (#178): the muscle-focus preset; empty for conditioning.
    public var muscleGroups: Set<MuscleGroup> {
        switch self {
        case .upper, .fullUpper: [.shoulders, .chest, .back, .arms]
        case .lower, .fullLower, .legs: [.hips, .legs]
        case .fullPower: [.chest, .back, .hips, .legs]
        case .push: [.shoulders, .chest, .arms]
        case .pull: [.back, .arms]
        case .conditioning: []
        case .chestTri: [.chest, .shoulders, .arms]
        case .backBi: [.back, .arms]
        case .shouldersArms: [.shoulders, .arms]
        case .chestBack: [.chest, .back]
        case .posterior: [.hips, .legs]
        }
    }
}
