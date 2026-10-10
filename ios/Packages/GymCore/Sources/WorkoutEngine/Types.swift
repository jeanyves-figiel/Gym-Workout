import Foundation

public enum Goal: String, Codable, CaseIterable, Sendable, Identifiable {
    case balanced, build, strength, climbing, endurance, athletic
    public var id: String { rawValue }
}

public enum Experience: String, Codable, CaseIterable, Sendable, Identifiable {
    case beginner, intermediate, advanced
    public var id: String { rawValue }
    public var level: Int {
        switch self {
        case .beginner: 1
        case .intermediate: 2
        case .advanced: 3
        }
    }
}

public enum Muscle: String, Codable, CaseIterable, Sendable {
    case chest
    case frontDelts = "front-delts"
    case sideDelts = "side-delts"
    case rearDelts = "rear-delts"
    case rotatorCuff = "rotator-cuff"
    case triceps, biceps, forearms, lats
    case upperBack = "upper-back"
    case lowerBack = "lower-back"
    case abs, obliques, glutes
    case hipFlexors = "hip-flexors"
    case adductors, quads, hamstrings, calves

    public var label: String { rawValue.replacingOccurrences(of: "-", with: " ") }
}

public enum Equipment: String, Codable, CaseIterable, Sendable, Identifiable {
    case barbell
    case trapBar = "trap-bar"
    case rack, bench, dumbbells, kettlebells, cable, smith
    case legPress = "leg-press"
    case hackSquat = "hack-squat"
    case legCurl = "leg-curl"
    case legExtension = "leg-extension"
    case latPulldown = "lat-pulldown"
    case seatedRow = "seated-row"
    case chestPress = "chest-press"
    case pecDeck = "pec-deck"
    case hipThrustMachine = "hip-thrust-machine"
    case backExtension = "back-extension"
    case pullupBar = "pullup-bar"
    case dipStation = "dip-station"
    case rings, trx, landmine
    case plyoBox = "plyo-box"
    case medBall = "med-ball"
    case slamBall = "slam-ball"
    case sled
    case battleRope = "battle-rope"
    case abWheel = "ab-wheel"
    case bands
    case foamRoller = "foam-roller"
    case mat, treadmill, bike
    case airBike = "air-bike"
    case rower
    case skiErg = "ski-erg"
    case stairClimber = "stair-climber"
    case elliptical
    case seatedCalf = "seated-calf"
    case hipAdAbductor = "hip-ad-abductor"
    case abCrunch = "ab-crunch"
    case torsoRotation = "torso-rotation"
    public var id: String { rawValue }
}

public enum Category: String, Codable, Sendable {
    case warmup, power, strength, mobility, cardio, stretch
}

public enum Pattern: String, Codable, Sendable {
    case squat, hinge
    case singleLeg = "single-leg"
    case hPush = "h-push"
    case vPush = "v-push"
    case hPull = "h-pull"
    case vPull = "v-pull"
    case coreAntiExt = "core-anti-ext"
    case coreAntiRot = "core-anti-rot"
    case coreFlex = "core-flex"
    case carry
    case armsFlex = "arms-flex"
    case armsExt = "arms-ext"
    case shoulderHealth = "shoulder-health"
    case calves
    case forearmAntagonist = "forearm-antagonist"
    case kneeFlex = "knee-flex"
    case kneeExt = "knee-ext"
    case lateralRaise = "lateral-raise"
    case jump, `throw`, ballistic
    case upperPlyo = "upper-plyo"
    case general
}

public enum Region: String, Codable, Sendable {
    case hips, shoulders, thoracic, wrists, ankles, spine
}

public enum Unit: String, Codable, Sendable {
    case reps, sec
}

public struct Exercise: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let category: Category
    public let pattern: Pattern
    public let primary: [Muscle]
    public let secondary: [Muscle]
    /// All required. Empty = bodyweight.
    public let equipment: [Equipment]
    /// Minimum experience: 1 beginner, 2 intermediate, 3 advanced.
    public let level: Int
    public let unilateral: Bool
    /// Seconds per rep (incl. tempo) for time estimates.
    public let secPerRep: Double?
    /// Heavy grip; avoided for frequent climbers to spare fingers/forearms.
    public let gripHeavy: Bool
    /// Eligible as main lift of a strength block.
    public let main: Bool
    public let unit: Unit?
    public let regions: [Region]
    public let cues: [String]
    /// False = only used by example workouts, never picked by the generator (keeps generated plans stable).
    public let generator: Bool

    public init(
        id: String, name: String, category: Category, pattern: Pattern,
        primary: [Muscle], secondary: [Muscle] = [], equipment: [Equipment], level: Int,
        unilateral: Bool = false, secPerRep: Double? = nil, gripHeavy: Bool = false, main: Bool = false,
        unit: Unit? = nil, regions: [Region] = [], cues: [String], generator: Bool = true
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.pattern = pattern
        self.primary = primary
        self.secondary = secondary
        self.equipment = equipment
        self.level = level
        self.unilateral = unilateral
        self.secPerRep = secPerRep
        self.gripHeavy = gripHeavy
        self.main = main
        self.unit = unit
        self.regions = regions
        self.cues = cues
        self.generator = generator
    }

    private static let byId: [String: Exercise] = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })

    public static func find(_ id: String) -> Exercise? { byId[id] }

    /// Crashes on unknown ids — ids come from the catalog itself.
    public static func get(_ id: String) -> Exercise {
        guard let e = byId[id] else { preconditionFailure("Unknown exercise \(id)") }
        return e
    }
}

public struct Profile: Codable, Hashable, Sendable {
    public var goal: Goal
    public var sessionsPerWeek: Int
    public var experience: Experience
    /// Climbing sessions per week (fatigue + antagonist logic).
    public var climbingDaysPerWeek: Int
    /// Optional hard cap on session minutes.
    public var maxSessionMinutes: Int?
    public var equipment: [Equipment]
    /// Weekdays the user climbs (1 = Monday … 7 = Sunday). Optional so older saved profiles still decode.
    public var climbingWeekdays: [Int]?
    /// Weekdays the user prefers for the gym (1 = Monday … 7 = Sunday); nil = any day.
    public var gymWeekdays: [Int]?
    /// Where the user trains; nil = the default scoped gym (older profiles).
    public var gym: GymRef?

    public init(
        goal: Goal = .balanced, sessionsPerWeek: Int = 3, experience: Experience = .intermediate,
        climbingDaysPerWeek: Int = 2, maxSessionMinutes: Int? = nil, equipment: [Equipment] = Gym.puls5.equipment,
        climbingWeekdays: [Int]? = nil, gymWeekdays: [Int]? = nil, gym: GymRef? = nil
    ) {
        self.goal = goal
        self.sessionsPerWeek = sessionsPerWeek
        self.experience = experience
        self.climbingDaysPerWeek = climbingDaysPerWeek
        self.maxSessionMinutes = maxSessionMinutes
        self.equipment = equipment
        self.climbingWeekdays = climbingWeekdays
        self.gymWeekdays = gymWeekdays
        self.gym = gym
    }
}

public enum Focus: String, Codable, Sendable {
    case fullLower = "full-lower"
    case fullUpper = "full-upper"
    case fullPower = "full-power"
    case upper, lower, push, pull, legs, conditioning
}

public enum BlockKind: String, Codable, Sendable, CaseIterable {
    case warmup, power, strength, mobility, cardio, cooldown
}

public struct Prescription: Codable, Hashable, Sendable {
    public var sets: Int
    /// e.g. "5", "8–10", "30 s", "20 min"
    public var reps: String
    public var restSec: Int
    public var intensity: String?
    public var note: String?
}

public struct PlannedExercise: Codable, Hashable, Sendable, Identifiable {
    public var uid: String
    public var exerciseId: String
    public var slot: Pattern
    public var prescription: Prescription
    /// Mobility drill done during rest of this exercise.
    public var pairedWith: String?
    /// uid of the exercise in whose rest this one is performed.
    public var supersetWith: String?
    public var estSec: Int
    public var id: String { uid }
}

public struct Block: Codable, Hashable, Sendable, Identifiable {
    public var kind: BlockKind
    public var title: String
    public var targetMin: Int
    public var items: [PlannedExercise]
    public var note: String?
    public var id: BlockKind { kind }
    public var estMin: Double { Double(items.reduce(0) { $0 + $1.estSec }) / 60 }
}

public struct Session: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var index: Int
    public var focus: Focus
    public var title: String
    public var targetMin: Int
    public var estMin: Int
    public var blocks: [Block]
    /// 1 = Monday … 7 = Sunday when the plan is laid out on weekdays (climbing/gym days set); nil otherwise.
    public var weekday: Int? = nil
}

public struct WeekPlan: Codable, Hashable, Sendable {
    /// 1…4 within the mesocycle.
    public var week: Int
    public var deload: Bool
    public var seed: UInt32
    public var sessionMinutes: Int
    public var sessions: [Session]
}
