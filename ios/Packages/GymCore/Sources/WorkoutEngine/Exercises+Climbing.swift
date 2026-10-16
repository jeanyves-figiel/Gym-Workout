// Climbing gym exercises (#366): the wall warm-up and cool-down drills MonkeyGrade's session planner uses that the
// catalog was missing, plus hangboard basics (in neither app before). Library-only like the #174/#182 extensions:
// never picked by the plan generator; played by the Wall session on climbing days (`WallSession`) and reached from
// Explore → Climbing. Names follow MonkeyGrade (`Climbing.monkeyGradeSlug`). Keep ids stable — they are persisted.

extension Exercise {
    static let climbingCatalog: [Exercise] = [
        // MARK: Wall warm-up
        Exercise(id: "finger-ramp", name: "Finger & forearm ramp", category: .warmup, pattern: .general, primary: [.forearms], secondary: [.forearmExtensors], equipment: [], level: 1, unit: .sec, regions: [.wrists], cues: ["Open the hands wide, then squeeze easy", "Each round a little firmer", "Never to pain"], generator: false),
        Exercise(id: "forearm-waves", name: "Forearm wrist waves", category: .warmup, pattern: .general, primary: [.forearms, .forearmExtensors], equipment: [], level: 1, unit: .sec, regions: [.wrists], cues: ["Arms out in front", "Wave the hands slowly up and down", "Light warmth, no strain"], generator: false),
        Exercise(id: "band-external-rotation", name: "Band external rotation", category: .warmup, pattern: .shoulderHealth, primary: [.rotatorCuff], secondary: [.rearDelts], equipment: [.bands], level: 1, unilateral: true, secPerRep: 3, cues: ["Elbow at your side, bent 90°", "Rotate the forearm outward", "Slow back in"], generator: false),
        Exercise(id: "hang-ramp", name: "Hangboard ramp", category: .warmup, pattern: .general, primary: [.forearms], secondary: [.lats, .upperBack], equipment: [.hangboard], level: 1, gripHeavy: true, unit: .sec, cues: ["Start on the biggest edge, feet on a chair if needed", "Each hang a smaller edge or less help", "Stop before strain"], generator: false),
        Exercise(id: "recruitment-pulls", name: "Recruitment pulls", category: .warmup, pattern: .vPull, primary: [.forearms, .lats], secondary: [.upperBack, .biceps], equipment: [.hangboard], level: 2, secPerRep: 3, gripHeavy: true, cues: ["Good edge, half crimp", "Short, near-hard pull", "Full rest between pulls"], generator: false),
        Exercise(id: "easy-traverse", name: "Easy traversing", category: .warmup, pattern: .general, primary: [.forearms, .lats], secondary: [.quads, .calves, .abs], equipment: [.climbingWall], level: 1, unit: .sec, cues: ["Big holds, big feet", "Relaxed grip, straight arms", "Move smoothly side to side"], generator: false),

        // MARK: Hangboard
        Exercise(id: "max-hangs", name: "Max hangs", category: .strength, pattern: .general, primary: [.forearms], secondary: [.lats, .upperBack], equipment: [.hangboard], level: 3, gripHeavy: true, unit: .sec, cues: ["20 mm edge, half crimp", "10 s hang, add weight only when easy", "Long rest: 2–3 min"], generator: false),
        Exercise(id: "repeaters", name: "Repeaters 7/3", category: .strength, pattern: .general, primary: [.forearms], secondary: [.lats], equipment: [.hangboard], level: 2, gripHeavy: true, unit: .sec, cues: ["7 s on, 3 s off, six times", "Same edge every rep", "Stop the set when the grip opens"], generator: false),
        Exercise(id: "open-hand-hang", name: "Open-hand hang", category: .strength, pattern: .general, primary: [.forearms], secondary: [.lats, .upperBack], equipment: [.hangboard], level: 2, gripHeavy: true, unit: .sec, cues: ["Three fingers drag, thumb off", "Shoulders engaged, elbows soft", "Easier on the pulleys than crimping"], generator: false),
        Exercise(id: "block-lift", name: "No-hang block lift", category: .strength, pattern: .general, primary: [.forearms], secondary: [.traps, .upperBack], equipment: [.liftBlock], level: 2, unilateral: true, gripHeavy: true, unit: .sec, cues: ["Weight hangs from the pin", "Half crimp, stand tall", "Lift 10 s, set it down slowly"], generator: false),
        Exercise(id: "pinch-block-lift", name: "Pinch block lift", category: .strength, pattern: .general, primary: [.forearms], secondary: [.traps], equipment: [.liftBlock], level: 1, unilateral: true, gripHeavy: true, unit: .sec, cues: ["Thumb opposes the fingers", "Lift straight up from the floor", "Wrist stays neutral"], generator: false),

        // MARK: Wall cool-down
        Exercise(id: "wrist-flexor-floor", name: "Wrist flexor floor stretch", category: .stretch, pattern: .general, primary: [.forearms], equipment: [], level: 1, unit: .sec, regions: [.wrists], cues: ["Kneel, palms down, fingers pointing back", "Ease your weight back slowly", "Gentle pull only"], generator: false),
    ]
}

/// Climbing gym exercises grouped for Explore → Climbing and the Wall session (#366), with MonkeyGrade's names.
public enum Climbing {
    /// Explore → Climbing sections, in display order.
    public enum Group: String, CaseIterable, Sendable, Identifiable {
        case warmup, hangboard, cooldown
        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .warmup: "Wall warm-up"
            case .hangboard: "Hangboard"
            case .cooldown: "Wall cool-down"
            }
        }

        public var ids: [String] {
            switch self {
            case .warmup:
                ["finger-ramp", "forearm-waves", "wrist-prep", "finger-extensions", "shoulder-car", "band-external-rotation",
                 "scap-pull-up", "hang-ramp", "recruitment-pulls", "easy-traverse", "hip-90-90", "deep-squat-pry"]
            case .hangboard:
                ["max-hangs", "repeaters", "open-hand-hang", "block-lift", "pinch-block-lift"]
            case .cooldown:
                ["forearm-extensor", "forearm-flexor", "wrist-flexor-floor", "reverse-wrist-curl", "sleeper-stretch",
                 "pec-stretch", "t-spine-roller", "straddle-stretch"]
            }
        }

        public var exercises: [Exercise] { ids.compactMap { Exercise.find($0) } }
    }

    /// Every climbing exercise (Explore count), in group order.
    public static var ids: [String] { Group.allCases.flatMap(\.ids) }

    /// The same drill in MonkeyGrade's session planner (`core/constants.py`, `GET /api/routines`): shows the MG tag and
    /// keeps the two apps' names in step. Hangboard drills have no MonkeyGrade twin yet.
    public static let monkeyGradeSlug: [String: String] = [
        "finger-ramp": "finger_forearm_ramp",
        "forearm-waves": "forearm_waves",
        "wrist-prep": "wu_wrist_prep",
        "finger-extensions": "wu_band_finger_ext",
        "shoulder-car": "wu_shoulder_cars",
        "band-external-rotation": "wu_band_external_rot",
        "scap-pull-up": "wu_scap_pullups",
        "hang-ramp": "wu_hang_ramp",
        "recruitment-pulls": "wu_recruitment_pulls",
        "easy-traverse": "wu_easy_traverse",
        "hip-90-90": "wu_hip_opener_90_90",
        "deep-squat-pry": "wu_deep_squat_hold",
        "dead-hang": "wu_hang_dead",
        "forearm-extensor": "cd_finger_extensor",
        "forearm-flexor": "cd_forearm_stretch",
        "wrist-flexor-floor": "cd_wrist_flexor_floor",
        "reverse-wrist-curl": "cd_reverse_wrist_curl",
        "sleeper-stretch": "cd_sleeper_stretch",
        "pec-stretch": "cd_doorway_pec_stretch",
        "t-spine-roller": "cd_thoracic_extension",
        "straddle-stretch": "cd_seated_straddle",
    ]
}

extension Exercise {
    /// MonkeyGrade's id for the same drill, when it has one (#366).
    public var monkeyGradeSlug: String? { Climbing.monkeyGradeSlug[id] }
}
