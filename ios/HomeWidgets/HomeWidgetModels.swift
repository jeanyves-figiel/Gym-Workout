import Foundation

// Home Screen widgets (#297): compiled into the iPhone app (writes the snapshot, Account settings, previews)
// and the widget extension (reads it). Only Foundation and SwiftUI here: the extension can't link the app.

/// What a widget shows.
enum HomeWidgetTopic: String, Codable, CaseIterable, Identifiable, Sendable {
    case nextUp, week, streak, readiness, level, records, lastWorkout, volume, climbing, fuel, dashboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nextUp: "Next up"
        case .week: "This week"
        case .streak: "Streak"
        case .readiness: "Readiness"
        case .level: "Level + XP"
        case .records: "Top lifts"
        case .lastWorkout: "Last workout"
        case .volume: "Volume"
        case .climbing: "Climbing"
        case .fuel: "Fuel"
        case .dashboard: "Week dashboard"
        }
    }

    var symbol: String {
        switch self {
        case .nextUp: "play.circle.fill"
        case .week: "circle.dashed.inset.filled"
        case .streak: "flame.fill"
        case .readiness: "heart.fill"
        case .level: "star.circle.fill"
        case .records: "trophy.fill"
        case .lastWorkout: "clock.arrow.circlepath"
        case .volume: "chart.bar.fill"
        case .climbing: "figure.climbing"
        case .fuel: "fork.knife"
        case .dashboard: "square.grid.2x2.fill"
        }
    }

    /// Gradient as 0xRRGGBB pairs, the Explore palette.
    var tint: (UInt32, UInt32) {
        switch self {
        case .nextUp: (0x3B6CFF, 0x8A4DFF)
        case .week: (0x00C9A7, 0x2F80ED)
        case .streak: (0xFF5F6D, 0xFFC371)
        case .readiness: (0xFF3CAC, 0xFF7A3D)
        case .level: (0x4B2FD6, 0xB23DFF)
        case .records: (0xF7971E, 0xFFD200)
        case .lastWorkout: (0x11998E, 0x38EF7D)
        case .volume: (0x1E9BFF, 0x3DFFB0)
        case .climbing: (0xFF7A18, 0xAF002D)
        case .fuel: (0xFF8A3D, 0xFF3D7F)
        case .dashboard: (0xFF3CAC, 0x784BA0)
        }
    }

    /// Dark text on the light gradients.
    var inkOnGradient: Bool { self == .records || self == .lastWorkout }

    /// Topics offered per size; the dashboard needs the large size.
    static func offered(for size: HomeWidgetSize) -> [HomeWidgetTopic] {
        switch size {
        case .large: allCases
        case .lock: [.nextUp, .week, .streak, .readiness, .level, .climbing, .fuel]
        default: allCases.filter { $0 != .dashboard }
        }
    }
}

enum HomeWidgetLook: String, Codable, CaseIterable, Identifiable, Sendable {
    /// A: Explore-style gradient cards.
    case gradient
    /// B: the monkey, level, XP and a nudge.
    case coach
    /// C: dark tiles with colour-coded numbers.
    case data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gradient: "Gradient cards"
        case .coach: "Monkey coach"
        case .data: "Data tiles"
        }
    }

    var detail: String {
        switch self {
        case .gradient: "One topic per widget, big number, vivid gradient."
        case .coach: "Your monkey's mood, level, XP and today's nudge."
        case .data: "Dark tiles with colour-coded numbers. Most info per widget."
        }
    }

    var tint: (UInt32, UInt32) {
        switch self {
        case .gradient: (0x3B6CFF, 0xFF3CAC)
        case .coach: (0x2E1A6E, 0x7A3CFF)
        case .data: (0x26272E, 0x1B1C21)
        }
    }
}

enum HomeWidgetSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small, medium, large, lock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .lock: "Lock Screen"
        }
    }

    var symbol: String {
        switch self {
        case .small: "square.fill"
        case .medium: "rectangle.fill"
        case .large: "square.grid.2x2.fill"
        case .lock: "lock.fill"
        }
    }
}

/// One-tap setups in Account → Home Screen widgets; Customise edits the sizes one by one.
enum HomeWidgetPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic, coach, data, climber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .coach: "Coach Monkey"
        case .data: "Data nerd"
        case .climber: "Climber"
        }
    }

    var settings: HomeWidgetSettings {
        switch self {
        case .classic: HomeWidgetSettings(look: .gradient, small: .streak, medium: .nextUp, large: .dashboard, lock: .week)
        case .coach: HomeWidgetSettings(look: .coach, small: .level, medium: .nextUp, large: .dashboard, lock: .level)
        case .data: HomeWidgetSettings(look: .data, small: .readiness, medium: .week, large: .dashboard, lock: .readiness)
        case .climber: HomeWidgetSettings(look: .gradient, small: .climbing, medium: .nextUp, large: .climbing, lock: .climbing)
        }
    }

    var summary: String {
        let s = settings
        return [s.small, s.medium, s.large].map(\.title).joined(separator: " · ")
    }
}

/// The member's pick (Account → Home Screen widgets). A widget's own Edit Widget choice overrides it.
struct HomeWidgetSettings: Codable, Equatable, Hashable, Sendable {
    var look: HomeWidgetLook
    var small: HomeWidgetTopic
    var medium: HomeWidgetTopic
    var large: HomeWidgetTopic
    var lock: HomeWidgetTopic

    static let `default` = HomeWidgetPreset.classic.settings

    func topic(_ size: HomeWidgetSize) -> HomeWidgetTopic {
        switch size {
        case .small: small
        case .medium: medium
        case .large: large
        case .lock: lock
        }
    }

    mutating func set(_ topic: HomeWidgetTopic, for size: HomeWidgetSize) {
        switch size {
        case .small: small = topic
        case .medium: medium = topic
        case .large: large = topic
        case .lock: lock = topic
        }
    }

    var preset: HomeWidgetPreset? { HomeWidgetPreset.allCases.first { $0.settings == self } }

    // Tolerant decoding: an unknown topic or look from a newer app falls back to the default.
    init(look: HomeWidgetLook, small: HomeWidgetTopic, medium: HomeWidgetTopic, large: HomeWidgetTopic, lock: HomeWidgetTopic) {
        self.look = look
        self.small = small
        self.medium = medium
        self.large = large
        self.lock = lock
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HomeWidgetPreset.classic.settings
        func topic(_ k: CodingKeys, _ fallback: HomeWidgetTopic) -> HomeWidgetTopic {
            (try? c.decode(String.self, forKey: k)).flatMap(HomeWidgetTopic.init) ?? fallback
        }
        look = (try? c.decode(String.self, forKey: .look)).flatMap(HomeWidgetLook.init) ?? d.look
        small = topic(.small, d.small)
        medium = topic(.medium, d.medium)
        large = topic(.large, d.large)
        lock = topic(.lock, d.lock)
    }
}

/// Everything the widgets draw, written by the app to the App Group container.
struct HomeWidgetSnapshot: Codable, Equatable, Sendable {
    struct Day: Codable, Equatable, Hashable, Sendable {
        /// 1 = Monday … 7 = Sunday.
        var weekday: Int
        var planned: Bool
        var done: Bool
        var missed: Bool
        var climb: Bool
    }

    struct Next: Codable, Equatable, Sendable {
        var id: String
        var title: String
        /// "Today", "Thursday", or "Extra".
        var day: String
        var minutes: Int
        var exercises: Int
        var tint: UInt32
    }

    struct Lift: Codable, Equatable, Hashable, Sendable {
        var name: String
        var kg: Double
    }

    struct Last: Codable, Equatable, Sendable {
        var title: String
        var date: Date
        var minutes: Int
        var sets: Int
        var volumeKg: Double
    }

    /// Today's Fuel (#496): the day's load, protein portions and glasses against the plan, the next meal.
    struct Fueling: Codable, Equatable, Sendable {
        var headline: String
        var palms: Int
        var palmsTarget: Int
        var glasses: Int
        var glassesTarget: Int
        var next: String?
        var nextTime: String?
    }

    struct Climbing: Codable, Equatable, Sendable {
        var thisWeek: Int
        var lastDate: Date?
        var lastKind: String?
        var lastGrade: String?
    }

    var generatedAt = Date()
    var settings = HomeWidgetSettings.default
    var signedIn = false
    var week = 1
    var weeks = 4
    var phase = "Build"
    var deload = false
    var days: [Day] = []
    var done = 0
    var target = 3
    var next: Next?
    var streakWeeks = 0
    var bestStreakWeeks = 0
    /// Verdict headline ("Ready to push", "Train as planned", "Take it easier"); nil without Health.
    var readiness: String?
    var sleepHours: Double?
    var hrv: Double?
    var restingHR: Double?
    var level = 1
    var rank = "Rookie"
    var xpInLevel = 0
    var xpPerLevel = 500
    var nextRank: String?
    var badges = 0
    var workouts = 0
    var records: [Lift] = []
    var last: Last?
    /// Kg lifted in each of the last 4 weeks, oldest first.
    var volumeWeeks: [Double] = []
    var climbing = Climbing(thisWeek: 0)
    /// Optional so a file written before Fuel still decodes.
    var fuel: Fueling?

    var weekDone: Bool { target > 0 && done >= target }
    var toGoal: Int { max(0, target - done) }

    /// Volume change of this week vs the average of the 3 before, in %; nil without data or before the
    /// first workout of the week (a fresh week isn't "-100%").
    var volumeTrend: Int? {
        guard volumeWeeks.count == 4, volumeWeeks[3] > 0 else { return nil }
        let before = volumeWeeks.prefix(3).reduce(0, +) / 3
        guard before > 0 else { return nil }
        return Int(((volumeWeeks[3] - before) / before * 100).rounded())
    }

    var volume4Weeks: Double { volumeWeeks.reduce(0, +) }
}

/// The App Group file shared by the app (writer) and the widget extension (reader).
enum HomeWidgetStore {
    /// `MWAppGroup` = $(APP_GROUP) in both Info.plists, so DEV and App Store builds keep separate containers.
    static let group = Bundle.main.object(forInfoDictionaryKey: "MWAppGroup") as? String
    static let kind = "MonkeyWorkoutHome"
    static let lockKind = "MonkeyWorkoutLock"

    static var url: URL? {
        group.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }?
            .appendingPathComponent("home-widgets.json")
    }

    static func load() -> HomeWidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(HomeWidgetSnapshot.self, from: data)
    }

    /// True when the file changed.
    @discardableResult
    static func save(_ snap: HomeWidgetSnapshot) -> Bool {
        guard let url else { return false }
        var s = snap
        if let old = load() {
            s.generatedAt = old.generatedAt
            if s == old { return false }
        }
        s.generatedAt = Date()
        guard let data = try? encoder.encode(s) else { return false }
        return (try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

/// Links the widgets open (`monkeyworkout://…`), handled by the app's `onOpenURL`.
enum HomeWidgetLink {
    static let scheme = "monkeyworkout"

    static func session(_ id: String) -> URL { URL(string: "\(scheme)://session/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)")! }
    static func tab(_ name: String) -> URL { URL(string: "\(scheme)://\(name)")! }

    static func url(for topic: HomeWidgetTopic, snap: HomeWidgetSnapshot) -> URL {
        switch topic {
        case .nextUp, .dashboard, .week: snap.next.map { session($0.id) } ?? tab("train")
        case .climbing: tab("climbing")
        case .fuel: tab("fuel")
        case .level: tab("level")
        case .readiness: tab("readiness")
        case .streak, .records, .lastWorkout, .volume: tab("progress")
        }
    }
}
