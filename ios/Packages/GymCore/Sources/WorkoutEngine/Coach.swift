import Foundation

/// In-workout coach (#379, design A + C from `workout-coach/proposals.png`): scripted lines from the member's own data,
/// on the device (works offline, no delay at rest end, nothing leaves the phone). The app speaks them and shows them.
public enum CoachStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case chill, hype, drill
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .chill: "Chill"
        case .hype: "Hype"
        case .drill: "Drill"
        }
    }
    public var emoji: String {
        switch self {
        case .chill: "😌"
        case .hype: "🔥"
        case .drill: "🎖"
        }
    }
}

/// How much the coach says out loud.
public enum CoachVoiceLevel: String, CaseIterable, Codable, Sendable, Identifiable {
    case off, keyMoments, everySet
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .off: "Off"
        case .keyMoments: "Key moments"
        case .everySet: "Every set"
        }
    }
}

/// What the coach reacts to.
public enum CoachMoment: Equatable, Sendable {
    /// Workout opened (first exercise).
    case start(exercises: Int)
    /// A loaded set was logged; `last*` = the same set number last time this exercise was done.
    case setLogged(set: Int, of: Int, kg: Double, reps: Int, lastKg: Double?, lastReps: Int?)
    /// The final set of an exercise with more than one set is next.
    case finalSet(exercise: String)
    /// Half the exercises are done.
    case halfway(left: Int)
    /// Rest is about to end.
    case restEnding(seconds: Int)
    /// Best set ever for this exercise; `heavierBy` when the weight itself is a record.
    case record(exercise: String, kg: Double, reps: Int, heavierBy: Double?)
    /// Workout finished.
    case finish(sets: Int, volumeKg: Double, minutes: Int)

    /// Key moments are spoken at the "Key moments" voice level; the others only at "Every set".
    public var isKey: Bool {
        switch self {
        case .setLogged, .restEnding: false
        default: true
        }
    }
}

public enum CoachLines {
    /// The line for a moment. `seed` picks one of the variants so lines don't repeat back to back.
    public static func line(_ m: CoachMoment, style: CoachStyle, seed: Int = 0) -> String {
        let options = variants(m, style: style)
        return options[abs(seed) % options.count]
    }

    /// Best set ever: a loaded set whose estimated 1RM beats every earlier set of the exercise, or a heavier weight
    /// than ever lifted. `history` = earlier sets only (not this session's). Needs some history, so a first session
    /// isn't a stream of records.
    public static func record(kg: Double, reps: Int, history: [SetLog]) -> (isRecord: Bool, heavierBy: Double?) {
        let earlier = history.filter { $0.kg > 0 && ($0.reps ?? 0) > 0 }
        guard kg > 0, reps > 0, !earlier.isEmpty else { return (false, nil) }
        let maxKg = earlier.map(\.kg).max() ?? 0
        if kg > maxKg + 0.01 { return (true, kg - maxKg) }
        let best = earlier.compactMap { LoadAdvisor.epley(kg: $0.kg, reps: $0.reps) }.max()
        if let now = LoadAdvisor.epley(kg: kg, reps: reps), let best, now > best + 0.25 { return (true, nil) }
        return (false, nil)
    }

    static func kgText(_ v: Double) -> String { LoadAdvisor.formatKg(v) + " kg" }

    static func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    private static func compare(kg: Double, reps: Int, lastKg: Double?, lastReps: Int?) -> String? {
        guard let lastKg, let lastReps else { return nil }
        if kg > lastKg + 0.01 { return "\(LoadAdvisor.formatKg(kg - lastKg)) kg more than last time" }
        if abs(kg - lastKg) < 0.01, reps > lastReps { return reps - lastReps == 1 ? "one rep more than last time" : "\(reps - lastReps) reps more than last time" }
        if abs(kg - lastKg) < 0.01, reps == lastReps { return "same as last time" }
        return nil
    }

    static func variants(_ m: CoachMoment, style: CoachStyle) -> [String] {
        switch (m, style) {
        case let (.start(n), .chill):
            return ["\(n) exercises today. Easy start, good form, we build from there.",
                    "Let's go. \(n) exercises, one at a time.",
                    "Nice to see you. Breathe, settle in, first set when you're ready."]
        case let (.start(n), .hype):
            return ["Let's go! \(n) exercises, let's own every one.",
                    "Game on! \(n) moves between you and a great workout.",
                    "You showed up. That's the hardest rep. \(n) exercises, let's do this!"]
        case let (.start(n), .drill):
            return ["\(n) exercises. No excuses. Move.",
                    "Clock's running. \(n) exercises. First set, now.",
                    "Focus. \(n) exercises. Every rep clean."]

        case let (.setLogged(i, n, kg, reps, lk, lr), .chill):
            let c = compare(kg: kg, reps: reps, lastKg: lk, lastReps: lr)
            return [c.map { "Set \(i). \(cap($0)). Nice." } ?? "Set \(i) of \(n) done. Nice and steady.",
                    "\(reps) reps at \(kgText(kg)). Shake it out, breathe.",
                    c.map { "Good set, \($0)." } ?? "Good set. Recover well."]
        case let (.setLogged(i, n, kg, reps, lk, lr), .hype):
            let c = compare(kg: kg, reps: reps, lastKg: lk, lastReps: lr)
            return [c.map { "Boom! \(cap($0))!" } ?? "Boom! Set \(i) of \(n) done!",
                    "\(reps) at \(kgText(kg))! That's how it's done!",
                    c.map { "Yes! \(cap($0))!" } ?? "Strong set! Keep that energy!"]
        case let (.setLogged(i, n, kg, reps, lk, lr), .drill):
            let c = compare(kg: kg, reps: reps, lastKg: lk, lastReps: lr)
            return [c.map { "Set \(i). \(cap($0)). Again." } ?? "Set \(i) of \(n). Logged. Next.",
                    "\(reps) at \(kgText(kg)). Recover. Don't get comfortable.",
                    c.map { "\(cap($0)). Expected." } ?? "Done. Rest is earned, not given."]

        case let (.finalSet(e), .chill):
            return ["Last set of \(e). Make it your best one.", "Final set. Smooth and controlled.", "One more set, then \(e) is done."]
        case let (.finalSet(e), .hype):
            return ["Last set! Make it count!", "Final set of \(e)! Empty the tank!", "This is the one! Last set, go!"]
        case let (.finalSet(e), .drill):
            return ["Final set. Leave nothing.", "Last set of \(e). Every rep. Full range.", "Final set. Finish strong or don't finish."]

        case let (.halfway(left), .chill):
            return ["Halfway there. \(left) to go, you're doing great.", "Half done. Keep the pace easy.", "That's half. Sip some water."]
        case let (.halfway(left), .hype):
            return ["Halfway! You're past the hump!", "Half done! \(left) left, let's finish this!", "Halfway and flying!"]
        case let (.halfway(left), .drill):
            return ["Halfway. \(left) left. No slowing down.", "Half done. The second half decides.", "Halfway. Stay sharp."]

        case let (.restEnding(s), .chill):
            return ["\(s) seconds. Get comfortable on the machine.", "Almost time. \(s) seconds.", "\(s) seconds, deep breath."]
        case let (.restEnding(s), .hype):
            return ["\(s) seconds! Get ready!", "\(s) seconds, here we go again!", "Get set, \(s) seconds!"]
        case let (.restEnding(s), .drill):
            return ["\(s) seconds. Hands on.", "\(s). Get in position.", "\(s) seconds. Up."]

        case let (.record(e, kg, reps, more), .chill):
            return [more.map { "New personal record! \(kgText(kg)), \(LoadAdvisor.formatKg($0)) kg on your best." }
                        ?? "New best set on \(e). \(reps) at \(kgText(kg)). Well done.",
                    "That's a record. \(reps) at \(kgText(kg)). Enjoy it."]
        case let (.record(e, kg, reps, more), .hype):
            return [more.map { "Beast mode! Plus \(LoadAdvisor.formatKg($0)) kg on your best!" } ?? "New record! \(reps) at \(kgText(kg))!",
                    "Personal record on \(e)! You're on fire!"]
        case let (.record(e, kg, reps, more), .drill):
            return [more.map { "Record. Plus \(LoadAdvisor.formatKg($0)) kg. Now beat it next time." } ?? "Record. \(reps) at \(kgText(kg)). Now own it.",
                    "New best on \(e). That's the standard now."]

        case let (.finish(sets, _, min), .chill):
            return ["Workout done. \(sets) sets in \(min) minutes. Rest well.", "All done. Good work today, be proud."]
        case let (.finish(sets, vol, min), .hype):
            return [vol >= 1 ? "Done! \(sets) sets, \(Int(vol.rounded())) kilos moved! Legend!" : "Done! \(sets) sets in \(min) minutes! Legend!",
                    "Workout crushed! See you next time, champ!"]
        case let (.finish(sets, _, min), .drill):
            return ["Done. \(sets) sets, \(min) minutes. Eat, sleep, repeat.", "Workout complete. Recover. Come back stronger."]
        }
    }
}
