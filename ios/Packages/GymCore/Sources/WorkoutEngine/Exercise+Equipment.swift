import Foundation

// Explore by machine (#456): exercises per piece of equipment, and the machine filter on Explore → Muscles.

/// Explore → Muscles machine filter: every exercise, the member's gym, one area of the gym, or no equipment.
public enum MachineFilter: Hashable, Sendable {
    case all
    /// Only what the member's current gym has (home or trip).
    case gym
    /// Exercises using any item of the area (Cables = cable tower, lat pulldown, seated row).
    case area(GymArea)
    /// No equipment, or only a mat / foam roller.
    case bodyweight

    /// Chip order on Explore.
    public static let chips: [MachineFilter] = [
        .all, .gym, .area(.barbells), .area(.dumbbells), .area(.cables), .area(.machines), .area(.stations), .area(.functional), .bodyweight,
    ]

    public var label: String {
        switch self {
        case .all: "All"
        case .gym: "My gym"
        case .area(let a): a.label
        case .bodyweight: "Body weight"
        }
    }

    /// Stored form for the remembered chip.
    public var key: String {
        switch self {
        case .all: "all"
        case .gym: "gym"
        case .area(let a): "area:" + a.rawValue
        case .bodyweight: "bodyweight"
        }
    }

    public init(key: String) {
        switch key {
        case "gym": self = .gym
        case "bodyweight": self = .bodyweight
        default:
            if key.hasPrefix("area:"), let a = GymArea(rawValue: String(key.dropFirst(5))) { self = .area(a) } else { self = .all }
        }
    }

    /// `gym` = the member's equipment (nil = not set up: everything passes).
    public func matches(_ e: Exercise, gym: Set<Equipment>?) -> Bool {
        switch self {
        case .all: true
        case .gym: gym.map { g in e.equipment.allSatisfy { g.contains($0) || GymArea.floor.contains($0) } } ?? true
        case .area(let a): e.equipment.contains { a.items.contains($0) }
        case .bodyweight: e.equipment.allSatisfy { GymArea.floor.contains($0) }
        }
    }
}

extension Exercise {
    /// Catalog and custom exercises using `item`, by name.
    public static func using(_ item: Equipment, custom: CustomExercises = .shared) -> [Exercise] {
        (catalog + custom.active).filter { $0.equipment.contains(item) }.sorted { $0.name < $1.name }
    }

    /// `using(item)` grouped by category (Category order).
    public static func using(_ item: Equipment, byCategory custom: CustomExercises = .shared) -> [(Category, [Exercise])] {
        let all = using(item, custom: custom)
        return Category.allCases.compactMap { c in
            let hits = all.filter { $0.category == c }
            return hits.isEmpty ? nil : (c, hits)
        }
    }

    /// Muscles `item` trains most, by how many of its exercises use them as a main mover (then as an assist).
    public static func muscles(using item: Equipment, custom: CustomExercises = .shared) -> [Muscle] {
        muscleLoad(using: item, custom: custom).map(\.muscle)
    }

    /// `muscles(using:)` with each muscle's share of the top one (1 = the main mover), for the body map heat:
    /// an assist muscle shows lighter than the muscle the machine is for.
    public static func muscleLoad(using item: Equipment, custom: CustomExercises = .shared) -> [(muscle: Muscle, load: Double)] {
        var score: [Muscle: Double] = [:]
        for e in using(item, custom: custom) { for (m, w) in e.muscleWeights { score[m, default: 0] += w } }
        let top = score.values.max() ?? 1
        return score.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key.name < $1.key.name) }
            .map { ($0.key, $0.value / top) }
    }

    /// `working(muscle)` narrowed by the Explore machine filter.
    public static func working(
        _ muscle: Muscle, filter: MachineFilter, gym: Set<Equipment>?, custom: CustomExercises = .shared
    ) -> [(Category, [MuscleHit])] {
        working(muscle, custom: custom).compactMap { c, hits in
            let kept = hits.filter { filter.matches($0.exercise, gym: gym) }
            return kept.isEmpty ? nil : (c, kept)
        }
    }
}

extension GymArea {
    /// Explore → Machines (#456): items of the area with at least one exercise, in area order.
    public func browsable(custom: CustomExercises = .shared) -> [(item: Equipment, count: Int)] {
        items.compactMap { i in
            let n = Exercise.using(i, custom: custom).count
            return n > 0 ? (i, n) : nil
        }
    }
}
