import Foundation

/// Workout chat (#381): the generator settings Coach Monkey sends back for what the member asked
/// ("45 min, legs, sore shoulder"). The app's own generator builds the workout from them, so it only ever holds
/// catalog exercises that fit the member's gym and level.
public struct CoachWorkoutSettings: Codable, Hashable, Sendable {
    public var name: String
    /// Whole session the member asked for, warm-up and cool-down included.
    public var minutes: Int
    public var groups: [String]
    public var rest: String
    public var grouping: String
    public var avoidGroups: [String]
    public var avoidEquipment: [String]
    public var avoidKeywords: [String]

    public init(name: String, minutes: Int, groups: [String], rest: String = RestStyle.standard.rawValue,
                grouping: String = Grouping.straight.rawValue, avoidGroups: [String] = [], avoidEquipment: [String] = [],
                avoidKeywords: [String] = []) {
        self.name = name
        self.minutes = minutes
        self.groups = groups
        self.rest = rest
        self.grouping = grouping
        self.avoidGroups = avoidGroups
        self.avoidEquipment = avoidEquipment
        self.avoidKeywords = avoidKeywords
    }

    /// Warm-up and cool-down minutes a chat workout starts with (the builder's defaults for a new workout).
    public static let flowMinutes: [BlockKind: Int] = [.warmup: 6, .cooldown: 5]

    /// Generator options; the exercise part gets the session minus warm-up and cool-down. Unknown values are dropped.
    public var options: MuscleWorkoutOptions {
        let flow = Self.flowMinutes.values.reduce(0, +)
        var o = MuscleWorkoutOptions(groups: Set(groups.compactMap(MuscleGroup.init(rawValue:))),
                                     minutes: max(10, minutes - flow),
                                     rest: RestStyle(rawValue: rest) ?? .standard,
                                     grouping: Grouping(rawValue: grouping) ?? .straight)
        o.avoidGroups = Set(avoidGroups.compactMap(MuscleGroup.init(rawValue:))).subtracting(o.groups)
        o.avoidEquipment = Set(avoidEquipment.compactMap(Equipment.init(rawValue:)))
        o.avoidKeywords = avoidKeywords.map { $0.lowercased() }.filter { $0.count >= 3 }
        return o
    }

    /// The workout for `profile`; empty items when nothing fits (the chat then says so).
    public func workout(profile: Profile, seed: UInt32, createdAt: Date = Date()) -> CustomWorkout {
        var w = CustomWorkout.generate(options, profile: profile, seed: seed, createdAt: createdAt)
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { w.name = String(n.prefix(CustomWorkout.maxNameLength)) }
        return w
    }
}
