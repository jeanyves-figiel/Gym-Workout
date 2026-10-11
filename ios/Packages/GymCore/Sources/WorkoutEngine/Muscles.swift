/// Muscle groups, body-map placement and muscle ↔ exercise lookups for the UI.
public enum MuscleGroup: String, CaseIterable, Sendable, Identifiable {
    case shoulders, chest, arms, back, core, hips, legs
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .shoulders: "Shoulders"
        case .chest: "Chest"
        case .arms: "Arms"
        case .back: "Back"
        case .core: "Core"
        case .hips: "Hips & glutes"
        case .legs: "Legs"
        }
    }

    public var muscles: [Muscle] { Muscle.allCases.filter { $0.group == self } }
}

extension Muscle: Identifiable {
    public var id: String { rawValue }

    public var group: MuscleGroup {
        switch self {
        case .frontDelts, .sideDelts, .rearDelts, .rotatorCuff: .shoulders
        case .chest, .serratus: .chest
        case .triceps, .biceps, .brachialis, .forearms, .forearmExtensors: .arms
        case .traps, .upperBack, .lats, .lowerBack: .back
        case .abs, .lowerAbs, .obliques, .deepCore: .core
        case .glutes, .gluteMed, .hipFlexors, .adductors: .hips
        case .quads, .hamstrings, .calves, .soleus, .tibialis: .legs
        }
    }

    /// Display name ("Front delts", "Lats", …).
    public var name: String {
        switch self {
        case .frontDelts: "Front delts"
        case .sideDelts: "Side delts"
        case .rearDelts: "Rear delts"
        case .rotatorCuff: "Rotator cuff"
        case .upperBack: "Mid back"
        case .lowerBack: "Lower back"
        case .hipFlexors: "Hip flexors"
        case .abs: "Abs"
        case .lowerAbs: "Lower abs"
        case .deepCore: "Deep core"
        case .gluteMed: "Glute med"
        case .traps: "Upper traps"
        case .forearms: "Forearm flexors"
        case .forearmExtensors: "Forearm extensors"
        case .calves: "Calves (gastrocnemius)"
        case .serratus: "Serratus"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// What it does — shown on the muscle page.
    public var role: String {
        switch self {
        case .chest: "Pushing, mantles, pressing out of compressions."
        case .frontDelts: "Raising the arm forward; overhead presses."
        case .sideDelts: "Arm abduction; shoulder width and definition."
        case .rearDelts: "Pulling the arm back; balances pressing and posture."
        case .rotatorCuff: "Stabilises the shoulder joint — key injury prevention for climbers."
        case .triceps: "Elbow extension: pushing, mantling, lock-offs at the top."
        case .biceps: "Elbow flexion: pulling, lock-offs."
        case .forearms: "Finger and wrist flexors — grip, crimping, hanging."
        case .forearmExtensors: "Open the hand and lift the wrist — balance crimping, protect the elbows."
        case .brachialis: "Elbow flexion under the biceps — strongest in palms-down and neutral pulls."
        case .lats: "Pulling down and in — the main climbing pull muscle."
        case .traps: "Shrug and lift the shoulder blades — carries, deadlifts, overhead lockout."
        case .upperBack: "Mid and lower traps, rhomboids — pull the shoulder blades back and down, posture."
        case .serratus: "Hold the shoulder blade on the ribs and reach — pressing, push-ups, shoulder health."
        case .lowerBack: "Spinal extension; protects the hinge."
        case .abs: "Rectus abdominis: trunk flexion and stiffness — keeps feet on in steep terrain."
        case .lowerAbs: "Lower part of the same muscle as abs, emphasised by curling the pelvis up — leg raises, toe hooks."
        case .deepCore: "Transverse abdominis: bracing corset under the abs — planks, dead bugs, heavy lifts."
        case .obliques: "Rotation and anti-rotation; flagging and twisting."
        case .glutes: "Hip extension and power — jumps, high-steps, rock-overs."
        case .gluteMed: "Side of the hip: abduction and pelvis stability — single-leg work, knee tracking, drop-knees."
        case .hipFlexors: "Lifting the knee — high-steps and toe hooks."
        case .adductors: "Inner thigh — drop-knees, stemming, wide positions."
        case .quads: "Knee extension — squats, step-ups, jumps."
        case .hamstrings: "Knee flexion & hip extension — heel hooks, hinges."
        case .calves: "Gastrocnemius: ankle push with a straight knee — jumping, standing on small footholds."
        case .soleus: "Deep calf, worked with a bent knee — endurance, ankle stability, Achilles health."
        case .tibialis: "Front of the shin: lifts the foot — knee and ankle health, toe hooks."
        }
    }

    /// Whether the muscle is drawn on the front and/or back body view.
    public var onFront: Bool { BodyMapLayout.muscles(.front).contains(self) }
    public var onBack: Bool { BodyMapLayout.muscles(.back).contains(self) }
}

extension Category: CaseIterable, Identifiable {
    public static let allCases: [Category] = [.warmup, .power, .strength, .mobility, .cardio, .stretch]
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .warmup: "Warm-up"
        case .power: "Explosive"
        case .strength: "Strength"
        case .mobility: "Mobility"
        case .cardio: "Cardio"
        case .stretch: "Stretching"
        }
    }

    public var blurb: String {
        switch self {
        case .warmup: "Raise temperature and open the ranges you'll use."
        case .power: "Fast, max-intent reps for dynamic movement."
        case .strength: "Build and define muscle with progressive load."
        case .mobility: "Active end-range control for climbing positions."
        case .cardio: "Aerobic engine and work capacity."
        case .stretch: "Static holds to restore length after loading."
        }
    }
}

extension BlockKind {
    /// Catalog category the block draws its exercises from.
    public var category: Category {
        switch self {
        case .warmup: .warmup
        case .power: .power
        case .strength: .strength
        case .mobility: .mobility
        case .cardio: .cardio
        case .cooldown: .stretch
        }
    }
}

public struct MuscleHit: Sendable, Hashable {
    public let exercise: Exercise
    /// true = primary mover, false = secondary.
    public let primary: Bool
}

extension Exercise {
    /// Primary = 1, secondary = 0.5.
    public var muscleWeights: [Muscle: Double] {
        var w: [Muscle: Double] = [:]
        for m in secondary { w[m] = 0.5 }
        for m in primary { w[m] = 1 }
        return w
    }

    public var muscles: [Muscle] { primary + secondary.filter { !primary.contains($0) } }

    /// Catalog and the user's custom exercises working `muscle`, grouped by category, primary movers first.
    public static func working(
        _ muscle: Muscle, equipment: Set<Equipment>? = nil, custom: CustomExercises = .shared
    ) -> [(Category, [MuscleHit])] {
        let all = catalog + custom.active
        return Category.allCases.compactMap { cat in
            let hits = all
                .filter { $0.category == cat && $0.muscles.contains(muscle) }
                .filter { e in equipment.map { eq in e.equipment.allSatisfy { eq.contains($0) } } ?? true }
                .map { MuscleHit(exercise: $0, primary: $0.primary.contains(muscle)) }
                .sorted { ($0.primary ? 0 : 1, $0.exercise.name) < ($1.primary ? 0 : 1, $1.exercise.name) }
            return hits.isEmpty ? nil : (cat, hits)
        }
    }

    /// Catalog and the user's custom exercises in `c`, by name.
    public static func inCategory(_ c: Category, custom: CustomExercises = .shared) -> [Exercise] {
        (catalog + custom.active).filter { $0.category == c }.sorted { $0.name < $1.name }
    }
}

extension Session {
    /// Normalised load 0…1 per muscle for heat maps.
    public var muscleHeat: [Muscle: Double] {
        let load = Generator.muscleLoad(blocks)
        let mx = load.values.max() ?? 1
        return load.mapValues { $0 / max(mx, 1e-9) }
    }

    /// Most-loaded muscles, descending.
    public func topMuscles(_ n: Int = 4) -> [Muscle] {
        muscleHeat.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key.rawValue < $1.key.rawValue) }.prefix(n).map(\.key)
    }

    /// Muscles touched by each block category (for the "what does each part do" overview).
    public func muscles(in kind: BlockKind) -> [Muscle] {
        guard let b = blocks.first(where: { $0.kind == kind }) else { return [] }
        var w: [Muscle: Double] = [:]
        for it in b.items { for (m, v) in Exercise.get(it.exerciseId).muscleWeights { w[m, default: 0] += v } }
        return w.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key.rawValue < $1.key.rawValue) }.map(\.key)
    }
}
