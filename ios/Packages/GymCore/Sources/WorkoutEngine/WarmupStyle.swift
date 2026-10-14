import Foundation

/// How a warm-up is built (#293). `.auto` = picked to match the exercises (cardio raise, then drills).
public enum WarmupStyle: String, Codable, CaseIterable, Sendable {
    case auto
    /// Mostly an easy cardio machine, then two drills.
    case pulse
    /// Drills only, no machine.
    case dynamic
    /// Short raise, then activation drills (glutes, scapulae, bands).
    case activation

    /// Unknown values (a newer app's styles) decode as automatic.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WarmupStyle(rawValue: raw) ?? .auto
    }
}

/// How a cool-down is built (#293). `.auto` = easy flush after hard cardio, stretches for the most-loaded muscles,
/// breathing.
public enum CooldownStyle: String, Codable, CaseIterable, Sendable {
    case auto
    /// Static stretches and breathing only.
    case stretch
    /// Foam rolling the most-loaded muscles, then stretches (stretches only without a foam roller).
    case foamRoll = "foam-roll"
    /// A few easy minutes on a cardio machine, then stretches.
    case easyCardio = "easy-cardio"
    /// Longer down-regulating breathing after the stretches.
    case breathe

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CooldownStyle(rawValue: raw) ?? .auto
    }
}

/// One workout's warm-up and cool-down choices (#293): a style per block, or the exact moves. nil fields follow
/// the profile's defaults.
public struct FlowTweaks: Codable, Hashable, Sendable {
    public var warmupStyle: WarmupStyle?
    public var cooldownStyle: CooldownStyle?
    /// Exact moves; the block is just these (their minutes set its length).
    public var warmupMoves: [BlockPick]?
    public var cooldownMoves: [BlockPick]?

    public init(warmupStyle: WarmupStyle? = nil, cooldownStyle: CooldownStyle? = nil,
                warmupMoves: [BlockPick]? = nil, cooldownMoves: [BlockPick]? = nil) {
        self.warmupStyle = warmupStyle
        self.cooldownStyle = cooldownStyle
        self.warmupMoves = warmupMoves
        self.cooldownMoves = cooldownMoves
    }

    /// Blocks that take tweaks.
    public static let kinds: [BlockKind] = [.warmup, .cooldown]

    public var isEmpty: Bool { self == FlowTweaks() }

    public func moves(_ k: BlockKind) -> [BlockPick]? {
        switch k {
        case .warmup: warmupMoves
        case .cooldown: cooldownMoves
        default: nil
        }
    }

    /// Sets (or with nil / empty clears) a block's exact moves.
    public mutating func setMoves(_ m: [BlockPick]?, for k: BlockKind) {
        let v = m?.isEmpty == false ? m : nil
        switch k {
        case .warmup: warmupMoves = v
        case .cooldown: cooldownMoves = v
        default: break
        }
    }

    /// Minutes of a block's exact moves, when it has some.
    public func movesMinutes(_ k: BlockKind) -> Int? {
        moves(k).map { $0.reduce(0) { $0 + $1.minutes } }
    }
}

extension Profile {
    /// Copy with one workout's warm-up / cool-down choices applied: styles replace the defaults, exact moves
    /// become the block's only picks.
    public func applying(_ t: FlowTweaks?) -> Profile {
        guard let t, !t.isEmpty else { return self }
        var p = self
        if let s = t.warmupStyle { p.warmupStyle = s }
        if let s = t.cooldownStyle { p.cooldownStyle = s }
        for k in FlowTweaks.kinds {
            if let m = t.moves(k), !m.isEmpty { p.setPicks(BlockPicks(items: m, only: true, inCustom: true), for: k) }
        }
        return p
    }
}
