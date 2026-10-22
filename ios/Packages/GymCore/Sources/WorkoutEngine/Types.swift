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
    // Muscle audit (#112). Additive: raw values are persisted, older data decodes unchanged.
    case traps, serratus, brachialis, tibialis, soleus
    case forearmExtensors = "forearm-extensors"
    case lowerAbs = "lower-abs"
    case deepCore = "deep-core"
    case gluteMed = "glute-med"

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
    // Gym audit (#162): common in commercial gyms, each with at least one exercise.
    case ezBar = "ez-bar"
    case preacherBench = "preacher-bench"
    case shoulderPress = "shoulder-press-machine"
    case standingCalf = "standing-calf"
    case tBarRow = "t-bar-row"
    case ghd
    case stabilityBall = "stability-ball"
    case jumpRope = "jump-rope"
    case assistedMachine = "assisted-pullup-dip"
    case reverseHyper = "reverse-hyper"
    case curlMachine = "biceps-curl-machine"
    case tricepsMachine = "triceps-machine"
    case dipBelt = "dip-belt"
    // Gym app comparison (#182).
    case rowMachine = "row-machine"
    case backExtensionMachine = "back-extension-machine"
    case squatMachine = "squat-machine"
    case beltSquat = "belt-squat"
    case gluteMachine = "glute-machine"
    case multiHip = "multi-hip"
    case pulloverMachine = "pullover-machine"
    case sandbag, sliders
    case balanceTrainer = "balance-trainer"
    case massageBall = "massage-ball"
    case stallBars = "stall-bars"
    // Climbing gym (#366).
    case hangboard
    case climbingWall = "climbing-wall"
    case liftBlock = "lift-block"
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

    /// Catalog exercise, or one of the user's custom exercises (`CustomExercises.shared`).
    public static func find(_ id: String) -> Exercise? { find(id, custom: .shared) }

    public static func find(_ id: String, custom: CustomExercises) -> Exercise? { byId[id] ?? custom.exercise(id) }

    /// Crashes on unknown ids — ids come from the catalog or the user's custom exercises.
    public static func get(_ id: String) -> Exercise {
        guard let e = find(id) else { preconditionFailure("Unknown exercise \(id)") }
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
    /// Gym day before / after a climbing day (#47); nil = `.light`. Optional so older profiles decode.
    public var climbBefore: ClimbNeighbour?
    public var climbAfter: ClimbNeighbour?
    /// Gym sessions on climbing days (#47); nil = `.avoid`.
    public var climbSameDay: ClimbSameDay?
    /// Show the Wall session on Train (#366; was the climbing-day add-on, #47); nil = on, false = off.
    public var climbDayAddon: Bool?
    /// Week-to-week variety (#64); nil = `.fresh`. Optional so older profiles decode.
    public var variety: PlanVariety?
    /// Rest between sets (#78); nil = the goal's default.
    public var restStyle: RestStyle?
    /// Supersets / circuits (#78); nil = the goal's default.
    public var grouping: Grouping?
    /// Training method (#156); nil = `.block`. Optional so older profiles decode.
    public var method: TrainingMethod?
    /// Accessories cycle through their variations week to week (#182); nil = off.
    public var rotateVariations: Bool?
    /// Blocks in every workout and their time split (#198); nil = the goal's automatic flow.
    public var sessionFlow: SessionFlow?
    /// Exercises always in a block, keyed by block kind (#204); nil = picked for the day as before.
    public var blockPicks: [String: BlockPicks]?
    /// Per-workout overrides (#106) keyed by session id ("w2s1"). Set by the app from the synced overrides when
    /// generating; not part of the profile form.
    public var sessionStyles: [String: SessionStyle]?
    /// This week's session-type changes (#342) keyed by session id ("w2s1"): one workout trains another focus.
    /// Set by the app from the synced overrides when generating; not part of the profile form.
    public var sessionFoci: [String: Focus]?
    /// How the week alternates muscle groups (#200); nil = `.auto` (the goal's own split).
    public var split: SplitStyle?
    /// Per-day session types in week order (#200), set by tapping a day; overrides `split` when it has one entry
    /// per session. nil = none.
    public var splitDays: [Focus]?
    /// Muscle groups to prioritise (#200): +1 set and first among accessories. nil / empty = none.
    public var focusMuscles: [MuscleGroup]?
    /// Where equipment sits in the home gym (#274): supersets / circuits stay in one zone. nil = grouped as before.
    public var gymLayout: GymLayout?
    /// Default warm-up / cool-down style (#293); nil = `.auto` (picked to match the exercises as before).
    public var warmupStyle: WarmupStyle?
    public var cooldownStyle: CooldownStyle?
    /// Learned exercise affinities (#299), frozen when the week's plan was made. Set by the app when generating;
    /// not part of the profile form. nil = nothing learned (plans exactly as before).
    public var learnedTaste: [String: Double]?
    /// Birth year from Body & Health (#375). Set by the app when generating; not part of the profile form.
    /// nil = unknown (plans exactly as before).
    public var birthYear: Int?

    /// Usual workout time (#377), minutes after midnight; nil = not set (plans as before).
    public var workoutTime: Int?

    /// Other sports with their days (#416); nil = none. Climbing stays in the climbing fields above.
    public var sports: [SportPlan]?

    /// Dated sport days and trips (#474), e.g. a snowboard week; nil = none. Planned like sport days, no gym on them.
    public var sportTrips: [SportTrip]?

    /// Hyrox hub (#426): division and goal; nil = not set. The race date is the Hyrox sport's event date.
    public var hyrox: HyroxProfile?

    /// Run & cardio programme (#618): a race with a goal time, or Hybrid; nil = none. Runs are planned around lifting.
    public var runGoal: RunGoal?

    /// Usually trains before 11:00: muscles start cooler, the warm-up gets one more minute of cardio (#377).
    public var trainsInMorning: Bool { workoutTime.map { $0 < 11 * 60 } ?? false }

    /// Age this year, when the birth year is known.
    public var age: Int? { birthYear.map { Calendar.current.component(.year, from: Date()) - $0 } }

    public init(
        goal: Goal = .balanced, sessionsPerWeek: Int = 3, experience: Experience = .intermediate,
        climbingDaysPerWeek: Int = 2, maxSessionMinutes: Int? = nil, equipment: [Equipment] = Gym.puls5.equipment,
        climbingWeekdays: [Int]? = nil, gymWeekdays: [Int]? = nil, gym: GymRef? = nil,
        climbBefore: ClimbNeighbour? = nil, climbAfter: ClimbNeighbour? = nil,
        climbSameDay: ClimbSameDay? = nil, climbDayAddon: Bool? = nil, variety: PlanVariety? = nil,
        restStyle: RestStyle? = nil, grouping: Grouping? = nil, method: TrainingMethod? = nil,
        rotateVariations: Bool? = nil, sessionFlow: SessionFlow? = nil
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
        self.climbBefore = climbBefore
        self.climbAfter = climbAfter
        self.climbSameDay = climbSameDay
        self.climbDayAddon = climbDayAddon
        self.variety = variety
        self.restStyle = restStyle
        self.grouping = grouping
        self.method = method
        self.rotateVariations = rotateVariations
        self.sessionFlow = sessionFlow
    }
}

public enum Focus: String, Codable, CaseIterable, Sendable {
    case fullLower = "full-lower"
    case fullUpper = "full-upper"
    case fullPower = "full-power"
    case upper, lower, push, pull, legs, conditioning
    /// Body-part days (#200).
    case chestTri = "chest-tri"
    case backBi = "back-bi"
    case shouldersArms = "shoulders-arms"
    case chestBack = "chest-back"
    case posterior

    /// Unknown values (a newer app's session types) decode as full body instead of failing the whole record.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Focus(rawValue: raw) ?? .fullUpper
    }

    /// Closest pre-#200 session type: stored in history so older app versions can still read it.
    public var legacy: Focus {
        switch self {
        case .chestTri: .push
        case .backBi: .pull
        case .shouldersArms, .chestBack: .upper
        case .posterior: .lower
        default: self
        }
    }
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
    /// Superset / circuit label (#78), e.g. "A1", "A2": same letter = done back to back, rest after the round.
    public var group: String? = nil
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
