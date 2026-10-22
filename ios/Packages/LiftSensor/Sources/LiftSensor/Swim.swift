import Foundation

// Swimming (#624, design A + B + C from `apple-tech-radar/x7.png`): swim workouts written as sets with send-offs
// (A), multi-week plans made of them (B), and a short swim block added to a gym day (C). Shared with the Watch,
// which runs the send-off clock under Water Lock (#615).

public enum SwimStroke: String, Codable, CaseIterable, Sendable, Identifiable {
    case free, back, breast, fly, im, drill, kick, easy

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .free: "free"
        case .back: "back"
        case .breast: "breast"
        case .fly: "fly"
        case .im: "IM"
        case .drill: "drill"
        case .kick: "kick"
        case .easy: "easy"
        }
    }
}

/// "4 × 100 free @ 2:00": `reps` swims of `meters`, each leaving on the send-off (rest is what's left of it).
public struct SwimSet: Codable, Hashable, Sendable {
    public var reps: Int
    public var meters: Int
    public var stroke: SwimStroke
    /// Seconds from one start to the next.
    public var sendOff: Int

    public init(reps: Int, meters: Int, stroke: SwimStroke, sendOff: Int) {
        self.reps = max(1, reps)
        self.meters = max(25, meters)
        self.stroke = stroke
        self.sendOff = max(15, sendOff)
    }

    public var totalMeters: Int { reps * meters }
    public var seconds: Int { reps * sendOff }

    /// "4×100 free", "300 m easy".
    public var title: String { reps == 1 ? "\(meters) m \(stroke.label)" : "\(reps)×\(meters) \(stroke.label)" }

    /// "4×100 free @ 2:00".
    public var full: String { reps == 1 ? title : "\(title) @ \(WodTimer.clock(sendOff))" }
}

public struct SwimWorkout: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var sets: [SwimSet]

    public init(id: String = UUID().uuidString, name: String, sets: [SwimSet]) {
        self.id = id
        self.name = name
        self.sets = sets
    }

    public var totalMeters: Int { sets.reduce(0) { $0 + $1.totalMeters } }
    public var seconds: Int { sets.reduce(0) { $0 + $1.seconds } }
    public var minutes: Int { Int((Double(seconds) / 60).rounded(.up)) }

    /// "300 m easy · 4×50 fast" style line: every set's title.
    public var summary: String { sets.map(\.title).joined(separator: " · ") }

    // MARK: Send-off clock

    public struct Clock: Equatable, Sendable {
        /// Index of the set and 1-based rep being swum.
        public let set: Int
        public let rep: Int
        /// Seconds until the next send-off (next rep or next set).
        public let nextIn: Int
        public let finished: Bool
    }

    /// Where the member is `elapsed` seconds after pushing off: sets follow each other with no gap.
    public func clock(at elapsed: TimeInterval) -> Clock {
        var t = 0
        let s = Int(max(0, elapsed).rounded(.down))
        for (i, set) in sets.enumerated() {
            if s < t + set.seconds {
                let into = s - t
                return Clock(set: i, rep: into / set.sendOff + 1, nextIn: set.sendOff - into % set.sendOff, finished: false)
            }
            t += set.seconds
        }
        return Clock(set: max(0, sets.count - 1), rep: sets.last?.reps ?? 1, nextIn: 0, finished: true)
    }

    /// Send-offs passed in (from, to]: the Watch buzzes once for each.
    public func sendOffs(from: TimeInterval, to: TimeInterval) -> Int {
        let a = Int(max(0, from).rounded(.down)), b = Int(max(0, to).rounded(.down))
        guard b > a else { return 0 }
        var starts: [Int] = []
        var t = 0
        for set in sets {
            for r in 0..<set.reps { starts.append(t + r * set.sendOff) }
            t += set.seconds
        }
        starts.append(t)
        return starts.filter { $0 > a && $0 <= b }.count
    }

    // MARK: Gym day block (C)

    public enum Place: String, Codable, CaseIterable, Sendable, Identifiable {
        case warmup, finisher

        public var id: String { rawValue }
        public var label: String { self == .warmup ? "Warm-up" : "Finisher" }
    }

    /// A short swim before or after lifting: easy swim plus fast 50s, sized to `minutes` at `pace` seconds per 100 m.
    public static func block(minutes: Int, place: Place, pace: Int = SwimPlan.Goal.oneK.pace) -> SwimWorkout {
        let total = max(5, minutes) * 60
        let easyMeters = max(100, (total / 2) * 100 / pace / 50 * 50)
        let easy = SwimSet(reps: 1, meters: easyMeters, stroke: .easy, sendOff: roundUp(Double(easyMeters) / 100 * Double(pace) * 1.1))
        let fastSend = roundUp(0.5 * Double(pace) + 20)
        let fastReps = max(2, (total - easy.seconds) / fastSend)
        let fast = SwimSet(reps: place == .warmup ? min(fastReps, 4) : fastReps, meters: 50, stroke: .free, sendOff: fastSend)
        return SwimWorkout(id: "block-\(place.rawValue)-\(minutes)", name: "Swim \(place.label.lowercased())", sets: [easy, fast])
    }

    /// Up to the next 5 seconds.
    static func roundUp(_ s: Double) -> Int { Int((s / 5).rounded(.up)) * 5 }
}

/// Multi-week swim plan (B): learn to swim → 1 km non-stop → 2 km, 2 or 3 swims a week on days without lifting.
public struct SwimPlan: Codable, Hashable, Sendable {
    public enum Goal: String, Codable, CaseIterable, Sendable, Identifiable {
        case learn, oneK, twoK

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .learn: "Learn to swim"
            case .oneK: "1 km non-stop"
            case .twoK: "2 km"
            }
        }

        /// Distance swum non-stop in the final session.
        public var test: Int {
            switch self {
            case .learn: 200
            case .oneK: 1000
            case .twoK: 2000
            }
        }

        /// Session volume in week 1 and the last week, metres.
        var volume: (Int, Int) {
            switch self {
            case .learn: (200, 500)
            case .oneK: (600, 1300)
            case .twoK: (1200, 2400)
            }
        }

        /// Easy pace per 100 m, seconds, used for send-offs until the Watch knows better.
        public var pace: Int {
            switch self {
            case .learn: 180
            case .oneK: 150
            case .twoK: 130
            }
        }
    }

    public var goal: Goal
    public var weeks: Int
    public var perWeek: Int
    /// First day of week 1.
    public var start: Date
    /// Weekdays the swims fall on (Calendar weekday, 1 = Sunday).
    public var days: [Int]
    /// Pool length, metres (25 or 50).
    public var pool: Int

    public init(goal: Goal, weeks: Int = 8, perWeek: Int = 2, start: Date, days: [Int], pool: Int = 25) {
        self.goal = goal
        self.weeks = max(2, weeks)
        self.perWeek = min(3, max(1, perWeek))
        self.start = start
        self.days = days
        self.pool = pool
    }

    /// Spread `perWeek` swims over the week, away from lifting days when there is room (fits lifting days).
    public static func days(perWeek: Int, lifting: Set<Int>) -> [Int] {
        // Spaced picks first (Tue Thu Sat…), lifting days only when the free ones run out.
        let order = [3, 5, 7, 2, 4, 6, 1]
        let free = order.filter { !lifting.contains($0) }
        var picked: [Int] = []
        for d in free where picked.count < perWeek && !picked.contains(where: { abs($0 - d) == 1 }) { picked.append(d) }
        for d in free + order where picked.count < perWeek && !picked.contains(d) { picked.append(d) }
        return picked.sorted()
    }

    /// 1-based week of `date`, nil before the start or after the last week.
    public func week(on date: Date, calendar: Calendar = .current) -> Int? {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)).day ?? -1
        guard days >= 0 else { return nil }
        let w = days / 7 + 1
        return w <= weeks ? w : nil
    }

    /// The swim planned on `date`, if it's a swim day of the plan.
    public func workout(on date: Date, calendar: Calendar = .current) -> SwimWorkout? {
        guard let w = week(on: date, calendar: calendar) else { return nil }
        let wd = calendar.component(.weekday, from: date)
        guard let i = days.sorted().firstIndex(of: wd) else { return nil }
        return workout(week: w, index: i)
    }

    /// Next swim day from `date` on (today included), with its workout.
    public func next(from date: Date, calendar: Calendar = .current) -> (day: Date, workout: SwimWorkout)? {
        let today = calendar.startOfDay(for: date)
        for k in 0..<14 {
            guard let d = calendar.date(byAdding: .day, value: k, to: today) else { continue }
            if let w = workout(on: d, calendar: calendar) { return (d, w) }
        }
        return nil
    }

    /// Session `index` (0-based within the week) of week `week`: intervals, longer reps, drills + steady; the last
    /// session of the last week is the non-stop test.
    public func workout(week: Int, index: Int) -> SwimWorkout {
        let w = min(max(1, week), weeks)
        let name = "Week \(w) · swim \(index + 1)"
        if w == weeks && index == perWeek - 1 {
            let send = SwimWorkout.roundUp(Double(goal.test) / 100 * Double(goal.pace) * 1.15)
            return SwimWorkout(id: "plan-\(goal.rawValue)-\(w)-\(index)", name: "\(goal.label) test",
                               sets: [SwimSet(reps: 1, meters: 100, stroke: .easy, sendOff: SwimWorkout.roundUp(Double(goal.pace) * 1.2)),
                                      SwimSet(reps: 1, meters: goal.test, stroke: .free, sendOff: send)])
        }
        let (lo, hi) = goal.volume
        let raw = Double(lo) + Double(hi - lo) * Double(w - 1) / Double(max(1, weeks - 1))
        let total = Int(raw / 50) * 50
        let unit = goal == .learn ? 25 : 50
        let warm = goal == .learn ? 50 : (total >= 1500 ? 300 : 200)
        let cool = goal == .learn ? 0 : 100
        let main = max(unit * 2, total - warm - cool)
        func send(_ meters: Int, rest: Int) -> Int { SwimWorkout.roundUp(Double(meters) / 100 * Double(goal.pace) + Double(rest)) }
        var sets = [SwimSet(reps: 1, meters: warm, stroke: .easy, sendOff: send(warm, rest: 20))]
        switch index % 3 {
        case 0:
            let d = unit * 2
            sets.append(SwimSet(reps: max(2, main / d), meters: d, stroke: .free, sendOff: send(d, rest: 15)))
        case 1:
            let d = goal == .learn ? 50 : (goal == .oneK ? 200 : 400)
            sets.append(SwimSet(reps: max(1, main / d), meters: d, stroke: .free, sendOff: send(d, rest: 25)))
        default:
            sets.append(SwimSet(reps: 4, meters: unit, stroke: .drill, sendOff: send(unit, rest: 20)))
            let steady = max(unit, (main - 4 * unit) / unit * unit)
            sets.append(SwimSet(reps: 1, meters: steady, stroke: .free, sendOff: send(steady, rest: 30)))
        }
        if cool > 0 { sets.append(SwimSet(reps: 1, meters: cool, stroke: .easy, sendOff: send(cool, rest: 20))) }
        return SwimWorkout(id: "plan-\(goal.rawValue)-\(w)-\(index)", name: name, sets: sets)
    }
}
