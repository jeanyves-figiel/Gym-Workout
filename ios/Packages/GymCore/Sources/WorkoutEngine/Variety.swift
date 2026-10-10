import Foundation

/// How a plan changes from week to week across the mesocycle (#64).
public enum PlanVariety: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Same exercises on each day every week; only the dose (RPE, peak set, deload) changes.
    case same
    /// Main lifts stay for progression; accessories, warm-up, mobility and cardio picks change weekly.
    case fresh
    /// Like `fresh`, plus the day order and each day's lead lift rotate weekly. Weekly volume per muscle is unchanged.
    case rotate
    public var id: String { rawValue }
}

extension Profile {
    /// Week-to-week variety; older profiles (nil) get `.fresh`.
    public var planVariety: PlanVariety { variety ?? .fresh }
}

extension Rules {
    /// Compound patterns that take turns leading a session in `.rotate` plans.
    static func leadPatterns(_ f: Focus) -> [Pattern] {
        switch f {
        case .fullLower: [.squat, .hinge]
        case .fullUpper: [.hPush, .vPull, .vPush]
        case .fullPower: [.hinge, .vPush, .hPull]
        case .upper: [.hPush, .vPull, .vPush, .hPull]
        case .lower, .legs: [.squat, .hinge]
        case .push: [.hPush, .vPush]
        case .pull: [.vPull, .hPull]
        case .conditioning: []
        }
    }

    /// Moves this step's lead pattern to the front (main lift); the rest keep their order, so the
    /// session trains the same patterns — only the emphasis changes.
    static func rotatingLead(_ slots: [Pattern], _ f: Focus, step: Int) -> [Pattern] {
        let leads = leadPatterns(f).filter(slots.contains)
        guard !leads.isEmpty else { return slots }
        let lead = leads[step % leads.count]
        var out = slots
        out.remove(at: out.firstIndex(of: lead)!)
        out.insert(lead, at: 0)
        return out
    }

    /// `.rotate`: the split shifts one day per week so each day leads with a different muscle group.
    static func rotatedSplit(_ split: [Focus], week: Int) -> [Focus] {
        guard !split.isEmpty else { return split }
        let k = (week - 1) % split.count
        return Array(split[k...] + split[..<k])
    }
}
