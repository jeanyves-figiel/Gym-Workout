struct Query {
    var category: Category
    var pattern: Pattern?
    var regions: [Region]?
    var main = false
    var prefer: [String] = []
}

/// Mutable generation state shared across a week (reference semantics on purpose).
final class Ctx {
    var rng: Rng
    let level: Int
    let equipment: Set<Equipment>
    /// Frequent climber (≥ 2 climbing days / week).
    let frequentClimber: Bool
    /// Current session is the day before a climbing day (weekday-scheduled plans only).
    var preClimb = false
    /// Day before climbing with a "strong" choice (#47): explosive work kept, grip still spared.
    var preClimbGrip = false
    /// Prefer exercises without heavy grip (frequent climber, or climbing tomorrow).
    var spareGrip: Bool { frequentClimber || preClimb || preClimbGrip }
    let climber: Bool
    let profile: Profile
    let week: Int
    let seed: UInt32
    let deload: Bool
    let variety: PlanVariety
    /// Main-lift picks: own RNG (seed only) and "used" set, so main lifts don't drift week to week.
    var mainRng: Rng
    var usedMain: Set<String> = []
    var usedWeek: Set<String> = []
    /// Every pick this week, keyed by session, block and call ("s2-st#3"), so `.same` plans can replay week 1.
    var picks: [String: String] = [:]
    /// `.same` plans after week 1: week 1's `picks`. Each call takes week 1's pick for the same key (if it
    /// still fits), so exercises stay put even when a week's dose changes how many fit the time budget.
    var replay: [String: String]?
    private var block = ""
    private var calls = 0
    var usedSession: Set<String> = []

    init(profile: Profile, week: Int, seed: UInt32) {
        self.profile = profile
        self.week = week
        self.seed = seed
        deload = week == Rules.mesocycleWeeks
        let variety = profile.planVariety
        self.variety = variety
        // `.same`: one RNG stream for every week → identical picks; otherwise picks vary by week.
        rng = Rng(seed: variety == .same ? seed : seed &+ UInt32(week) &* 7919)
        mainRng = Rng(seed: seed ^ 0x9E37_79B9)
        level = profile.experience.level
        equipment = Set(profile.equipment)
        frequentClimber = profile.climbingDaysPerWeek >= 2
        climber = profile.goal == .climbing || profile.climbingDaysPerWeek >= 1
    }
}

extension Ctx {
    /// Starts a block's pick keys; `uid` is the block uid ("w1s2-st"), the week part is dropped.
    func begin(_ uid: String) {
        block = String(uid.drop(while: { $0 != "s" }))
        calls = 0
    }

    func nextKey() -> String {
        calls += 1
        return "\(block)#\(calls)"
    }

    /// Marks a pick used for this session / week (and as a main lift) and records it.
    func use(_ e: Exercise, main: Bool, key: String) -> Exercise {
        if main { usedMain.insert(e.id) }
        usedSession.insert(e.id)
        usedWeek.insert(e.id)
        picks[key] = e.id
        return e
    }

    /// Mobility drill paired into a strength rest: random, or week 1's when replaying (none if it no longer fits).
    func pickPaired(_ pool: [Exercise]) -> Exercise? {
        let key = nextKey()
        let pick: Exercise?
        if let replay { pick = pool.first { $0.id == replay[key] } } else { pick = rng.pick(pool) }
        if let pick { picks[key] = pick.id }
        return pick
    }
}

enum Selector {
    static func isAvailable(_ e: Exercise, _ equipment: Set<Equipment>) -> Bool {
        e.equipment.allSatisfy { equipment.contains($0) }
    }

    static func candidates(level: Int, equipment: Set<Equipment>, _ q: Query) -> [Exercise] {
        Exercise.catalog.filter { e in
            (e.generator || (Exercise.travelIds.contains(e.id) && isTravelKit(equipment)))
                && e.category == q.category
                && (q.pattern == nil || e.pattern == q.pattern)
                && (q.regions == nil || e.regions.contains { q.regions!.contains($0) })
                && e.level <= level
                && isAvailable(e, equipment)
        }
    }

    /// Best-scoring candidate, random tie-break. Marks it used.
    static func select(_ ctx: Ctx, _ q: Query) -> Exercise? {
        let pool = candidates(level: ctx.level, equipment: ctx.equipment, q).filter { !ctx.usedSession.contains($0.id) }
        let key = ctx.nextKey()
        guard !pool.isEmpty else { return nil }
        if let replay = ctx.replay {
            guard let e = pool.first(where: { $0.id == replay[key] }) else { return nil }
            return ctx.use(e, main: q.main, key: key)
        }
        func score(_ e: Exercise) -> Double {
            var s = 0.0
            if q.main && e.main { s += 8 }
            // Intermediate+ main lifts: favour free-weight compounds over machines.
            if q.main && ctx.level >= 2 && e.level >= 2 { s += 1.5 }
            if let i = q.prefer.firstIndex(of: e.id) { s += 4 - Double(min(3, i)) * 0.5 }
            if ctx.spareGrip && !e.gripHeavy { s += 2 }
            if !(q.main ? ctx.usedMain : ctx.usedWeek).contains(e.id) { s += 1 }
            if let r = q.regions { s += 0.5 * Double(e.regions.filter { r.contains($0) }.count) }
            return s
        }
        let scores = pool.map(score)
        let best = scores.max()!
        let top = zip(pool, scores).filter { $0.1 >= best - 1e-9 }.map(\.0)
        return ctx.use(q.main ? ctx.mainRng.pick(top) : ctx.rng.pick(top), main: q.main, key: key)
    }
}

extension Exercise {
    /// Swap options: same role (pattern / target muscle / region), available, level-appropriate.
    public func alternatives(for profile: Profile) -> [Exercise] {
        let pool = Selector.candidates(level: profile.experience.level, equipment: Set(profile.equipment), Query(category: category))
            .filter { $0.id != id }
        switch category {
        case .strength, .power: return pool.filter { $0.pattern == pattern }
        case .stretch: return pool.filter { $0.primary.contains { primary.contains($0) } }
        case .mobility, .warmup: return pool.filter { $0.regions.contains { regions.contains($0) } }
        case .cardio: return pool
        }
    }
}
