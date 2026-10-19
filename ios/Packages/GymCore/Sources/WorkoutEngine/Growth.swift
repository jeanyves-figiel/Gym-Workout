import Foundation

// MARK: - Block review (#495, option A)

/// One main lift's best estimated 1RM in the block just finished vs the block before.
public struct LiftChange: Codable, Hashable, Sendable, Identifiable {
    public var exerciseId: String
    public var beforeKg: Double
    public var afterKg: Double
    public var id: String { exerciseId }
    /// 0.08 = +8 %.
    public var change: Double { beforeKg > 0 ? afterKg / beforeKg - 1 : 0 }

    public init(exerciseId: String, beforeKg: Double, afterKg: Double) {
        self.exerciseId = exerciseId
        self.beforeKg = beforeKg
        self.afterKg = afterKg
    }
}

/// A lift whose estimated 1RM stayed flat for `weeks` weekly bests.
public struct Plateau: Codable, Hashable, Sendable, Identifiable {
    public var exerciseId: String
    public var weeks: Int
    /// Variation the next block swaps in; nil when none fits the gym.
    public var swapTo: String?
    public var id: String { exerciseId }

    public init(exerciseId: String, weeks: Int, swapTo: String?) {
        self.exerciseId = exerciseId
        self.weeks = weeks
        self.swapTo = swapTo
    }
}

/// What the 4-week block just finished brought, and what the next one changes.
public struct BlockReview: Codable, Hashable, Sendable {
    /// Monday the block began (`PlanCalendar.key`).
    public var blockKey: String
    /// 1 = the member's first reviewed block.
    public var number: Int
    public var sessionsDone: Int
    public var sessionsPlanned: Int
    public var lifts: [LiftChange]
    public var plateaus: [Plateau]
    /// Growth level after this review (before: `level - 1` on a level up).
    public var level: Int
    public var levelUp: Bool
    /// Experience the level up moves to, when it crosses a threshold.
    public var experience: Experience?
    /// Muscle group behind its counterpart, and that counterpart.
    public var lagging: MuscleGroup?
    public var laggingVs: MuscleGroup?
    /// Logged sets ended with 3+ reps in reserve on average.
    public var easyEffort: Bool

    public var adherence: Double { sessionsPlanned > 0 ? Double(sessionsDone) / Double(sessionsPlanned) : 0 }
    /// Mean change of the main lifts; nil without lifts in both blocks.
    public var strengthChange: Double? {
        lifts.isEmpty ? nil : lifts.map(\.change).reduce(0, +) / Double(lifts.count)
    }
    /// Nothing to change: no level up, plateau or lagging muscle.
    public var hasChanges: Bool { levelUp || !plateaus.isEmpty || lagging != nil }
}

/// The member's growth over blocks: level, block reviews, long-term goal (#495).
public enum Growth {
    public static let blockWeeks = Generator.mesocycleWeeks
    /// Adherence and strength gain a block needs to level up.
    static let levelUpAdherence = 0.75
    static let levelUpGain = 0.02
    /// Lagging: under 70 % of the counterpart's sets.
    static let laggingRatio = 0.7

    /// Experience a growth level stands for: level 3 → intermediate, 6 → advanced.
    public static func experience(forLevel level: Int) -> Experience {
        level >= 6 ? .advanced : level >= 3 ? .intermediate : .beginner
    }

    /// First growth level for a member: the start of their experience band.
    public static func startLevel(_ e: Experience) -> Int {
        switch e {
        case .beginner: 1
        case .intermediate: 3
        case .advanced: 6
        }
    }

    /// Reviews the block that began on `blockStart` (4 weeks) against the 4 weeks before it.
    /// `rirs`: reps in reserve of the block's logged sets. Nil when fewer than 2 workouts were done in the block.
    public static func review(
        records: [WorkoutRecord], blockStart: Date, profile: Profile, level: Int, number: Int,
        rirs: [Int] = [], calendar cal: Calendar = Progression.calendar()
    ) -> BlockReview? {
        guard let end = cal.date(byAdding: .day, value: 7 * blockWeeks, to: blockStart),
              let before = cal.date(byAdding: .day, value: -7 * blockWeeks, to: blockStart) else { return nil }
        let block = records.filter { $0.startedAt >= blockStart && $0.startedAt < end }
        guard block.count >= 2 else { return nil }
        let previous = records.filter { $0.startedAt >= before && $0.startedAt < blockStart }

        func best(_ rs: [WorkoutRecord]) -> [String: Double] {
            var out: [String: Double] = [:]
            for r in rs where !r.deload {
                for e in r.exercises where e.setsDone > 0 {
                    if let orm = e.estimatedOneRepMax { out[e.exerciseId] = max(out[e.exerciseId] ?? 0, orm) }
                }
            }
            return out
        }
        let now = best(block), then = best(previous)
        let lifts = now.compactMap { id, kg -> LiftChange? in
            guard Exercise.find(id)?.main == true, let b = then[id], b > 0 else { return nil }
            return LiftChange(exerciseId: id, beforeKg: b, afterKg: kg)
        }
        .sorted { $0.afterKg > $1.afterKg }

        let upToEnd = records.filter { $0.startedAt < end && !$0.deload }
        let strengthIds = Set(block.flatMap(\.exercises).filter { $0.category == .strength && $0.setsDone > 0 }.map(\.exerciseId))
        let plateaus = strengthIds.sorted().compactMap { id -> Plateau? in
            guard let weeks = flatWeeks(Progression.oneRepMaxTrend(id, records: upToEnd, calendar: cal), since: blockStart) else { return nil }
            let swap = Exercise.find(id)?.swapOptions(for: profile).first?.id
            return Plateau(exerciseId: id, weeks: weeks, swapTo: swap)
        }
        .sorted { $0.weeks > $1.weeks }

        let done = block.count
        let planned = max(1, profile.sessionsPerWeek * blockWeeks)
        let gains: Double? = lifts.isEmpty ? nil : lifts.map(\.change).reduce(0, +) / Double(lifts.count)
        let levelUp = Double(done) / Double(planned) >= levelUpAdherence && (gains ?? 0) >= levelUpGain
        let newLevel = level + (levelUp ? 1 : 0)
        let e = experience(forLevel: newLevel)
        let lag = lagging(block, profile: profile)
        let easy = rirs.count >= 6 && Double(rirs.reduce(0, +)) / Double(rirs.count) >= 3

        return BlockReview(
            blockKey: PlanCalendar.key(blockStart, cal), number: number, sessionsDone: done, sessionsPlanned: planned,
            lifts: Array(lifts.prefix(4)), plateaus: Array(plateaus.prefix(2)), level: newLevel, levelUp: levelUp,
            experience: levelUp && e.level > profile.experience.level ? e : nil,
            lagging: lag?.0, laggingVs: lag?.1, easyEffort: easy)
    }

    /// Weekly bests that stayed within 1 % of the best before them: 3 or more, all since `since`, else nil.
    static func flatWeeks(_ trend: [(Date, Double)], since: Date) -> Int? {
        guard trend.count >= 4 else { return nil }
        var flat = 0
        for i in stride(from: trend.count - 1, through: 1, by: -1) {
            let earlierBest = trend[..<i].map { $0.1 }.max() ?? 0
            guard trend[i].1 <= earlierBest * 1.01, trend[i].0 >= since else { break }
            flat += 1
        }
        return flat >= 3 ? flat : nil
    }

    /// Hard sets per muscle group (primary muscles) of strength and power work.
    public static func groupSets(_ records: [WorkoutRecord]) -> [MuscleGroup: Int] {
        var out: [MuscleGroup: Int] = [:]
        for r in records {
            for e in r.exercises where e.setsDone > 0 && (e.category == .strength || e.category == .power) {
                guard let ex = Exercise.find(e.exerciseId) else { continue }
                for g in Set(ex.primary.map(\.group)) { out[g, default: 0] += e.setsDone }
            }
        }
        return out
    }

    /// The group furthest behind its counterpart (chest ↔ back, legs ↔ hips), when under 70 % and not focused yet.
    static func lagging(_ records: [WorkoutRecord], profile: Profile) -> (MuscleGroup, MuscleGroup)? {
        let sets = groupSets(records)
        let pairs: [(MuscleGroup, MuscleGroup)] = [(.back, .chest), (.chest, .back), (.hips, .legs), (.legs, .hips)]
        let focus = profile.focusGroups
        return pairs
            .filter { a, b in (sets[b] ?? 0) >= 12 && !focus.contains(a) && Double(sets[a] ?? 0) < Double(sets[b] ?? 0) * laggingRatio }
            .min { Double(sets[$0.0] ?? 0) / Double(sets[$0.1] ?? 1) < Double(sets[$1.0] ?? 0) / Double(sets[$1.1] ?? 1) }
    }
}

extension Profile {
    /// The profile for the next block: the level up's experience and the lagging muscle as a focus, when picked.
    public func growing(_ r: BlockReview, levelUp: Bool, focus: Bool) -> Profile {
        var p = self
        if levelUp, let e = r.experience { p.experience = e }
        if focus, let g = r.lagging {
            var f = p.focusMuscles ?? []
            if !f.contains(g) { f.append(g) }
            p.focusMuscles = f
        }
        return p
    }
}

// MARK: - Growth path (#495, option C)

/// A long-term strength goal: an estimated 1RM to reach on one lift.
public struct GrowthGoal: Codable, Hashable, Sendable {
    public var exerciseId: String
    public var targetKg: Double
    public var startKg: Double
    public var startDate: Date
    /// When the member saw it reached (and moved on).
    public var hitAt: Date?

    public init(exerciseId: String, targetKg: Double, startKg: Double, startDate: Date, hitAt: Date? = nil) {
        self.exerciseId = exerciseId
        self.targetKg = targetKg
        self.startKg = startKg
        self.startDate = startDate
        self.hitAt = hitAt
    }
}

/// One step on the road to a goal.
public struct GoalMilestone: Hashable, Sendable, Identifiable {
    public var kg: Double
    public var reachedAt: Date?
    public var predicted: Date?
    /// The goal after this one (shown, not yet set).
    public var beyond: Bool
    public var id: Double { kg }
}

/// Where a goal stands, from the lift's weekly best estimated 1RM.
public struct GoalStatus: Hashable, Sendable {
    public var currentKg: Double?
    /// 0…1 from the start to the target.
    public var progress: Double
    /// When the trend reaches the target; nil when flat, falling or under 3 weeks of data.
    public var predicted: Date?
    public var kgPerWeek: Double?
    public var milestones: [GoalMilestone]
    public var reached: Bool
}

extension GrowthGoal {
    /// Goal weights round to 2.5 kg.
    public static func round(_ kg: Double) -> Double { (kg / 2.5).rounded() * 2.5 }
    static func roundUp5(_ kg: Double) -> Double { (kg / 5).rounded(.up) * 5 }

    /// The next target after this one: about 8 % more, a multiple of 5.
    public var nextTargetKg: Double {
        let t = Self.roundUp5(targetKg * 1.08)
        return t > targetKg ? t : targetKg + 5
    }

    /// The goal after this one is reached, starting now.
    public func next(now: Date = Date()) -> GrowthGoal {
        GrowthGoal(exerciseId: exerciseId, targetKg: nextTargetKg, startKg: targetKg, startDate: now)
    }

    public func status(records: [WorkoutRecord], now: Date = Date(), calendar cal: Calendar = Progression.calendar()) -> GoalStatus {
        let trend = Progression.oneRepMaxTrend(exerciseId, records: records.filter { !$0.deload && $0.startedAt <= now }, calendar: cal)
        let current = trend.last?.1
        let span = max(0.1, targetKg - startKg)
        let progress = min(1, max(0, ((current ?? startKg) - startKg) / span))
        let reached = (current ?? 0) >= targetKg

        // Least squares over the last 8 weeks' weekly bests.
        let since = cal.date(byAdding: .day, value: -56, to: now) ?? now
        let recent = trend.filter { $0.0 >= since }
        var perDay: Double?
        if recent.count >= 3 {
            let xs = recent.map { $0.0.timeIntervalSince(recent[0].0) / 86_400 }
            let ys = recent.map { $0.1 }
            let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
            let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
            if sxx > 0 {
                let slope = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / sxx
                if slope > 0.001 { perDay = slope }
            }
        }
        func predict(_ kg: Double) -> Date? {
            guard let perDay, let current, kg > current else { return nil }
            return cal.date(byAdding: .day, value: Int(((kg - current) / perDay).rounded(.up)), to: now)
        }
        let mid = Self.round(startKg + (targetKg - startKg) / 2)
        let kgs = [Self.round(startKg), mid, targetKg].reduce(into: [Double]()) { if !$0.contains($1) { $0.append($1) } }
        var milestones = kgs.map { kg in
            GoalMilestone(kg: kg, reachedAt: kg <= startKg ? Optional(startDate) : trend.first { $0.1 >= kg }?.0, predicted: predict(kg), beyond: false)
        }
        milestones.append(GoalMilestone(kg: nextTargetKg, reachedAt: nil, predicted: predict(nextTargetKg), beyond: true))
        return GoalStatus(currentKg: current, progress: progress, predicted: reached ? nil : predict(targetKg),
                          kgPerWeek: perDay.map { $0 * 7 }, milestones: milestones, reached: reached)
    }

    /// A first goal: the main lift with the most weekly bests in the last 8 weeks (3 or more), about 10 % above
    /// its current estimated 1RM.
    public static func suggest(records: [WorkoutRecord], now: Date = Date(), calendar cal: Calendar = Progression.calendar()) -> GrowthGoal? {
        let since = cal.date(byAdding: .day, value: -56, to: now) ?? now
        let recent = records.filter { $0.startedAt >= since && $0.startedAt <= now && !$0.deload }
        let ids = Set(recent.flatMap(\.exercises).filter { $0.setsDone > 0 && $0.estimatedOneRepMax != nil }.map(\.exerciseId))
            .filter { Exercise.find($0)?.main == true }
        let picks = ids.map { id in (id, Progression.oneRepMaxTrend(id, records: recent, calendar: cal)) }
            .filter { $0.1.count >= 3 }
            .sorted { a, b in
                if a.1.count != b.1.count { return a.1.count > b.1.count }
                let ka = a.1.last?.1 ?? 0, kb = b.1.last?.1 ?? 0
                return ka != kb ? ka > kb : a.0 < b.0
            }
        guard let pick = picks.first, let current = pick.1.last?.1 else { return nil }
        return GrowthGoal(exerciseId: pick.0, targetKg: roundUp5(current * 1.1), startKg: round(current), startDate: now)
    }
}

// MARK: - What Monkey noticed (#495, option C)

/// One weekly observation, with what tapping its action does.
public struct Insight: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// Rests longer than planned.
        case longRests
        /// A gym day mostly skipped; `weekday` → `toWeekday` moves it.
        case skippedDay
        /// The growth goal was reached; the action sets the next one.
        case goalHit
        /// A major muscle group had no sets in 2 weeks; the action adds it as a focus.
        case untrained
        /// New best lifts this week.
        case bests
    }

    public var kind: Kind
    public var title: String
    public var detail: String
    /// Big value on the right, e.g. "+80s", "4/5".
    public var value: String
    public var weekday: Int?
    public var toWeekday: Int?
    public var group: MuscleGroup?
    public var id: String {
        [kind.rawValue, weekday.map { "\($0)" }, group?.rawValue].compactMap { $0 }.joined(separator: "-")
    }

    public init(kind: Kind, title: String, detail: String, value: String, weekday: Int? = nil, toWeekday: Int? = nil, group: MuscleGroup? = nil) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.value = value
        self.weekday = weekday
        self.toWeekday = toWeekday
        self.group = group
    }
}

public enum Noticed {
    static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// "3:20".
    static func clock(_ sec: Int) -> String { "\(sec / 60):" + String(format: "%02d", sec % 60) }

    /// The week's observations (last 7 days, history back 5 weeks), most useful first, at most 4.
    /// `plannedRest`: rest seconds per exercise in the plan (120 s when unknown).
    public static func week(
        records: [WorkoutRecord], sets: [SetLog], profile: Profile, goal: GrowthGoal?, plannedRest: [String: Int] = [:],
        now: Date = Date(), calendar cal: Calendar = Progression.calendar()
    ) -> [Insight] {
        var out: [Insight] = []
        if let goal, goal.hitAt == nil, let ex = Exercise.find(goal.exerciseId) {
            let st = goal.status(records: records, now: now, calendar: cal)
            if st.reached, let kg = st.currentKg {
                out.append(Insight(kind: .goalHit, title: "\(ex.name) goal hit",
                                   detail: "\(GoalFormat.kg(goal.targetKg)) reached · next: \(GoalFormat.kg(goal.nextTargetKg))",
                                   value: GoalFormat.kg(kg)))
            }
        }
        if let i = skippedDay(records: records, profile: profile, now: now, calendar: cal) { out.append(i) }
        if let i = longRests(sets: sets, plannedRest: plannedRest, now: now) { out.append(i) }
        if let i = untrained(records: records, now: now, calendar: cal) { out.append(i) }
        if let i = bests(records: records, now: now, calendar: cal) { out.append(i) }
        return Array(out.prefix(4))
    }

    /// A gym weekday trained in at most 1 of the last 5 weeks while the member trained in 3 or more of them.
    static func skippedDay(records: [WorkoutRecord], profile: Profile, now: Date, calendar cal: Calendar) -> Insight? {
        guard let days = profile.gymWeekdays, !days.isEmpty else { return nil }
        let thisMonday = Progression.weekStart(now, cal)
        guard let from = cal.date(byAdding: .day, value: -35, to: thisMonday) else { return nil }
        let past = records.filter { $0.startedAt >= from && $0.startedAt < thisMonday }
        let weeks = Set(past.map { Progression.weekStart($0.startedAt, cal) })
        guard weeks.count >= 3 else { return nil }
        var perDay: [Int: Set<Date>] = [:]
        for r in past {
            perDay[WeekSchedule.fromCalendar(cal.component(.weekday, from: r.startedAt)), default: []].insert(Progression.weekStart(r.startedAt, cal))
        }
        let count: (Int) -> Int = { perDay[$0]?.count ?? 0 }
        guard let day = days.sorted().first(where: { count($0) <= 1 }) else { return nil }
        let blocked = Set(days).union(profile.climbingWeekdays ?? [])
        let to = WeekSchedule.weekdays.filter { !blocked.contains($0) && count($0) >= 2 }
            .max { count($0) != count($1) ? count($0) < count($1) : abs($0 - day) > abs($1 - day) }
        let name = dayNames[day - 1]
        let skipped = 5 - count(day)
        return Insight(kind: .skippedDay, title: "\(name)s get skipped",
                       detail: to.map { "\(skipped) of 5 weeks · move to \(dayNames[$0 - 1])?" } ?? "\(skipped) of 5 weeks · a better day?",
                       value: "\(skipped)/5", weekday: day, toWeekday: to)
    }

    /// Average rest between sets of the last 7 days more than 60 s over the plan (6 gaps or more).
    static func longRests(sets: [SetLog], plannedRest: [String: Int], now: Date) -> Insight? {
        let recent = sets.filter { $0.date <= now && now.timeIntervalSince($0.date) < 7 * 86_400 }
        let groups = Dictionary(grouping: recent) { "\($0.sessionId ?? "-")|\($0.exerciseId)" }
        var gaps: [Double] = [], plans: [Double] = []
        for (_, list) in groups {
            let sorted = list.sorted { $0.date < $1.date }
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                let gap = b.date.timeIntervalSince(a.date)
                // Sets logged together afterwards, or a break between visits, say nothing about rest.
                guard gap >= 20, gap <= 15 * 60 else { continue }
                gaps.append(gap)
                plans.append(Double(plannedRest[b.exerciseId] ?? 120))
            }
        }
        guard gaps.count >= 6 else { return nil }
        let avg = gaps.reduce(0, +) / Double(gaps.count), plan = plans.reduce(0, +) / Double(plans.count)
        let extra = Int((avg - plan).rounded())
        guard extra > 60 else { return nil }
        return Insight(kind: .longRests, title: "Rests run long",
                       detail: "Avg \(clock(Int(avg.rounded()))) vs \(clock(Int(plan.rounded()))) planned · the rest timer helps",
                       value: "+\(extra)s")
    }

    /// A major group with no hard sets in 14 days while 3 or more workouts were done.
    static func untrained(records: [WorkoutRecord], now: Date, calendar cal: Calendar) -> Insight? {
        guard let from = cal.date(byAdding: .day, value: -14, to: now) else { return nil }
        let recent = records.filter { $0.startedAt >= from && $0.startedAt <= now }
        guard recent.count >= 3 else { return nil }
        let sets = Growth.groupSets(recent)
        guard let g = [MuscleGroup.chest, .back, .legs, .hips, .shoulders].first(where: { (sets[$0] ?? 0) == 0 }) else { return nil }
        return Insight(kind: .untrained, title: "No \(g.label.lowercased()) for 2 weeks",
                       detail: "\(recent.count) workouts, none for \(g.label.lowercased()) · make it a focus?", value: "0", group: g)
    }

    /// Lifts whose best estimated 1RM of the last 7 days beats every earlier one.
    static func bests(records: [WorkoutRecord], now: Date, calendar cal: Calendar) -> Insight? {
        let from = now.addingTimeInterval(-7 * 86_400)
        var before: [String: Double] = [:], week: [String: Double] = [:]
        for r in records where r.startedAt <= now && !r.deload {
            for e in r.exercises where e.setsDone > 0 {
                guard let orm = e.estimatedOneRepMax else { continue }
                if r.startedAt >= from { week[e.exerciseId] = max(week[e.exerciseId] ?? 0, orm) }
                else { before[e.exerciseId] = max(before[e.exerciseId] ?? 0, orm) }
            }
        }
        let new = week.filter { id, kg in before[id].map { kg > $0 * 1.005 } ?? false }
        guard let top = new.max(by: { $0.value / (before[$0.key] ?? 1) < $1.value / (before[$1.key] ?? 1) }),
              let name = Exercise.find(top.key)?.name else { return nil }
        return Insight(kind: .bests, title: new.count == 1 ? "New best lift" : "\(new.count) new best lifts",
                       detail: "\(name) up to \(GoalFormat.kg(top.value)) est. 1RM", value: "\(new.count)")
    }
}

/// "72.5 kg", "80 kg".
public enum GoalFormat {
    public static func kg(_ v: Double) -> String {
        let r = GrowthGoal.round(v)
        return r == r.rounded() ? "\(Int(r)) kg" : String(format: "%.1f kg", r)
    }
}

// MARK: - Coach memory (#495, option C)

public enum CoachMemory {
    /// Facts the coach keeps about the member, for Ask Coach: what the app knows, then the member's own notes.
    public static func facts(
        profile: Profile, goal: GrowthGoal?, goalStatus: GoalStatus?, level: Int?, liked: [String], avoided: [String], notes: [String]
    ) -> [String] {
        var out: [String] = []
        if let goal, let ex = Exercise.find(goal.exerciseId) {
            let now = goalStatus?.currentKg.map { " (now \(GoalFormat.kg($0)))" } ?? ""
            out.append("Working toward \(ex.name) \(GoalFormat.kg(goal.targetKg)) est. 1RM\(now)")
        }
        if let level { out.append("Growth level \(level)") }
        if let days = profile.gymWeekdays, !days.isEmpty {
            out.append("Trains \(days.count)× a week: " + days.sorted().map { WeekSchedule.shortNames[$0 - 1] }.joined(separator: ", "))
        } else {
            out.append("Trains \(profile.sessionsPerWeek)× a week")
        }
        if let f = profile.focusMuscles, !f.isEmpty { out.append("Focus muscles: " + f.map(\.label).joined(separator: ", ")) }
        let likedNames = liked.prefix(3).compactMap { Exercise.find($0)?.name }
        if !likedNames.isEmpty { out.append("Likes " + likedNames.joined(separator: ", ")) }
        let avoidedNames = avoided.prefix(3).compactMap { Exercise.find($0)?.name }
        if !avoidedNames.isEmpty { out.append("Avoids " + avoidedNames.joined(separator: ", ")) }
        let sports = (profile.sports ?? []).filter(\.isOn).map(\.sport.label)
        if !sports.isEmpty { out.append("Also does " + sports.joined(separator: ", ")) }
        return out + notes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
