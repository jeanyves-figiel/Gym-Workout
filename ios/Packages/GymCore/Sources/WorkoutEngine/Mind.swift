import Foundation

// Mental health & relaxation (#834, designs A + B + C from `mental-health/proposals.png`): a short mood check-in,
// guided breathing and relax sessions, and a daily Mind score with the patterns Coach finds in them.

/// One breathing or relax session in Explore → Calm. Every session is a breathing pattern repeated for its length;
/// guided ones (body scan, pre-lift focus) add spoken cues spread evenly over the session.
public enum Breath: String, CaseIterable, Codable, Sendable, Identifiable {
    case box, sleep478, sigh, wake, bodyScan, focus

    public var id: String { rawValue }

    public enum Group: String, CaseIterable, Sendable {
        case breathe, relax
        public var label: String { self == .breathe ? "Breathe" : "Relax" }
    }

    public var group: Group { [.bodyScan, .focus].contains(self) ? .relax : .breathe }

    public var label: String {
        switch self {
        case .box: "Box 4-4-4-4"
        case .sleep478: "4-7-8"
        case .sigh: "Physio sigh"
        case .wake: "Wake-up"
        case .bodyScan: "Body scan"
        case .focus: "Pre-lift focus"
        }
    }

    /// What it is for, on the tile.
    public var purpose: String {
        switch self {
        case .box: "Focus"
        case .sleep478: "Sleep"
        case .sigh: "Stress"
        case .wake: "Energy"
        case .bodyScan: "Unwind"
        case .focus: "Before a workout"
        }
    }

    public var symbol: String {
        switch self {
        case .box: "square"
        case .sleep478: "moon.stars.fill"
        case .sigh: "wind"
        case .wake: "bolt.fill"
        case .bodyScan: "figure.mind.and.body"
        case .focus: "scope"
        }
    }

    /// One line on how to do it, under the player's title.
    public var how: String {
        switch self {
        case .box: "In 4, hold 4, out 4, hold 4. Calms and sharpens."
        case .sleep478: "In through the nose 4, hold 7, slowly out 8."
        case .sigh: "Two breaths in through the nose, one long sigh out."
        case .wake: "Deep in, quick out. Stop if you feel light-headed."
        case .bodyScan: "Slow breathing while you relax one area at a time."
        case .focus: "Slow breathing, then picture your first set."
        }
    }

    /// Gradient, top leading → bottom trailing.
    public var colors: [UInt32] {
        switch self {
        case .box: [0xFF3D9A, 0x7A2CFF]
        case .sleep478: [0x3B3F8F, 0x7A2CFF]
        case .sigh: [0xFFB23C, 0xFF3D6E]
        case .wake: [0xD4FF3A, 0x2EE6A0]
        case .bodyScan: [0x13C6A3, 0x2E8BFF]
        case .focus: [0xFF3D9A, 0x2E8BFF]
        }
    }

    /// Dark type on the light lime gradient, white on the rest.
    public var lightGradient: Bool { self == .wake }

    /// Lengths offered in minutes; the first is the default.
    public var lengths: [Int] {
        switch self {
        case .box: [3, 5, 10]
        case .sleep478: [4, 8]
        case .sigh: [1, 3, 5]
        case .wake: [2, 4]
        case .bodyScan: [8, 15]
        case .focus: [2, 4]
        }
    }

    public var defaultMinutes: Int { lengths[0] }

    public struct Phase: Sendable, Hashable {
        public enum Kind: String, Sendable {
            case inhale, topUp, hold, exhale, rest
        }

        public let kind: Kind
        public let seconds: Double

        public init(_ kind: Kind, _ seconds: Double) {
            self.kind = kind
            self.seconds = seconds
        }

        /// Spoken and shown in the player.
        public var label: String {
            switch kind {
            case .inhale: "Breathe in"
            case .topUp: "In a little more"
            case .hold: "Hold"
            case .exhale: "Breathe out"
            case .rest: "Hold empty"
            }
        }

        /// Size of the breathing square at the end of the phase, 0 (empty) to 1 (full).
        public var fill: Double {
            switch kind {
            case .inhale: 0.85
            case .topUp, .hold: 1
            case .exhale, .rest: 0
            }
        }
    }

    /// One cycle.
    public var phases: [Phase] {
        switch self {
        case .box: [.init(.inhale, 4), .init(.hold, 4), .init(.exhale, 4), .init(.rest, 4)]
        case .sleep478: [.init(.inhale, 4), .init(.hold, 7), .init(.exhale, 8)]
        case .sigh: [.init(.inhale, 2), .init(.topUp, 1), .init(.exhale, 6)]
        case .wake: [.init(.inhale, 2.5), .init(.exhale, 1.5)]
        case .bodyScan: [.init(.inhale, 4), .init(.exhale, 6)]
        case .focus: [.init(.inhale, 4), .init(.hold, 2), .init(.exhale, 6)]
        }
    }

    public var cycleSeconds: Double { phases.reduce(0) { $0 + $1.seconds } }

    /// Whole cycles for `minutes` (at least one), so a session always ends on a breath out.
    public func cycles(minutes: Int) -> Int { max(1, Int((Double(minutes) * 60 / cycleSeconds).rounded())) }

    public func totalSeconds(minutes: Int) -> Double { Double(cycles(minutes: minutes)) * cycleSeconds }

    /// Spoken cues of guided sessions, spread evenly over the session.
    public var cues: [String] {
        switch self {
        case .bodyScan:
            ["Close your eyes and let your breath slow down", "Relax your feet and toes", "Let your calves and knees go soft",
             "Release your thighs and hips", "Let your belly rise and fall", "Drop your shoulders away from your ears",
             "Soften your arms and hands", "Unclench your jaw, relax your face", "Feel your whole body, heavy and calm"]
        case .focus:
            ["Slow your breath, long out-breaths", "Picture your first set, clean reps", "Feel your feet planted, core braced",
             "One cue for today: tight and smooth", "Ready. Go lift"]
        default: []
        }
    }

    /// Where the session is `t` seconds in: the phase and its index in `phases`, seconds into it, the cycle (from 0)
    /// and the cue showing.
    public func at(_ t: Double, minutes: Int) -> (phase: Phase, index: Int, into: Double, cycle: Int, cue: String?) {
        let total = totalSeconds(minutes: minutes)
        let clamped = min(max(0, t), max(0, total - 0.001))
        let cycle = min(cycles(minutes: minutes) - 1, Int(clamped / cycleSeconds))
        var rest = clamped - Double(cycle) * cycleSeconds
        var index = phases.count - 1
        for (i, p) in phases.enumerated() {
            if rest < p.seconds {
                index = i
                break
            }
            rest -= p.seconds
        }
        let phase = phases[index]
        let cue: String? = cues.isEmpty ? nil : cues[min(cues.count - 1, Int(clamped / (total / Double(cues.count))))]
        return (phase, index, min(max(0, rest), phase.seconds), cycle, cue)
    }
}

/// What weighs on the member's mood today, picked on the check-in (Apple Health State of Mind associations).
public enum MindFeeling: String, CaseIterable, Codable, Sendable, Identifiable {
    case sleep, work, family, friends, training, health, money, weather

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sleep: "Sleep"
        case .work: "Work"
        case .family: "Family"
        case .friends: "Friends"
        case .training: "Training"
        case .health: "Health"
        case .money: "Money"
        case .weather: "Weather"
        }
    }
}

/// One mood check-in: mood 1–5 (`Feel` raw values) and what it is about.
public struct MindCheckIn: Codable, Sendable, Hashable {
    public var date: Date
    public var mood: Int
    public var feelings: [MindFeeling]

    public init(date: Date, mood: Int, feelings: [MindFeeling] = []) {
        self.date = date
        self.mood = min(5, max(1, mood))
        self.feelings = feelings
    }
}

/// One finished breathing or relax session (mindful minutes).
public struct MindSession: Codable, Sendable, Hashable {
    public var date: Date
    public var breath: Breath
    public var seconds: Int

    public init(date: Date, breath: Breath, seconds: Int) {
        self.date = date
        self.breath = breath
        self.seconds = seconds
    }
}

/// Daily Mind score 0–100 (design C): mood, HRV against the 30-day baseline, sleep and recent training load,
/// plus a small bonus for calm minutes today. A part with no reading drops out and the rest are reweighted.
public enum MindScore {
    public static let moodWeight = 35.0
    public static let hrvWeight = 25.0
    public static let sleepWeight = 25.0
    public static let loadWeight = 15.0
    /// HRV at or under this share of the baseline scores 0, at or over `hrvHigh` scores full.
    public static let hrvLow = 0.7
    public static let hrvHigh = 1.2
    /// Sleep hours scoring 0 and full.
    public static let sleepLow = 5.0
    public static let sleepHigh = 8.0
    /// Workout days in the last `loadDays` days (today included) and the load points each count leaves.
    public static let loadDays = 3
    public static let loadPoints: [Double] = [1, 0.8, 0.5, 0.2]
    /// +1 a calm minute today, up to this.
    public static let calmBonusMax = 5
    /// Check-ins in the last 28 days before Coach looks for patterns.
    public static let patternMin = 5

    public struct Inputs: Sendable, Equatable {
        public var mood: Int?
        public var hrv: Double?
        public var hrvBaseline: Double?
        public var sleepHours: Double?
        public var workoutDays: Int
        public var calmMinutes: Int

        public init(mood: Int? = nil, hrv: Double? = nil, hrvBaseline: Double? = nil, sleepHours: Double? = nil,
                    workoutDays: Int = 0, calmMinutes: Int = 0) {
            self.mood = mood
            self.hrv = hrv
            self.hrvBaseline = hrvBaseline
            self.sleepHours = sleepHours
            self.workoutDays = workoutDays
            self.calmMinutes = calmMinutes
        }

        /// Today's HRV over the baseline, when both are known.
        public var hrvRatio: Double? {
            guard let hrv, let b = hrvBaseline, b > 0 else { return nil }
            return hrv / b
        }
    }

    public enum Level: String, Sendable {
        case calm, steady, strained, low

        public var title: String {
            switch self {
            case .calm: "Calm"
            case .steady: "Steady"
            case .strained: "Strained"
            case .low: "Low"
            }
        }

        /// Score from which the mind counts as steady (below: strained or low).
        public static let steadyFrom = 55

        public static func of(_ score: Int) -> Level {
            switch score {
            case 75...: .calm
            case steadyFrom...: .steady
            case 35...: .strained
            default: .low
            }
        }
    }

    /// One part of the score: points 0–1 and its weight.
    public struct Part: Sendable, Equatable {
        public let name: String
        public let points: Double
        public let weight: Double
    }

    public static func parts(_ i: Inputs) -> [Part] {
        var out: [Part] = []
        if let m = i.mood { out.append(Part(name: "Mood", points: Double(min(5, max(1, m)) - 1) / 4, weight: moodWeight)) }
        if let r = i.hrvRatio { out.append(Part(name: "HRV", points: clamp((r - hrvLow) / (hrvHigh - hrvLow)), weight: hrvWeight)) }
        if let s = i.sleepHours { out.append(Part(name: "Sleep", points: clamp((s - sleepLow) / (sleepHigh - sleepLow)), weight: sleepWeight)) }
        out.append(Part(name: "Load", points: loadPoints[min(loadPoints.count - 1, max(0, i.workoutDays))], weight: loadWeight))
        return out
    }

    /// nil until there is a mood, an HRV or a night's sleep: training load alone says nothing about the mind.
    public static func score(_ i: Inputs) -> Int? {
        guard i.mood != nil || i.hrvRatio != nil || i.sleepHours != nil else { return nil }
        let p = parts(i)
        let weight = p.reduce(0) { $0 + $1.weight }
        let base = p.reduce(0) { $0 + $1.points * $1.weight } / weight * 100
        return min(100, max(0, Int(base.rounded()) + min(calmBonusMax, max(0, i.calmMinutes))))
    }

    /// Coach's one line under today's Body + Mind pair on Progress (#852). `body`: the auto-tune ready score.
    public static func todayCall(body: Int, mind: Int?) -> String {
        guard let mind else { return "Check in to see your Mind next to your Body." }
        let bodyLow = body < AutoTune.lightBelow, bodyHigh = body >= AutoTune.pushFrom
        let mindLow = mind < Level.steadyFrom
        switch (bodyLow, mindLow) {
        case (true, true): return "Both low: keep it light and breathe 3 min first."
        case (true, false): return "Body's tired, mind's fine: keep today light."
        case (false, true): return "Mind's strained: 3 min of breathing before you train helps."
        default: return bodyHigh ? "Both high: a good day to push." : "Steady day: train as planned."
        }
    }

    /// Coach's breathing pick for now: evening → 4-7-8, low mood → physio sigh, low HRV → box, a so-so morning →
    /// wake-up, otherwise box.
    public static func coachPick(mood: Int?, hrvRatio: Double?, hour: Int) -> (breath: Breath, why: String) {
        if hour >= 20 || hour < 4 { return (.sleep478, "Winding down") }
        if let mood, mood <= 2 { return (.sigh, "Rough day") }
        if let r = hrvRatio, r < 0.85 { return (.box, "HRV low") }
        if hour < 11, mood == nil || mood == 3 { return (.wake, "Morning boost") }
        return (.box, "Stay sharp")
    }

    /// Average mood of `checkIns` (last one per day), nil when none.
    public static func averageMood(_ checkIns: [MindCheckIn], calendar: Calendar) -> Double? {
        let perDay = lastPerDay(checkIns, calendar: calendar)
        guard !perDay.isEmpty else { return nil }
        return Double(perDay.values.reduce(0) { $0 + $1.mood }) / Double(perDay.count)
    }

    /// Last check-in of each day, keyed by start of day.
    public static func lastPerDay(_ checkIns: [MindCheckIn], calendar: Calendar) -> [Date: MindCheckIn] {
        var out: [Date: MindCheckIn] = [:]
        for c in checkIns.sorted(by: { $0.date < $1.date }) { out[calendar.startOfDay(for: c.date)] = c }
        return out
    }

    /// The pattern Coach spots in the last 28 days, nil with fewer than `patternMin` check-ins or nothing clear:
    /// mood the day after a workout against other days, then what low days are about, then short sleep.
    public static func pattern(checkIns: [MindCheckIn], workoutDays: Set<Date>, shortSleepDays: Set<Date> = [],
                               now: Date, calendar: Calendar) -> String? {
        let since = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: now)) ?? now
        let days = lastPerDay(checkIns.filter { $0.date >= since && $0.date <= now }, calendar: calendar)
        guard days.count >= patternMin else { return nil }
        var after: [Int] = [], other: [Int] = []
        for (day, c) in days {
            let before = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            if workoutDays.contains(before) { after.append(c.mood) } else { other.append(c.mood) }
        }
        if after.count >= 2, other.count >= 2 {
            let a = Double(after.reduce(0, +)) / Double(after.count), o = Double(other.reduce(0, +)) / Double(other.count)
            if a - o >= 0.5 { return "Your mood is higher the day after you train. Training is working for your head too." }
            if o - a >= 0.5 { return "Your mood dips the day after training. Easier sessions or a 4-7-8 at night may help." }
        }
        let low = days.values.filter { $0.mood <= 2 }
        if low.count >= 2 {
            var count: [MindFeeling: Int] = [:]
            for c in low { for f in c.feelings { count[f, default: 0] += 1 } }
            if let top = count.max(by: { $0.value == $1.value ? $0.key.rawValue > $1.key.rawValue : $0.value < $1.value }), top.value >= 2 {
                return "Low days often come with \(top.key.label.lowercased()). A 1-minute physio sigh helps when it hits."
            }
        }
        let shortLow = days.filter { shortSleepDays.contains($0.key) && $0.value.mood <= 2 }.count
        if shortLow >= 2 { return "Short nights are followed by low mornings. Try 4-7-8 before bed." }
        return nil
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
}
