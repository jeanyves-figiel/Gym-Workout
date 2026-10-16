import Foundation

/// Generate a workout from chosen muscle groups (#119): strength exercises for those groups that fit the member's
/// equipment and level, dosed for their goal, sized to a duration, with the chosen rest and grouping.
/// The result is an ordinary `CustomWorkout`, edited in the builder before it is saved.
public struct MuscleWorkoutOptions: Hashable, Sendable {
    public var groups: Set<MuscleGroup>
    public var minutes: Int
    public var rest: RestStyle
    public var grouping: Grouping
    /// Workout chat (#381): skip exercises that load these groups (primary or secondary), e.g. a sore shoulder.
    public var avoidGroups: Set<MuscleGroup> = []
    /// Equipment not wanted today (busy rack, no barbell).
    public var avoidEquipment: Set<Equipment> = []
    /// Lowercase words of exercise names to skip ("lunge").
    public var avoidKeywords: [String] = []

    public init(groups: Set<MuscleGroup> = [], minutes: Int = 45, rest: RestStyle = .standard, grouping: Grouping = .straight) {
        self.groups = groups
        self.minutes = minutes
        self.rest = rest
        self.grouping = grouping
    }

    /// Whether `e` stays out of this workout (avoided groups, equipment or name words).
    func avoids(_ e: Exercise) -> Bool {
        if !avoidGroups.isEmpty, (e.primary + e.secondary).contains(where: { avoidGroups.contains($0.group) }) { return true }
        if e.equipment.contains(where: { avoidEquipment.contains($0) }) { return true }
        let name = e.name.lowercased()
        return avoidKeywords.contains { !$0.isEmpty && (name.contains($0) || e.id.contains($0)) }
    }

    /// Defaults from the profile: its rest and grouping (the goal's unless overridden) and about three quarters
    /// of its session length (the rest of a plan session is warm-up, cardio and cool-down).
    public init(profile: Profile, groups: Set<MuscleGroup> = []) {
        let target = Double(Generator.sessionMinutes(profile)) * 0.75
        let minutes = Self.durations.min { abs(Double($0) - target) < abs(Double($1) - target) } ?? 45
        self.init(groups: groups, minutes: minutes, rest: profile.rest, grouping: profile.group)
    }

    public static let durations = [20, 30, 45, 60, 75, 90]
    public static let maxExercises = 12
}

extension MuscleGroup {
    /// Body area used by circuits: upper body, lower body, core.
    var area: String {
        switch self {
        case .shoulders, .chest, .arms, .back: "upper"
        case .hips, .legs: "lower"
        case .core: "core"
        }
    }
}

/// One exercise picked for a muscle group.
struct MusclePick {
    let exercise: Exercise
    let group: MuscleGroup
    /// Gets the goal's main-lift dose.
    let main: Bool
    /// Core, calves, prehab: light dose, played last.
    let light: Bool
}

extension CustomWorkout {
    /// Name for a generated workout: the groups in body order ("Chest + Back"), "Full body" for five or more.
    public static func generatedName(_ groups: Set<MuscleGroup>) -> String {
        let ordered = MuscleGroup.allCases.filter { groups.contains($0) }
        if ordered.count >= 5 { return "Full body" }
        return ordered.map(\.label).joined(separator: " + ")
    }

    /// A workout for `options.groups`; empty when no group is chosen or nothing fits the equipment.
    /// Same `seed` → same workout; a new seed gives another pick.
    public static func generate(_ options: MuscleWorkoutOptions, profile: Profile, seed: UInt32, createdAt: Date = Date()) -> CustomWorkout {
        let groups = MuscleGroup.allCases.filter { options.groups.contains($0) }
        let base = CustomWorkout(name: generatedName(options.groups), createdAt: createdAt)
        guard !groups.isEmpty else { return base }

        var rng = Rng(seed: seed)
        let level = profile.experience.level
        let equipment = Set(profile.equipment)
        let spareGrip = profile.climbingDaysPerWeek >= 2
        let pools: [MuscleGroup: [Exercise]] = Dictionary(uniqueKeysWithValues: groups.map { g in
            (g, Exercise.catalog.filter { e in
                e.category == .strength && e.level <= level && Selector.isAvailable(e, equipment)
                    && !Exercise.libraryOnlyIds.contains(e.id)
                    && e.primary.contains { $0.group == g }
                    && !options.avoids(e)
            })
        })

        var picks: [MusclePick] = []
        var used: Set<String> = []
        var covered: [MuscleGroup: Set<Muscle>] = [:]
        var patterns: [MuscleGroup: Set<Pattern>] = [:]
        // Heavy main lifts (goal's main dose): the first pick of the first two groups, when it is a main lift.
        var mains = 0

        func pick(_ g: MuscleGroup) -> MusclePick? {
            let pool = (pools[g] ?? []).filter { !used.contains($0.id) }
            guard !pool.isEmpty else { return nil }
            let first = covered[g] == nil
            func score(_ e: Exercise) -> Double {
                let targets = e.primary.filter { $0.group == g }
                var s = 2 * Double(targets.filter { !(covered[g] ?? []).contains($0) }.count)
                if !(patterns[g] ?? []).contains(e.pattern) { s += 1.5 }
                if first && e.main { s += 3 }
                if first && !Rules.lightPatterns.contains(e.pattern) { s += 1 }
                if spareGrip && e.gripHeavy { s -= 1.5 }
                if e.generator { s += 0.5 }
                return s + rng.next()
            }
            let scored = pool.map { (exercise: $0, score: score($0)) }
            let e = scored.max { $0.score < $1.score }!.exercise
            used.insert(e.id)
            covered[g, default: []].formUnion(e.primary.filter { $0.group == g })
            patterns[g, default: []].insert(e.pattern)
            let light = Rules.lightPatterns.contains(e.pattern)
            let main = first && e.main && !light && mains < 2
            if main { mains += 1 }
            return MusclePick(exercise: e, group: g, main: main, light: light)
        }

        func build(_ picks: [MusclePick]) -> CustomWorkout {
            var w = base
            w.items = CustomWorkout.ordered(picks, options: options, profile: profile)
            return w
        }

        // Round-robin over the groups until the workout fills the duration (every group gets at least one).
        let budget = Double(options.minutes)
        var exhausted: Set<MuscleGroup> = []
        fill: while picks.count < MuscleWorkoutOptions.maxExercises && exhausted.count < groups.count {
            for g in groups where !exhausted.contains(g) {
                guard picks.count < MuscleWorkoutOptions.maxExercises else { break fill }
                let hasOne = picks.contains { $0.group == g }
                guard let p = pick(g) else { exhausted.insert(g); continue }
                let est = Double(build(picks + [p]).session.estMin)
                if hasOne && est > budget + 4 { exhausted = Set(groups); break fill }
                picks.append(p)
                if est >= budget - 2 && picks.count >= groups.count { break fill }
            }
        }
        return build(picks)
    }

    /// Items in playing order with the goal's dose: main lifts first, then accessories, light work (core, calves,
    /// prehab) last; same-muscle accessories grouped per `options.grouping`.
    static func ordered(_ picks: [MusclePick], options: MuscleWorkoutOptions, profile: Profile) -> [Item] {
        let g = profile.goal.config
        let beginner = profile.experience == .beginner
        let tier: (MusclePick) -> Int = { $0.main ? 0 : ($0.light ? 2 : 1) }
        let sorted = picks.enumerated().sorted { (tier($0.element), $0.offset) < (tier($1.element), $1.offset) }.map(\.element)

        var items: [(item: Item, key: String?)] = sorted.map { p -> (item: Item, key: String?) in
            let e = p.exercise
            var d: Dose
            if p.main { d = g.main }
            else if p.light { d = Dose(sets: beginner ? 2 : 3, reps: "12–15", repsMid: 13, restSec: 45, rpe: 7) }
            else { d = g.accessory }
            // Minimal dose (#156): 2 hard sets per exercise.
            let sets = profile.trainingMethod == .minimal ? 2 : max(1, d.sets - (beginner && !p.light ? 1 : 0))
            let reps: Int = switch Measure(e) {
            case .reps: d.repsMid
            case .seconds: 40
            case .minutes: 10
            }
            let rest = options.rest.restSec(d.restSec, main: p.main, light: p.light)
            let key: String? = p.main || options.grouping == .straight ? nil
                : (options.grouping == .supersets ? p.group.rawValue : p.group.area)
            return (item: Item(exerciseId: e.id, sets: sets, reps: reps, restSec: rest), key: key)
        }

        guard options.grouping != .straight else { return items.map { $0.item } }
        // Buckets by key in order of appearance, chunked in pairs (supersets) or up to 4 (circuits).
        let size = options.grouping == .supersets ? 2 : 4
        var buckets: [String: [Int]] = [:]
        var order: [String] = []
        for (i, it) in items.enumerated() {
            guard let k = it.key else { continue }
            if buckets[k] == nil { order.append(k) }
            buckets[k, default: []].append(i)
        }
        // Gym zones (#274): a group only holds exercises near each other.
        let near: (Int, Int) -> Bool = { profile.gymLayout.near(items[$0].item.exerciseId, items[$1].item.exerciseId) }
        var groups: [[Int]] = []
        for k in order {
            for chunk in GymLayout.chunk(buckets[k]!, size: size, near: near) {
                // A single joins the previous circuit of that area (when near), else stays straight.
                if chunk.count == 1 {
                    if options.grouping == .circuits, let lastGroup = groups.last, items[lastGroup[0]].key == k,
                       lastGroup.allSatisfy({ near($0, chunk[0]) }) {
                        groups[groups.count - 1].append(chunk[0])
                    }
                } else {
                    groups.append(chunk)
                }
            }
        }
        // Each group sits at its first member's position; members share the longest rest.
        var out: [Item] = []
        var placed: Set<Int> = []
        for (n, g) in groups.enumerated() {
            let rest = g.map { items[$0].item.restSec }.max() ?? 0
            for i in g {
                items[i].item.group = "g\(n + 1)"
                items[i].item.restSec = rest
            }
        }
        for i in items.indices where !placed.contains(i) {
            if let g = groups.first(where: { $0.first == i }) {
                for m in g { out.append(items[m].item); placed.insert(m) }
            } else if !groups.contains(where: { $0.contains(i) }) {
                out.append(items[i].item)
                placed.insert(i)
            }
        }
        return out
    }
}
