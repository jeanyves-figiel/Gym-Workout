import Foundation

/// Weekly Coach review (#867, design A + C from `ai-epic/a1.png`): on Sunday and Monday Train shows Coach's look at the
/// week just done (sessions, bests, sleep, mood) and up to 3 changes for the coming week, each applied with one tap.
/// The app sends a digest without identifiers; Coach may only name sessions and exercises from it, and every change is
/// checked again here before it is shown.
public struct WeekReviewDigest: Codable, Sendable, Equatable {
    /// One workout of the week under review.
    public struct Day: Codable, Sendable, Equatable {
        public var weekday: Int
        public var title: String
        public var done: Bool
        public var minutes: Int?

        public init(weekday: Int, title: String, done: Bool, minutes: Int? = nil) {
            self.weekday = weekday
            self.title = title
            self.done = done
            self.minutes = minutes
        }
    }

    /// One exercise of a coming workout.
    public struct Lift: Codable, Sendable, Equatable {
        public var uid: String
        public var name: String
        public var sets: Int

        public init(uid: String, name: String, sets: Int) {
            self.uid = uid
            self.name = name
            self.sets = sets
        }
    }

    /// One workout of the coming week, what the changes may touch.
    public struct Next: Codable, Sendable, Equatable {
        public var id: String
        public var weekday: Int
        public var title: String
        public var lifts: [Lift]

        public init(id: String, weekday: Int, title: String, lifts: [Lift]) {
            self.id = id
            self.weekday = weekday
            self.title = title
            self.lifts = lifts
        }
    }

    /// Monday of the week under review ("2026-10-26").
    public var weekOf: String
    public var goal: String?
    public var level: String?
    public var days: [Day]
    /// Bests of the week, e.g. "Bench press 85 kg (was 82.5)".
    public var bests: [String]
    public var sleepHours: Double?
    /// HRV against the member's 30-day baseline, e.g. "−8 % vs usual".
    public var hrv: String?
    /// Mood check-ins of the week, 1 (low) to 5 (great), average.
    public var mood: Double?
    /// What weighed on the mood most ("Work", "Sleep").
    public var moodAbout: [String]
    public var next: [Next]
    /// Weekdays of the coming week with no training possible (away, rest days kept free).
    public var offDays: [Int]

    public init(weekOf: String, goal: String? = nil, level: String? = nil, days: [Day], bests: [String] = [], sleepHours: Double? = nil,
                hrv: String? = nil, mood: Double? = nil, moodAbout: [String] = [], next: [Next], offDays: [Int] = []) {
        self.weekOf = weekOf
        self.goal = goal
        self.level = level
        self.days = days
        self.bests = bests
        self.sleepHours = sleepHours
        self.hrv = hrv
        self.mood = mood
        self.moodAbout = moodAbout
        self.next = next
        self.offDays = offDays
    }

    public var doneCount: Int { days.filter(\.done).count }
}

/// One change Coach suggests for the coming week.
public struct WeekReviewChange: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// The workout moves to `weekday`, that week only.
        case move
        /// The workout is skipped that week.
        case skip
        /// Every lift of the workout one set fewer (never under one).
        case lighter
        /// One set more on `uid` (its superset partners too).
        case addSet
    }

    public var kind: Kind
    public var sessionId: String
    public var weekday: Int?
    public var uid: String?
    /// Button line, e.g. "Move legs to Tue (you skip Thu)".
    public var label: String

    public var id: String { [kind.rawValue, sessionId, weekday.map(String.init) ?? "", uid ?? ""].joined(separator: ":") }

    public init(kind: Kind, sessionId: String, weekday: Int? = nil, uid: String? = nil, label: String) {
        self.kind = kind
        self.sessionId = sessionId
        self.weekday = weekday
        self.uid = uid
        self.label = label
    }
}

/// Coach's review of one week.
public struct WeekReview: Codable, Sendable, Equatable {
    public static let maxChanges = 3
    public static let maxSets = 8

    public var weekOf: String
    /// 0–100, how the week went.
    public var score: Int
    /// Card title line, e.g. "4 of 5 done · 2 PRs · sleep ↓".
    public var headline: String
    /// Two or three plain sentences.
    public var summary: String
    public var changes: [WeekReviewChange]

    public init(weekOf: String, score: Int, headline: String, summary: String, changes: [WeekReviewChange]) {
        self.weekOf = weekOf
        self.score = score
        self.headline = headline
        self.summary = summary
        self.changes = changes
    }

    /// Keeps only changes the app can make on the digest's coming week: known workout and lift, a free other day,
    /// one change per workout and kind, at most `maxChanges`; text trimmed, score 0–100.
    public func cleaned(for digest: WeekReviewDigest) -> WeekReview {
        var seen = Set<String>()
        var moved = Set<Int>()
        let taken = Set(digest.next.map(\.weekday))
        let kept = changes.compactMap { c -> WeekReviewChange? in
            guard let s = digest.next.first(where: { $0.id == c.sessionId }) else { return nil }
            var c = c
            c.label = String(c.label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
            guard !c.label.isEmpty else { return nil }
            switch c.kind {
            case .move:
                guard let wd = c.weekday, (1...7).contains(wd), wd != s.weekday, !digest.offDays.contains(wd),
                      !taken.contains(wd), !moved.contains(wd) else { return nil }
                c.uid = nil
            case .skip, .lighter:
                c.weekday = nil
                c.uid = nil
            case .addSet:
                guard let uid = c.uid, let lift = s.lifts.first(where: { $0.uid == uid }), lift.sets < Self.maxSets else { return nil }
                c.weekday = nil
            }
            let key = "\(c.sessionId):\(c.kind == .addSet ? c.uid ?? "" : c.kind.rawValue)"
            guard !seen.contains(key) else { return nil }
            // A skipped workout takes no other change.
            if c.kind == .skip, seen.contains(where: { $0.hasPrefix("\(c.sessionId):") }) { return nil }
            if c.kind != .skip, seen.contains("\(c.sessionId):skip") { return nil }
            seen.insert(key)
            if c.kind == .move, let wd = c.weekday { moved.insert(wd) }
            return c
        }
        return WeekReview(weekOf: weekOf, score: min(100, max(0, score)),
                          headline: String(headline.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)),
                          summary: String(summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400)),
                          changes: Array(kept.prefix(Self.maxChanges)))
    }

    /// Sunday and Monday: the week just done gets its review (Sunday: this week; Monday: last week).
    public static func reviewedWeek(on date: Date, calendar: Calendar) -> Date? {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
        let monday = Progression.weekStart(date, calendar)
        switch weekday {
        case 1: return monday
        case 2: return calendar.date(byAdding: .day, value: -7, to: monday)
        default: return nil
        }
    }
}

extension [Block] {
    /// Weekly review "lighter" (#867): every strength and power lift one set fewer, never under one; time follows.
    public func lighter() -> [Block] {
        map { b in
            guard b.kind == .strength || b.kind == .power else { return b }
            var b = b
            for i in b.items.indices { b.items[i].setSets(b.items[i].prescription.sets - 1) }
            return b
        }
    }

    /// Weekly review "+1 set" (#867): one set more on `uid` and its superset / circuit partners (rounds stay equal).
    public func addingSet(_ uid: String) -> [Block] {
        map { b in
            let members = Set(b.groupMembers(of: uid).map(\.uid))
            guard !members.isEmpty else { return b }
            var b = b
            for i in b.items.indices where members.contains(b.items[i].uid) {
                b.items[i].setSets(Swift.min(WeekReview.maxSets, b.items[i].prescription.sets + 1))
            }
            return b
        }
    }
}

extension PlannedExercise {
    /// New set count (at least one) with the time estimate scaled to it.
    mutating func setSets(_ n: Int) {
        let old = Swift.max(1, prescription.sets)
        let new = Swift.max(1, n)
        guard new != prescription.sets else { return }
        estSec = estSec * new / old
        prescription.sets = new
    }
}

extension WeekReviewDigest {
    /// Heaviest weight per lift in `[from, to)` above every earlier one: "Bench press 85 kg (was 82.5)", best gains first.
    public static func bests(records: [WorkoutRecord], from: Date, to: Date, limit: Int = 5) -> [String] {
        var before: [String: Double] = [:]
        var week: [String: Double] = [:]
        for r in records where r.startedAt < to {
            for e in r.exercises where e.setsDone > 0 {
                guard let kg = e.weightKg, kg > 0 else { continue }
                if r.startedAt >= from { week[e.exerciseId] = Swift.max(week[e.exerciseId] ?? 0, kg) } else { before[e.exerciseId] = Swift.max(before[e.exerciseId] ?? 0, kg) }
            }
        }
        let gains = week.compactMap { id, kg -> (String, Double, Double)? in
            guard let was = before[id], kg > was else { return nil }
            return (id, kg, was)
        }
        return gains.sorted { ($0.1 - $0.2, $0.0) > ($1.1 - $1.2, $1.0) }.prefix(limit).map { id, kg, was in
            String("\(Exercise.find(id)?.name ?? id) \(Self.kg(kg)) kg (was \(Self.kg(was)))".suffix(80))
        }
    }

    /// Mood check-ins in `[from, to)`: the average and what weighed on low days (mood ≤ 2) most, most often first.
    public static func mood(_ checkIns: [MindCheckIn], from: Date, to: Date) -> (average: Double?, about: [String]) {
        let week = checkIns.filter { $0.date >= from && $0.date < to }
        guard !week.isEmpty else { return (nil, []) }
        let avg = Double(week.map(\.mood).reduce(0, +)) / Double(week.count)
        var count: [MindFeeling: Int] = [:]
        for c in week where c.mood <= 2 { for f in c.feelings { count[f, default: 0] += 1 } }
        let about = count.sorted { ($0.value, $1.key.rawValue) > ($1.value, $0.key.rawValue) }.prefix(3).map(\.key.label)
        return ((avg * 10).rounded() / 10, Array(about))
    }

    /// The lifts of a coming workout (strength and power blocks) the review may change.
    public static func lifts(_ s: Session) -> [Lift] {
        s.blocks.filter { $0.kind == .strength || $0.kind == .power }.flatMap(\.items).filter { $0.supersetWith == nil }.prefix(20).map {
            Lift(uid: $0.uid, name: String((Exercise.find($0.exerciseId)?.name ?? $0.exerciseId).prefix(60)), sets: Swift.min(20, $0.prescription.sets))
        }
    }

    private static func kg(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}
