import Foundation

/// App levels and modules (#1052, design A + B from `usage-levels/a.png` + `b.png`): a member who wants a simpler app
/// picks a level at sign up and fine-tunes modules in Settings → My app. Workouts are always on. A module that is off
/// hides its tab, Train cards, player buttons, sheets and prompts; its data stays and comes back when it is on again.
/// Members from before, and anyone who picks Everything, see the whole app as it is.
public enum AppModule: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Week planning tools, programmes and the Explore tab.
    case plan
    /// Coach Monkey: Ask Coach, weekly review, set talk, nudges on cards.
    case coach
    /// The Insights tab.
    case insights
    /// XP, levels, week chest, streak cards.
    case game
    /// Sport days, climbing, sport add-ons.
    case sports
    /// Mind card, morning check-in, breathing.
    case mind
    /// The Fuel tab.
    case fuel
    /// The Social tab.
    case social
    /// Film my workout, form check.
    case camera

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .plan: "Plan & Explore"
        case .coach: "Coach AI"
        case .insights: "Insights"
        case .game: "Game & XP"
        case .sports: "Sports & climbing"
        case .mind: "Mind"
        case .fuel: "Fuel"
        case .social: "Social"
        case .camera: "Camera tools"
        }
    }

    public var detail: String {
        switch self {
        case .plan: "Calendar, programmes, weekly reviews, Explore"
        case .coach: "Ask Coach, talk mid-set, tips"
        case .insights: "Progress, records, body"
        case .game: "Levels, chests, streaks"
        case .sports: "Sport days, climbing, add-ons"
        case .mind: "Check-ins, breathing"
        case .fuel: "Meals, water, supplements"
        case .social: "Feed, friends, challenges"
        case .camera: "Film my workout, form check"
        }
    }

    public var symbol: String {
        switch self {
        case .plan: "calendar"
        case .coach: "bubble.left.and.text.bubble.right.fill"
        case .insights: "sparkles"
        case .game: "trophy.fill"
        case .sports: "figure.climbing"
        case .mind: "brain.head.profile"
        case .fuel: "fork.knife"
        case .social: "person.3.fill"
        case .camera: "video.fill"
        }
    }
}

/// One tap at sign up (#1052 A): each level is a set of modules.
public enum AppLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Today's workout, Start, log sets, history.
    case workouts
    /// Plus the week plan, programmes, Explore, Coach and Insights.
    case plan
    /// The whole app (default).
    case everything

    public var id: String { rawValue }

    /// A level from a newer app reads as Everything instead of failing the whole profile.
    public init(from decoder: Decoder) throws {
        self = AppLevel(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .everything
    }

    public var title: String {
        switch self {
        case .workouts: "Just workouts"
        case .plan: "Follow a plan"
        case .everything: "Everything"
        }
    }

    public var detail: String {
        switch self {
        case .workouts: "Today's workout, Start, log sets. History. Nothing else."
        case .plan: "Plus week plan, programmes, Explore, Coach and Insights."
        case .everything: "Plus Fuel, Social, Mind, sports, camera, game, Watch extras."
        }
    }

    public var symbol: String {
        switch self {
        case .workouts: "dumbbell.fill"
        case .plan: "calendar"
        case .everything: "sparkles"
        }
    }

    /// Modules on at this level.
    public var modules: Set<AppModule> {
        switch self {
        case .workouts: [.insights]
        case .plan: [.plan, .coach, .insights]
        case .everything: Set(AppModule.allCases)
        }
    }
}

/// The member's modules, synced with the profile. Stores the modules turned off, by name, so a module from a newer
/// app is kept as it was and a module added later is on unless the member's level leaves it out.
public struct AppModules: Codable, Equatable, Sendable {
    /// The level last picked; nil = mixed by hand in My app.
    public var level: AppLevel?
    /// Modules turned off (raw names).
    public var off: [String]

    public init(level: AppLevel) {
        self.level = level
        off = AppModule.allCases.filter { !level.modules.contains($0) }.map(\.rawValue)
    }

    /// Everything on: members from before #1052 and anyone without a pick.
    public static let everything = AppModules(level: .everything)

    public func shows(_ module: AppModule) -> Bool { !off.contains(module.rawValue) }

    /// Modules on, in grid order.
    public var on: [AppModule] { AppModule.allCases.filter(shows) }

    /// Turns one module on or off; the level follows when the modules match one again.
    public mutating func set(_ module: AppModule, on: Bool) {
        if on { off.removeAll { $0 == module.rawValue } } else if shows(module) { off.append(module.rawValue) }
        off.sort()
        level = AppLevel.allCases.first { Set(self.on) == $0.modules }
    }

    /// Short summary for the Settings row, e.g. "Just workouts" or "6 of 9".
    public var summary: String {
        if let level { return level.title }
        return "\(on.count) of \(AppModule.allCases.count)"
    }
}

extension TrainWidgetKind {
    /// The module a Train widget belongs to (#1052); nil = always shown (workouts).
    public var module: AppModule? {
        switch self {
        case .coach: .coach
        case .level, .streak: .game
        case .climbing: .sports
        case .calendar, .programme: .plan
        case .fuel: .fuel
        case .volume, .records, .body, .muscles: .insights
        case .actions, .week, .nextUp, .lastWorkout, .thisWeek, .move: nil
        }
    }
}

extension TrainLayout {
    /// Only the widgets whose module is on (#1052).
    public func showing(_ modules: AppModules) -> TrainLayout {
        var l = self
        l.widgets.removeAll { $0.kind.module.map { !modules.shows($0) } ?? false }
        return l
    }
}
