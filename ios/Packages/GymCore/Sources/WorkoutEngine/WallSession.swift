import Foundation

/// Wall session on climbing days (#366): what the member does at the climbing gym around the climbing itself.
/// The day type picks the parts (design A + C): a warm-up before, the climbing (logged in MonkeyGrade, synced back)
/// or a hangboard session in the middle, and antagonists + cool-down after. A rest day is one mobility session.
public enum WallDay: String, CaseIterable, Codable, Sendable, Identifiable {
    case bouldering, hangboard, rope, rest
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .bouldering: "Bouldering"
        case .hangboard: "Hangboard"
        case .rope: "Rope day"
        case .rest: "Rest day"
        }
    }

    public var symbol: String {
        switch self {
        case .bouldering: "figure.climbing"
        case .hangboard: "hand.raised.fill"
        case .rope: "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .rest: "figure.mind.and.body"
        }
    }

    /// The parts of the day, in order.
    public var parts: [WallPart] {
        switch self {
        case .bouldering: [.before(WallSession.boulderBefore), .climb, .after(WallSession.boulderAfter)]
        case .hangboard: [.before(WallSession.hangboardBefore), .session(WallSession.hangboard), .after(WallSession.hangboardAfter)]
        case .rope: [.before(WallSession.ropeBefore), .climb, .after(WallSession.ropeAfter)]
        case .rest: [.session(WallSession.restDay)]
        }
    }

    /// Short line under the tile: "12′ before · 18′ after".
    public var summary: String {
        parts.compactMap { p -> String? in
            switch p {
            case .before(let t): "\(t.session.estMin)′ before"
            case .session(let t): "\(t.session.estMin)′ \(t.name.lowercased())"
            case .after(let t): "\(t.session.estMin)′ after"
            case .climb: nil
            }
        }.joined(separator: " · ")
    }
}

/// One band of the Wall session card.
public enum WallPart: Hashable, Sendable, Identifiable {
    case before(WorkoutTemplate)
    /// The climbing itself: logged in MonkeyGrade (or Log climb), not played here.
    case climb
    /// A startable middle part (hangboard protocol, rest-day mobility).
    case session(WorkoutTemplate)
    case after(WorkoutTemplate)

    public var id: String { template?.id ?? "climb" }

    public var template: WorkoutTemplate? {
        switch self {
        case .before(let t), .session(let t), .after(let t): t
        case .climb: nil
        }
    }
}

public enum WallSession {
    /// Every Wall session template, so `WorkoutTemplate.find(sessionId:)` resolves them (session view, player, history).
    public static let templates: [WorkoutTemplate] = [
        boulderBefore, boulderAfter, hangboardBefore, hangboard, hangboardAfter, ropeBefore, ropeAfter, restDay,
    ]

    typealias Item = WorkoutTemplate.Item

    // MARK: Bouldering

    static let boulderBefore = WorkoutTemplate(
        id: "wall-boulder-before", name: "Wall warm-up", focus: .pull, goal: .mobility, kit: "Climbing gym", level: 1, main: .warmup,
        items: [
            Item("finger-ramp", sets: 1, reps: 60, rest: 0, block: .warmup),
            Item("wrist-prep", sets: 1, reps: 10, rest: 0, block: .warmup),
            Item("shoulder-car", sets: 1, reps: 5, rest: 0, block: .warmup),
            Item("band-external-rotation", sets: 2, reps: 12, rest: 20, block: .warmup),
            Item("scap-pull-up", sets: 2, reps: 8, rest: 45, block: .warmup),
            Item("hang-ramp", sets: 4, reps: 10, rest: 45, block: .warmup),
            Item("recruitment-pulls", sets: 1, reps: 3, rest: 0, block: .warmup),
            Item("easy-traverse", sets: 1, reps: 180, rest: 0, block: .warmup),
        ])

    static let boulderAfter = WorkoutTemplate(
        id: "wall-boulder-after", name: "Antagonists & cool-down", focus: .push, goal: .mobility, kit: "Climbing gym", level: 1,
        items: [
            Item("push-up", sets: 3, reps: 10, rest: 60),
            Item("push-up-plus", sets: 2, reps: 12, rest: 45),
            Item("band-pull-apart", sets: 2, reps: 15, rest: 45),
            Item("finger-extensions", sets: 2, reps: 20, rest: 30),
            Item("dead-bug", sets: 2, reps: 10, rest: 45),
            Item("forearm-flexor", sets: 1, reps: 30, rest: 0, block: .cooldown),
            Item("forearm-extensor", sets: 1, reps: 30, rest: 0, block: .cooldown),
            Item("wrist-flexor-floor", sets: 1, reps: 30, rest: 0, block: .cooldown),
            Item("sleeper-stretch", sets: 1, reps: 30, rest: 0, block: .cooldown),
            Item("pec-stretch", sets: 1, reps: 30, rest: 0, block: .cooldown),
        ])

    // MARK: Hangboard

    static let hangboardBefore = WorkoutTemplate(
        id: "wall-hangboard-before", name: "Finger warm-up", focus: .pull, goal: .mobility, kit: "Hangboard", level: 1, main: .warmup,
        items: [
            Item("finger-ramp", sets: 1, reps: 60, rest: 0, block: .warmup),
            Item("forearm-waves", sets: 1, reps: 30, rest: 0, block: .warmup),
            Item("shoulder-car", sets: 1, reps: 5, rest: 0, block: .warmup),
            Item("scap-pull-up", sets: 2, reps: 8, rest: 45, block: .warmup),
            Item("hang-ramp", sets: 4, reps: 10, rest: 45, block: .warmup),
            Item("recruitment-pulls", sets: 1, reps: 3, rest: 0, block: .warmup),
        ])

    static let hangboard = WorkoutTemplate(
        id: "wall-hangboard", name: "Hangboard", focus: .pull, goal: .muscle, kit: "Hangboard", level: 2,
        items: [
            Item("max-hangs", sets: 5, reps: 10, rest: 180),
            Item("repeaters", sets: 3, reps: 60, rest: 180),
            Item("open-hand-hang", sets: 3, reps: 10, rest: 120),
            Item("pinch-block-lift", sets: 3, reps: 10, rest: 90),
        ])

    static let hangboardAfter = WorkoutTemplate(
        id: "wall-hangboard-after", name: "Finger cool-down", focus: .push, goal: .mobility, kit: "Hangboard", level: 1, main: .cooldown,
        items: [
            Item("finger-extensions", sets: 2, reps: 20, rest: 30, block: .cooldown),
            Item("forearm-flexor", sets: 1, reps: 30, rest: 0, block: .cooldown),
            Item("forearm-extensor", sets: 1, reps: 30, rest: 0, block: .cooldown),
            Item("wrist-flexor-floor", sets: 1, reps: 30, rest: 0, block: .cooldown),
        ])

    // MARK: Rope day

    static let ropeBefore = WorkoutTemplate(
        id: "wall-rope-before", name: "Endurance warm-up", focus: .pull, goal: .mobility, kit: "Climbing gym", level: 1, main: .warmup,
        items: [
            Item("finger-ramp", sets: 1, reps: 60, rest: 0, block: .warmup),
            Item("forearm-waves", sets: 1, reps: 30, rest: 0, block: .warmup),
            Item("shoulder-car", sets: 1, reps: 5, rest: 0, block: .warmup),
            Item("hip-90-90", sets: 1, reps: 8, rest: 0, block: .warmup),
            Item("easy-traverse", sets: 2, reps: 180, rest: 60, block: .warmup),
        ])

    static let ropeAfter = WorkoutTemplate(
        id: "wall-rope-after", name: "Cool-down", focus: .push, goal: .mobility, kit: "Climbing gym", level: 1, main: .cooldown,
        items: [
            Item("forearm-flexor", sets: 1, reps: 30, rest: 0, block: .cooldown),
            Item("forearm-extensor", sets: 1, reps: 30, rest: 0, block: .cooldown),
            Item("pec-stretch", sets: 1, reps: 30, rest: 0, block: .cooldown),
            Item("t-spine-roller", sets: 1, reps: 8, rest: 0, block: .cooldown),
            Item("straddle-stretch", sets: 1, reps: 45, rest: 0, block: .cooldown),
        ])

    // MARK: Rest day

    static let restDay = WorkoutTemplate(
        id: "wall-rest", name: "Mobility", focus: .push, goal: .mobility, kit: "No kit", level: 1, main: .mobility,
        items: [
            Item("finger-extensions", sets: 2, reps: 20, rest: 30),
            Item("reverse-wrist-curl", sets: 2, reps: 15, rest: 30),
            Item("wrist-flexor-floor", sets: 1, reps: 30, rest: 0),
            Item("forearm-flexor", sets: 1, reps: 30, rest: 0),
            Item("shoulder-car", sets: 1, reps: 5, rest: 0),
            Item("hip-90-90", sets: 1, reps: 8, rest: 0),
            Item("deep-squat-pry", sets: 1, reps: 45, rest: 0),
            Item("t-spine-roller", sets: 1, reps: 8, rest: 0),
            Item("straddle-stretch", sets: 1, reps: 45, rest: 0),
        ])
}
