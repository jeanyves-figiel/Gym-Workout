public struct Dose: Sendable {
    public var sets: Int
    public var reps: String
    /// Rep count used for time estimates.
    public var repsMid: Int
    public var restSec: Int
    public var rpe: Int
}

public struct Mix: Sendable {
    public var power: Double
    public var strength: Double
    public var mobility: Double
    public var cardio: Double

    var normalised: Mix {
        let t = power + strength + mobility + cardio
        return Mix(power: power / t, strength: strength / t, mobility: mobility / t, cardio: cardio / t)
    }
}

public enum CardioMode: String, Sendable {
    case zone2, intervals, threshold, sprints
}

public struct GoalConfig: Sendable {
    public let label: String
    public let blurb: String
    /// Session minutes at 3×/week, intermediate.
    public let baseMinutes: Double
    public let mix: Mix
    public let main: Dose
    public let accessory: Dose
    /// Cardio mode rotation across the week's sessions.
    public let cardio: [CardioMode]
}

extension Goal {
    public var config: GoalConfig {
        switch self {
        case .balanced:
            GoalConfig(
                label: "Balanced athlete",
                blurb: "Strength + definition, climber mobility, endurance and explosiveness in every session.",
                baseMinutes: 70, mix: Mix(power: 0.12, strength: 0.5, mobility: 0.13, cardio: 0.25),
                main: Dose(sets: 4, reps: "5–8", repsMid: 6, restSec: 150, rpe: 8),
                accessory: Dose(sets: 3, reps: "8–12", repsMid: 10, restSec: 75, rpe: 8),
                cardio: [.zone2, .intervals, .zone2, .threshold])
        case .build:
            GoalConfig(
                label: "Build & define",
                blurb: "Hypertrophy-biased volume for a defined physique, cardio kept for leanness.",
                baseMinutes: 70, mix: Mix(power: 0.07, strength: 0.65, mobility: 0.08, cardio: 0.2),
                main: Dose(sets: 4, reps: "6–10", repsMid: 8, restSec: 120, rpe: 8),
                accessory: Dose(sets: 3, reps: "10–15", repsMid: 12, restSec: 60, rpe: 9),
                cardio: [.zone2, .intervals])
        case .strength:
            GoalConfig(
                label: "Max strength",
                blurb: "Heavy compounds, long rests, minimal junk volume.",
                baseMinutes: 75, mix: Mix(power: 0.12, strength: 0.68, mobility: 0.08, cardio: 0.12),
                main: Dose(sets: 5, reps: "3–5", repsMid: 4, restSec: 180, rpe: 8),
                accessory: Dose(sets: 3, reps: "6–8", repsMid: 7, restSec: 120, rpe: 8),
                cardio: [.zone2])
        case .climbing:
            GoalConfig(
                label: "Climbing performance",
                blurb: "Strength-to-weight, antagonist & shoulder health, hip/shoulder mobility, power for dynos.",
                baseMinutes: 60, mix: Mix(power: 0.15, strength: 0.4, mobility: 0.25, cardio: 0.2),
                main: Dose(sets: 4, reps: "4–6", repsMid: 5, restSec: 150, rpe: 8),
                accessory: Dose(sets: 3, reps: "8–10", repsMid: 9, restSec: 75, rpe: 8),
                cardio: [.zone2, .zone2, .intervals])
        case .endurance:
            GoalConfig(
                label: "Endurance",
                blurb: "Aerobic engine first; strength maintained with lighter, faster circuits.",
                baseMinutes: 65, mix: Mix(power: 0.05, strength: 0.35, mobility: 0.1, cardio: 0.5),
                main: Dose(sets: 3, reps: "8–12", repsMid: 10, restSec: 90, rpe: 7),
                accessory: Dose(sets: 3, reps: "12–15", repsMid: 13, restSec: 45, rpe: 7),
                cardio: [.zone2, .threshold, .zone2, .intervals])
        case .athletic:
            GoalConfig(
                label: "Explosive / athletic",
                blurb: "Jumps, throws and fast lifts with strength support.",
                baseMinutes: 65, mix: Mix(power: 0.25, strength: 0.45, mobility: 0.1, cardio: 0.2),
                main: Dose(sets: 4, reps: "3–5", repsMid: 4, restSec: 150, rpe: 8),
                accessory: Dose(sets: 3, reps: "6–8", repsMid: 7, restSec: 90, rpe: 8),
                cardio: [.sprints, .zone2, .intervals])
        }
    }
}

enum Rules {
    /// Fewer sessions → longer sessions; more sessions → shorter but more weekly volume.
    static let frequencyFactor: [Int: Double] = [2: 1.2, 3: 1.0, 4: 0.9, 5: 0.82, 6: 0.75]
    static func experienceDelta(_ e: Experience) -> Double {
        switch e {
        case .beginner: -10
        case .intermediate: 0
        case .advanced: 10
        }
    }
    static let minSession = 35
    static let maxSession = 100
    static let mesocycleWeeks = 4

    static let splits: [Int: [Focus]] = [
        2: [.fullLower, .fullUpper],
        3: [.fullLower, .fullUpper, .fullPower],
        4: [.upper, .lower, .upper, .lower],
        5: [.upper, .lower, .conditioning, .upper, .lower],
        6: [.push, .pull, .legs, .push, .pull, .legs],
    ]

    /// Strength slots by priority; index 0 is the main lift. Variant B used for the 2nd occurrence.
    static func strengthSlots(_ f: Focus, variant: Int) -> [Pattern] {
        switch (f, variant) {
        case (.fullLower, _): [.squat, .hPull, .hinge, .hPush, .singleLeg, .coreAntiRot, .shoulderHealth, .calves]
        case (.fullUpper, _): [.hPush, .vPull, .hinge, .vPush, .singleLeg, .coreAntiExt, .shoulderHealth, .armsFlex, .armsExt]
        case (.fullPower, _): [.hinge, .vPush, .hPull, .singleLeg, .coreFlex, .carry, .lateralRaise]
        case (.upper, 0): [.hPush, .vPull, .vPush, .hPull, .shoulderHealth, .lateralRaise, .armsExt, .armsFlex, .forearmAntagonist]
        case (.upper, _): [.vPush, .hPull, .hPush, .vPull, .shoulderHealth, .lateralRaise, .armsFlex, .armsExt, .forearmAntagonist]
        case (.lower, 0): [.squat, .hinge, .singleLeg, .kneeFlex, .coreAntiExt, .calves, .carry]
        case (.lower, _): [.hinge, .singleLeg, .squat, .kneeExt, .coreAntiRot, .calves, .coreFlex]
        case (.push, 0): [.hPush, .vPush, .hPush, .lateralRaise, .armsExt, .shoulderHealth, .coreAntiExt]
        case (.push, _): [.vPush, .hPush, .hPush, .lateralRaise, .armsExt, .shoulderHealth, .coreAntiRot]
        case (.pull, 0): [.vPull, .hPull, .hinge, .shoulderHealth, .armsFlex, .coreFlex, .forearmAntagonist]
        case (.pull, _): [.hPull, .vPull, .hinge, .shoulderHealth, .armsFlex, .coreFlex, .forearmAntagonist]
        case (.legs, 0): [.squat, .hinge, .singleLeg, .kneeFlex, .kneeExt, .calves, .coreAntiRot]
        case (.legs, _): [.hinge, .squat, .singleLeg, .kneeExt, .kneeFlex, .calves, .coreAntiExt]
        case (.conditioning, 0): [.singleLeg, .carry, .coreAntiExt, .shoulderHealth, .coreAntiRot]
        case (.conditioning, _): [.singleLeg, .carry, .coreAntiRot, .shoulderHealth, .coreAntiExt]
        }
    }

    static func powerPatterns(_ f: Focus) -> [Pattern] {
        switch f {
        case .fullLower: [.jump, .throw]
        case .fullUpper: [.upperPlyo, .jump]
        case .fullPower: [.jump, .ballistic, .throw, .upperPlyo]
        case .upper: [.upperPlyo, .throw]
        case .lower, .legs: [.jump, .ballistic]
        case .push: [.throw, .upperPlyo]
        case .pull: [.upperPlyo, .ballistic]
        case .conditioning: [.ballistic, .throw, .jump]
        }
    }

    static func regions(_ f: Focus) -> [Region] {
        switch f {
        case .fullLower: [.hips, .ankles, .thoracic, .shoulders]
        case .fullUpper: [.shoulders, .thoracic, .hips, .wrists]
        case .fullPower: [.hips, .shoulders, .ankles, .thoracic]
        case .upper, .push: [.shoulders, .thoracic, .wrists]
        case .lower, .legs: [.hips, .ankles, .spine]
        case .pull: [.shoulders, .thoracic, .wrists, .spine]
        case .conditioning: [.hips, .shoulders, .thoracic, .ankles, .wrists]
        }
    }

    /// Session-type adjustment of the goal mix.
    static func focusMix(_ f: Focus) -> Mix {
        switch f {
        case .fullPower: Mix(power: 1.6, strength: 1, mobility: 1, cardio: 1.1)
        case .conditioning: Mix(power: 1.4, strength: 0.4, mobility: 1.4, cardio: 1.8)
        default: Mix(power: 1, strength: 1, mobility: 1, cardio: 1)
        }
    }

    /// Light dosing / superset candidates (prehab, core, carries).
    static let lightPatterns: Set<Pattern> = [.shoulderHealth, .forearmAntagonist, .calves, .coreAntiExt, .coreAntiRot, .coreFlex, .carry]
}

extension Focus {
    public var label: String {
        switch self {
        case .fullLower: "Full body · lower emphasis"
        case .fullUpper: "Full body · upper emphasis"
        case .fullPower: "Full body · power"
        case .upper: "Upper body"
        case .lower: "Lower body"
        case .push: "Push"
        case .pull: "Pull"
        case .legs: "Legs"
        case .conditioning: "Conditioning & mobility"
        }
    }
}
