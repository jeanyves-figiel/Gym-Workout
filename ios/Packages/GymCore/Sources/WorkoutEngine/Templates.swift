import Foundation

/// Ready-made example workouts: fixed exercise lists shown next to the generated week.
public struct WorkoutTemplate: Identifiable, Hashable, Sendable {
    public struct Item: Hashable, Sendable {
        public let exerciseId: String
        public let sets: Int
        /// Reps per set, or seconds (holds, stretches) / minutes (cardio) as read by `CustomWorkout.Measure`.
        public let reps: Int
        /// Calories for this exercise as given by the source plan, when stated.
        public let kcal: Int?
        public let restSec: Int
        /// Superset / circuit label ("A1", "A2"): same letter = back to back, shared rest after the round.
        public let group: String?
        /// Block it is played in; nil = from its category (warm-up, cool-down, else the main block).
        public let block: BlockKind?

        init(_ exerciseId: String, sets: Int = 3, reps: Int = 10, kcal: Int? = nil, rest: Int = WorkoutTemplate.restSec,
             group: String? = nil, block: BlockKind? = nil) {
            self.exerciseId = exerciseId
            self.sets = sets
            self.reps = reps
            self.kcal = kcal
            self.restSec = rest
            self.group = group
            self.block = block
        }
    }

    /// What a built-in workout is for: library filter and tag (#252).
    public enum Goal: String, CaseIterable, Sendable {
        case muscle, fullBody, conditioning, core, mobility

        public var label: String {
            switch self {
            case .muscle: "Muscle"
            case .fullBody: "Full body"
            case .conditioning: "Cardio"
            case .core: "Core"
            case .mobility: "Mobility"
            }
        }
    }

    public let id: String
    public let name: String
    public let focus: Focus
    /// Totals as given by the source plan.
    public let kcal: Int?
    public let activityPoints: Int?
    public let items: [Item]
    public let goal: Goal
    /// Short kit tag ("Gym", "Dumbbells", "No kit").
    public let kit: String
    /// 1 beginner … 3 advanced.
    public let level: Int
    /// Block kind of the main exercises.
    public let main: BlockKind

    public var levelLabel: String { level <= 1 ? "Beginner" : level == 2 ? "Intermediate" : "Advanced" }

    init(id: String, name: String, focus: Focus, kcal: Int? = nil, activityPoints: Int? = nil, goal: Goal = .muscle, kit: String = "Gym",
         level: Int = 2, main: BlockKind = .strength, items: [Item]) {
        self.id = id
        self.name = name
        self.focus = focus
        self.kcal = kcal
        self.activityPoints = activityPoints
        self.goal = goal
        self.kit = kit
        self.level = level
        self.main = main
        self.items = items
    }

    static let restSec = 90
    static let idPrefix = "example-"

    public var sessionId: String { Self.idPrefix + id }

    /// Block an item is played in: warm-up and stretch moves around the main block, unless the whole workout is mobility.
    func blockKind(_ it: Item) -> BlockKind {
        if let b = it.block { return b }
        guard main != .mobility, let e = Exercise.find(it.exerciseId) else { return main }
        switch e.category {
        case .warmup: return .warmup
        case .stretch: return .cooldown
        default: return main
        }
    }

    /// The template as a session (warm-up, main, cool-down blocks), so the session view and player work unchanged.
    public var session: Session {
        // Shared rest per circuit letter (the longest), as in custom workouts.
        var groupRest: [Character: Int] = [:]
        for it in items { if let l = it.group?.first { groupRest[l] = max(groupRest[l] ?? 0, it.restSec) } }
        let planned = items.enumerated().map { i, it -> (BlockKind, PlannedExercise) in
            let e = Exercise.get(it.exerciseId)
            let measure = CustomWorkout.Measure(e)
            let rest = it.group?.first.flatMap { groupRest[$0] } ?? it.restSec
            let perSet: Double = switch measure {
            case .reps: Double(it.reps) * (e.secPerRep ?? 3) * (e.unilateral ? 2 : 1)
            case .seconds: Double(it.reps) * (e.unilateral ? 2 : 1)
            case .minutes: Double(it.reps) * 60
            }
            let last = it.group.map { g in items[(i + 1)...].first { $0.group?.first == g.first } == nil } ?? true
            let restSec = it.group == nil ? (it.sets - 1) * rest : (last ? (it.sets - 1) * rest : 15 * it.sets)
            var p = PlannedExercise(
                uid: "\(sessionId)-\(i)", exerciseId: it.exerciseId, slot: e.pattern,
                prescription: Prescription(sets: it.sets, reps: measure.text(it.reps), restSec: rest, note: it.kcal.map { "≈ \($0) kcal" }),
                estSec: Int(perSet * Double(it.sets)) + restSec + (it.group == nil || last ? 60 : 0))
            p.group = it.group
            return (blockKind(it), p)
        }
        let kinds = BlockKind.allCases.filter { k in planned.contains { $0.0 == k } }.sorted { $0.order < $1.order }
        let blocks = kinds.map { k in
            let ex = planned.filter { $0.0 == k }.map { $0.1 }
            let min = Int((Double(ex.reduce(0) { $0 + $1.estSec }) / 60).rounded())
            let circuits = k == main && ex.contains { $0.group != nil }
            return Block(kind: k, title: k == main && k == .strength ? "Strength" : k.category.label, targetMin: min, items: ex,
                         note: circuits ? "Same-letter exercises back to back (A1 → A2), rest after the round." : nil)
        }
        let est = Int((Double(planned.reduce(0) { $0 + $1.1.estSec }) / 60).rounded())
        return Session(id: sessionId, index: 0, focus: focus, title: name, targetMin: est, estMin: est, blocks: blocks)
    }

    public static func find(sessionId: String) -> WorkoutTemplate? {
        (all + [climbAddon] + WallSession.templates + SportPrep.templates).first { $0.sessionId == sessionId }
    }

    /// Optional short session on climbing days (#47): push antagonists, shoulder health, finger extensors, core.
    /// No pulling or grip, so it stacks with a climbing session. Replaced on Train by the Wall session (#366); kept so
    /// sessions logged with it still resolve.
    public static let climbAddon = WorkoutTemplate(
        id: "climb-addon", name: "Climbing-day add-on", focus: .push, kcal: 90, activityPoints: 60,
        items: [
            Item("push-up", sets: 3, reps: 10),
            Item("push-up-plus", sets: 2, reps: 12),
            Item("face-pull", sets: 2, reps: 12),
            Item("cable-external-rotation", sets: 2, reps: 12),
            Item("reverse-wrist-curl", sets: 2, reps: 15),
            Item("finger-extensions", sets: 2, reps: 20),
            Item("dead-bug", sets: 2, reps: 10),
        ])

    public static let all: [WorkoutTemplate] = [lowerbody, armsShoulder, chestBack] + library

    /// Built-in library workouts with distinct focus points (#252).
    static let library: [WorkoutTemplate] = [
        pushPower, pullStrength, posteriorChain, dumbbellFullBody, bodyweight, machineStarter, coreCrusher, hiitCircuit, climberStrength,
        mobilityReset,
    ]

    static let lowerbody = WorkoutTemplate(
        id: "lowerbody", name: "Lower body", focus: .lower, kcal: 249, activityPoints: 214,
        items: [
            Item("back-squat", kcal: 63),
            Item("barbell-split-squat", kcal: 42),
            Item("bulgarian-split-squat", kcal: 111),
            Item("hip-thrust-machine", kcal: 9),
            Item("seated-calf-raise"),
            Item("hip-adduction"),
            Item("hip-abduction"),
            Item("crunch-machine"),
            Item("torso-rotation"),
            Item("back-extension"),
        ])

    static let armsShoulder = WorkoutTemplate(
        id: "arms-shoulder", name: "Arms + Shoulder", focus: .upper, kcal: 81, activityPoints: 70,
        items: [
            Item("barbell-curl"),
            Item("ohp"),
            Item("dips", kcal: 51),
            Item("incline-db-curl"),
            Item("db-lateral-raise"),
            Item("barbell-french-press"),
            Item("hammer-curl"),
            Item("db-reverse-fly"),
            Item("db-french-press"),
            Item("diamond-push-up", kcal: 30),
        ])

    /// Trainer's plan "Trainingspläne 3 – Chest & Back" (#451), as given: 3 × 10 (pull-ups 3 × 12).
    static let chestBack = WorkoutTemplate(
        id: "chest-back", name: "Chest & Back", focus: .chestBack, kcal: 102, activityPoints: 88,
        items: [
            Item("bench-press"),
            Item("incline-bench-press"),
            Item("db-fly"),
            Item("low-high-cable-fly", kcal: 6),
            Item("pull-up", reps: 12, kcal: 72),
            Item("plate-loaded-pulldown"),
            Item("single-arm-cable-row"),
            Item("deadlift", kcal: 24),
            Item("db-reverse-fly"),
            Item("db-shrug"),
        ])

    static let pushPower = WorkoutTemplate(
        id: "push-power", name: "Push power", focus: .chestTri,
        items: [
            Item("arm-circles", sets: 1, reps: 15, rest: 0),
            Item("scap-push-up", sets: 1, reps: 10, rest: 0),
            Item("bench-press", sets: 4, reps: 6, rest: 150),
            Item("incline-db-press", sets: 3, reps: 10),
            Item("seated-db-press", sets: 3, reps: 10),
            Item("cable-fly", sets: 3, reps: 12, rest: 60),
            Item("db-lateral-raise", sets: 3, reps: 15, rest: 60, group: "A1"),
            Item("rope-pushdown", sets: 3, reps: 12, rest: 60, group: "A2"),
            Item("ez-overhead-triceps", sets: 2, reps: 12, rest: 60),
            Item("pec-stretch", sets: 1, reps: 30, rest: 0),
            Item("triceps-stretch", sets: 1, reps: 30, rest: 0),
        ])

    static let pullStrength = WorkoutTemplate(
        id: "pull-strength", name: "Pull strength", focus: .backBi,
        items: [
            Item("band-dislocates", sets: 1, reps: 10, rest: 0),
            Item("cat-cow", sets: 1, reps: 8, rest: 0),
            Item("pull-up", sets: 4, reps: 6, rest: 150),
            Item("barbell-row", sets: 4, reps: 8, rest: 120),
            Item("seated-cable-row", sets: 3, reps: 10),
            Item("face-pull", sets: 3, reps: 15, rest: 60, group: "A1"),
            Item("ez-bar-curl", sets: 3, reps: 10, rest: 60, group: "A2"),
            Item("hammer-curl", sets: 3, reps: 12, rest: 60),
            Item("lat-stretch", sets: 1, reps: 30, rest: 0),
            Item("biceps-wall", sets: 1, reps: 30, rest: 0),
        ])

    static let posteriorChain = WorkoutTemplate(
        id: "posterior-chain", name: "Posterior chain", focus: .posterior,
        items: [
            Item("glute-bridge", sets: 1, reps: 12, rest: 0),
            Item("leg-swings", sets: 1, reps: 10, rest: 0),
            Item("rdl", sets: 4, reps: 8, rest: 150),
            Item("hip-thrust", sets: 4, reps: 10, rest: 120),
            Item("leg-curl", sets: 3, reps: 12),
            Item("back-extension", sets: 3, reps: 12, rest: 60),
            Item("cable-pull-through", sets: 3, reps: 15, rest: 60),
            Item("single-leg-rdl", sets: 2, reps: 10, rest: 60),
            Item("hamstring-stretch", sets: 1, reps: 30, rest: 0),
            Item("pigeon", sets: 1, reps: 45, rest: 0),
        ])

    static let dumbbellFullBody = WorkoutTemplate(
        id: "dumbbell-full-body", name: "Dumbbell full body", focus: .fullUpper, goal: .fullBody, kit: "Dumbbells", level: 1,
        items: [
            Item("inchworm", sets: 1, reps: 6, rest: 0),
            Item("worlds-greatest", sets: 1, reps: 6, rest: 0),
            Item("goblet-squat", sets: 3, reps: 10),
            Item("db-bench", sets: 3, reps: 10),
            Item("one-arm-db-row", sets: 3, reps: 10),
            Item("db-rdl", sets: 3, reps: 10),
            Item("reverse-lunge", sets: 3, reps: 8, rest: 75, group: "A1"),
            Item("seated-db-press", sets: 3, reps: 10, rest: 75, group: "A2"),
            Item("dead-bug", sets: 3, reps: 10, rest: 45),
            Item("couch-stretch", sets: 1, reps: 45, rest: 0),
            Item("childs-pose-reach", sets: 1, reps: 30, rest: 0),
        ])

    static let bodyweight = WorkoutTemplate(
        id: "bodyweight-anywhere", name: "Bodyweight anywhere", focus: .fullLower, goal: .fullBody, kit: "No kit", level: 1,
        items: [
            Item("squat-to-stand", sets: 1, reps: 8, rest: 0),
            Item("cat-cow", sets: 1, reps: 8, rest: 0),
            Item("bw-squat", sets: 3, reps: 15, rest: 90, group: "A1"),
            Item("push-up", sets: 3, reps: 10, rest: 90, group: "A2"),
            Item("bw-reverse-lunge", sets: 3, reps: 10, rest: 90, group: "A3"),
            Item("pike-push-up", sets: 3, reps: 8, rest: 90, group: "A4"),
            Item("mountain-climber", sets: 3, reps: 20, rest: 60, group: "B1"),
            Item("plank", sets: 3, reps: 30, rest: 60, group: "B2"),
            Item("burpee", sets: 3, reps: 1, rest: 60, group: "B3"),
            Item("downward-dog", sets: 1, reps: 30, rest: 0),
            Item("figure-4", sets: 1, reps: 30, rest: 0),
        ])

    static let machineStarter = WorkoutTemplate(
        id: "machine-starter", name: "Machine starter", focus: .fullUpper, goal: .fullBody, kit: "Machines", level: 1,
        items: [
            Item("bike", sets: 1, reps: 5, rest: 0, block: .warmup),
            Item("leg-press", sets: 3, reps: 12),
            Item("chest-press-machine", sets: 3, reps: 12),
            Item("lat-pulldown", sets: 3, reps: 12),
            Item("machine-row", sets: 3, reps: 12),
            Item("machine-shoulder-press", sets: 3, reps: 12),
            Item("leg-curl", sets: 3, reps: 12),
            Item("crunch-machine", sets: 2, reps: 15, rest: 60),
            Item("standing-quad-stretch", sets: 1, reps: 30, rest: 0),
            Item("lat-stretch", sets: 1, reps: 30, rest: 0),
        ])

    static let coreCrusher = WorkoutTemplate(
        id: "core-crusher", name: "Core crusher", focus: .fullUpper, goal: .core,
        items: [
            Item("cat-cow", sets: 1, reps: 10, rest: 0),
            Item("hanging-knee-raise", sets: 3, reps: 12, rest: 60),
            Item("pallof-press", sets: 3, reps: 10, rest: 60, group: "A1"),
            Item("side-plank", sets: 3, reps: 30, rest: 60, group: "A2"),
            Item("ab-wheel", sets: 3, reps: 10, rest: 60),
            Item("cable-woodchop", sets: 3, reps: 12, rest: 60, group: "B1"),
            Item("hollow-hold", sets: 3, reps: 30, rest: 60, group: "B2"),
            Item("sphinx", sets: 1, reps: 30, rest: 0),
            Item("supine-twist", sets: 1, reps: 30, rest: 0),
        ])

    static let hiitCircuit = WorkoutTemplate(
        id: "hiit-circuit", name: "HIIT circuit", focus: .conditioning, goal: .conditioning, kit: "Kettlebell", main: .cardio,
        items: [
            Item("jump-rope", sets: 1, reps: 3, rest: 0, block: .warmup),
            Item("worlds-greatest", sets: 1, reps: 6, rest: 0),
            Item("kb-swing", sets: 4, reps: 15, rest: 90, group: "A1"),
            Item("ball-slam", sets: 4, reps: 10, rest: 90, group: "A2"),
            Item("rower", sets: 4, reps: 1, rest: 90, group: "A3"),
            Item("mountain-climber", sets: 3, reps: 20, rest: 60, group: "B1"),
            Item("battle-rope-waves", sets: 3, reps: 30, rest: 60, group: "B2"),
            Item("burpee", sets: 3, reps: 1, rest: 60, group: "B3"),
            Item("breathing", sets: 1, reps: 90, rest: 0),
            Item("hamstring-stretch", sets: 1, reps: 30, rest: 0),
        ])

    /// Pulling strength plus the antagonists and finger extensors climbers skip.
    static let climberStrength = WorkoutTemplate(
        id: "climber-strength", name: "Climber's strength", focus: .pull,
        items: [
            Item("hanging-shoulder-circles", sets: 1, reps: 8, rest: 0, block: .warmup),
            Item("band-dislocates", sets: 1, reps: 10, rest: 0),
            Item("pull-up", sets: 4, reps: 5, rest: 150),
            Item("one-arm-db-row", sets: 3, reps: 8),
            Item("db-bench", sets: 3, reps: 10, rest: 75, group: "A1"),
            Item("face-pull", sets: 3, reps: 15, rest: 75, group: "A2"),
            Item("hanging-leg-raise", sets: 3, reps: 8, rest: 60),
            Item("reverse-wrist-curl", sets: 2, reps: 15, rest: 45, group: "B1"),
            Item("finger-extensions", sets: 2, reps: 20, rest: 45, group: "B2"),
            Item("cable-external-rotation", sets: 2, reps: 12, rest: 45),
            Item("forearm-flexor", sets: 1, reps: 30, rest: 0),
            Item("lat-stretch", sets: 1, reps: 30, rest: 0),
        ])

    static let mobilityReset = WorkoutTemplate(
        id: "mobility-reset", name: "Mobility reset", focus: .fullLower, goal: .mobility, kit: "No kit", level: 1, main: .mobility,
        items: [
            Item("cat-cow", sets: 1, reps: 10, rest: 0),
            Item("worlds-greatest", sets: 1, reps: 6, rest: 0),
            Item("hip-90-90", sets: 2, reps: 8, rest: 15),
            Item("open-book", sets: 2, reps: 8, rest: 15),
            Item("thread-needle", sets: 2, reps: 8, rest: 15),
            Item("deep-squat-pry", sets: 2, reps: 45, rest: 15),
            Item("couch-stretch", sets: 1, reps: 60, rest: 0),
            Item("pigeon", sets: 1, reps: 60, rest: 0),
            Item("hamstring-stretch", sets: 1, reps: 45, rest: 0),
            Item("breathing", sets: 1, reps: 120, rest: 0),
        ])
}

extension WorkoutTemplate.Goal {
    /// Best guess for any library workout (custom or shared): cardio, mobility, core, full body, else muscle.
    public init(_ s: Session) {
        let items = s.blocks.flatMap(\.items).map { Exercise.get($0.exerciseId) }
        let main = items.filter { $0.category != .warmup && $0.category != .stretch }
        let core: Set<Muscle> = [.abs, .obliques, .deepCore]
        if s.focus == .conditioning || (!main.isEmpty && main.allSatisfy { $0.category == .cardio || $0.category == .power }) {
            self = .conditioning
        } else if main.allSatisfy({ $0.category == .mobility }) {
            self = .mobility
        } else if !main.isEmpty, main.filter({ $0.primary.contains { core.contains($0) } }).count * 3 >= main.count * 2 {
            self = .core
        } else if [.fullUpper, .fullLower, .fullPower].contains(s.focus) {
            self = .fullBody
        } else {
            self = .muscle
        }
    }
}

extension Session {
    /// Muscles the work targets (main blocks; mobility when there are none), most loaded first.
    public func workMuscles(_ n: Int) -> [Muscle] {
        let top = topMuscles(n)
        return top.isEmpty ? Array(muscles(in: .mobility).prefix(n)) : top
    }
}

extension Session {
    /// Example and custom workouts carry their own name; generated sessions are named by focus.
    public var isExample: Bool { id.hasPrefix(WorkoutTemplate.idPrefix) }
    public var displayTitle: String { isStandalone ? title : focus.label }
}
