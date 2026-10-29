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
        /// Superset / circuit letter (#119): items sharing it are done back to back, rest after the round.
        /// Labels shown to the user come from `groupLabels` (renumbered, groups of one dropped).
        public var group: String?

        public init(id: UUID = UUID(), exerciseId: String, sets: Int = 3, reps: Int = 10, restSec: Int = 90, kcal: Int? = nil,
                    group: String? = nil) {
            self.id = id
            self.exerciseId = exerciseId
            self.sets = sets
            self.reps = reps
            self.restSec = restSec
            self.kcal = kcal
            self.group = group
        }

        enum CodingKeys: String, CodingKey { case id, exerciseId, sets, reps, restSec, kcal, group }

        /// Lenient: records written by other app versions may miss fields.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            exerciseId = try c.decode(String.self, forKey: .exerciseId)
            sets = try c.decodeIfPresent(Int.self, forKey: .sets) ?? 3
            reps = try c.decodeIfPresent(Int.self, forKey: .reps) ?? 10
            restSec = try c.decodeIfPresent(Int.self, forKey: .restSec) ?? CustomWorkout.defaultRestSec
            kcal = try c.decodeIfPresent(Int.self, forKey: .kcal)
            group = try? c.decodeIfPresent(String.self, forKey: .group)
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
    /// Set by the server while AI moderation holds its shared name for review (#871; read-only, never sent).
    public var inReview: Bool
    /// Session flow (#198): warm-up, explosive, mobility, cardio and cool-down blocks played around the
    /// member's own exercises, picked when the flow was set. Empty = just the exercises.
    public var flow: [Block]
    /// Warm-up / cool-down style or exact moves chosen for this workout (#293); nil = the profile's defaults.
    public var flowTweaks: FlowTweaks?
    /// Set when it's the member's own daily routine (#732): shown in Explore → Daily → Mine and on Train's Daily row.
    public var routine: RoutineLook?
    /// Saved from a video (#909): the post it came from, credited on the workout.
    public var source: WorkoutSource?
    /// Server version this copy was pulled or saved as, sent back as `baseUpdatedAt` so an edit never overwrites a
    /// newer copy from another device. Nil until the server has it.
    public var updatedAt: String?

    public init(id: UUID = UUID(), name: String, items: [Item] = [], createdAt: Date = Date(), visibility: WorkoutVisibility = .private,
                flow: [Block] = [], flowTweaks: FlowTweaks? = nil, routine: RoutineLook? = nil, source: WorkoutSource? = nil) {
        self.id = id
        self.name = name
        self.items = items
        self.createdAt = createdAt
        self.visibility = visibility
        self.hidden = false
        self.inReview = false
        self.flow = flow
        self.flowTweaks = flowTweaks
        self.routine = routine
        self.source = source
    }

    enum CodingKeys: String, CodingKey { case id, name, items, createdAt, visibility, flow, flowTweaks, routine, source, updatedAt }
    private enum ServerKeys: String, CodingKey { case hidden, inReview }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "My workout"
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        visibility = (try? c.decodeIfPresent(WorkoutVisibility.self, forKey: .visibility)) ?? .private
        flow = ((try? c.decodeIfPresent([Block].self, forKey: .flow)) ?? nil) ?? []
        flowTweaks = (try? c.decodeIfPresent(FlowTweaks.self, forKey: .flowTweaks)) ?? nil
        routine = (try? c.decodeIfPresent(RoutineLook.self, forKey: .routine)) ?? nil
        source = (try? c.decodeIfPresent(WorkoutSource.self, forKey: .source)) ?? nil
        updatedAt = (try? c.decodeIfPresent(String.self, forKey: .updatedAt)) ?? nil
        let server = try? decoder.container(keyedBy: ServerKeys.self)
        hidden = (try? server?.decodeIfPresent(Bool.self, forKey: .hidden)) ?? false
        inReview = (try? server?.decodeIfPresent(Bool.self, forKey: .inReview)) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(items, forKey: .items)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(visibility, forKey: .visibility)
        if !flow.isEmpty { try c.encode(flow, forKey: .flow) }
        if let flowTweaks, !flowTweaks.isEmpty { try c.encode(flowTweaks, forKey: .flowTweaks) }
        try c.encodeIfPresent(routine, forKey: .routine)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
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
            it.group = it.group.map { String($0.prefix(8)) }
            return it
        }
        w.flow = flow.filter { $0.kind != .strength }.prefix(5).map { b in
            var b = b
            b.items = b.items.filter { Exercise.find($0.exerciseId) != nil }
            return b
        }.filter { !$0.items.isEmpty }
        w.routine = routine?.sanitized
        w.source = source?.sanitized
        if w.routine != nil { w.flow = [] }
        return w
    }

    /// Sum of the per-exercise calories the user entered, when any.
    public var kcal: Int? {
        let values = items.compactMap(\.kcal)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    // MARK: Session conversion

    static let idPrefix = "custom-"
    /// Session ids of custom workouts start with it.
    public static var sessionPrefix: String { idPrefix }

    public var sessionId: String { Self.idPrefix + id.uuidString.lowercased() }

    /// Items the player can run (exercise present in this app's catalog).
    public var playableItems: [Item] { items.filter { $0.exercise != nil } }

    /// The workout as a single-block session, so the session view, player and history work unchanged.
    public var session: Session {
        let pairs: [(item: Item, exercise: Exercise)] = playableItems.compactMap { it in
            guard let e = it.exercise else { return nil }
            return (item: it, exercise: e)
        }
        let labels = groupLabels
        // Per group letter: shared rest (the longest), rounds and the last member, which carries the rest.
        var groupRest: [Character: Int] = [:]
        var groupRounds: [Character: Int] = [:]
        var groupSize: [Character: Int] = [:]
        var lastOfGroup: [Character: UUID] = [:]
        for pair in pairs {
            guard let l = labels[pair.item.id]?.first else { continue }
            groupRest[l] = max(groupRest[l] ?? 0, max(0, pair.item.restSec))
            groupRounds[l] = max(groupRounds[l] ?? 1, max(1, pair.item.sets))
            groupSize[l, default: 0] += 1
            lastOfGroup[l] = pair.item.id
        }
        let planned = pairs.map { pair -> PlannedExercise in
            let it = pair.item
            let e = pair.exercise
            let label = labels[it.id]
            let letter = label?.first
            let sets = max(1, it.sets)
            let reps = max(1, it.reps)
            let rest = letter.flatMap { groupRest[$0] } ?? max(0, it.restSec)
            let measure = Measure(e)
            let perSet: Double
            switch measure {
            case .reps: perSet = Double(reps) * (e.secPerRep ?? 3) * (e.unilateral ? 2 : 1)
            case .seconds: perSet = Double(reps) * (e.unilateral ? 2 : 1)
            case .minutes: perSet = Double(reps) * 60
            }
            let work = perSet * Double(sets)
            let kcalNote = it.kcal.map { "≈ \($0) kcal" }
            guard let label, let letter else {
                return PlannedExercise(
                    uid: "\(sessionId)-\(it.id.uuidString.lowercased())", exerciseId: e.id, slot: e.pattern,
                    prescription: Prescription(sets: sets, reps: measure.text(reps), restSec: rest, note: kcalNote),
                    estSec: Int(work) + (sets - 1) * rest + 60)
            }
            // Grouped: work plus a short move per set; the round's rest (and the change-over) sits on the last member.
            let size = groupSize[letter] ?? 2
            let last = lastOfGroup[letter] == it.id
            let rounds = groupRounds[letter] ?? sets
            let groupNote = label.dropFirst() == "1"
                ? (size == 2 ? "Superset" : "Circuit") + ": \(size) exercises back to back, rest after the round" : nil
            var p = PlannedExercise(
                uid: "\(sessionId)-\(it.id.uuidString.lowercased())", exerciseId: e.id, slot: e.pattern,
                prescription: Prescription(sets: sets, reps: measure.text(reps), restSec: rest,
                                           note: [groupNote, kcalNote].compactMap { $0 }.joined(separator: " · ").nilIfEmpty),
                estSec: Int(work) + 15 * sets + (last ? (rounds - 1) * rest + 60 : 0))
            p.group = label
            return p
        }
        let exercises = pairs.map { $0.exercise }
        let categories = Set(exercises.map { $0.category })
        // An own routine (#732) of stretches and mobility drills plays as one mobility block (no strength, no finisher).
        let kind: BlockKind = categories.count == 1 ? Self.blockKind(categories.first!)
            : routine != nil && categories.isSubset(of: [.mobility, .stretch]) ? .mobility : .strength
        let est = Int((Double(planned.reduce(0) { $0 + $1.estSec }) / 60).rounded())
        let note: String? = labels.isEmpty ? nil
            : "\(Set(groupSize.values).contains { $0 > 2 } ? "Circuits" : "Supersets"): same-letter exercises back to back (A1 → A2), rest after the round."
        let main = Block(kind: kind, title: kind.category.label, targetMin: est, items: planned, note: note)
        // Flow blocks (#198) around the member's exercises, in session order; ids prefixed so ticks stay per workout.
        // Moves this app doesn't know (a newer version's, another device's custom one) are left out, never played.
        let extras = flow.map { b -> Block in
            var b = b
            b.items = b.items.filter { Exercise.find($0.exerciseId) != nil }
            for i in b.items.indices { b.items[i].uid = "\(sessionId)-\(b.items[i].uid)" }
            return b
        }.filter { !$0.items.isEmpty }
        let blocks = planned.isEmpty ? [main] : extras.filter { $0.kind.order < BlockKind.strength.order } + [main]
            + extras.filter { $0.kind.order > BlockKind.strength.order }
        let total = est + extras.reduce(0) { $0 + $1.targetMin }
        let estTotal = Int(blocks.reduce(0) { $0 + $1.estMin }.rounded())
        return Session(id: sessionId, index: 0, focus: Self.focus(exercises), title: name, targetMin: total,
                       estMin: extras.isEmpty ? est : estTotal, blocks: blocks)
    }

    /// Superset / circuit labels by item ("A1", "A2", "B1", …): letters renumbered in order of appearance,
    /// members numbered in list order; groups left with a single playable item are dropped.
    public var groupLabels: [UUID: String] {
        let playable = playableItems
        var members: [String: [UUID]] = [:]
        var order: [String] = []
        for it in playable {
            guard let g = it.group, !g.isEmpty else { continue }
            if members[g] == nil { order.append(g) }
            members[g, default: []].append(it.id)
        }
        var out: [UUID: String] = [:]
        var letter = 0
        for g in order {
            guard let ids = members[g], ids.count > 1 else { continue }
            let l = String(Character(Unicode.Scalar(UInt8(65 + letter % 26))))
            letter += 1
            for (n, id) in ids.enumerated() { out[id] = "\(l)\(n + 1)" }
        }
        return out
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
        let lowerMuscles: Set<Muscle> = [.glutes, .gluteMed, .hipFlexors, .adductors, .quads, .hamstrings, .calves, .soleus, .tibialis]
        let lower = exercises.filter { e in e.primary.contains { lowerMuscles.contains($0) } }.count
        if lower * 3 >= exercises.count * 2 { return .lower }
        if lower * 3 <= exercises.count { return .upper }
        return lower * 2 >= exercises.count ? .fullLower : .fullUpper
    }

    // MARK: Copies

    /// A new, editable custom workout with the example's exercises.
    /// Warm-up and cool-down moves come along as session flow blocks (#252).
    public init(duplicating t: WorkoutTemplate, createdAt: Date = Date()) {
        let main = t.items.filter { t.blockKind($0) == t.main }
        self.init(
            name: "\(t.name) (copy)",
            items: main.map { Item(exerciseId: $0.exerciseId, sets: $0.sets, reps: $0.reps, restSec: $0.restSec, kcal: $0.kcal, group: $0.group?.first.map(String.init)) },
            createdAt: createdAt, flow: t.session.blocks.filter { $0.kind != t.main })
    }

    /// A copy with fresh ids (workout and items).
    public func duplicated(createdAt: Date = Date()) -> CustomWorkout {
        CustomWorkout(
            name: String("\(name) (copy)".prefix(Self.maxNameLength)),
            items: items.map { Item(exerciseId: $0.exerciseId, sets: $0.sets, reps: $0.reps, restSec: $0.restSec, kcal: $0.kcal, group: $0.group) },
            createdAt: createdAt, flow: flow, flowTweaks: flowTweaks, routine: routine, source: source)
    }
}

/// How a member's own daily routine looks (#732): a colour from the routine palette and an icon.
public struct RoutineLook: Codable, Hashable, Sendable {
    public var color: Int
    public var symbol: String

    public init(color: Int = 0, symbol: String = RoutineLook.symbols[0]) {
        self.color = color
        self.symbol = symbol
    }

    /// Colours offered (indexes into the app's routine palette).
    public static let colors = 0..<6
    public static let symbols = ["star.fill", "figure.flexibility", "figure.cooldown", "figure.yoga", "sun.max.fill",
                                 "moon.stars.fill", "hand.raised.fill", "heart.fill", "bolt.fill", "leaf.fill"]

    /// A move added to a routine: one round, no rest, 45 s holds.
    public static func item(adding e: Exercise) -> CustomWorkout.Item {
        var it = CustomWorkout.Item(adding: e)
        it.sets = 1
        it.restSec = 0
        if CustomWorkout.Measure(e) == .seconds { it.reps = 45 }
        return it
    }

    var sanitized: RoutineLook {
        RoutineLook(color: Self.colors.contains(color) ? color : 0, symbol: Self.symbols.contains(symbol) ? symbol : Self.symbols[0])
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

    /// Catalog plus the user's custom exercises, filtered for the workout builder: every word of `query`
    /// must appear in the name, machine, a muscle or equipment label; optional category and muscle
    /// (primary or secondary) filters.
    public static func search(
        _ query: String = "", category: Category? = nil, muscle: Muscle? = nil, custom registry: CustomExercises = .shared
    ) -> [Exercise] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let custom = registry.active
        let all = custom.isEmpty ? byName : (byName + custom).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return all.filter { e in
            if let category, e.category != category { return false }
            if let muscle, !e.muscles.contains(muscle) { return false }
            guard !words.isEmpty else { return true }
            let machine = registry.record(e.id)?.machine ?? ""
            let haystack = ([e.name, e.id, machine] + e.muscles.map(\.name) + e.equipment.map(\.label)).joined(separator: " ")
            return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension Comparable {
    fileprivate func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
