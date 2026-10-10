import Foundation

/// Ready-made example workouts: fixed exercise lists shown next to the generated week.
public struct WorkoutTemplate: Identifiable, Hashable, Sendable {
    public struct Item: Hashable, Sendable {
        public let exerciseId: String
        public let sets: Int
        public let reps: Int
        /// Calories for this exercise as given by the source plan, when stated.
        public let kcal: Int?

        init(_ exerciseId: String, sets: Int = 3, reps: Int = 10, kcal: Int? = nil) {
            self.exerciseId = exerciseId
            self.sets = sets
            self.reps = reps
            self.kcal = kcal
        }
    }

    public let id: String
    public let name: String
    public let focus: Focus
    /// Totals as given by the source plan.
    public let kcal: Int
    public let activityPoints: Int
    public let items: [Item]

    static let restSec = 90
    static let idPrefix = "example-"

    public var sessionId: String { Self.idPrefix + id }

    /// The template as a single-block session, so the session view and player work unchanged.
    public var session: Session {
        let planned = items.enumerated().map { i, it -> PlannedExercise in
            let e = Exercise.get(it.exerciseId)
            let work = Double(it.sets * it.reps) * (e.secPerRep ?? 3) * (e.unilateral ? 2 : 1)
            return PlannedExercise(
                uid: "\(sessionId)-\(i)", exerciseId: it.exerciseId, slot: e.pattern,
                prescription: Prescription(sets: it.sets, reps: "\(it.reps)", restSec: Self.restSec, note: it.kcal.map { "≈ \($0) kcal" }),
                estSec: Int(work) + (it.sets - 1) * Self.restSec + 60)
        }
        let est = Int((Double(planned.reduce(0) { $0 + $1.estSec }) / 60).rounded())
        return Session(id: sessionId, index: 0, focus: focus, title: name, targetMin: est, estMin: est,
                       blocks: [Block(kind: .strength, title: "Strength", targetMin: est, items: planned)])
    }

    public static func find(sessionId: String) -> WorkoutTemplate? { all.first { $0.sessionId == sessionId } }

    public static let all: [WorkoutTemplate] = [lowerbody, armsShoulder]

    static let lowerbody = WorkoutTemplate(
        id: "lowerbody", name: "Lowerbody", focus: .lower, kcal: 249, activityPoints: 214,
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
}

extension Session {
    /// Example workouts carry their own name; generated sessions are named by focus.
    public var isExample: Bool { id.hasPrefix(WorkoutTemplate.idPrefix) }
    public var displayTitle: String { isExample ? title : focus.label }
}
