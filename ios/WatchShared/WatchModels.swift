import Foundation

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

    var items: [WItem] { blocks.flatMap(\.items) }
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

/// Watch → phone, queued with `transferUserInfo` so nothing is lost while the phone is away.
enum WatchEvent: Codable, Equatable {
    case setLogged(sessionId: String, exerciseId: String, setIndex: Int, kg: Double, reps: Int, rir: Int?)
    case itemDone(uid: String)
    case finished(WFinished)
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
