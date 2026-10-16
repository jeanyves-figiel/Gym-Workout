import Foundation

/// How a lift is measured from the wrist (#383).
public struct LiftProfile: Equatable, Sendable {
    public enum Direction: String, Codable, Sendable {
        /// The weight goes up on the lifting part (squat, bench, deadlift, presses, rows, curls, raises).
        case up
        /// The weight comes down on the lifting part (pulldown, pushdown).
        case down
        /// Mostly sideways or diagonal (cable and machine rows, chest press machine, flies): main axis of the
        /// movement, the faster direction is the lifting part.
        case axis
    }

    public enum Family: String, Codable, Sendable {
        case squat, hinge, bench, overhead, row, arm, other
    }

    public var direction: Direction
    public var family: Family

    public init(direction: Direction, family: Family) {
        self.direction = direction
        self.family = family
    }

    /// Minimum velocity threshold (m/s) at a true 1RM, from the velocity-based training literature; nil when
    /// the lift has no useful 1RM (curls, raises, flies).
    public var minimumVelocity: Double? {
        switch family {
        case .squat: 0.30
        case .hinge: 0.15
        case .bench: 0.17
        case .overhead: 0.19
        case .row: 0.40
        case .arm, .other: nil
        }
    }

    /// Smallest movement (m) that counts as a rep.
    public var minRange: Double { family == .hinge ? 0.06 : 0.08 }

    /// Profile for an exercise, from its name (and id); nil when the wrist doesn't move with the load
    /// (leg press, leg extension and curl, calf raises, hip thrust, pull-ups, dips, core, cardio).
    public static func `for`(name: String, exerciseId: String = "") -> LiftProfile? {
        let n = (name + " " + exerciseId).lowercased().replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }

        if has("leg press", "leg extension", "leg curl", "hamstring curl", "calf", "hip thrust", "glute bridge", "pull up", "pullup",
               "chin up", "chinup", "dip", "plank", "crunch", "sit up", "situp", "leg raise", "knee raise", "hanging", "abductor",
               "adductor", "abduction", "adduction", "stretch", "mobility", "carry", "walk", "run", "bike", "cycle", "rower",
               "rowing machine", "skierg", "ski erg", "jump rope", "battle rope", "dead hang", "hangboard", "treadmill", "elliptical", "stair", "jump", "burpee", "hollow", "dead bug",
               "bird dog", "superman", "pallof", "russian twist", "wall sit") {
            return nil
        }
        let family: Family
        if has("deadlift", "rdl", "romanian", "good morning", "rack pull", "clean", "snatch", "swing", "shrug") {
            family = .hinge
        } else if has("squat", "lunge", "step up", "thruster", "split") {
            family = .squat
        } else if has("bench", "floor press", "chest press", "push up", "pushup") {
            family = .bench
        } else if has("overhead", "shoulder press", "military", "push press", "arnold", "landmine press") {
            family = .overhead
        } else if has("row", "pulldown", "pull down", "face pull") {
            family = .row
        } else if has("curl", "raise", "extension", "pushdown", "push down", "kickback", "skull", "fly", "flye", "crossover",
                      "pec deck", "straight arm", "pullover") {
            family = .arm
        } else {
            family = .other
        }

        if has("pulldown", "pull down", "pushdown", "push down", "straight arm") {
            return LiftProfile(direction: .down, family: family)
        }
        if has("cable", "machine", "seated row", "chest press", "pec deck", "fly", "flye", "crossover", "face pull", "kickback",
               "landmine", "sled") {
            return LiftProfile(direction: .axis, family: family)
        }
        if family == .other { return LiftProfile(direction: .axis, family: .other) }
        return LiftProfile(direction: .up, family: family)
    }
}
