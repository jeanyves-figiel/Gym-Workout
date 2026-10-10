import Foundation

/// How the gym day right before or after a climbing day is shaped (#47).
public enum ClimbNeighbour: String, Codable, CaseIterable, Sendable, Identifiable {
    /// No heavy pulling, grip or jumps; push and legs preferred.
    case light
    /// A hard push or legs day is welcome; only heavy pulling and grip are kept light.
    case strong
    /// Keep the day free of gym sessions when possible.
    case rest
    /// Climbing ignored for this day.
    case any
    public var id: String { rawValue }
}

/// Gym sessions on climbing days (#47).
public enum ClimbSameDay: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Only when there is no other way.
    case avoid
    /// Fine (e.g. gym in the morning, climb in the evening).
    case allow
    public var id: String { rawValue }
}

/// The user's choices for scheduling around climbing (#47). Defaults = original behaviour.
public struct ClimbPrefs: Hashable, Sendable {
    public var before: ClimbNeighbour
    public var after: ClimbNeighbour
    public var sameDay: ClimbSameDay

    public init(before: ClimbNeighbour = .light, after: ClimbNeighbour = .light, sameDay: ClimbSameDay = .avoid) {
        self.before = before
        self.after = after
        self.sameDay = sameDay
    }
}

/// Weekday-aware placement of gym sessions around climbing days.
/// Weekdays are numbered 1 = Monday … 7 = Sunday (ISO 8601); the week wraps (Sunday → Monday).
public enum WeekSchedule {
    public static let weekdays = Array(1...7)

    static let shortNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    static func index(_ weekday: Int) -> Int { ((weekday - 1) % 7 + 7) % 7 }

    public static func shortName(_ weekday: Int) -> String { shortNames[index(weekday)] }
    public static func name(_ weekday: Int) -> String { names[index(weekday)] }
    /// Single letter for compact pickers ("M", "T", …).
    public static func initial(_ weekday: Int) -> String { String(shortNames[index(weekday)].prefix(1)) }

    public static func next(_ weekday: Int) -> Int { index(weekday) + 1 == 7 ? 1 : index(weekday) + 2 }
    public static func previous(_ weekday: Int) -> Int { index(weekday) == 0 ? 7 : index(weekday) }

    /// Converts `Calendar.component(.weekday, …)` (1 = Sunday) to this numbering (1 = Monday).
    public static func fromCalendar(_ calendarWeekday: Int) -> Int { (calendarWeekday + 5) % 7 + 1 }

    /// Sorted, de-duplicated, valid weekdays.
    public static func normalized(_ days: [Int]?) -> [Int] {
        Array(Set((days ?? []).filter { (1...7).contains($0) })).sorted()
    }

    // MARK: Assignment

    public struct Slot: Hashable, Sendable {
        public let weekday: Int
        public let focus: Focus
    }

    /// Places the split's sessions on weekdays. Returns nil when neither climbing nor gym weekdays are set
    /// (the plan then stays a plain "Day 1…N" list, exactly as before).
    ///
    /// Every choice of days × ordering of the split is scored (≤ 35 × 90 candidates); lowest score wins,
    /// ties keep the first candidate so the result is deterministic.
    public static func assign(_ split: [Focus], climbing: [Int], gym: [Int], prefs: ClimbPrefs = ClimbPrefs()) -> [Slot]? {
        let climb = Set(normalized(climbing))
        let preferred = Set(normalized(gym))
        guard !climb.isEmpty || !preferred.isEmpty, !split.isEmpty, split.count <= 7 else { return nil }
        let orders = distinctPermutations(split)
        var best: [Slot]?
        var bestScore = Double.infinity
        for days in combinations(weekdays, split.count) {
            for order in orders {
                let s = score(days: days, order: order, climbing: climb, gym: preferred, prefs: prefs)
                if s < bestScore - 1e-9 {
                    bestScore = s
                    best = zip(days, order).map { Slot(weekday: $0, focus: $1) }
                }
            }
        }
        return best
    }

    /// Lower is better. See `assign`.
    static func score(days: [Int], order: [Focus], climbing: Set<Int>, gym: Set<Int>, prefs: ClimbPrefs = ClimbPrefs()) -> Double {
        var byDay: [Int: Focus] = [:]
        for (d, f) in zip(days, order) { byDay[d] = f }
        var s = 0.0
        for (d, f) in zip(days, order) {
            let climbBefore = climbing.contains(previous(d))
            let climbAfter = climbing.contains(next(d))
            // Doubling up with a climbing session only when there is no other way (unless allowed).
            if climbing.contains(d) { s += prefs.sameDay == .allow ? 1 : 12 }
            // Preferred gym days are respected whenever there are enough of them.
            if !gym.isEmpty && !gym.contains(d) { s += 20 }
            var antagonist = 0.0
            if climbAfter {
                switch prefs.before {
                // Day before climbing: no heavy pulling/grip, no high-intensity lower-body power.
                case .light: s += 3 * pullLoad(f) + 2 * lowerPower(f); antagonist = 1
                // Hard push/legs welcome; fingers and lats still spared.
                case .strong: s += 3 * pullLoad(f); antagonist = 2
                case .rest: s += 8
                case .any: break
                }
            }
            if climbBefore {
                switch prefs.after {
                // Day after climbing: fingers and lats are still tired.
                case .light: s += pullLoad(f); antagonist = max(antagonist, 1)
                case .strong: s += pullLoad(f); antagonist = max(antagonist, 2)
                case .rest: s += 8
                case .any: break
                }
            }
            // Antagonist push and leg days fit next to climbing days.
            s -= antagonist * antagonistBonus(f)
            // Spread sessions out; never stack similar sessions back to back.
            if let g = byDay[next(d)] {
                s += 1
                if g == f { s += 2 }
                if group(f) != 0 && group(f) == group(g) { s += 1.5 }
            }
        }
        return s
    }

    /// Heavy pulling / grip demand of a session type.
    static func pullLoad(_ f: Focus) -> Double {
        switch f {
        case .pull: 3
        case .upper, .fullUpper: 2
        case .fullPower: 1.5
        case .fullLower: 1
        case .lower, .legs, .conditioning: 0.5
        case .push: 0
        }
    }

    /// High-intensity lower-body power (jumps, heavy squats/hinges).
    static func lowerPower(_ f: Focus) -> Double {
        switch f {
        case .lower, .legs, .fullPower: 2
        case .fullLower: 1.5
        case .conditioning: 1
        case .fullUpper: 0.5
        case .upper, .push, .pull: 0
        }
    }

    static func antagonistBonus(_ f: Focus) -> Double {
        switch f {
        case .push: 1.5
        case .lower, .legs: 1
        case .fullLower, .upper: 0.5
        case .fullUpper, .fullPower, .pull, .conditioning: 0
        }
    }

    /// 1 = lower-dominant, 2 = pull-dominant, 0 = neither.
    static func group(_ f: Focus) -> Int {
        switch f {
        case .lower, .legs, .fullLower, .fullPower: 1
        case .pull, .upper, .fullUpper: 2
        case .push, .conditioning: 0
        }
    }

    /// k-element subsets in lexicographic order.
    static func combinations(_ items: [Int], _ k: Int) -> [[Int]] {
        guard k > 0 else { return [[]] }
        guard items.count >= k else { return [] }
        var out: [[Int]] = []
        func rec(_ start: Int, _ acc: [Int]) {
            if acc.count == k {
                out.append(acc)
                return
            }
            guard start < items.count else { return }
            for i in start..<items.count { rec(i + 1, acc + [items[i]]) }
        }
        rec(0, [])
        return out
    }

    /// Orderings of a multiset, each listed once, in a stable order (first-appearance order of the input).
    static func distinctPermutations(_ xs: [Focus]) -> [[Focus]] {
        var kinds: [Focus] = []
        var counts: [Focus: Int] = [:]
        for x in xs {
            if counts[x] == nil { kinds.append(x) }
            counts[x, default: 0] += 1
        }
        var out: [[Focus]] = []
        func rec(_ acc: [Focus]) {
            if acc.count == xs.count {
                out.append(acc)
                return
            }
            for k in kinds where counts[k, default: 0] > 0 {
                counts[k, default: 0] -= 1
                rec(acc + [k])
                counts[k, default: 0] += 1
            }
        }
        rec([])
        return out
    }

    // MARK: Display

    /// Short reason shown on a session card, e.g. "Climbing tomorrow · grip & jumps kept light".
    public static func note(weekday: Int, climbing: [Int], prefs: ClimbPrefs = ClimbPrefs()) -> String? {
        let climb = Set(normalized(climbing))
        if climb.contains(weekday) {
            return prefs.sameDay == .allow ? "Climbing day too · gym first, climb after" : "Climbing day too · keep it light"
        }
        if climb.contains(next(weekday)) {
            switch prefs.before {
            case .light, .rest: return "Climbing tomorrow · grip & explosive work kept light"
            case .strong: return "Climbing tomorrow · push hard, pulling & grip kept light"
            case .any: return "Climbing tomorrow"
            }
        }
        if climb.contains(previous(weekday)) { return "Day after climbing" }
        return nil
    }
}

extension Profile {
    /// Picked climbing weekdays (sorted, valid); empty when none are set.
    public var climbingDays: [Int] { WeekSchedule.normalized(climbingWeekdays) }
    /// Picked gym weekdays (sorted, valid); empty when none are set.
    public var gymDays: [Int] { WeekSchedule.normalized(gymWeekdays) }

    /// Scheduling choices around climbing days (#47).
    public var climbPrefs: ClimbPrefs {
        ClimbPrefs(before: climbBefore ?? .light, after: climbAfter ?? .light, sameDay: climbSameDay ?? .avoid)
    }

    /// Keeps `climbingDaysPerWeek` equal to the number of picked climbing weekdays, when any are picked.
    public mutating func syncClimbingDays() {
        let n = climbingDays.count
        if n > 0 { climbingDaysPerWeek = n }
    }
}

extension Session {
    /// "Monday" for weekday-scheduled sessions, otherwise "Day N".
    public var dayLabel: String { weekday.map { WeekSchedule.name($0) } ?? "Day \(index + 1)" }
}
