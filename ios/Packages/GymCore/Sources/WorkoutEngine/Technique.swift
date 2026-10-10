/// How to set up and hold correct position for an exercise.
public enum BodyPart: String, Codable, Sendable, CaseIterable, Identifiable {
    case head, shoulders, elbows, hands, back, core, hips, knees, feet
    public var id: String { rawValue }

    public var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public struct Checkpoint: Hashable, Sendable {
    public let part: BodyPart
    public let cue: String

    public init(_ part: BodyPart, _ cue: String) {
        self.part = part
        self.cue = cue
    }
}

public struct Technique: Hashable, Sendable {
    /// Machine / equipment adjustments and getting into the start position, in order.
    public let setup: [String]
    /// What correct position looks like, joint by joint, head to feet.
    public let position: [Checkpoint]
    /// Common errors to avoid.
    public let mistakes: [String]
    /// Breathing pattern.
    public let breathing: String

    public init(setup: [String], position: [Checkpoint], mistakes: [String], breathing: String) {
        self.setup = setup
        self.position = position
        self.mistakes = mistakes
        self.breathing = breathing
    }

    static let catalog: [String: Technique] = strengthA
        .merging(strengthB) { a, _ in a }
        .merging(powerCardioWarmup) { a, _ in a }
        .merging(mobilityStretch) { a, _ in a }
        .merging(examples) { a, _ in a }
}

extension Exercise {
    /// Setup, body position, mistakes and breathing for this exercise.
    public var technique: Technique? { Technique.catalog[id] }
}
