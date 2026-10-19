import Foundation
import LiftSensor

// Data exchanged between the iPhone app and the Watch app over WatchConnectivity (#56).
// Compiled into both targets; the Watch has no access to the workout engine, so the phone flattens
// everything the Watch shows into these plain values.

/// Everything the Watch shows while browsing, sent as the WatchConnectivity application context.
struct WatchSnapshot: Codable, Equatable {
    var generatedAt = Date()
    /// Mesocycle week 1…weeks.
    var week = 1
    var weeks = 4
    var deload = false
    /// This week's plan, in order.
    var sessions: [WSession] = []
    /// Example and custom workouts.
    var extras: [WSession] = []
    var nextSessionId: String?
    /// Readiness headline from Apple Health ("Ready to push"), if known.
    var readiness: String?
    var progress = WProgress()
    /// MonkeyWorkout Pro (#126): false = starting workouts on the Watch is locked. nil (older phone app) = allowed.
    var pro: Bool?
    /// Watch home style (#219) picked on the iPhone or the Watch, and when; nil = default (coach).
    var homeStyle: WatchHomeStyle?
    var homeStyleChangedAt: Date?
    /// Game mode rewards (#219); nil from older phone apps.
    var game: WGame?
    /// What the Watch does when a workout starts on the iPhone (#347); nil (older phone app) = ask.
    var watchStart: WatchStartMode?
    /// What an Apple Watch Ultra Action button press does during a workout (#349); nil (older phone app) = smart.
    var actionButton: WatchActionMode?
    /// Lift sensor (#383): reps and bar speed from the Watch's motion sensors; nil (older phone app) = default.
    var liftSensor: WatchLiftMode?
    /// Lift sensor counting level and how a racked set is logged (#410); nil (older phone app) = normal / auto.
    var liftCounting: WatchLiftCounting?
    var liftLogging: WatchLiftLogging?
    /// Counting level each exercise learned from corrections (#410): exercise id → -1.5…1.5.
    var liftLearned: [String: Double]?
    /// Hyrox (#426): division, goal, last race, and how to upload a race straight from the Watch; nil when unset.
    var hyrox: WHyrox?
    /// "Start on Watch" for another sport on the iPhone (#439); used for a few minutes after `at`.
    var sportStart: WSportStart?

    /// Today's water from Fuel (#496); a tap on the Watch adds a glass.
    var water: WWater?

    func session(_ id: String) -> WSession? { (sessions + extras).first { $0.id == id } }
}

struct WSession: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var title: String
    /// "Mon", "Day 2", "Example", "My workout".
    var dayLabel: String
    var estMin: Int
    var done: Bool
    /// Category colour as 0xRRGGBB.
    var tint: UInt32
    var blocks: [WBlock]
    /// Planned on an earlier day this week and not done (#266); nil from older phone apps.
    var missed: Bool? = nil

    var items: [WItem] { blocks.flatMap(\.items) }
    var isMissed: Bool { missed == true && !done }
}

struct WBlock: Codable, Equatable, Hashable {
    var title: String
    var tint: UInt32
    var tint2: UInt32
    var items: [WItem]
}

struct WItem: Codable, Equatable, Hashable, Identifiable {
    var uid: String
    var exerciseId: String
    var name: String
    var sets: Int
    /// As prescribed: "8–10", "4 min", "45 s/side".
    var reps: String
    var restSec: Int
    var intensity: String?
    var cues: [String]
    /// kg × reps logging applies.
    var loggable: Bool
    /// Timed work and, for intervals, the easy part used as rest.
    var timedSec: Int?
    var easySec: Int?
    /// Suggested load and reps for the coming sets.
    var kg: Double?
    var targetReps: Int?
    var kgStep: Double
    /// Mobility drill done during rest.
    var pairedName: String?

    var id: String { uid }
}

struct WProgress: Codable, Equatable {
    var streakWeeks = 0
    var bestStreakWeeks = 0
    var thisWeek = 0
    var target = 3
    var records: [WRecord] = []
    var recent: [WRecent] = []
}

struct WRecord: Codable, Equatable, Hashable {
    var name: String
    var kg: Double
}

struct WRecent: Codable, Equatable, Hashable {
    var title: String
    var date: Date
    var minutes: Int
    var sets: Int
}

/// Watch home screen styles (#219); the member picks one on the iPhone or the Watch.
enum WatchHomeStyle: String, Codable, CaseIterable, Identifiable {
    case coach, deck, rings

    static let `default` = WatchHomeStyle.coach

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coach: "Monkey coach"
        case .deck: "Crown deck"
        case .rings: "Charge & go"
        }
    }

    var detail: String {
        switch self {
        case .coach: "Your monkey cheers you on. Tap it for your streak, next PR and week."
        case .deck: "One card per day. Turn the Digital Crown to flip through your week."
        case .rings: "Week, streak and readiness rings. Press and hold to start."
        }
    }

    var symbol: String {
        switch self {
        case .coach: "face.smiling.inverse"
        case .deck: "rectangle.stack.fill"
        case .rings: "circle.circle.fill"
        }
    }

    /// Card gradient as 0xRRGGBB pairs.
    var tint: (UInt32, UInt32) {
        switch self {
        case .coach: (0xB23DFF, 0xFF3DA8)
        case .deck: (0x1E9BFF, 0x3DFFB0)
        case .rings: (0xFF7A3D, 0xFF3D5A)
        }
    }
}

/// Game layer (#219, #227): XP, level, weeks cleared and badges, computed on the phone (`GameProgress`,
/// `Achievements`) and shown in every look on the iPhone and the Watch. The Watch adds a finished
/// workout's XP until the next snapshot arrives.
struct WGame: Codable, Equatable {
    var xp = 0
    var workouts = 0
    var totalSets = 0
    /// Earned badge ids (`Achievements`).
    var badges: [String] = []
    /// Weeks with the session goal met (quest chests); nil from older phone apps.
    var weeksCleared: Int?
    /// Every badge, earned or not, so the Watch can draw them; nil from older phone apps.
    var catalog: [WBadge]?
    /// XP bar colour picked on the iPhone from Steel on (#242); nil = lime.
    var accent: GameAccent?

    /// Same numbers as `GameProgress` in the workout engine (the Watch can't link it).
    static let perLevel = 500
    static let weekBonus = 200
    /// XP for one workout: 50 + 5 per set.
    static func xp(sets: Int) -> Int { 50 + 5 * max(0, sets) }

    var level: Int { xp / Self.perLevel + 1 }
    var levelProgress: Double { Double(xp % Self.perLevel) / Double(Self.perLevel) }
    var xpInLevel: Int { xp % Self.perLevel }
    var earned: [WBadge] { (catalog ?? []).filter { badges.contains($0.id) } }
    var rank: GameRank { .of(level: level) }
}

/// One badge as the Watch draws it. Tier 1 bronze, 2 silver, 3 gold.
struct WBadge: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var title: String
    var symbol: String
    var tier: Int

    /// Gradient as 0xRRGGBB, same tier colours as the iPhone's badges.
    var tint: (UInt32, UInt32) {
        switch tier {
        case 3: (0xFFC71A, 0xFFED80)
        case 2: (0xB3BFD1, 0xF2F7FF)
        default: (0xD98547, 0xFFB873)
        }
    }
}

/// Watch → phone, queued with `transferUserInfo` so nothing is lost while the phone is away.
enum WatchEvent: Codable, Equatable {
    case setLogged(sessionId: String, exerciseId: String, setIndex: Int, kg: Double, reps: Int, rir: Int?)
    case itemDone(uid: String)
    case finished(WFinished)
    /// Home style picked on the Watch (#219).
    case homeStyle(WatchHomeStyle, changedAt: Date)
    /// The Watch tracks (or stopped tracking) heart rate for the iPhone workout of this session (#347).
    case tracking(sessionId: String, on: Bool)
    /// The Watch saved the Health workout for an iPhone workout it tracked (#347).
    case tracked(WTracked)
    /// Reps and bar speed the Watch measured for a set (#383).
    case liftSet(WLiftSet)
    /// A Hyrox race or sim recorded on the Watch (#426); its id is the Health workout's.
    case hyroxRace(HyroxRace)
}

/// Reps and bar speed the Watch measured for one set (#383). Speeds in m/s, ranges in m, times in s.
struct WLiftSet: Codable, Equatable, Hashable, Identifiable {
    var id = UUID()
    var sessionId: String
    var exerciseId: String
    var setIndex: Int
    var date: Date
    var kg: Double
    /// Mean speed of each rep's lifting part.
    var velocities: [Double]
    var peaks: [Double]
    var ranges: [Double]
    var concentric: [Double]
    /// Lowering time per rep; 0 = not found.
    var eccentric: [Double]
    /// Measured with the Watch strapped on the machine (#383 machine mode), not on the wrist.
    var machine: Bool
    /// Reps the member logged when it differs from the count (Crown correction, #410); nil = not known.
    var logged: Int? = nil

    var reps: Int { velocities.count }
    var best: Double? { velocities.max() }
    var mean: Double? { velocities.isEmpty ? nil : velocities.reduce(0, +) / Double(velocities.count) }
    /// Drop of the last rep against the fastest (0…1).
    var velocityLoss: Double {
        guard let best, best > 0, let last = velocities.last else { return 0 }
        return max(0, 1 - last / best)
    }
    var meanRange: Double? { ranges.isEmpty ? nil : ranges.reduce(0, +) / Double(ranges.count) }
    /// Mean power of the lifting parts, W.
    var power: Double? { mean.flatMap { kg > 0 ? kg * 9.80665 * $0 : nil } }
}

/// Live lift sensor state for the set the iPhone player shows (#383), sent while the Watch tracks it.
struct WLiftLive: Codable, Equatable {
    var sessionId: String
    var exerciseId: String
    var setIndex: Int
    var reps: Int
    /// Mean speed of the last rep, m/s.
    var lastVelocity: Double?
    var velocityLoss: Double
    /// The Watch is on the machine (machine mode).
    var machine: Bool
    /// The bar is racked: the set looks done.
    var ended: Bool
    /// Machine mode: where to strap the Watch, while the Watch waits for it.
    var strapHint: String?
}

/// Lift sensor setting (#383): off, or on with the velocity-loss stop cue (or no cue).
enum WatchLiftMode: String, Codable, CaseIterable, Identifiable {
    case off, noCue, loss10, loss20, loss30

    static let `default` = WatchLiftMode.loss20

    var id: String { rawValue }

    var on: Bool { self != .off }

    /// Velocity loss (0…1) that triggers the "Rack it" buzz.
    var lossLimit: Double? {
        switch self {
        case .loss10: 0.10
        case .loss20: 0.20
        case .loss30: 0.30
        case .off, .noCue: nil
        }
    }

    var title: String {
        switch self {
        case .off: "Off"
        case .noCue: "On, no stop buzz"
        case .loss10: "Buzz at 10 % slower (power)"
        case .loss20: "Buzz at 20 % slower (strength)"
        case .loss30: "Buzz at 30 % slower (muscle)"
        }
    }

    var short: String {
        switch self {
        case .off: "Off"
        case .noCue: "On"
        case .loss10: "Stop at −10 %"
        case .loss20: "Stop at −20 %"
        case .loss30: "Stop at −30 %"
        }
    }
}

/// Heart rate and energy the Watch measured for a workout run on the iPhone (#347).
struct WTracked: Codable, Equatable {
    var recordId: UUID
    var avgHeartRate: Double?
    var maxHeartRate: Double?
    var kcal: Double?
    /// The Watch saved the Apple Health workout; the phone must not save another.
    var savedToHealth: Bool
}

/// What the Watch does when a workout starts on the iPhone (#347).
enum WatchStartMode: String, Codable, CaseIterable, Identifiable {
    /// Wake the Watch and ask.
    case ask
    /// Wake the Watch and start tracking without asking.
    case always
    /// Leave the Watch alone (it still mirrors when its app is open).
    case never

    static let `default` = WatchStartMode.ask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: "Ask on Watch"
        case .always: "Start automatically"
        case .never: "Never"
        }
    }
}

/// What an Apple Watch Ultra Action button press does during a workout (#349).
enum WatchActionMode: String, Codable, CaseIterable, Identifiable {
    /// The obvious next step: log the set, skip rest, start/pause a timed set, next exercise, finish.
    case smart
    /// Always "I finished this set" (timed sets too); during rest, skip it.
    case set
    /// Start or end the rest countdown; timed sets start/pause. Sets are logged on screen.
    case rest

    static let `default` = WatchActionMode.smart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: "Smart next"
        case .set: "Log set"
        case .rest: "Rest timer"
        }
    }
}

/// How an iPhone workout ended, sent with `WatchKeys.liveEnded` (#347).
enum WLiveOutcome: String, Codable {
    case finished, discarded, paused
}

struct WFinished: Codable, Equatable {
    var id = UUID()
    var sessionId: String
    var setsDone: [String: Int]
    var start: Date
    var end: Date
    var avgHeartRate: Double?
    var maxHeartRate: Double?
    var kcal: Double?
    /// The Watch saved the Apple Health workout; the phone must not save another.
    var savedToHealth: Bool
}

/// Phone player state mirrored on the Watch while a workout runs on the iPhone.
struct WLive: Codable, Equatable {
    var sessionTitle: String
    var exercise: String
    var setLabel: String
    var detail: String
    var restEnd: Date?
    var next: String
    var tint: UInt32
    /// A set was just logged and its effort can be given.
    var effortPending: Bool
    /// The lime button's label on the phone ("SET 2 DONE", "START 4:00", "NEXT").
    var action: String
    /// Session the phone runs (#347); nil from older phone apps.
    var sessionId: String?
    var estMin: Int?
    var exercises: Int?
    /// Current set, so the Watch can measure it (#383); nil from older phone apps.
    var exerciseId: String?
    var setIndex: Int?
    var loggable: Bool?
    var kg: Double?
    /// Coach line just said on the phone (#379) and when; the Watch shows it a few seconds with a tap.
    var coach: String? = nil
    var coachAt: Date? = nil
}

/// How strict the lift sensor counts reps (#410).
enum WatchLiftCounting: String, Codable, CaseIterable, Identifiable {
    case relaxed, normal, strict

    static let `default` = WatchLiftCounting.normal

    var id: String { rawValue }

    /// `Strictness` level of the setting.
    var level: Double {
        switch self {
        case .relaxed: -1
        case .normal: 0
        case .strict: 1
        }
    }

    var title: String {
        switch self {
        case .relaxed: "Relaxed"
        case .normal: "Normal"
        case .strict: "Strict"
        }
    }

    /// Name of a level, for a learned exercise level.
    static func name(_ level: Double) -> String {
        level <= -0.5 ? "Relaxed" : level >= 0.5 ? "Strict" : "Normal"
    }
}

/// What happens when the bar is racked (#410).
enum WatchLiftLogging: String, Codable, CaseIterable, Identifiable {
    /// Logs itself after a countdown with Undo.
    case auto
    /// Asks "8 reps?" and waits for a tap.
    case confirm
    /// Counts only; the member logs the set as usual.
    case manual

    static let `default` = WatchLiftLogging.auto
    /// Countdown before an automatic log, s.
    static let countdown = 6.0

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .confirm: "Tap ✓"
        case .manual: "I log"
        }
    }
}

/// Practice mode (#410): the iPhone starts, recounts at another level, or stops a practice on the Watch.
struct WLiftPracticeCommand: Codable, Equatable {
    /// nil = stop.
    var level: Double?
}

/// Practice mode (#410): what the Watch sees, sent to the iPhone a few times a second.
struct WLiftPracticeState: Codable, Equatable {
    var level: Double
    var reps: Int
    var velocities: [Double]
    var ranges: [Double]
    /// Smoothed acceleration along the movement (g), 20 values a second, the last 6 s.
    var trace: [Double]
    /// Where each counted rep ends in `trace` (index).
    var marks: [Int]
}

/// Fuel water (#496): glasses counted today against the day's target.
struct WWater: Codable, Equatable {
    /// `PlanCalendar` day key the counts belong to.
    var day: String
    var glasses: Int
    var target: Int
    var glassMl: Int

    /// Same format as `PlanCalendar.key` (the Watch has no WorkoutEngine).
    static func key(_ date: Date, _ cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Glasses for today; a snapshot from yesterday counts as 0.
    func today(_ now: Date = Date()) -> Int { day == Self.key(now) ? glasses : 0 }
}

/// Watch → phone remote control of the iPhone player.
enum WCommand: String, Codable {
    case main, skipRest, addRest, effort0, effort1, effort2, effort3, effort4, next, previous
}

enum WatchKeys {
    static let snapshot = "snapshot"
    static let event = "event"
    static let live = "live"
    static let liveEnded = "liveEnded"
    static let command = "command"
    /// `WLiveOutcome` raw value, with `liveEnded` (#347).
    static let outcome = "outcome"
    /// Workout record the phone saved, with outcome `finished` (#347).
    static let recordId = "recordId"
    /// `WLiftLive` from the Watch while it measures a set of the iPhone workout (#383).
    static let lift = "lift"
    /// Live heart rate (Int bpm) of an iPhone workout the Watch tracks, for the Live Activity (#371).
    static let heartRate = "heartRate"
    /// Practice mode (#410): `WLiftPracticeCommand` phone → Watch, `WLiftPracticeState` Watch → phone.
    static let practice = "practice"
    static let practiceState = "practiceState"
    /// Watch → phone: one glass of water for this day key (#496), sent with `transferUserInfo`.
    static let water = "water"
}

extension JSONEncoder {
    static let watch: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
}

extension JSONDecoder {
    static let watch: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

/// Hyrox settings for the Watch (#426), from the iPhone's Hyrox hub.
/// A sport the iPhone asked the Watch to track (#439). `sport` is the shared raw value (`Sport` / `TrackedSport`).
struct WSportStart: Codable, Equatable {
    var sport: String
    var saver: Bool
    var at: Date
}

struct WHyrox: Codable, Equatable {
    var division = HyroxDivision()
    /// Goal for a full race, seconds.
    var goalSeconds: Double?
    var raceName: String?
    var raceDate: Date?
    /// Last full race, for the PB on the finish screen.
    var lastRace: HyroxRace?
    /// Upload-only key for `POST /v1/watch/sports` and the API base URL, so a Watch with a network sends the race
    /// at once; nil until the iPhone fetched one.
    var uploadKey: String?
    var apiBase: String?
    /// "Start race on Watch" on the iPhone: the format and when it was asked (used for a few minutes).
    var start: HyroxFormat?
    var startAt: Date?
}
