import Foundation

/// WOD and combat timers (#622, design A + B + C from `apple-tech-radar/x5.png`): one engine for Tabata, EMOM, AMRAP,
/// For time and Rounds (boxing), run on the Watch, on the iPhone big screen and in the builder. Pure maths: the
/// caller owns the clock and passes the seconds elapsed (pauses taken out).
public struct WodTimer: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable, Identifiable {
        case tabata, emom, amrap, forTime, rounds

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .tabata: "Tabata"
            case .emom: "EMOM"
            case .amrap: "AMRAP"
            case .forTime: "For time"
            case .rounds: "Rounds"
            }
        }

        /// Gradient of the kind's tile (start, end), shared by the iPhone and the Watch.
        public var tint: (UInt32, UInt32) {
            switch self {
            case .tabata: (0xFF3D8B, 0xFF9A5E)
            case .emom: (0x3D59FF, 0x00C7FF)
            case .amrap: (0xFF7A00, 0xFFC23D)
            case .forTime: (0x00B86B, 0x3DD9FF)
            case .rounds: (0xD6246E, 0xFF5F6D)
            }
        }

        /// Only AMRAP and For time have a single capped block; the others repeat rounds.
        public var capped: Bool { self == .amrap || self == .forTime }
    }

    public var id: String
    public var name: String
    public var kind: Kind
    /// Seconds of work per round; AMRAP and For time: the time cap.
    public var work: Int
    /// Seconds of rest between rounds (none after the last).
    public var rest: Int
    public var rounds: Int
    /// Moves shown under the clock ("10 KB swings"), in order.
    public var moves: [String]
    /// Boxing: the Watch counts punches per round (#611 C).
    public var punches: Bool
    /// Countdown before the first round.
    public var prep: Int

    public init(id: String = UUID().uuidString, name: String, kind: Kind, work: Int, rest: Int = 0, rounds: Int = 1,
                moves: [String] = [], punches: Bool = false, prep: Int = 10) {
        self.id = id
        self.name = name
        self.kind = kind
        self.work = max(5, work)
        self.rest = max(0, rest)
        self.rounds = kind.capped ? 1 : max(1, rounds)
        self.moves = moves
        self.punches = punches
        self.prep = max(0, prep)
    }

    // MARK: Presets

    public static let tabata = WodTimer(id: "preset-tabata", name: "Tabata", kind: .tabata, work: 20, rest: 10, rounds: 8)
    public static let emom = WodTimer(id: "preset-emom", name: "EMOM 10", kind: .emom, work: 60, rounds: 10)
    public static let amrap = WodTimer(id: "preset-amrap", name: "AMRAP 12", kind: .amrap, work: 12 * 60,
                                       moves: ["10 KB swings", "10 push-ups", "10 squats"])
    public static let forTime = WodTimer(id: "preset-fortime", name: "For time", kind: .forTime, work: 20 * 60)
    /// Boxing rounds (B): 6 × 3′ with 1′ rest, bell, clap at 10″, punches counted.
    public static let boxing = WodTimer(id: "preset-boxing", name: "Boxing", kind: .rounds, work: 180, rest: 60, rounds: 6, punches: true)
    /// Amateur bout: 3 × 3′ / 1′.
    public static let bout = WodTimer(id: "preset-bout", name: "Bout 3 × 3′", kind: .rounds, work: 180, rest: 60, rounds: 3, punches: true)

    public static let presets: [WodTimer] = [.tabata, .emom, .amrap, .forTime, .boxing]

    /// A fresh timer of `kind` with its usual numbers, for the builder.
    public static func starting(_ kind: Kind) -> WodTimer {
        var t = presets.first { $0.kind == kind } ?? .tabata
        t.id = UUID().uuidString
        t.name = kind.label
        return t
    }

    /// "8 × 20″ / 10″", "Every min × 10", "12′ cap", "6 × 3′ / 1′".
    public var summary: String {
        switch kind {
        case .tabata, .rounds:
            rest > 0 ? "\(rounds) × \(Self.short(work)) / \(Self.short(rest))" : "\(rounds) × \(Self.short(work))"
        case .emom:
            work == 60 ? "Every min × \(rounds)" : "Every \(Self.short(work)) × \(rounds)"
        case .amrap:
            "\(Self.short(work)) as many rounds"
        case .forTime:
            "\(Self.short(work)) cap"
        }
    }

    /// 20 → 20″, 180 → 3′, 90 → 1′30″.
    public static func short(_ s: Int) -> String {
        if s < 60 { return "\(s)″" }
        return s % 60 == 0 ? "\(s / 60)′" : "\(s / 60)′\(s % 60)″"
    }

    /// 754 → "12:34".
    public static func clock(_ s: Int) -> String {
        let t = max(0, s)
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }

    // MARK: Phases

    public enum PhaseKind: String, Codable, Sendable {
        case prep, work, rest
    }

    public struct Phase: Equatable, Sendable {
        public let kind: PhaseKind
        /// 1-based round; 0 for prep.
        public let round: Int
        /// Start offset and length, seconds.
        public let start: Int
        public let seconds: Int

        public var end: Int { start + seconds }
    }

    /// Prep, then each round's work with rest between rounds.
    public var phases: [Phase] {
        var out: [Phase] = []
        var t = 0
        if prep > 0 {
            out.append(Phase(kind: .prep, round: 0, start: 0, seconds: prep))
            t = prep
        }
        for r in 1...rounds {
            out.append(Phase(kind: .work, round: r, start: t, seconds: work))
            t += work
            if rest > 0 && r < rounds {
                out.append(Phase(kind: .rest, round: r, start: t, seconds: rest))
                t += rest
            }
        }
        return out
    }

    /// Whole timer, prep included.
    public var totalSeconds: Int { phases.last?.end ?? 0 }

    public struct State: Equatable, Sendable {
        public let phase: Phase?
        /// Seconds left in the phase (shown as the countdown).
        public let remaining: Int
        /// Seconds into the phase (For time counts up).
        public let into: Int
        public let finished: Bool
    }

    public func state(at elapsed: TimeInterval) -> State {
        let s = Int(max(0, elapsed).rounded(.down))
        let list = phases
        guard let p = list.first(where: { s < $0.end }) else {
            return State(phase: list.last, remaining: 0, into: list.last?.seconds ?? 0, finished: true)
        }
        return State(phase: p, remaining: p.end - s, into: s - p.start, finished: false)
    }

    /// What the clock shows: For time counts up during work, everything else counts down.
    public func display(at elapsed: TimeInterval) -> Int {
        let st = state(at: elapsed)
        return kind == .forTime && st.phase?.kind == .work ? st.into : st.remaining
    }

    // MARK: Cues

    public enum Cue: String, Equatable, Sendable {
        /// Round starts.
        case bell
        /// Work ends, rest starts.
        case rest
        /// 10 seconds left in a work round (boxing clap), only for rounds of 30 s or more.
        case clap
        /// 3-2-1 before a round starts.
        case tick
        /// Last round over.
        case done
    }

    /// Cues whose second falls in (from, to]: the caller asks for each stretch of time it ran, so none is missed or doubled.
    /// A first round with no prep starts at 0: the caller rings its bell on start.
    public func cues(from: TimeInterval, to: TimeInterval) -> [Cue] {
        let a = Int(max(0, from).rounded(.down)), b = Int(max(0, to).rounded(.down))
        guard b > a else { return [] }
        var out: [Cue] = []
        let list = phases
        for second in (a + 1)...b {
            for (i, p) in list.enumerated() {
                if p.kind == .work && p.start == second && second > 0 { out.append(.bell) }
                if p.kind == .work && p.seconds >= 30 && p.end - 10 == second { out.append(.clap) }
                if p.kind == .work && p.end == second {
                    out.append(i == list.count - 1 ? .done : .rest)
                }
                if p.kind != .work, i + 1 < list.count, list[i + 1].kind == .work, (1...3).contains(p.end - second) {
                    out.append(.tick)
                }
            }
        }
        return out
    }
}
