import Foundation

// MARK: - Learned exercise taste (#299)

/// Something the member did that says how they feel about an exercise.
public enum TasteSignal: Sendable, Equatable {
    /// Picked as a replacement (`kept`: for that day in future weeks too).
    case swappedIn(kept: Bool)
    /// Replaced by another exercise.
    case swappedOut(kept: Bool)
    /// Added to a workout before starting it.
    case added
    /// Removed from a workout before starting it.
    case removed
    /// Left at 0 sets while a later exercise of the same workout was done.
    case skipped
    /// Every planned set done.
    case finished
}

/// Decayed signal amounts for one exercise, as of `at`.
public struct ExerciseTaste: Codable, Hashable, Sendable {
    /// Swapped in / added (a kept swap counts 1.5).
    public var chosen: Double = 0
    /// Swapped away / removed (a kept swap counts 1.5).
    public var dropped: Double = 0
    public var skipped: Double = 0
    public var finished: Double = 0
    /// What the member said on What Monkey learned; overrides the learned score.
    public var mark: TasteMark?
    public var at: Date

    public init(at: Date) { self.at = at }

    func decayed(to now: Date) -> ExerciseTaste {
        let days = max(0, now.timeIntervalSince(at) / 86_400)
        guard days > 0 else { return self }
        let f = pow(0.5, days / MemberTaste.halfLifeDays)
        var t = self
        t.chosen *= f; t.dropped *= f; t.skipped *= f; t.finished *= f
        t.at = now
        return t
    }

    /// Positive = liked, negative = disliked. Finishing sets adds a little, capped so one swap still counts.
    var raw: Double {
        chosen - dropped - 0.5 * skipped + min(0.6, 0.15 * finished)
    }

    var weight: Double { chosen + dropped + skipped + finished + (mark == nil ? 0 : 1) }
}

/// The member's own word on an exercise (#299).
public enum TasteMark: String, Codable, Sendable {
    /// Never suggest: out of every generated plan when anything else fits.
    case never
    /// "Actually, I like it": counts as liked.
    case liked
}

/// What the app learned about the member's exercise likes and dislikes (#299): deterministic, explainable,
/// synced with the profile. Signals fade with a 60-day half-life, so tastes can change.
public struct MemberTaste: Codable, Hashable, Sendable {
    public var exercises: [String: ExerciseTaste] = [:]

    public static let halfLifeDays = 60.0
    /// Exercises kept; the faintest go first.
    static let maxEntries = 300
    /// Affinity at or below which an exercise counts as disliked: plan templates' favourites lose their bonus
    /// and plan variations leave it out when there is another option.
    public static let dislikeThreshold = -1.5

    public init() {}

    public var isEmpty: Bool { exercises.isEmpty }

    public mutating func record(_ id: String, _ signal: TasteSignal, at now: Date) {
        var t = exercises[id]?.decayed(to: now) ?? ExerciseTaste(at: now)
        switch signal {
        case .swappedIn(let kept): t.chosen += kept ? 1.5 : 1
        case .swappedOut(let kept): t.dropped += kept ? 1.5 : 1
        case .added: t.chosen += 1
        case .removed: t.dropped += 1
        case .skipped: t.skipped += 1
        case .finished: t.finished += 1
        }
        exercises[id] = t
        prune(at: now)
    }

    /// Score added to the generator's pick score: up to +0.9 for liked (just below the "not used yet this week"
    /// bonus, so variety still wins), down to -3 for disliked (two swaps away already beat freshness).
    public func affinity(_ id: String, at now: Date) -> Double {
        guard let t = exercises[id] else { return 0 }
        switch t.mark {
        case .never: return Self.never
        case .liked: return 0.9
        case nil: break
        }
        let r = t.decayed(to: now).raw
        let a = r > 0 ? min(0.9, 0.3 * r) : max(-3, 0.75 * r)
        return (a * 100).rounded() / 100
    }

    /// Non-zero affinities: what a week's plan is generated with.
    public func affinities(at now: Date) -> [String: Double] {
        var out: [String: Double] = [:]
        for id in exercises.keys {
            let a = affinity(id, at: now)
            if a != 0 { out[id] = a }
        }
        return out
    }

    /// Most liked first.
    public func liked(at now: Date) -> [String] {
        affinities(at: now).filter { $0.value > 0 }.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }

    /// Most disliked first.
    public func disliked(at now: Date) -> [String] {
        affinities(at: now).filter { $0.value < 0 }.sorted { ($0.value, $0.key) < ($1.value, $1.key) }.map(\.key)
    }

    /// Forgets one exercise (the member says the app got it wrong).
    public mutating func forget(_ id: String) { exercises[id] = nil }

    /// Affinity of a "Never suggest" exercise: far below anything learned, so it is only picked when nothing else fits.
    public static let never = -10.0

    public mutating func mark(_ id: String, _ mark: TasteMark, at now: Date) {
        var t = exercises[id]?.decayed(to: now) ?? ExerciseTaste(at: now)
        t.mark = mark
        exercises[id] = t
    }

    public func mark(_ id: String) -> TasteMark? { exercises[id]?.mark }

    /// Why the app thinks so, for What Monkey learned: "Swapped out or removed 2× · finished 8×".
    public func reason(_ id: String, at now: Date) -> String {
        guard let t = exercises[id]?.decayed(to: now) else { return "" }
        var parts: [String] = []
        switch t.mark {
        case .never: parts.append("You said never")
        case .liked: parts.append("You said you like it")
        case nil: break
        }
        func add(_ v: Double, _ label: String) {
            let n = Int(v.rounded())
            if n >= 1 { parts.append("\(label) \(n)×") }
        }
        add(t.chosen, "Picked")
        add(t.dropped, "Swapped out or removed")
        add(t.skipped, "Skipped")
        add(t.finished, "Finished")
        guard !parts.isEmpty else { return "A while ago" }
        return parts.enumerated().map { $0.offset == 0 ? $0.element : $0.element.lowercased() }.joined(separator: " · ")
    }

    private mutating func prune(at now: Date) {
        exercises = exercises.filter { $0.value.mark != nil || $0.value.decayed(to: now).weight >= 0.05 }
        guard exercises.count > Self.maxEntries else { return }
        let keep = exercises.sorted { ($0.value.decayed(to: now).weight, $0.key) > ($1.value.decayed(to: now).weight, $1.key) }
            .prefix(Self.maxEntries)
        exercises = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }
}

extension MemberTaste {
    /// A finished workout: exercises done in full are a small plus; one left at 0 sets while a later one was
    /// done was skipped on purpose. Exercises not reached (stopped early) say nothing.
    public mutating func learn(from workout: WorkoutRecord) {
        let now = workout.endedAt
        let items = workout.exercises
        let lastDone = items.lastIndex { $0.setsDone > 0 }
        for (i, e) in items.enumerated() {
            if e.setsDone >= max(1, e.setsPlanned) {
                record(e.exerciseId, .finished, at: now)
            } else if e.setsDone == 0, let lastDone, i < lastDone {
                record(e.exerciseId, .skipped, at: now)
            }
        }
    }

    /// An edit of a workout's exercise list before starting (#295), `before` → `after`: same item with another
    /// exercise is a swap, a missing item was removed, a new one added. Undoing an edit cancels it out.
    public mutating func learn(edit before: [Block], _ after: [Block], at now: Date) {
        let old = Dictionary(before.flatMap(\.items).map { ($0.uid, $0.exerciseId) }, uniquingKeysWith: { a, _ in a })
        let new = Dictionary(after.flatMap(\.items).map { ($0.uid, $0.exerciseId) }, uniquingKeysWith: { a, _ in a })
        for (uid, id) in old.sorted(by: { $0.key < $1.key }) {
            if let to = new[uid] {
                guard to != id else { continue }
                record(id, .swappedOut(kept: false), at: now)
                record(to, .swappedIn(kept: false), at: now)
            } else {
                record(id, .removed, at: now)
            }
        }
        for (uid, id) in new.sorted(by: { $0.key < $1.key }) where old[uid] == nil {
            record(id, .added, at: now)
        }
    }

    /// A swap in the plan (#101): `from` → `to`.
    public mutating func learn(swap from: String, to: String, kept: Bool, at now: Date) {
        guard from != to else { return }
        record(from, .swappedOut(kept: kept), at: now)
        record(to, .swappedIn(kept: kept), at: now)
    }
}

extension Profile {
    /// Learned affinity of an exercise in this week's plan (#299); 0 when nothing was learned.
    func taste(_ id: String) -> Double { learnedTaste?[id] ?? 0 }

    func dislikes(_ id: String) -> Bool { taste(id) <= MemberTaste.dislikeThreshold }
}

// MARK: - New-week recap (#299)

/// One way a new week's plan differs because of what the app learned.
public struct TasteChange: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// `from` left out (disliked), `to` in its place.
        case out
        /// `to` picked because the member likes it.
        case more
    }

    public var kind: Kind
    public var from: String
    public var to: String
    /// Workouts of the week it changed in.
    public var workouts: Int
    /// The exercise the change is about: undoing it forgets this one.
    public var subject: String { kind == .out ? from : to }
    public var id: String { "\(kind.rawValue)-\(subject)" }

    public init(kind: Kind, from: String, to: String, workouts: Int = 1) {
        self.kind = kind
        self.from = from
        self.to = to
        self.workouts = workouts
    }
}

/// What the coach tells the member when a new week is made with learned tastes.
public struct TasteRecap: Codable, Hashable, Sendable {
    public var week: Int
    public var changes: [TasteChange]

    public init(week: Int, changes: [TasteChange]) {
        self.week = week
        self.changes = changes
    }
}

extension WeekPlan {
    /// How this plan (made with `taste`) differs from `plain` (made without), item by item: a disliked exercise
    /// left out, or a liked one brought in. Knock-on changes (a pick freed up elsewhere) are left out.
    /// One change per exercise, left-out ones first; at most `limit`.
    public func tasteChanges(from plain: WeekPlan, taste: [String: Double], limit: Int = 5) -> [TasteChange] {
        var before: [String: String] = [:]
        for s in plain.sessions { for b in s.blocks { for it in b.items { before[it.uid] = it.exerciseId } } }
        var out: [TasteChange] = []
        var more: [TasteChange] = []
        for s in sessions {
            for b in s.blocks {
                for it in b.items {
                    guard let was = before[it.uid], was != it.exerciseId else { continue }
                    if (taste[was] ?? 0) < 0 {
                        if let i = out.firstIndex(where: { $0.from == was }) { out[i].workouts += 1 } else {
                            out.append(TasteChange(kind: .out, from: was, to: it.exerciseId))
                        }
                    } else if (taste[it.exerciseId] ?? 0) > 0 {
                        if let i = more.firstIndex(where: { $0.to == it.exerciseId }) { more[i].workouts += 1 } else {
                            more.append(TasteChange(kind: .more, from: was, to: it.exerciseId))
                        }
                    }
                }
            }
        }
        return Array((out + more).prefix(limit))
    }
}
