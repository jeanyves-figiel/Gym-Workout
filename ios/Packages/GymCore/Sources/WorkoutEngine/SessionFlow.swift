import Foundation

/// Which blocks a workout runs and how its time is split (#198). Set plan-wide in Edit plan (`Profile.sessionFlow`)
/// or for one workout (`SessionStyle.flow`). The session length never changes: time of a block switched off goes to
/// the remaining work blocks, a block switched on takes its minimum from strength, and a dragged split (`shares`)
/// sets every block's share directly.
public struct SessionFlow: Codable, Hashable, Sendable {
    /// Blocks switched off.
    public var off: Set<BlockKind>
    /// Blocks switched on although the goal's mix leaves them out.
    public var on: Set<BlockKind>
    /// Dragged split: relative weight (minutes as dragged) per block in the flow, scaled to each session; nil = automatic.
    public var shares: [BlockKind: Int]?

    public init(off: Set<BlockKind> = [], on: Set<BlockKind> = [], shares: [BlockKind: Int]? = nil) {
        self.off = off
        self.on = on
        self.shares = shares
    }

    enum CodingKeys: String, CodingKey { case off, on, shares }

    /// Lenient: unknown block names from newer app versions are dropped.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let offNames: [String]? = try? c.decodeIfPresent([String].self, forKey: .off)
        let onNames: [String]? = try? c.decodeIfPresent([String].self, forKey: .on)
        let raw: [String: Int]? = try? c.decodeIfPresent([String: Int].self, forKey: .shares)
        off = Set((offNames ?? []).compactMap(BlockKind.init(rawValue:)))
        on = Set((onNames ?? []).compactMap(BlockKind.init(rawValue:)))
        shares = raw.map { r in
            Dictionary(uniqueKeysWithValues: r.compactMap { k, v in BlockKind(rawValue: k).map { ($0, max(0, v)) } })
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(BlockKind.allCases.filter { off.contains($0) }.map(\.rawValue), forKey: .off)
        try c.encode(BlockKind.allCases.filter { on.contains($0) }.map(\.rawValue), forKey: .on)
        if let shares {
            try c.encode(Dictionary(uniqueKeysWithValues: shares.map { ($0.key.rawValue, $0.value) }), forKey: .shares)
        }
    }

    /// Follows the plan's automatic split: nothing switched or dragged.
    public var isAuto: Bool { off.isEmpty && on.isEmpty && shares == nil }

    /// Blocks that hold the actual training; at least one stays in every flow.
    public static let workBlocks: [BlockKind] = [.power, .strength, .mobility, .cardio]

    /// Smallest useful time per block (minutes); a block switched on or dragged never goes below it.
    public static func minimum(_ k: BlockKind) -> Int {
        switch k {
        case .warmup, .cooldown, .mobility: 4
        case .power: 5
        case .strength: 8
        case .cardio: 6
        }
    }

    public func contains(_ k: BlockKind) -> Bool { !off.contains(k) }

    /// Copy with `k` switched on or off; never leaves the flow without a work block. A dragged split keeps its
    /// shares for the other blocks (a block switched on gets its minimum share, taken from the largest).
    public func setting(_ k: BlockKind, _ included: Bool, autoMinutes: [BlockKind: Int] = [:]) -> SessionFlow {
        var f = self
        if included {
            f.off.remove(k)
            if (autoMinutes[k] ?? 0) == 0 { f.on.insert(k) }
            if var s = f.shares, s[k] == nil, let big = s.max(by: { $0.value < $1.value })?.key {
                let want = min(10, (s[big] ?? 0) / 2)
                s[big, default: 0] -= want
                s[k] = want
                f.shares = s
            }
        } else {
            f.on.remove(k)
            f.off.insert(k)
            if Self.workBlocks.allSatisfy({ f.off.contains($0) }) { return self }
            if var s = f.shares, let gone = s.removeValue(forKey: k), gone > 0 {
                let keep = Self.workBlocks.filter { s[$0] != nil }
                let sum = keep.reduce(0) { $0 + (s[$1] ?? 0) }
                var left = gone
                for (i, w) in keep.enumerated() {
                    let add = i == keep.count - 1 ? left : (sum > 0 ? gone * (s[w] ?? 0) / sum : 0)
                    s[w, default: 0] += add
                    left -= add
                }
                f.shares = s
            }
        }
        return f
    }

    /// The flow with at least one work block in it (strength switched back on otherwise).
    public var sanitized: SessionFlow {
        var f = self
        if Self.workBlocks.allSatisfy({ f.off.contains($0) }) { f.off.remove(.strength) }
        f.on.subtract(f.off)
        if let s = f.shares {
            let kept = s.filter { !f.off.contains($0.key) && $0.value > 0 }
            f.shares = kept.isEmpty ? nil : kept
        }
        return f
    }

    // MARK: Presets (Edit plan)

    public enum Preset: String, CaseIterable, Sendable, Identifiable {
        case full, liftFocus, liftMobility, express
        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .full: "Full"
            case .liftFocus: "Lift focus"
            case .liftMobility: "Lift + mobility"
            case .express: "Express"
            }
        }

        public var detail: String {
            switch self {
            case .full: "Your goal's mix"
            case .liftFocus: "No explosive, no cardio"
            case .liftMobility: "Longer mobility"
            case .express: "Warm-up + strength"
            }
        }

        public var flow: SessionFlow {
            switch self {
            case .full: SessionFlow()
            case .liftFocus: SessionFlow(off: [.power, .cardio])
            case .liftMobility:
                SessionFlow(off: [.power, .cardio], on: [.mobility],
                            shares: [.warmup: 13, .strength: 57, .mobility: 20, .cooldown: 10])
            case .express: SessionFlow(off: [.power, .mobility, .cardio, .cooldown])
            }
        }
    }

    /// The preset this flow equals, if any.
    public var preset: Preset? { Preset.allCases.first { $0.flow == self } }
}

extension BlockKind {
    /// Short name for flow chips and the time bar.
    public var flowLabel: String {
        switch self {
        case .warmup: "Warm-up"
        case .power: "Explosive"
        case .strength: "Strength"
        case .mobility: "Mobility"
        case .cardio: "Cardio"
        case .cooldown: "Cool-down"
        }
    }
}

extension Generator {
    /// Minutes per block before any flow (goal × focus mix), as `generateSession` has always split them.
    static func autoSplit(_ p: Profile, _ focus: Focus, _ minutes: Int) -> [BlockKind: Int] {
        // Short quick sessions (#178, under 25 min) keep a 3-min warm-up / cool-down so most of the time is work.
        let lo = minutes < 25 ? 3 : 6
        let warm = clamp(Int((Double(minutes) * 0.12).rounded()), lo, 10)
        let cool = clamp(Int((Double(minutes) * 0.11).rounded()), lo, 10)
        let work = Double(minutes - warm - cool)
        let mix = sessionMix(p, focus)
        var powerMin = Int((work * mix.power).rounded())
        var mobilityMin = Int((work * mix.mobility).rounded())
        var cardioMin = Int((work * mix.cardio).rounded())
        if powerMin < 4 { powerMin = 0 }
        if mobilityMin < 3 { mobilityMin = 0 }
        if cardioMin < 6 { cardioMin = 0 }
        let strengthMin = Int(work) - powerMin - mobilityMin - cardioMin
        return [.warmup: warm, .power: powerMin, .strength: strengthMin, .mobility: mobilityMin, .cardio: cardioMin, .cooldown: cool]
    }

    /// Minutes per block with `flow` applied; blocks left out have no entry. Total stays `minutes`.
    static func split(_ auto: [BlockKind: Int], minutes: Int, flow: SessionFlow) -> [BlockKind: Int] {
        let flow = flow.sanitized
        if let shares = flow.shares {
            let sum = max(1, shares.values.reduce(0, +))
            var out: [BlockKind: Int] = [:]
            for k in BlockKind.allCases { if let s = shares[k] { out[k] = Int((Double(minutes * s) / Double(sum)).rounded()) } }
            if let big = out.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key.order > $1.key.order) })?.key {
                out[big, default: 0] += minutes - out.values.reduce(0, +)
            }
            return out.filter { $0.value > 0 }
        }
        var m = auto
        // Switched on: its minimum, from strength (else the largest work block).
        for k in BlockKind.allCases where flow.on.contains(k) && (m[k] ?? 0) < SessionFlow.minimum(k) {
            let need = SessionFlow.minimum(k) - (m[k] ?? 0)
            let donors = SessionFlow.workBlocks.filter { $0 != k && !flow.off.contains($0) }
            let strengthCanGive = (m[.strength] ?? 0) >= need + SessionFlow.minimum(.strength) && donors.contains(.strength)
            let donor: BlockKind? = strengthCanGive ? BlockKind.strength : donors.max { (m[$0] ?? 0) < (m[$1] ?? 0) }
            guard let donor, (m[donor] ?? 0) > need else { continue }
            m[donor, default: 0] -= need
            m[k] = SessionFlow.minimum(k)
        }
        // Switched off: its time to the remaining work blocks, in proportion to their size.
        var freed = 0
        for k in flow.off { freed += m[k] ?? 0; m[k] = 0 }
        let keep = SessionFlow.workBlocks.filter { (m[$0] ?? 0) > 0 }
        if keep.isEmpty {
            let k = SessionFlow.workBlocks.first { !flow.off.contains($0) } ?? .strength
            m[k] = freed
        } else {
            let sum = keep.reduce(0) { $0 + (m[$1] ?? 0) }
            var left = freed
            for (i, k) in keep.enumerated() {
                let add = i == keep.count - 1 ? left : Int((Double(freed * (m[k] ?? 0)) / Double(sum)).rounded())
                m[k, default: 0] += add
                left -= add
            }
        }
        return m.filter { $0.value > 0 }
    }

    /// The flow a session would run (block, minutes) in order, for the time bar.
    public static func flowMinutes(_ profile: Profile, focus: Focus, minutes: Int, flow: SessionFlow?) -> [(kind: BlockKind, minutes: Int)] {
        let auto = autoSplit(profile, focus, minutes)
        let m = flow.map { split(auto, minutes: minutes, flow: $0) } ?? auto.filter { $0.value > 0 }
        return BlockKind.allCases.compactMap { k in m[k].map { (k, $0) } }
    }

    /// Session type the plan-wide flow preview is drawn for: the week's first non-conditioning day.
    public static func referenceFocus(_ p: Profile) -> Focus {
        let split = Rules.split(p)
        return split.first { $0 != .conditioning } ?? .fullLower
    }

    /// Automatic minutes per block (no flow), e.g. to tell which blocks the goal leaves out.
    public static func autoFlowMinutes(_ profile: Profile, focus: Focus, minutes: Int) -> [BlockKind: Int] {
        autoSplit(profile, focus, minutes)
    }

    /// Flow-sized extra blocks (#198) around a custom workout's own exercises: warm-up, explosive, mobility,
    /// cardio and cool-down, picked for the member's equipment and the workout's focus.
    public static func flowBlocks(_ profile: Profile, around exercises: [Exercise], minutes: [BlockKind: Int], seed: UInt32) -> [Block] {
        guard !exercises.isEmpty else { return [] }
        let ctx = Ctx(profile: profile, week: 2, seed: seed)
        let focus = CustomWorkout.focus(exercises)
        var before: [Block] = []
        var after: [Block] = []
        if let w = minutes[.warmup], w > 0,
           let b = withPicks(ctx, .warmup, w, "flow-wu", custom: true, { warmup(ctx, focus, $0, "flow-wu") }) { before.append(b) }
        if let p = minutes[.power], p > 0, let b = power(ctx, focus, p, "flow-pw") { before.append(b) }
        if let mo = minutes[.mobility], mo > 0,
           let b = withPicks(ctx, .mobility, mo, "flow-mo", custom: true, { mobility(ctx, focus, $0, "flow-mo") }) { after.append(b) }
        let mode: CardioMode = profile.goal.config.cardio.first ?? .zone2
        if let ca = minutes[.cardio], ca > 0,
           let b = withPicks(ctx, .cardio, ca, "flow-ca", custom: true, { cardioBlock(ctx, mode, $0, "flow-ca") }) { after.append(b) }
        if let cd = minutes[.cooldown], cd > 0 {
            let main = Block(kind: .strength, title: "", targetMin: 0, items: exercises.enumerated().map { i, e in
                PlannedExercise(uid: "m\(i)", exerciseId: e.id, slot: e.pattern,
                                prescription: Prescription(sets: 3, reps: "10", restSec: 60), estSec: 0)
            })
            let prior = [main] + after
            if let b = withPicks(ctx, .cooldown, cd, "flow-cd", custom: true, { cooldown(ctx, $0, prior, "flow-cd") }) { after.append(b) }
        }
        return before + after
    }
}

extension BlockKind {
    /// Position in a session.
    var order: Int { BlockKind.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - My picks per block (#204)

/// An exercise the member always wants in a block, with its own time (e.g. Treadmill 7 min in every warm-up).
public struct BlockPick: Codable, Hashable, Sendable, Identifiable {
    public var exerciseId: String
    public var minutes: Int
    public var id: String { exerciseId }

    public init(exerciseId: String, minutes: Int) {
        self.exerciseId = exerciseId
        self.minutes = minutes
    }

    public static let minutesRange = 1...30
}

/// The member's picks for one block. Pinned exercises go in first and keep their time; the app fills the rest
/// of the block unless `only` is on. Nothing pinned = the block is picked as before.
public struct BlockPicks: Codable, Hashable, Sendable {
    public var items: [BlockPick]
    /// Nothing else in the block: it lasts as long as the picks.
    public var only: Bool
    /// Also used for the flow blocks added around the member's own workouts; nil = yes.
    public var inCustom: Bool?

    public init(items: [BlockPick] = [], only: Bool = false, inCustom: Bool? = nil) {
        self.items = items
        self.only = only
        self.inCustom = inCustom
    }

    public var isEmpty: Bool { items.isEmpty }
    public var minutes: Int { items.reduce(0) { $0 + $1.minutes } }

    /// Blocks that take picks: strength keeps its own picks through Swap.
    public static let kinds: [BlockKind] = [.warmup, .mobility, .cardio, .cooldown]

    /// Starting time for a newly pinned exercise: machines get a real stint, drills and stretches a couple of minutes.
    public static func defaultMinutes(_ e: Exercise, in kind: BlockKind) -> Int {
        guard e.category == .cardio else { return 2 }
        return kind == .cardio ? 15 : 5
    }
}

extension Profile {
    /// Picks per block, decoded from `blockPicks`.
    public func picks(_ kind: BlockKind) -> BlockPicks? {
        guard let p = blockPicks?[kind.rawValue], !p.isEmpty else { return nil }
        return p
    }

    /// Sets (or with empty picks clears) a block's picks.
    public mutating func setPicks(_ picks: BlockPicks, for kind: BlockKind) {
        var all = blockPicks ?? [:]
        all[kind.rawValue] = picks.isEmpty ? nil : picks
        blockPicks = all.isEmpty ? nil : all
    }
}

extension Generator {
    /// Pinned exercises of `picks` as planned items (ones the gym lacks are left out).
    static func pinnedItems(_ picks: BlockPicks, equipment: Set<Equipment>, uid: String) -> [PlannedExercise] {
        picks.items.enumerated().compactMap { i, p in
            guard let e = Exercise.find(p.exerciseId), Selector.isAvailable(e, equipment) else { return nil }
            let m = min(BlockPick.minutesRange.upperBound, max(BlockPick.minutesRange.lowerBound, p.minutes))
            return PlannedExercise(
                uid: "\(uid)-pin\(i)", exerciseId: e.id, slot: e.category == .strength ? e.pattern : .general,
                prescription: Prescription(sets: 1, reps: "\(m) min\(perSide(e))", restSec: 0, note: "Your pick"),
                estSec: m * 60)
        }
    }

    /// `make` builds the block for some minutes. With picks for `kind`, they go first and keep their time and
    /// `make` fills what is left (nothing with `only`, or when too little is left); without, `make(minutes)`.
    static func withPicks(_ ctx: Ctx, _ kind: BlockKind, _ minutes: Int, _ uid: String, custom: Bool = false,
                          _ make: (Int) -> Block?) -> Block? {
        guard let picks = ctx.profile.picks(kind), !custom || picks.inCustom != false else { return make(minutes) }
        let pinned = pinnedItems(picks, equipment: ctx.equipment, uid: uid)
        guard !pinned.isEmpty else { return make(minutes) }
        let pinMin = pinned.reduce(0) { $0 + $1.estSec } / 60
        let left = minutes - pinMin
        let ids = Set(pinned.map(\.exerciseId))
        ctx.usedSession.formUnion(ids)
        let filled = picks.only || left < SessionFlow.minimum(kind) ? nil : make(left)
        var block = filled ?? Block(kind: kind, title: kind.blockTitle(climber: ctx.climber), targetMin: 0, items: [], note: nil)
        block.items.removeAll { ids.contains($0.exerciseId) }
        block.items = pinned + block.items
        block.targetMin = picks.only ? pinMin : max(minutes, pinMin)
        block.note = picks.only ? "Your picks." : ["Your picks first.", filled?.note].compactMap { $0 }.joined(separator: " ")
        return block
    }
}

extension BlockKind {
    /// Title of a generated block of this kind.
    func blockTitle(climber: Bool) -> String {
        switch self {
        case .warmup: "Warm-up"
        case .power: "Explosive"
        case .strength: "Strength"
        case .mobility: climber ? "Climber mobility" : "Mobility"
        case .cardio: "Cardio"
        case .cooldown: "Stretching & cool-down"
        }
    }
}
