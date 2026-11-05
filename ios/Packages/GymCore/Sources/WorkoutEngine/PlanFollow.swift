import Foundation

/// Part of a plan (#1052 D, `usage-levels/d.png`): a member who doesn't want the whole week follows only some days,
/// one workout at a time or only their own workouts, and can cut each workout to its lifts or a quick 15′.
/// Synced with the profile; nil = the whole plan, full workouts, as before. The plan itself is unchanged, so going
/// back to the whole plan brings everything back.
public enum PlanScope: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Week, programme, auto-tune: the plan as made.
    case whole
    /// Only the weekdays picked; the other plan days are not the member's (no missed nudges).
    case someDays
    /// No week: the next workout not done is today's.
    case oneAtATime
    /// Only workouts the member adds (library, own, generated); the app plans nothing.
    case ownWorkouts

    public var id: String { rawValue }

    /// A scope from a newer app reads as the whole plan instead of failing the whole profile.
    public init(from decoder: Decoder) throws {
        self = PlanScope(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .whole
    }

    public var title: String {
        switch self {
        case .whole: "Whole plan"
        case .someDays: "Some days"
        case .oneAtATime: "One workout at a time"
        case .ownWorkouts: "My own workouts"
        }
    }

    public var detail: String {
        switch self {
        case .whole: "Week, programme, auto-tune. As it is."
        case .someDays: "Pick the days you do. Other plan days are free, no missed nudges."
        case .oneAtATime: "No week. Open the app, today's workout is the next one you haven't done."
        case .ownWorkouts: "Only workouts you add. The app never plans."
        }
    }

    public var symbol: String {
        switch self {
        case .whole: "calendar"
        case .someDays: "pin.fill"
        case .oneAtATime: "bolt.fill"
        case .ownWorkouts: "books.vertical.fill"
        }
    }
}

/// How much of each workout (#1052 D): the member's default, applied to every plan workout not started yet.
public enum WorkoutCut: String, Codable, CaseIterable, Sendable, Identifiable {
    case full
    /// Power and strength blocks only: no warm-up, mobility, cardio or cool-down.
    case lifts
    /// Fitted to 15 minutes, like Finish early.
    case quick

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        self = WorkoutCut(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .full
    }

    public var title: String {
        switch self {
        case .full: "Full"
        case .lifts: "Lifts only"
        case .quick: "Quick 15′"
        }
    }

    public static let quickMinutes = 15

    /// The session cut; HIIT and sessions without lifts stay as they are.
    public func apply(_ s: Session) -> Session {
        guard s.hiit == nil else { return s }
        switch self {
        case .full:
            return s
        case .lifts:
            let kept = s.blocks.filter { $0.kind == .strength || $0.kind == .power }
            guard !kept.isEmpty, kept.count < s.blocks.count else { return s }
            var out = s
            let before = s.blocks.estSec, after = kept.estSec
            out.blocks = kept
            out.estMin = max(1, s.estMin + Int((Double(after - before) / 60).rounded()))
            return out
        case .quick:
            guard s.estMin > Self.quickMinutes else { return s }
            let fit = FinishEarly.fit(s.blocks, setsDone: [:], current: nil, minutes: Self.quickMinutes)
            return FinishEarly.session(s, fit)
        }
    }
}

/// What the member follows of the plan.
public struct PlanFollow: Codable, Equatable, Sendable {
    public var scope: PlanScope
    /// Weekdays (1 = Monday … 7 = Sunday) kept with `someDays`.
    public var days: [Int]
    public var cut: WorkoutCut

    public init(scope: PlanScope = .whole, days: [Int] = [], cut: WorkoutCut = .full) {
        self.scope = scope
        self.days = days.sorted()
        self.cut = cut
    }

    public static let whole = PlanFollow()

    /// Tolerant: missing fields read as the whole plan.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scope = (try? c.decodeIfPresent(PlanScope.self, forKey: .scope)) ?? .whole
        days = ((try? c.decodeIfPresent([Int].self, forKey: .days)) ?? []).filter { (1...7).contains($0) }.sorted()
        cut = (try? c.decodeIfPresent(WorkoutCut.self, forKey: .cut)) ?? .full
    }

    private enum CodingKeys: String, CodingKey { case scope, days, cut }

    /// The week as the member follows it. `keep`: sessions done or in progress, always kept as they are so history
    /// and the player still find them. `today`: weekday 1…7.
    public func applying(to plan: WeekPlan, keep: Set<String>, today: Int) -> WeekPlan {
        var out = plan
        switch scope {
        case .whole:
            break
        case .someDays:
            out.sessions = plan.sessions.filter { s in
                keep.contains(s.id) || s.isPlanInsert || (s.weekday.map { days.contains($0) } ?? true)
            }
        case .oneAtATime:
            var next: Session?
            out.sessions = []
            for s in plan.sessions {
                if keep.contains(s.id) || s.isPlanInsert {
                    out.sessions.append(s)
                } else if next == nil {
                    var n = s
                    if s.weekday != nil { n.weekday = today }
                    next = n
                    out.sessions.append(n)
                }
            }
        case .ownWorkouts:
            out.sessions = plan.sessions.filter { keep.contains($0.id) || $0.isPlanInsert }
        }
        if cut != .full {
            out.sessions = out.sessions.map { keep.contains($0.id) ? $0 : cut.apply($0) }
        }
        return out
    }

    /// Short summary for rows, e.g. "Some days · Mon Thu" or "Whole plan · Lifts only".
    public func summary(dayName: (Int) -> String) -> String {
        var s = scope.title
        if scope == .someDays, !days.isEmpty { s += " · " + days.map(dayName).joined(separator: " ") }
        if cut != .full { s += " · " + cut.title }
        return s
    }
}
