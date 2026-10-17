import Foundation

// Hyrox add-on (#426, A + B + C from `other-sports/hyrox-proposals.png`): the race format, divisions and their weights,
// a pacing plan from a goal time, the recorded race and its report. Shared by the iPhone and the Watch (no Core Motion).

/// The 8 stations, in race order. Each follows a 1 km run.
public enum HyroxStation: Int, CaseIterable, Codable, Sendable, Identifiable {
    case skiErg, sledPush, sledPull, burpeeBroadJumps, rowing, farmersCarry, sandbagLunges, wallBalls

    public var id: Int { rawValue }

    public var name: String {
        switch self {
        case .skiErg: "SkiErg"
        case .sledPush: "Sled push"
        case .sledPull: "Sled pull"
        case .burpeeBroadJumps: "Burpee broad jumps"
        case .rowing: "Rowing"
        case .farmersCarry: "Farmers carry"
        case .sandbagLunges: "Sandbag lunges"
        case .wallBalls: "Wall balls"
        }
    }

    public var work: String {
        switch self {
        case .skiErg, .rowing: "1000 m"
        case .sledPush, .sledPull: "50 m"
        case .burpeeBroadJumps: "80 m"
        case .farmersCarry: "200 m"
        case .sandbagLunges: "100 m"
        case .wallBalls: "100 reps"
        }
    }

    /// Reps counted on the Watch (strokes, jumps, throws); nil for sleds and carries.
    public var counts: Bool { [HyroxStation.skiErg, .burpeeBroadJumps, .rowing, .wallBalls].contains(self) }

    /// Typical minutes of an age-group finisher (~1:30 race), used to share a goal time between stations.
    var typicalMinutes: Double {
        switch self {
        case .skiErg: 4.5
        case .sledPush: 3.5
        case .sledPull: 4.5
        case .burpeeBroadJumps: 5.0
        case .rowing: 4.75
        case .farmersCarry: 2.0
        case .sandbagLunges: 4.5
        case .wallBalls: 6.0
        }
    }
}

/// Open, Pro, Doubles or Relay, for men, women or mixed teams.
public struct HyroxDivision: Codable, Hashable, Sendable {
    public enum Category: String, Codable, CaseIterable, Sendable { case open, pro, doubles, relay }
    public enum Group: String, Codable, CaseIterable, Sendable { case men, women, mixed }

    public var category: Category
    public var group: Group

    public init(_ category: Category = .open, _ group: Group = .men) {
        self.category = category
        self.group = group == .mixed && category != .doubles && category != .relay ? .men : group
    }

    public var label: String {
        let g = switch group {
        case .men: "Men"
        case .women: "Women"
        case .mixed: "Mixed"
        }
        return "\(category.rawValue.capitalized) \(g)"
    }

    /// Pro weights; Doubles and Relay race Open weights (mixed teams: men's), which the member can change.
    private var heavy: Bool { category == .pro }
    private var women: Bool { group == .women }

    /// Default load of a station, as raced (e.g. "152 kg", "2 × 24 kg", "6 kg"); nil when there is none.
    public func load(_ s: HyroxStation) -> String? {
        switch s {
        case .sledPush: "\(women ? (heavy ? 152 : 102) : (heavy ? 202 : 152)) kg"
        case .sledPull: "\(women ? (heavy ? 103 : 78) : (heavy ? 153 : 103)) kg"
        case .farmersCarry: "2 × \(women ? (heavy ? 24 : 16) : (heavy ? 32 : 24)) kg"
        case .sandbagLunges: "\(women ? (heavy ? 20 : 10) : (heavy ? 30 : 20)) kg"
        case .wallBalls: "\(women ? (heavy ? 6 : 4) : (heavy ? 9 : 6)) kg"
        default: nil
        }
    }
}

/// One part of a race or sim.
public enum HyroxStep: Codable, Hashable, Sendable {
    /// Run number (1-based) of `meters`.
    case run(Int, meters: Int)
    case station(HyroxStation)

    public var isRun: Bool { if case .run = self { true } else { false } }

    public var station: HyroxStation? { if case let .station(s) = self { s } else { nil } }

    public var label: String {
        switch self {
        case let .run(n, m): m == 1000 ? "Run \(n)" : "Run \(n) · \(m) m"
        case let .station(s): s.name
        }
    }
}

/// A full race or a training sim recorded the same way.
public enum HyroxFormat: Codable, Hashable, Sendable {
    case full
    /// Runs and stations 1–4 (`second` false) or 5–8.
    case half(second: Bool)
    /// Compromised running: `rounds` × (1 km run + the station).
    case compromised(HyroxStation, rounds: Int)

    public var label: String {
        switch self {
        case .full: "Full race"
        case let .half(second): second ? "Sim · second half" : "Sim · first half"
        case let .compromised(s, rounds): "\(rounds) × 1 km + \(s.name)"
        }
    }

    public var steps: [HyroxStep] {
        switch self {
        case .full:
            return HyroxStation.allCases.flatMap { [HyroxStep.run($0.rawValue + 1, meters: 1000), .station($0)] }
        case let .half(second):
            return HyroxStation.allCases.filter { second ? $0.rawValue >= 4 : $0.rawValue < 4 }
                .enumerated().flatMap { [HyroxStep.run($0.offset + 1, meters: 1000), .station($0.element)] }
        case let .compromised(s, rounds):
            return (1...max(1, rounds)).flatMap { [HyroxStep.run($0, meters: 1000), .station(s)] }
        }
    }
}

/// Target seconds per step from a goal time: runs ~50 %, Roxzone ~7 %, stations share the rest by their typical
/// time. Runs slow down through the race (fresh 0.95 → 1.05 at the end).
public struct HyroxPacing: Equatable, Sendable {
    public var targets: [Double]
    public var roxzone: Double

    public init(goalSeconds: Double, steps: [HyroxStep]) {
        let runs = steps.filter(\.isRun).count
        let stations = steps.compactMap(\.station)
        roxzone = goalSeconds * 0.07 * Double(steps.count) / 16
        let stationWeight = stations.reduce(0) { $0 + $1.typicalMinutes }
        // Shares follow a typical race: 8 runs ≈ 40 min, stations ≈ 35 min.
        let runShare = Double(runs) * 5.0, stationShare = stationWeight
        let work = goalSeconds - roxzone
        let perRun = work * runShare / (runShare + stationShare) / Double(max(1, runs))
        var runIndex = 0
        targets = steps.map { step in
            switch step {
            case .run:
                let fade = runs > 1 ? 0.95 + 0.10 * Double(runIndex) / Double(runs - 1) : 1
                runIndex += 1
                return perRun * fade
            case let .station(s):
                return work * stationShare / (runShare + stationShare) * s.typicalMinutes / max(stationWeight, 1)
            }
        }
    }
}

/// One recorded step. `auto`: the Watch detected its start and end (false when moved on by hand or fixed later).
public struct HyroxSplit: Codable, Hashable, Sendable {
    public var step: HyroxStep
    public var start: Date
    public var end: Date
    public var reps: Int?
    public var auto: Bool

    public init(step: HyroxStep, start: Date, end: Date, reps: Int? = nil, auto: Bool = true) {
        self.step = step
        self.start = start
        self.end = end
        self.reps = reps
        self.auto = auto
    }

    public var seconds: Double { max(0, end.timeIntervalSince(start)) }
}

/// A race or sim as recorded on the Watch (or fixed in the report).
public struct HyroxRace: Codable, Hashable, Sendable, Identifiable {
    /// Same id as the Apple Health workout, so the iPhone shows one session.
    public var id: UUID
    public var format: HyroxFormat
    public var division: HyroxDivision
    public var start: Date
    public var end: Date
    public var goalSeconds: Double?
    public var splits: [HyroxSplit]
    public var avgHR: Double?
    public var maxHR: Double?

    public init(id: UUID = UUID(), format: HyroxFormat, division: HyroxDivision, start: Date, end: Date,
                goalSeconds: Double? = nil, splits: [HyroxSplit], avgHR: Double? = nil, maxHR: Double? = nil) {
        self.id = id
        self.format = format
        self.division = division
        self.start = start
        self.end = end
        self.goalSeconds = goalSeconds
        self.splits = splits
        self.avgHR = avgHR
        self.maxHR = maxHR
    }

    public var total: Double { max(0, end.timeIntervalSince(start)) }
    public var runSeconds: Double { splits.filter(\.step.isRun).reduce(0) { $0 + $1.seconds } }
    public var stationSeconds: Double { splits.filter { !$0.step.isRun }.reduce(0) { $0 + $1.seconds } }
    /// Time between steps (entering and leaving the stations).
    public var roxzone: Double { max(0, total - runSeconds - stationSeconds) }
    public var complete: Bool { splits.count == format.steps.count }
}

/// What the race report shows (C): every split against the plan and the last comparable race, run pace fade and
/// the station that cost the most.
public struct HyroxReport: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public var step: HyroxStep
        public var seconds: Double
        public var target: Double?
        public var last: Double?
        public var reps: Int?
        /// Seconds slower (+) or faster (−) than the plan.
        public var delta: Double? { target.map { seconds - $0 } }
    }

    public var rows: [Row]
    /// Later runs vs the first two, e.g. 0.12 = 12 % slower at the end.
    public var fade: Double?
    /// The station furthest over its target (relative), when there is a plan.
    public var weakest: HyroxStation?
    /// Change in total time vs the last comparable race (negative = faster).
    public var vsLast: Double?

    public init(_ race: HyroxRace, last: HyroxRace? = nil) {
        let pacing = race.goalSeconds.map { HyroxPacing(goalSeconds: $0, steps: race.format.steps) }
        let lastByStep = Dictionary((last?.splits ?? []).map { ($0.step, $0.seconds) }, uniquingKeysWith: { a, _ in a })
        let steps = race.format.steps
        rows = race.splits.map { sp in
            let i = steps.firstIndex(of: sp.step)
            return Row(step: sp.step, seconds: sp.seconds, target: i.flatMap { pacing?.targets[$0] },
                       last: lastByStep[sp.step], reps: sp.reps)
        }
        let runs = race.splits.filter(\.step.isRun).map(\.seconds)
        if runs.count >= 4 {
            let early = runs.prefix(2).reduce(0, +) / 2
            let late = runs.suffix(3).reduce(0, +) / 3
            fade = early > 0 ? late / early - 1 : nil
        }
        weakest = rows.compactMap { r -> (HyroxStation, Double)? in
            guard let s = r.step.station, let t = r.target, t > 0 else { return nil }
            return (s, r.seconds / t)
        }.max { $0.1 < $1.1 }.flatMap { $0.1 > 1.05 ? $0.0 : nil }
        if let last, last.format == race.format, last.complete, race.complete { vsLast = race.total - last.total }
    }

    /// What to train next, from the weakest station or the run fade.
    public var focus: String? {
        if let weakest {
            switch weakest {
            case .sledPush, .sledPull: return "\(weakest.name) · legs and pulling strength under fatigue"
            case .wallBalls, .sandbagLunges: return "\(weakest.name) · squat and lunge endurance"
            case .burpeeBroadJumps: return "\(weakest.name) · jumps under fatigue"
            case .farmersCarry: return "\(weakest.name) · grip and carries"
            case .skiErg, .rowing: return "\(weakest.name) · pacing on the erg"
            }
        }
        if let fade, fade > 0.08 { return "Compromised runs · keep your pace after the stations" }
        return nil
    }
}

public enum HyroxTime {
    /// "1:18:42", "4:38".
    public static func clock(_ s: Double) -> String {
        let t = Int(max(0, s).rounded())
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }

    /// "−0:14", "+0:44".
    public static func delta(_ s: Double) -> String {
        (s < 0 ? "−" : "+") + clock(abs(s))
    }
}
