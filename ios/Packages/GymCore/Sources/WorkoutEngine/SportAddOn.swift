import Foundation

/// Sport add-on (#620 C): a 15′ block for a sport added to a few of the week's gym sessions, the plan otherwise
/// unchanged ("Push day + Climb add-on: antagonists, finger care").
public struct SportAddOnPref: Codable, Hashable, Sendable {
    public var sport: SeasonSport
    /// Sessions a week that get it (1–3).
    public var perWeek: Int

    public init(sport: SeasonSport, perWeek: Int = 2) {
        self.sport = sport
        self.perWeek = min(3, max(1, perWeek))
    }
}

public enum SportAddOn {
    /// What the add-on works on, for its card ("Rotator cuff, wrist, lateral lunges").
    public static func summary(_ s: SeasonSport) -> String {
        switch s {
        case .ski: "Sideways power, wall sits, groin"
        case .padel: "Rotator cuff, wrist, lateral lunges"
        case .climb: "Antagonists · finger care"
        case .run: "Shins, calves, hips"
        case .surf: "Paddle shoulders, pop-ups"
        case .football: "Hamstrings, groin, bounds"
        }
    }

    /// Exercises, sets and reps of the add-on.
    static func moves(_ s: SeasonSport) -> [(id: String, sets: Int, reps: String)] {
        switch s {
        case .ski: [("lateral-bound", 3, "6"), ("wall-sit", 2, "45 s"), ("copenhagen-plank", 2, "20 s")]
        case .padel: [("side-lying-external-rotation", 2, "12"), ("pronation-supination", 2, "15"), ("lateral-lunge", 2, "8")]
        case .climb: [("push-up", 2, "10"), ("reverse-wrist-curl", 2, "15"), ("finger-extensions", 2, "20"), ("band-external-rotation", 2, "12")]
        case .run: [("tib-raise", 2, "15"), ("bw-calf-raise", 2, "15"), ("side-lying-hip-abduction", 2, "15")]
        case .surf: [("band-pull-apart", 2, "15"), ("prone-ytw", 2, "8"), ("plyo-push-up", 2, "5")]
        case .football: [("nordic-curl", 2, "5"), ("copenhagen-plank", 2, "20 s"), ("lateral-bound", 2, "6")]
        }
    }

    public static let minutes = 15

    /// The add-on's exercises for session `sessionId`.
    public static func items(_ s: SeasonSport, sessionId: String) -> [PlannedExercise] {
        let moves = moves(s)
        let each = minutes * 60 / max(1, moves.count)
        return moves.enumerated().map { i, m in
            let e = Exercise.get(m.id)
            return PlannedExercise(uid: "\(sessionId)-ao\(i)", exerciseId: m.id, slot: e.pattern,
                                   prescription: Prescription(sets: m.sets, reps: m.reps + Generator.perSide(e), restSec: 45),
                                   estSec: each)
        }
    }

    /// The plan with the add-on in the first `perWeek` sessions that have a strength block (by day): appended to
    /// their mobility block, or as a mobility block of its own placed in block order.
    public static func apply(_ plan: WeekPlan, _ pref: SportAddOnPref?) -> WeekPlan {
        guard let pref else { return plan }
        let picked = plan.sessions.enumerated()
            .filter { $0.element.blocks.contains { $0.kind == .strength } }
            .sorted { ($0.element.weekday ?? 8, $0.offset) < ($1.element.weekday ?? 8, $1.offset) }
            .prefix(pref.perWeek).map(\.element.id)
        var out = plan
        out.sessions = plan.sessions.map { s in
            guard picked.contains(s.id) else { return s }
            return withAddOn(s, pref.sport)
        }
        return out
    }

    public static func title(_ s: SeasonSport) -> String { "\(s.label) add-on" }

    static func withAddOn(_ s: Session, _ sport: SeasonSport) -> Session {
        var out = s
        let items = items(sport, sessionId: s.id)
        if let i = out.blocks.firstIndex(where: { $0.kind == .mobility }) {
            out.blocks[i].items += items
            out.blocks[i].title += " + \(title(sport))"
            out.blocks[i].targetMin += minutes
        } else {
            let block = Block(kind: .mobility, title: title(sport), targetMin: minutes, items: items, note: summary(sport))
            let order = BlockKind.allCases
            let at = out.blocks.firstIndex { (order.firstIndex(of: $0.kind) ?? 0) > (order.firstIndex(of: .mobility) ?? 0) }
            out.blocks.insert(block, at: at ?? out.blocks.count)
        }
        out.estMin += minutes
        return out
    }

    /// Coach suggestion (#620 B): the season sport played at least 3 times in the last 14 days, most played first.
    public static func suggestion(_ logs: [(sport: Sport, start: Date)], now: Date) -> (sport: SeasonSport, count: Int)? {
        let since = now.addingTimeInterval(-14 * 86_400)
        var counts: [SeasonSport: Int] = [:]
        for l in logs where l.start >= since && l.start <= now {
            if let s = SeasonSport.of(l.sport) { counts[s, default: 0] += 1 }
        }
        return counts.filter { $0.value >= 3 }
            .max { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue }
            .map { ($0.key, $0.value) }
    }
}
