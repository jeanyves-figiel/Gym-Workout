import Foundation

// Around sport days (#658): the "Around climbing" choices, worded for any sport from its body load.

extension Sport {
    /// The sport as a noun for "Day before …" and "as if there were no …": "climbing", "running", "football".
    public var activity: String {
        switch self {
        case .climbing: "climbing"
        case .snowboard: "snowboarding"
        case .ski: "skiing"
        case .crossCountrySki: "cross-country skiing"
        case .mountainBike: "mountain biking"
        case .roadBike: "cycling"
        case .run: "running"
        case .trailRun: "trail running"
        case .hike: "hiking"
        case .mountaineering: "mountaineering"
        case .hyrox: "Hyrox"
        case .crossfit: "CrossFit"
        case .swim: "swimming"
        case .rowing: "rowing"
        case .football, .basketball, .volleyball, .tennis, .padel, .squash, .golf, .yoga: label.lowercased()
        case .martialArts: "martial arts"
        case .boxing: "boxing"
        case .surf: "surfing"
        case .scubaDiving: "diving"
        case .skate: "skating"
        case .other: "your sport"
        }
    }

    /// Areas the sport works hard, as gym words ("pulling and grip", "legs"); empty for light sports.
    var worked: [String] {
        if self == .climbing { return ["pulling", "grip"] }
        var out: [String] = []
        if load.legs >= 0.6 { out.append("legs") }
        if load.pull >= 0.6 { out.append("pulling") }
        if load.push >= 0.6 { out.append("pushing") }
        return out
    }

    /// What's left free for a hard gym day next to it ("push or legs", "upper body"); nil = nothing left free.
    var free: String? {
        if self == .climbing { return "push or legs" }
        let w = Set(worked)
        switch (w.contains("legs"), w.contains("pulling"), w.contains("pushing")) {
        case (false, false, false): return nil
        case (true, false, false): return "upper body"
        case (false, true, false): return "push or legs"
        case (false, false, true): return "legs or pull"
        case (true, true, false): return "push"
        case (true, false, true): return "pull"
        case (false, true, true): return "legs"
        case (true, true, true): return nil
        }
    }

    /// Light sports (yoga, golf, diving's body load) barely clash with any gym day.
    public var isLightLoad: Bool { worked.isEmpty }

    /// Card title for each choice ("Strong upper body").
    public func aroundLabel(_ o: ClimbNeighbour) -> String {
        switch o {
        case .light: "Keep it light"
        case .strong: free.map { "Strong \($0)" } ?? "Strong session"
        case .rest: "Rest"
        case .any: "No adjustment"
        }
    }

    /// One line under the title, for the day before or after.
    public func aroundBlurb(_ o: ClimbNeighbour, before: Bool) -> String {
        let spare = Self.list(worked)
        switch o {
        case .light:
            if self == .climbing {
                return before ? "No heavy pulling, grip or jumps. Push and legs preferred." : "Light on pulling and grip while fingers recover."
            }
            if spare.isEmpty { return before ? "Moderate session, nothing to failure." : "Easy session, nothing to failure." }
            if before {
                let jumps = worked.contains("legs") ? " or jumps" : ""
                let then = free.map { " \(Self.capitalised($0)) preferred." } ?? " Short and easy."
                return "No heavy \(spare)\(jumps).\(then)"
            }
            return "Light on \(spare) while you recover."
        case .strong:
            guard let free, !spare.isEmpty else { return "Hard gym day welcome, volume kept moderate." }
            return before ? "Hard \(free) day welcome. Only \(spare) kept light." : "Hard \(free) day welcome. \(Self.capitalised(spare)) kept light."
        case .rest: return "Keep this day free of gym sessions when the week allows."
        case .any: return "Plan the gym session as if there were no \(activity)."
        }
    }

    /// Same-day choice titles ("Run only", "Gym allowed").
    public func sameDayLabel(_ o: ClimbSameDay) -> String {
        o == .avoid ? "\(self == .climbing ? "Climb" : short) only" : "Gym allowed"
    }

    public func sameDayBlurb(_ o: ClimbSameDay) -> String {
        o == .avoid ? "Gym sessions go on \(activity) days only when the week has no room."
                    : "A gym session can share the day, e.g. gym in the morning, \(activity) in the evening."
    }

    static func capitalised(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// "legs", "pulling and grip", "legs, pulling and pushing".
    static func list(_ parts: [String]) -> String {
        guard let last = parts.last else { return "" }
        return parts.count == 1 ? last : parts.dropLast().joined(separator: ", ") + " and " + last
    }
}

extension Profile {
    /// Around sport days default for all sports (#658).
    public var sportDefaults: SportDefaults { SportDefaults(before: sportBefore, after: sportAfter, sameDay: sportSameDay) }

    /// The sport of a day, dated trips first (#658): a Snowboard day on a weekly climbing day is a snowboard day.
    /// `weekday` 1 = Monday … 7 = Sunday; `key` the day key ("2026-10-23") for trips.
    public func sport(onWeekday weekday: Int, key: String?, date: Date = Date()) -> Sport? {
        if let key, let t = sportTrip(on: key) { return t.sport }
        if Generator.isClimber(self) && climbingDays.contains(weekday) { return .climbing }
        return (sports ?? []).filter { $0.sport != .climbing }.first { $0.days(on: date).contains { $0.weekday == weekday } }?.sport
    }
}
