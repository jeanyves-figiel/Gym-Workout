import Foundation

/// HIIT sessions (#693, designs A + B + C from `hiit/proposals.png`): timed blocks of library moves (Tabata, EMOM,
/// AMRAP, For time, Pyramid, 30/30) with a warm-up and a cool-down. A: Coach plans HIIT days (`HiitPlan`) and
/// rotates the formats week to week; B: Explore → HIIT builds one from a format, a length, a kit and an impact
/// (`HiitSpec`, the spec is the session id so it resolves everywhere without storage); C: the interval player walks
/// `steps` (one move per work interval) and logs to History.
public enum HiitFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    case tabata, emom, amrap, forTime, pyramid, intervals

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .tabata: "Tabata"
        case .emom: "EMOM"
        case .amrap: "AMRAP"
        case .forTime: "For time"
        case .pyramid: "Pyramid"
        case .intervals: "30/30"
        }
    }

    /// Tile line under the name.
    public var tag: String {
        switch self {
        case .tabata: "20″ on · 10″ off × 8"
        case .emom: "Every minute"
        case .amrap: "Max rounds"
        case .forTime: "Race the cap"
        case .pyramid: "20-40-60-40-20″"
        case .intervals: "30″ on · 30″ off"
        }
    }

    public var symbol: String {
        switch self {
        case .tabata: "timer"
        case .emom: "clock.arrow.circlepath"
        case .amrap: "infinity"
        case .forTime: "flag.checkered"
        case .pyramid: "chart.bar.fill"
        case .intervals: "bolt.fill"
        }
    }

    /// Tile gradient (start, end); Tabata, EMOM, AMRAP and For time match the WOD timers (#622).
    public var tint: (UInt32, UInt32) {
        switch self {
        case .tabata: (0xFF3D8B, 0xFF9A5E)
        case .emom: (0x3D59FF, 0x00C7FF)
        case .amrap: (0xFF7A00, 0xFFC23D)
        case .forTime: (0x00B86B, 0x3DD9FF)
        case .pyramid: (0x9A3BD8, 0xFF3D9A)
        case .intervals: (0xE8B10E, 0xF08A3D)
        }
    }

    /// One capped block worked through at your own pace (rounds tapped / Done), not interval by interval.
    public var open: Bool { self == .amrap || self == .forTime }
}

/// A move of a HIIT block: reps for EMOM, AMRAP and For time ("10 Kettlebell swing", "12 cal Rower"); nil = worked
/// for the interval's time.
public struct HiitMove: Codable, Hashable, Sendable {
    public var exerciseId: String
    public var reps: Int?

    public init(_ exerciseId: String, reps: Int? = nil) {
        self.exerciseId = exerciseId
        self.reps = reps
    }

    public var name: String { Exercise.find(exerciseId)?.name ?? exerciseId }

    /// "10 Kettlebell swing", "12 cal Rower", or the name alone.
    public var label: String {
        guard let reps else { return name }
        return Exercise.find(exerciseId)?.category == .cardio && Hiit.machines.contains(exerciseId) ? "\(reps) cal \(name)" : "\(reps) \(name)"
    }
}

public struct HiitBlock: Codable, Hashable, Sendable {
    public var format: HiitFormat
    public var moves: [HiitMove]
    /// Work intervals (Tabata 8, EMOM minutes, 30/30 rounds, Pyramid steps); For time: rounds of the moves; AMRAP 1.
    public var rounds: Int
    /// Seconds per work interval (Pyramid: the shortest step); AMRAP and For time: the time cap.
    public var work: Int
    /// Seconds of rest between work intervals.
    public var rest: Int
    /// Seconds of rest after the block, before the next one.
    public var restAfter: Int

    public init(format: HiitFormat, moves: [HiitMove], rounds: Int, work: Int, rest: Int = 0, restAfter: Int = 0) {
        self.format = format
        self.moves = moves
        self.rounds = max(1, rounds)
        self.work = max(5, work)
        self.rest = max(0, rest)
        self.restAfter = max(0, restAfter)
    }

    /// Pyramid steps go 1-2-3-2-1 times the shortest.
    static let pyramid = [1, 2, 3, 2, 1]

    /// Work seconds of interval `i` (0-based).
    public func workSeconds(_ i: Int) -> Int {
        format == .pyramid ? work * Self.pyramid[i % Self.pyramid.count] : work
    }

    /// Intervals the player steps through: one capped step for AMRAP and For time.
    public var intervals: Int { format.open ? 1 : rounds }

    /// Block length without the rest after it.
    public var seconds: Int {
        if format.open { return work }
        return (0..<rounds).reduce(0) { $0 + workSeconds($1) } + rest * (rounds - 1)
    }

    /// "8 × 20″ / 10″", "Every min × 10", "6′ AMRAP", "3 rounds · 12′ cap", "Pyramid × 5", "10 × 30″ / 30″".
    public var summary: String {
        switch format {
        case .tabata, .intervals: "\(rounds) × \(Hiit.short(work)) / \(Hiit.short(rest))"
        case .emom: work == 60 ? "Every min × \(rounds)" : "Every \(Hiit.short(work)) × \(rounds)"
        case .amrap: "\(Hiit.short(work)) AMRAP"
        case .forTime: "\(rounds) rounds · \(Hiit.short(work)) cap"
        case .pyramid: "Pyramid × \(rounds) · \(Hiit.short(rest)) rest"
        }
    }

    /// Move of work interval `i`: Tabata, 30/30, Pyramid and EMOM cycle through the moves.
    public func move(_ i: Int) -> HiitMove? { moves.isEmpty ? nil : moves[i % moves.count] }

    /// Times each move is worked (its sets in History).
    public func sets(of moveIndex: Int) -> Int {
        if format.open { return format == .forTime ? rounds : 1 }
        guard !moves.isEmpty else { return 0 }
        return (0..<rounds).filter { $0 % moves.count == moveIndex }.count
    }
}

public struct HiitWorkout: Codable, Hashable, Sendable {
    public var name: String
    public var blocks: [HiitBlock]
    /// Timed warm-up and cool-down moves, `Hiit.easySec` each.
    public var warmup: [String]
    public var cooldown: [String]
    /// No jumps (B's Impact: Low).
    public var lowImpact: Bool
    /// Kit line ("Kettlebell · body").
    public var kit: String

    public init(name: String, blocks: [HiitBlock], warmup: [String] = Hiit.warmupMoves, cooldown: [String] = Hiit.cooldownMoves,
                lowImpact: Bool = false, kit: String = "No kit") {
        self.name = name
        self.blocks = blocks
        self.warmup = warmup
        self.cooldown = cooldown
        self.lowImpact = lowImpact
        self.kit = kit
    }

    /// "Tabata + EMOM + AMRAP".
    public var formats: String {
        var seen: [HiitFormat] = []
        for b in blocks where !seen.contains(b.format) { seen.append(b.format) }
        return seen.map(\.label).joined(separator: " + ")
    }

    public var totalSeconds: Int { steps.last.map { $0.start + $0.seconds } ?? 0 }
    public var minutes: Int { Int((Double(totalSeconds) / 60).rounded()) }

    // MARK: Steps

    public enum StepKind: String, Codable, Sendable {
        case prep, warmup, work, rest, cooldown
    }

    /// One screen of the interval player: a work interval with its move, a rest, or a warm-up / cool-down move.
    public struct Step: Hashable, Sendable {
        public let kind: StepKind
        public let start: Int
        public let seconds: Int
        /// Block index for work and rest; nil around them.
        public let block: Int?
        /// 1-based work interval within the block, and how many it has.
        public let round: Int
        public let rounds: Int
        /// Move shown (work, warm-up, cool-down); a rest shows the next move.
        public let exerciseId: String?
        public let title: String
        /// AMRAP and For time: every move of the round, in order.
        public let moves: [String]
        /// Index of the move within its block (work steps).
        public let moveIndex: Int?

        public var end: Int { start + seconds }
        /// AMRAP / For time: one capped step the member works through at their own pace.
        public var open: Bool { !moves.isEmpty }
    }

    /// Prep, warm-up moves, each block's work and rest intervals (rest after a block), cool-down moves.
    public var steps: [Step] {
        var out: [Step] = []
        var t = 0
        func add(_ kind: StepKind, _ seconds: Int, block: Int? = nil, round: Int = 0, rounds: Int = 0, exerciseId: String? = nil,
                 title: String, moves: [String] = [], moveIndex: Int? = nil) {
            guard seconds > 0 else { return }
            out.append(Step(kind: kind, start: t, seconds: seconds, block: block, round: round, rounds: rounds, exerciseId: exerciseId,
                            title: title, moves: moves, moveIndex: moveIndex))
            t += seconds
        }
        add(.prep, Hiit.prepSec, title: "Get ready")
        for (i, id) in warmup.enumerated() {
            add(.warmup, Hiit.easySec, round: i + 1, rounds: warmup.count, exerciseId: id, title: Exercise.find(id)?.name ?? id)
        }
        for (b, block) in blocks.enumerated() {
            if block.format.open {
                add(.work, block.work, block: b, round: 1, rounds: 1, exerciseId: block.moves.first?.exerciseId, title: block.format.label,
                    moves: block.moves.map(\.label), moveIndex: 0)
            } else {
                for r in 0..<block.rounds {
                    let m = block.move(r)
                    add(.work, block.workSeconds(r), block: b, round: r + 1, rounds: block.rounds, exerciseId: m?.exerciseId,
                        title: m?.label ?? block.format.label, moveIndex: block.moves.isEmpty ? nil : r % block.moves.count)
                    if r < block.rounds - 1 {
                        let next = block.move(r + 1)
                        add(.rest, block.rest, block: b, round: r + 1, rounds: block.rounds, exerciseId: next?.exerciseId,
                            title: next?.label ?? "Rest")
                    }
                }
            }
            if b < blocks.count - 1 {
                let next = blocks[b + 1]
                add(.rest, block.restAfter, block: b, round: block.intervals, rounds: block.intervals,
                    exerciseId: next.moves.first?.exerciseId, title: "Next: \(next.format.label)")
            }
        }
        for (i, id) in cooldown.enumerated() {
            add(.cooldown, Hiit.easySec, round: i + 1, rounds: cooldown.count, exerciseId: id, title: Exercise.find(id)?.name ?? id)
        }
        return out
    }

    /// Step `elapsed` seconds in (pauses taken out); nil once past the end.
    public func step(at elapsed: TimeInterval) -> Step? {
        let s = Int(max(0, elapsed).rounded(.down))
        return steps.first { s < $0.end }
    }

    // MARK: Session

    /// Item uid of a block's move, so the session's items and the player's steps match after uids are re-prefixed
    /// (plan inserts): the group label ("A1", "B2") is kept.
    public static func group(block: Int, move: Int) -> String {
        let letters = Array("ABCDEFGHIJ")
        return "\(letters[min(block, letters.count - 1)])\(move + 1)"
    }

    /// The workout as a session: warm-up, one HIIT block (letter per format block), cool-down; `hiit` carries the timing.
    public func session(id: String, index: Int = 0) -> Session {
        func timed(_ ids: [String], _ tag: String) -> [PlannedExercise] {
            ids.enumerated().map { i, eid in
                let e = Exercise.get(eid)
                return PlannedExercise(uid: "\(id)-\(tag)\(i)", exerciseId: eid, slot: e.pattern,
                                       prescription: Prescription(sets: 1, reps: "\(Hiit.easySec) s", restSec: 0, intensity: nil, note: nil),
                                       estSec: Hiit.easySec)
            }
        }
        var main: [PlannedExercise] = []
        for (b, block) in blocks.enumerated() {
            for (m, move) in block.moves.enumerated() {
                let e = Exercise.get(move.exerciseId)
                let sets = block.sets(of: m)
                let reps: String = move.reps.map { Hiit.machines.contains(move.exerciseId) ? "\($0) cal" : "\($0)" }
                    ?? "\(block.work) s"
                var p = PlannedExercise(
                    uid: "\(id)-h\(b)-\(m)", exerciseId: move.exerciseId, slot: e.pattern,
                    prescription: Prescription(sets: max(1, sets), reps: reps, restSec: block.format.open ? 0 : block.rest,
                                               intensity: "\(block.format.label) · \(block.summary)", note: nil),
                    estSec: (block.seconds + (b < blocks.count - 1 ? block.restAfter : 0)) / max(1, block.moves.count))
                p.group = Self.group(block: b, move: m)
                main.append(p)
            }
        }
        var out: [Block] = []
        let warm = timed(warmup, "wu")
        if !warm.isEmpty { out.append(Block(kind: .warmup, title: "Warm-up", targetMin: max(1, warm.count * Hiit.easySec / 60), items: warm)) }
        let mainMin = Int((Double(main.reduce(0) { $0 + $1.estSec }) / 60).rounded())
        out.append(Block(kind: .cardio, title: "HIIT · \(formats)", targetMin: mainMin, items: main,
                         note: blocks.map { "\($0.format.label): \($0.summary)" }.joined(separator: " · ")))
        let cool = timed(cooldown, "cd")
        if !cool.isEmpty { out.append(Block(kind: .cooldown, title: "Cool-down", targetMin: max(1, cool.count * Hiit.easySec / 60), items: cool)) }
        var s = Session(id: id, index: index, focus: .conditioning, title: name, targetMin: minutes, estMin: minutes, blocks: out)
        s.hiit = self
        return s
    }

    /// Low readiness or a deload: a quarter fewer work intervals, a little more rest, shorter caps.
    public func eased() -> HiitWorkout {
        var w = self
        for i in w.blocks.indices {
            var b = w.blocks[i]
            if b.format.open {
                b.work = max(120, b.work * 3 / 4 / 30 * 30)
                if b.format == .forTime { b.rounds = max(1, b.rounds - 1) }
            } else {
                b.rounds = max(2, (b.rounds * 3 + 3) / 4)
                if b.format != .emom { b.rest += 5 }
            }
            w.blocks[i] = b
        }
        return w
    }
}

extension Session {
    /// This session rebuilt from `workout` (same id, day, gym and synergy note).
    public func withHiit(_ workout: HiitWorkout) -> Session {
        var s = workout.session(id: id, index: index)
        s.weekday = weekday
        s.place = place
        s.synergy = synergy
        return s
    }
}

// MARK: - Building

public enum Hiit {
    public static let prepSec = 10
    /// Warm-up and cool-down moves.
    public static let easySec = 30

    public static let warmupMoves = ["jumping-jacks", "arm-circles", "leg-swings", "inchworm", "worlds-greatest", "bw-squat"]
    static let lowWarmupMoves = ["arm-circles", "leg-swings", "inchworm", "worlds-greatest", "bw-squat", "glute-bridge"]
    public static let cooldownMoves = ["breathing", "hamstring-stretch", "half-kneeling-hf", "pec-stretch"]

    /// Cardio machines: reps are calories.
    static let machines: Set<String> = ["rower", "ski-erg", "air-bike", "bike"]

    /// 20 → 20″, 180 → 3′, 90 → 1′30″.
    public static func short(_ s: Int) -> String {
        if s < 60 { return "\(s)″" }
        return s % 60 == 0 ? "\(s / 60)′" : "\(s / 60)′\(s % 60)″"
    }

    /// 754 → "12:34".
    public static func clock(_ s: Int) -> String {
        let t = max(0, s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    enum Area { case legs, upper, core, full }

    /// A move HIIT can use: area for balance, jumps (left out at low impact), reps for EMOM / AMRAP / For time.
    struct Pick {
        let id: String
        let area: Area
        let jumps: Bool
        let reps: Int
    }

    static let pool: [Pick] = [
        Pick(id: "burpee", area: .full, jumps: true, reps: 8),
        Pick(id: "mountain-climber", area: .core, jumps: false, reps: 20),
        Pick(id: "squat-jump", area: .legs, jumps: true, reps: 12),
        Pick(id: "high-knees", area: .full, jumps: true, reps: 30),
        Pick(id: "jumping-jacks", area: .full, jumps: true, reps: 30),
        Pick(id: "push-up", area: .upper, jumps: false, reps: 10),
        Pick(id: "bw-squat", area: .legs, jumps: false, reps: 15),
        Pick(id: "bear-crawl", area: .full, jumps: false, reps: 10),
        Pick(id: "tuck-jump", area: .legs, jumps: true, reps: 8),
        Pick(id: "v-up", area: .core, jumps: false, reps: 10),
        Pick(id: "sit-up", area: .core, jumps: false, reps: 12),
        Pick(id: "kb-swing", area: .full, jumps: false, reps: 15),
        Pick(id: "kb-thruster", area: .full, jumps: false, reps: 10),
        Pick(id: "kb-clean", area: .full, jumps: false, reps: 8),
        Pick(id: "goblet-squat", area: .legs, jumps: false, reps: 12),
        Pick(id: "db-thruster", area: .full, jumps: false, reps: 10),
        Pick(id: "db-snatch", area: .full, jumps: false, reps: 8),
        Pick(id: "reverse-lunge", area: .legs, jumps: false, reps: 10),
        Pick(id: "ball-slam", area: .upper, jumps: false, reps: 10),
        Pick(id: "battle-rope-waves", area: .upper, jumps: false, reps: 30),
        Pick(id: "box-jump", area: .legs, jumps: true, reps: 8),
        Pick(id: "rower", area: .full, jumps: false, reps: 12),
        Pick(id: "ski-erg", area: .upper, jumps: false, reps: 12),
        Pick(id: "air-bike", area: .legs, jumps: false, reps: 10),
    ]

    /// Kit picked in the builder (B); plan days use the day's gym.
    public enum Kit: String, Codable, CaseIterable, Sendable, Identifiable {
        case body, dumbbells, kettlebell, gym

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .body: "No kit"
            case .dumbbells: "Dumbbells"
            case .kettlebell: "Kettlebell"
            case .gym: "My gym"
            }
        }

        func equipment(_ gym: [Equipment]) -> Set<Equipment> {
            switch self {
            case .body: [.mat]
            case .dumbbells: [.mat, .dumbbells]
            case .kettlebell: [.mat, .kettlebells]
            case .gym: Set(gym).union([.mat])
            }
        }
    }

    /// Moves the kit allows: at least four, bodyweight ones as the fallback.
    static func moves(_ kit: Set<Equipment>, lowImpact: Bool) -> [Pick] {
        let ok = pool.filter { p in
            guard !(lowImpact && p.jumps), let e = Exercise.find(p.id) else { return false }
            return e.equipment.allSatisfy { kit.contains($0) || $0 == .mat }
        }
        return ok.count >= 4 ? ok : pool.filter { p in !(lowImpact && p.jumps) && (Exercise.find(p.id)?.equipment ?? [.barbell]).allSatisfy { $0 == .mat } }
    }

    /// Picks `n` moves from areas in turn, kit moves first, none used twice in the workout while others remain.
    static func pick(_ n: Int, from list: [Pick], used: inout Set<String>, rng: inout Rng) -> [Pick] {
        let kitFirst = list.filter { !(Exercise.find($0.id)?.equipment ?? []).filter { $0 != .mat }.isEmpty }
        var out: [Pick] = []
        let areas: [Area] = [.full, .legs, .upper, .core]
        var a = Int(rng.next() * Double(areas.count))
        while out.count < n {
            let area = areas[a % areas.count]
            a += 1
            let fresh = list.filter { p in !used.contains(p.id) && !out.contains { $0.id == p.id } }
            let source = fresh.isEmpty ? list.filter { p in !out.contains { $0.id == p.id } } : fresh
            guard !source.isEmpty else { break }
            let inArea = source.filter { $0.area == area }
            let preferKit = inArea.filter { p in kitFirst.contains { $0.id == p.id } }
            let options = !preferKit.isEmpty && rng.next() < 0.7 ? preferKit : (inArea.isEmpty ? source : inArea)
            let p = rng.pick(options)
            out.append(p)
            used.insert(p.id)
        }
        return out
    }

    static func block(_ format: HiitFormat, seconds: Int, list: [Pick], used: inout Set<String>, rng: inout Rng,
                      easy: Bool = false, restAfter: Int = 60) -> HiitBlock {
        func take(_ n: Int, reps: Bool) -> [HiitMove] {
            pick(n, from: list, used: &used, rng: &rng).map { HiitMove($0.id, reps: reps ? $0.reps : nil) }
        }
        switch format {
        case .tabata:
            return HiitBlock(format: .tabata, moves: take(2, reps: false), rounds: 8, work: 20, rest: 10, restAfter: restAfter)
        case .intervals:
            let work = easy ? 20 : 30, rest = easy ? 40 : 30
            return HiitBlock(format: .intervals, moves: take(4, reps: false), rounds: max(4, seconds / 60), work: work, rest: rest,
                             restAfter: restAfter)
        case .pyramid:
            return HiitBlock(format: .pyramid, moves: take(3, reps: false), rounds: 5, work: 20, rest: 15, restAfter: restAfter)
        case .emom:
            var m = take(2, reps: true)
            if easy { m = m.map { HiitMove($0.exerciseId, reps: $0.reps.map { max(4, $0 * 2 / 3) }) } }
            return HiitBlock(format: .emom, moves: m, rounds: max(4, seconds / 60), work: 60, restAfter: restAfter)
        case .amrap:
            return HiitBlock(format: .amrap, moves: take(3, reps: true), rounds: 1, work: max(180, seconds / 60 * 60), restAfter: restAfter)
        case .forTime:
            let cap = max(300, seconds / 60 * 60)
            return HiitBlock(format: .forTime, moves: take(3, reps: true), rounds: max(2, cap / 180), work: cap, restAfter: restAfter)
        }
    }

    /// Length of the main part for a workout of `minutes` (warm-up and cool-down take the rest).
    static func mainSeconds(_ minutes: Int, warm: Int, cool: Int) -> Int {
        max(4 * 60, minutes * 60 - prepSec - (warm + cool) * easySec)
    }

    static func wrap(_ name: String, _ blocks: [HiitBlock], lowImpact: Bool, kit: String) -> HiitWorkout {
        var blocks = blocks
        if !blocks.isEmpty { blocks[blocks.count - 1].restAfter = 0 }
        return HiitWorkout(name: name, blocks: blocks, warmup: lowImpact ? lowWarmupMoves : warmupMoves, cooldown: cooldownMoves,
                           lowImpact: lowImpact, kit: kit)
    }

    // MARK: B · Builder

    /// One format filling the length: Tabata and Pyramid repeat blocks with a minute between, EMOM and 30/30 run long,
    /// AMRAP splits in two past 16′.
    public static func build(_ spec: HiitSpec, gym: [Equipment] = []) -> HiitWorkout {
        let list = moves(spec.kit.equipment(gym), lowImpact: spec.lowImpact)
        var rng = Rng(seed: UInt32(truncatingIfNeeded: spec.shuffle &* 7919 &+ spec.minutes &* 31 &+ (HiitFormat.allCases.firstIndex(of: spec.format) ?? 0) &+ 1))
        var used: Set<String> = []
        let warm = (spec.lowImpact ? lowWarmupMoves : warmupMoves).count
        let main = mainSeconds(spec.minutes, warm: warm, cool: cooldownMoves.count)
        var blocks: [HiitBlock] = []
        switch spec.format {
        case .tabata, .pyramid:
            let one = 240
            let n = max(1, (main + 60) / (one + 60))
            for _ in 0..<n { blocks.append(block(spec.format, seconds: one, list: list, used: &used, rng: &rng)) }
        case .amrap where main > 16 * 60:
            let half = (main - 60) / 2
            blocks = [block(.amrap, seconds: half, list: list, used: &used, rng: &rng),
                      block(.amrap, seconds: half, list: list, used: &used, rng: &rng)]
        default:
            blocks = [block(spec.format, seconds: main, list: list, used: &used, rng: &rng)]
        }
        let kitLine = spec.kit == .body ? "No kit" : "\(spec.kit.label) · body"
        return wrap("\(spec.format.label) · \(spec.minutes)′", blocks, lowImpact: spec.lowImpact, kit: kitLine)
    }

    /// Session of a library spec id (`example-hiit-…`), nil for any other id.
    public static func session(sessionId: String, gym: [Equipment] = []) -> Session? {
        guard let spec = HiitSpec(sessionId: sessionId) else { return nil }
        return build(spec, gym: gym).session(id: sessionId)
    }

    // MARK: A · Plan

    /// Coach's weekly rotation: each HIIT day of a week takes the next one; week 4 (deload) is easy intervals.
    static let rotation: [(name: String, parts: [HiitFormat])] = [
        ("Engine burner", [.tabata, .emom, .amrap]),
        ("Thirty-thirty", [.intervals, .amrap]),
        ("Pyramid power", [.pyramid, .pyramid, .emom]),
        ("Race the clock", [.tabata, .forTime]),
    ]

    /// Planned HIIT workout `n` (0-based) of plan week `week`, `minutes` long.
    public static func planned(week: Int, n: Int, minutes: Int, equipment: [Equipment], lowImpact: Bool, seed: UInt32) -> HiitWorkout {
        let list = moves(Set(equipment).union([.mat]), lowImpact: lowImpact)
        var rng = Rng(seed: seed &+ UInt32(truncatingIfNeeded: week &* 101 &+ n &* 13 &+ 5))
        var used: Set<String> = []
        let warm = (lowImpact ? lowWarmupMoves : warmupMoves).count
        let main = mainSeconds(minutes, warm: warm, cool: cooldownMoves.count)
        let kit = Set(equipment).isDisjoint(with: [.kettlebells, .dumbbells, .rower, .skiErg, .airBike, .slamBall, .battleRope]) ? "No kit" : "Gym · body"
        if Generator.phaseIndex(week) == Generator.mesocycleWeeks - 1 {
            let b = block(.intervals, seconds: main, list: list, used: &used, rng: &rng, easy: true)
            return wrap("Easy intervals", [b], lowImpact: lowImpact, kit: kit)
        }
        let r = rotation[(Generator.phaseIndex(week) + n) % rotation.count]
        // Fixed-length parts first (Tabata and Pyramid 4′, AMRAP / For time 6′), the stretchy one (EMOM, 30/30) fills the rest.
        let fixed: (HiitFormat) -> Int? = { f in
            switch f {
            case .tabata: 240
            case .pyramid: 240
            case .amrap: 360
            case .forTime: max(360, main / 2 / 60 * 60)
            case .emom, .intervals: nil
            }
        }
        let gaps = 60 * (r.parts.count - 1)
        let set = r.parts.compactMap(fixed).reduce(0, +)
        let stretch = max(240, main - set - gaps)
        let blocks = r.parts.map { f in block(f, seconds: fixed(f) ?? stretch, list: list, used: &used, rng: &rng) }
        return wrap(r.name, blocks, lowImpact: lowImpact, kit: kit)
    }

    /// Length of a planned HIIT day: half the plan's session, 15–30′ (shorter in a deload).
    static func plannedMinutes(_ p: Profile, deload: Bool) -> Int {
        let m = Generator.clamp(Generator.round5(Double(Generator.sessionMinutes(p)) * 0.5), 15, 30)
        return deload ? max(15, Generator.round5(Double(m) * 0.75)) : m
    }

    /// Adds the profile's HIIT days to a generated week (A): appended as conditioning sessions with their own ids,
    /// on free days away from leg days and from each other; none when no day is free. A plan without weekdays gets
    /// them unscheduled. Lifting sessions stay as they are, except with Finisher on: their cardio block becomes a
    /// 4′ Tabata.
    public static func addDays(_ plan: WeekPlan, _ profile: Profile) -> WeekPlan {
        guard let h = profile.hiit, h.on else { return plan }
        var plan = plan
        if h.finisher { plan = finishers(plan, profile) }
        guard h.days > 0, !plan.sessions.contains(where: { $0.hiit != nil }) else { return plan }
        let lifting = plan.sessions.compactMap(\.weekday)
        let scheduled = !lifting.isEmpty || plan.sessions.isEmpty
        var days: [Int?] = []
        if scheduled {
            let sport = Set(profile.climbingDays).union(profile.sportDays().map(\.weekday))
            let taken = Set(lifting).union(sport)
            let legs = Set(plan.sessions.filter { RunPlanner.legHeavy($0.focus) }.compactMap(\.weekday))
            var picked: [Int] = []
            for _ in 0..<h.days {
                let free = WeekSchedule.weekdays.filter { !taken.contains($0) && !picked.contains($0) }
                func score(_ d: Int) -> Int {
                    let near = [WeekSchedule.previous(d), WeekSchedule.next(d)]
                    return near.filter { legs.contains($0) }.count * 3 + near.filter { picked.contains($0) }.count * 4
                        + near.filter { sport.contains($0) }.count
                }
                guard let d = free.min(by: { (score($0), $0) < (score($1), $1) }) else { break }
                picked.append(d)
            }
            days = picked.sorted().map { Optional($0) }
        } else {
            days = Array(repeating: nil, count: h.days)
        }
        let minutes = plannedMinutes(profile, deload: plan.deload)
        for (n, wd) in days.enumerated() {
            let i = plan.sessions.count
            let w = planned(week: plan.week, n: n, minutes: minutes, equipment: profile.equipment, lowImpact: h.lowImpact, seed: plan.seed)
            var s = w.session(id: "w\(plan.week)s\(i + 1)", index: i)
            s.weekday = wd
            plan.sessions.append(s)
        }
        return plan
    }

    /// "Finisher only" / extra: lifting days end with a 4′ Tabata in place of their cardio block (no change without one).
    static func finishers(_ plan: WeekPlan, _ profile: Profile) -> WeekPlan {
        var plan = plan
        let list = moves(Set(profile.equipment).union([.mat]), lowImpact: profile.hiit?.lowImpact ?? false)
        for i in plan.sessions.indices where plan.sessions[i].hiit == nil && plan.sessions[i].focus != .conditioning {
            guard let k = plan.sessions[i].blocks.firstIndex(where: { $0.kind == .cardio }) else { continue }
            var rng = Rng(seed: plan.seed &+ UInt32(truncatingIfNeeded: plan.week &* 17 &+ i &* 3))
            var used = Set(plan.sessions[i].blocks.flatMap { $0.items.map(\.exerciseId) })
            let b = block(.tabata, seconds: 240, list: list, used: &used, rng: &rng)
            let id = plan.sessions[i].id
            let items = b.moves.enumerated().map { m, move -> PlannedExercise in
                let e = Exercise.get(move.exerciseId)
                var p = PlannedExercise(uid: "\(id)-fin\(m)", exerciseId: move.exerciseId, slot: e.pattern,
                                        prescription: Prescription(sets: b.sets(of: m), reps: "\(b.work) s", restSec: b.rest,
                                                                   intensity: "Tabata · \(b.summary)", note: nil),
                                        estSec: b.seconds / max(1, b.moves.count))
                p.group = "F\(m + 1)"
                return p
            }
            plan.sessions[i].blocks[k] = Block(kind: .cardio, title: "Finisher · Tabata 4′", targetMin: 4, items: items,
                                               note: "20″ all out, 10″ rest, 8 rounds: F1 and F2 in turn.")
            plan.sessions[i].estMin = Int(plan.sessions[i].blocks.reduce(0) { $0 + $1.estMin }.rounded())
        }
        return plan
    }
}

/// HIIT in the plan (A), Training profile → HIIT: days a week, finisher, impact. nil = off (plans as before).
public struct HiitPlan: Codable, Hashable, Sendable {
    /// HIIT days a week, 0–3.
    public var days: Int
    /// Lifting days end with a 4′ Tabata finisher.
    public var finisher: Bool
    /// No jumps.
    public var lowImpact: Bool

    public init(days: Int = 1, finisher: Bool = false, lowImpact: Bool = false) {
        self.days = min(3, max(0, days))
        self.finisher = finisher
        self.lowImpact = lowImpact
    }

    public var on: Bool { days > 0 || finisher }
}

/// A built HIIT from Explore (B). The id is the spec, so it opens, plans and logs like any library workout.
public struct HiitSpec: Codable, Hashable, Sendable, Identifiable {
    public var format: HiitFormat
    public var minutes: Int
    public var kit: Hiit.Kit
    public var lowImpact: Bool
    /// ↻ Reshuffle: another pick of moves.
    public var shuffle: Int

    public static let lengths = [10, 15, 20, 30]

    public init(format: HiitFormat, minutes: Int = 20, kit: Hiit.Kit = .body, lowImpact: Bool = false, shuffle: Int = 0) {
        self.format = format
        self.minutes = Self.lengths.min { abs($0 - minutes) < abs($1 - minutes) } ?? 20
        self.kit = kit
        self.lowImpact = lowImpact
        self.shuffle = max(0, shuffle)
    }

    static let prefix = WorkoutTemplate.idPrefix + "hiit-"

    /// `example-hiit-tabata-20-body-low-0`.
    public var sessionId: String {
        Self.prefix + [format.rawValue, "\(minutes)", kit.rawValue, lowImpact ? "low" : "std", "\(shuffle)"].joined(separator: "-")
    }

    public var id: String { sessionId }

    public init?(sessionId: String) {
        guard sessionId.hasPrefix(Self.prefix) else { return nil }
        // Plan inserts append their own marker; the spec is what comes before it.
        let core = sessionId.dropFirst(Self.prefix.count).components(separatedBy: PlanInsert.marker)[0]
        let parts = core.split(separator: "-").map(String.init)
        guard parts.count == 5, let f = HiitFormat(rawValue: parts[0]), let m = Int(parts[1]), let k = Hiit.Kit(rawValue: parts[2]),
              let s = Int(parts[4]) else { return nil }
        self.init(format: f, minutes: m, kit: k, lowImpact: parts[3] == "low", shuffle: s)
    }

    public static func isHiit(_ sessionId: String) -> Bool { sessionId.hasPrefix(prefix) }
}
