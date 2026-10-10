import Foundation

/// A workout the user built in the app: own name and an ordered list of catalog exercises.
/// Synced to the server as an opaque record and played like an example workout.
public struct CustomWorkout: Codable, Hashable, Sendable, Identifiable {
    public struct Item: Codable, Hashable, Sendable, Identifiable {
        /// Stable per item so ticks and set counts survive edits and reordering.
        public var id: UUID
        public var exerciseId: String
        public var sets: Int
        /// Reps per set, or seconds per set for time-based exercises.
        public var reps: Int
        public var restSec: Int
        /// Optional calories for this exercise, as the user entered them.
        public var kcal: Int?

        public init(id: UUID = UUID(), exerciseId: String, sets: Int = 3, reps: Int = 10, restSec: Int = 90, kcal: Int? = nil) {
            self.id = id
            self.exerciseId = exerciseId
            self.sets = sets
            self.reps = reps
            self.restSec = restSec
            self.kcal = kcal
        }

        enum CodingKeys: String, CodingKey { case id, exerciseId, sets, reps, restSec, kcal }

        /// Lenient: records written by other app versions may miss fields.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            exerciseId = try c.decode(String.self, forKey: .exerciseId)
            sets = try c.decodeIfPresent(Int.self, forKey: .sets) ?? 3
            reps = try c.decodeIfPresent(Int.self, forKey: .reps) ?? 10
            restSec = try c.decodeIfPresent(Int.self, forKey: .restSec) ?? CustomWorkout.defaultRestSec
            kcal = try c.decodeIfPresent(Int.self, forKey: .kcal)
        }

        /// Sensible starting prescription for a newly added exercise.
        public init(adding e: Exercise) {
            let rest = e.category == .strength || e.category == .power ? CustomWorkout.defaultRestSec : 30
            switch Measure(e) {
            case .reps: self.init(exerciseId: e.id, sets: 3, reps: 10, restSec: rest)
            case .seconds: self.init(exerciseId: e.id, sets: 3, reps: 30, restSec: rest)
            case .minutes: self.init(exerciseId: e.id, sets: 1, reps: 10, restSec: 60)
            }
        }

        /// Whether the exercise is known to this app's catalog (unknown ones are kept but not played).
        public var exercise: Exercise? { Exercise.find(exerciseId) }
    }

    /// How an item's `reps` is read: repetitions, seconds (holds, stretches) or minutes (cardio machines).
    public enum Measure: Sendable, Equatable {
        case reps, seconds, minutes

        public init(_ e: Exercise) {
            if e.category == .cardio {
                self = .minutes
            } else if e.unit == .sec {
                self = .seconds
            } else {
                self = .reps
            }
        }

        public var label: String {
            switch self {
            case .reps: "Reps"
            case .seconds: "Seconds"
            case .minutes: "Minutes"
            }
        }

        /// Prescription text for one set ("10", "30 s", "10 min").
        public func text(_ n: Int) -> String {
            switch self {
            case .reps: "\(n)"
            case .seconds: "\(n) s"
            case .minutes: "\(n) min"
            }
        }

        /// Stepper increment in the editor.
        public var step: Int {
            switch self {
            case .reps: 1
            case .seconds: 5
            case .minutes: 1
            }
        }
    }

    public var id: UUID
    public var name: String
    public var items: [Item]
    public var createdAt: Date
    /// Shared in the workout library (#62); private by default.
    public var visibility: WorkoutVisibility
    /// Set by the server when reports hid it from other members (read-only, never sent).
    public var hidden: Bool

    public init(id: UUID = UUID(), name: String, items: [Item] = [], createdAt: Date = Date(), visibility: WorkoutVisibility = .private) {
        self.id = id
        self.name = name
        self.items = items
        self.createdAt = createdAt
        self.visibility = visibility
        self.hidden = false
    }

    enum CodingKeys: String, CodingKey { case id, name, items, createdAt, visibility }
    private enum ServerKeys: String, CodingKey { case hidden }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "My workout"
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        visibility = (try? c.decodeIfPresent(WorkoutVisibility.self, forKey: .visibility)) ?? .private
        hidden = (try? decoder.container(keyedBy: ServerKeys.self).decodeIfPresent(Bool.self, forKey: .hidden)) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(items, forKey: .items)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(visibility, forKey: .visibility)
    }

    // MARK: Limits (mirrored by the API: name ≤ 100 chars, ≤ 100 items)

    public static let maxNameLength = 100
    public static let maxItems = 100
    public static let setsRange = 1...20
    public static let repsRange = 1...600
    public static let restRange = 0...600
    public static let kcalRange = 0...5000
    public static let defaultRestSec = 90

    /// Copy with a trimmed, non-empty name and every number clamped to the editor's ranges.
    public var sanitized: CustomWorkout {
        var w = self
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        w.name = String((trimmed.isEmpty ? "My workout" : trimmed).prefix(Self.maxNameLength))
        w.items = Array(items.prefix(Self.maxItems)).map { it in
            var it = it
            it.sets = it.sets.clamped(to: Self.setsRange)
            it.reps = it.reps.clamped(to: Self.repsRange)
            it.restSec = it.restSec.clamped(to: Self.restRange)
            it.kcal = it.kcal.map { $0.clamped(to: Self.kcalRange) }
            return it
        }
        return w
    }

    /// Sum of the per-exercise calories the user entered, when any.
    public var kcal: Int? {
        let values = items.compactMap(\.kcal)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    // MARK: Session conversion

    static let idPrefix = "custom-"

    public var sessionId: String { Self.idPrefix + id.uuidString.lowercased() }

    /// Items the player can run (exercise present in this app's catalog).
    public var playableItems: [Item] { items.filter { $0.exercise != nil } }

    /// The workout as a single-block session, so the session view, player and history work unchanged.
    public var session: Session {
        let pairs: [(item: Item, exercise: Exercise)] = playableItems.compactMap { it in
            guard let e = it.exercise else { return nil }
            return (item: it, exercise: e)
        }
        let planned = pairs.map { pair -> PlannedExercise in
            let it = pair.item
            let e = pair.exercise
            let sets = max(1, it.sets)
            let reps = max(1, it.reps)
            let rest = max(0, it.restSec)
            let measure = Measure(e)
            let perSet: Double
            switch measure {
            case .reps: perSet = Double(reps) * (e.secPerRep ?? 3) * (e.unilateral ? 2 : 1)
            case .seconds: perSet = Double(reps) * (e.unilateral ? 2 : 1)
            case .minutes: perSet = Double(reps) * 60
            }
            let work = perSet * Double(sets)
            return PlannedExercise(
                uid: "\(sessionId)-\(it.id.uuidString.lowercased())", exerciseId: e.id, slot: e.pattern,
                prescription: Prescription(sets: sets, reps: measure.text(reps), restSec: rest, note: it.kcal.map { "≈ \($0) kcal" }),
                estSec: Int(work) + (sets - 1) * rest + 60)
        }
        let exercises = pairs.map { $0.exercise }
        let categories = Set(exercises.map { $0.category })
        let kind: BlockKind = categories.count == 1 ? Self.blockKind(categories.first!) : .strength
        let est = Int((Double(planned.reduce(0) { $0 + $1.estSec }) / 60).rounded())
        return Session(id: sessionId, index: 0, focus: Self.focus(exercises), title: name, targetMin: est, estMin: est,
                       blocks: [Block(kind: kind, title: kind.category.label, targetMin: est, items: planned)])
    }

    static func blockKind(_ c: Category) -> BlockKind {
        switch c {
        case .warmup: .warmup
        case .power: .power
        case .strength: .strength
        case .mobility: .mobility
        case .cardio: .cardio
        case .stretch: .cooldown
        }
    }

    /// Rough focus from where the primary movers sit (used for history and colours, never shown as title).
    static func focus(_ exercises: [Exercise]) -> Focus {
        guard !exercises.isEmpty else { return .upper }
        if exercises.allSatisfy({ $0.category == .cardio }) { return .conditioning }
        let lowerMuscles: Set<Muscle> = [.glutes, .hipFlexors, .adductors, .quads, .hamstrings, .calves]
        let lower = exercises.filter { e in e.primary.contains { lowerMuscles.contains($0) } }.count
        if lower * 3 >= exercises.count * 2 { return .lower }
        if lower * 3 <= exercises.count { return .upper }
        return lower * 2 >= exercises.count ? .fullLower : .fullUpper
    }

    // MARK: Copies

    /// A new, editable custom workout with the example's exercises.
    public init(duplicating t: WorkoutTemplate, createdAt: Date = Date()) {
        self.init(
            name: "\(t.name) (copy)",
            items: t.items.map { Item(exerciseId: $0.exerciseId, sets: $0.sets, reps: $0.reps, restSec: WorkoutTemplate.restSec, kcal: $0.kcal) },
            createdAt: createdAt)
    }

    /// A copy with fresh ids (workout and items).
    public func duplicated(createdAt: Date = Date()) -> CustomWorkout {
        CustomWorkout(
            name: String("\(name) (copy)".prefix(Self.maxNameLength)),
            items: items.map { Item(exerciseId: $0.exerciseId, sets: $0.sets, reps: $0.reps, restSec: $0.restSec, kcal: $0.kcal) },
            createdAt: createdAt)
    }
}

extension Session {
    /// Built by the user (see `CustomWorkout`).
    public var isCustom: Bool { id.hasPrefix(CustomWorkout.idPrefix) }
    /// Example or custom workout: fixed list outside the generated week, carries its own name.
    public var isStandalone: Bool { isExample || isCustom }
}

extension Exercise {
    private static let byName: [Exercise] = catalog.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    /// Catalog filtered for the workout builder: every word of `query` must appear in the name,
    /// a muscle or equipment label; optional category and muscle (primary or secondary) filters.
    public static func search(_ query: String = "", category: Category? = nil, muscle: Muscle? = nil) -> [Exercise] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return byName.filter { e in
            if let category, e.category != category { return false }
            if let muscle, !e.muscles.contains(muscle) { return false }
            guard !words.isEmpty else { return true }
            let haystack = ([e.name, e.id] + e.muscles.map(\.name) + e.equipment.map(\.label)).joined(separator: " ")
            return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}

extension Comparable {
    fileprivate func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
