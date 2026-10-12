import Foundation

/// How a week alternates muscle groups (#200). `.auto` keeps the goal's own split.
public enum SplitStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case auto
    case fullBody = "full-body"
    case upperLower = "upper-lower"
    case ppl
    case upperLowerFull = "upper-lower-full"
    case pplUpperLower = "ppl-upper-lower"
    case bodyPart = "body-part"
    case arnold
    case hybrid
    public var id: String { rawValue }

    /// Day types repeated in order to fill the week; empty for `.auto`.
    public var cycle: [Focus] {
        switch self {
        case .auto: []
        case .fullBody: [.fullLower, .fullUpper, .fullPower]
        case .upperLower: [.upper, .lower]
        case .ppl: [.push, .pull, .legs]
        case .upperLowerFull: [.upper, .lower, .fullPower]
        case .pplUpperLower: [.push, .pull, .legs, .upper, .lower]
        case .bodyPart: [.chestTri, .backBi, .legs, .shouldersArms, .posterior]
        case .arnold: [.chestBack, .shouldersArms, .legs]
        case .hybrid: [.fullLower, .conditioning, .fullUpper, .conditioning, .fullPower, .conditioning]
        }
    }

    /// The week's session types at `n` sessions.
    public func foci(_ n: Int) -> [Focus] {
        let c = cycle
        guard !c.isEmpty, n > 0 else { return [] }
        return (0..<n).map { c[$0 % c.count] }
    }

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .fullBody: "Full body"
        case .upperLower: "Upper / Lower"
        case .ppl: "Push Pull Legs"
        case .upperLowerFull: "Upper / Lower + Full"
        case .pplUpperLower: "PPL + Upper / Lower"
        case .bodyPart: "Body part"
        case .arnold: "Arnold"
        case .hybrid: "Strength + cardio"
        }
    }

    public var blurb: String {
        switch self {
        case .auto: "Your goal picks the split."
        case .fullBody: "Every muscle, every session."
        case .upperLower: "Upper and lower days alternate."
        case .ppl: "Push, pull and legs days rotate."
        case .upperLowerFull: "Upper, lower, then a full-body power day."
        case .pplUpperLower: "Push, pull, legs, then upper and lower."
        case .bodyPart: "Chest, back, legs, shoulders & arms, glutes: one area per day."
        case .arnold: "Chest & back, shoulders & arms, legs."
        case .hybrid: "Full-body strength alternates with conditioning."
        }
    }
}

extension Profile {
    /// Split style, nil = `.auto`.
    public var splitStyle: SplitStyle { split ?? .auto }

    /// The week's session types in order (#200): per-day picks, split style or the goal's own.
    public var weekFoci: [Focus] { Rules.split(self) }

    /// Whether the week uses per-day picks.
    public var customSplit: Bool { (splitDays?.count ?? 0) == sessionsPerWeek && splitDays != nil }

    /// Prioritised muscle groups (#200).
    public var focusGroups: Set<MuscleGroup> { Set(focusMuscles ?? []) }

    /// Sets the type of the `index`-th session of the week (in `weekFoci` order).
    public mutating func setDay(_ index: Int, to focus: Focus) {
        var days = weekFoci
        guard days.indices.contains(index) else { return }
        days[index] = focus
        splitDays = days
    }

    /// Picks a split style and drops per-day picks.
    public mutating func applySplit(_ style: SplitStyle) {
        split = style == .auto ? nil : style
        splitDays = nil
    }
}

extension Generator {
    /// Session types offered per day (#200).
    public static let dayFoci: [Focus] = [
        .fullUpper, .fullLower, .fullPower, .upper, .lower, .push, .pull, .legs,
        .chestTri, .backBi, .shouldersArms, .chestBack, .posterior, .conditioning,
    ]

    /// The week's sessions as (weekday, type) in plan order, for previews (#200). Weekdays are nil without
    /// climbing or gym days set.
    public static func weekPreview(_ p: Profile) -> [(weekday: Int?, focus: Focus)] {
        var p = p
        p.syncClimbingDays()
        let split = p.weekFoci
        guard let slots = WeekSchedule.assign(split, climbing: p.climbingDays, gym: p.gymDays, prefs: p.climbPrefs,
                                              keepOrder: p.customSplit)
        else { return split.map { (nil, $0) } }
        return slots.map { ($0.weekday, $0.focus) }
    }
}

extension Pattern {
    /// Muscle groups a strength slot trains, for focus muscles (#200).
    public var muscleGroups: Set<MuscleGroup> {
        switch self {
        case .squat, .kneeExt, .kneeFlex, .calves: [.legs]
        case .singleLeg: [.legs, .hips]
        case .hinge: [.hips]
        case .hPush: [.chest]
        case .vPush, .lateralRaise, .shoulderHealth: [.shoulders]
        case .hPull, .vPull: [.back]
        case .armsFlex, .armsExt, .forearmAntagonist: [.arms]
        case .coreAntiExt, .coreAntiRot, .coreFlex, .carry: [.core]
        case .jump, .throw, .ballistic, .upperPlyo, .general: []
        }
    }
}
