import Foundation

// MARK: - Streak shields (#501)

/// Week streak with shields (#501): one shield for every 4 goal weeks in a row, 2 held at most. A past week that
/// missed the goal uses a shield and the streak carries on; with none left it starts again. The week `through`
/// counts once its goal is met and never breaks the streak while it is still running.
public struct StreakRun: Sendable, Equatable {
    public static let weeksPerShield = 4
    public static let maxShields = 2

    public var current = 0
    public var best = 0
    /// Shields held now.
    public var shields = 0
    /// Past weeks a shield saved, oldest first.
    public var shielded: [Date] = []

    public init(current: Int = 0, best: Int = 0, shields: Int = 0, shielded: [Date] = []) {
        self.current = current
        self.best = best
        self.shields = shields
        self.shielded = shielded
    }

    /// `counts`: week start → sessions that week. Weeks before the first session don't count.
    public static func evaluate(counts: [Date: Int], target: Int, through week: Date,
                                calendar cal: Calendar = Progression.calendar()) -> StreakRun {
        var r = StreakRun()
        guard let first = counts.filter({ $0.value > 0 }).keys.min(), first <= week else { return r }
        let target = max(1, target)
        var cursor = first
        var sinceShield = 0
        while cursor <= week {
            if (counts[cursor] ?? 0) >= target {
                r.current += 1
                sinceShield += 1
                if sinceShield >= weeksPerShield {
                    sinceShield = 0
                    r.shields = min(maxShields, r.shields + 1)
                }
            } else if cursor < week {
                if r.current > 0 && r.shields > 0 {
                    r.shields -= 1
                    r.shielded.append(cursor)
                } else {
                    r.current = 0
                    sinceShield = 0
                }
            }
            r.best = max(r.best, r.current)
            guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return r
    }

    /// The week before `week` was saved by a shield.
    public func savedWeekBefore(_ week: Date, calendar cal: Calendar = Progression.calendar()) -> Bool {
        guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: week) else { return false }
        return shielded.contains(prev)
    }
}

// MARK: - Comeback quest (#501)

/// Comeback quest (#501): after `gapDays` or more without training, the first session back and the next ones within
/// `windowDays` of it, `sessions` in all, each earn `xpPerSession`. Loads ease on their own after a break (#156).
public struct Comeback: Sendable, Equatable {
    public static let gapDays = 10
    public static let sessions = 3
    public static let windowDays = 21
    public static let xpPerSession = 100

    /// Days without training before the first session back (or until now, before it).
    public var daysAway: Int
    /// Quest sessions done (0 before the first session back).
    public var done: Int
    /// Last day the quest counts sessions (nil before the first session back).
    public var endsAt: Date?

    public init(daysAway: Int, done: Int, endsAt: Date? = nil) {
        self.daysAway = daysAway
        self.done = done
        self.endsAt = endsAt
    }

    public var complete: Bool { done >= Self.sessions }
    public var xpEarned: Int { done * Self.xpPerSession }

    /// One quest: when it started, how long the member was away, its sessions in order.
    public struct Quest: Sendable, Equatable {
        public var start: Date
        public var daysAway: Int
        public var ids: [UUID]
    }

    /// Every quest in the history, oldest first. A first session ever is a start, not a comeback.
    public static func quests(_ records: [WorkoutRecord]) -> [Quest] {
        let sorted = records.sorted { $0.startedAt < $1.startedAt }
        var out: [Quest] = []
        for (i, r) in sorted.enumerated() where i > 0 {
            let gap = r.startedAt.timeIntervalSince(sorted[i - 1].startedAt)
            if gap >= Double(gapDays) * 86_400 {
                out.append(Quest(start: r.startedAt, daysAway: Int(gap / 86_400), ids: [r.id]))
            } else if var q = out.last, q.ids.count < sessions,
                      r.startedAt.timeIntervalSince(q.start) <= Double(windowDays) * 86_400 {
                q.ids.append(r.id)
                out[out.count - 1] = q
            }
        }
        return out
    }

    /// Ids of the sessions that earned the quest bonus.
    public static func questIds(_ records: [WorkoutRecord]) -> Set<UUID> {
        Set(quests(records).flatMap(\.ids))
    }

    /// What Train shows at `now`: away `gapDays`+ (quest about to start), or a quest still open. nil otherwise.
    public static func current(records: [WorkoutRecord], now: Date = Date()) -> Comeback? {
        guard let last = records.max(by: { $0.startedAt < $1.startedAt }) else { return nil }
        let away = now.timeIntervalSince(last.startedAt)
        if away >= Double(gapDays) * 86_400 { return Comeback(daysAway: Int(away / 86_400), done: 0) }
        guard let q = quests(records).last, q.ids.count < sessions else { return nil }
        let end = q.start.addingTimeInterval(Double(windowDays) * 86_400)
        guard now <= end else { return nil }
        return Comeback(daysAway: q.daysAway, done: q.ids.count, endsAt: end)
    }

    /// Where `record` sits in its quest: (session number, days away before the quest), or nil.
    public static func step(of record: WorkoutRecord, in records: [WorkoutRecord]) -> (n: Int, daysAway: Int)? {
        for q in quests(records) { if let i = q.ids.firstIndex(of: record.id) { return (i + 1, q.daysAway) } }
        return nil
    }
}

// MARK: - Wins you missed (#501)

/// One personal win on the finish sheet: icon tile, title, detail, big number + unit.
public struct Win: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case comeback, heavier, weekGoal, shield, allSets, moreSets, newMove, feel, sessionCount, minutes, muscles, sets
    }
    public var kind: Kind
    public var title: String
    public var detail: String
    public var value: String
    public var unit: String
    public var id: String { kind.rawValue }

    public init(_ kind: Kind, title: String, detail: String, value: String, unit: String) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.value = value
        self.unit = unit
    }
}

/// How the member felt after a session (#501), saved from the finish sheet.
public enum Feel: Int, Sendable, CaseIterable, Codable {
    /// Raw values are saved; `amazing` came with the Apple Health mood tiles (#614).
    case drained = 1, meh, good, great, amazing

    public var emoji: String {
        switch self {
        case .drained: "😫"
        case .meh: "😐"
        case .good: "🙂"
        case .great: "😄"
        case .amazing: "🤩"
        }
    }

    public var label: String {
        switch self {
        case .drained: "Drained"
        case .meh: "Meh"
        case .good: "Good"
        case .great: "Great"
        case .amazing: "Amazing"
        }
    }

    public var feltGood: Bool { rawValue >= Feel.good.rawValue }
}

/// Three personal wins for a finished session (#501), even on a weak day: not only records but showing up, coming
/// back, more than last time, a new move, feeling good. Plain wins (session count, minutes, muscles) fill the rest.
public enum Wins {
    public static let count = 3

    /// `history` may hold `record`; `weights` are all logged sets; `feels`: earlier sessions' feelings, oldest first.
    public static func find(
        record r: WorkoutRecord, history: [WorkoutRecord], weights: [WeightEntry], targetPerWeek: Int,
        feels: [Feel] = [], calendar cal: Calendar = Progression.calendar()
    ) -> [Win] {
        let all = (history.filter { $0.id != r.id } + [r]).sorted { $0.startedAt < $1.startedAt }
        let earlier = all.filter { $0.id != r.id && $0.startedAt < r.startedAt }
        var out: [Win] = []

        // Comeback quest.
        if let s = Comeback.step(of: r, in: all) {
            let n = Comeback.sessions, xp = Comeback.xpPerSession
            if s.n == 1 {
                out.append(Win(.comeback, title: "Back after \(s.daysAway) days", detail: "Comeback quest 1/\(n) · +\(xp) XP",
                               value: "1/\(n)", unit: "quest"))
            } else if s.n >= n {
                out.append(Win(.comeback, title: "Comeback complete", detail: "\(n) sessions back · +\(n * xp) XP",
                               value: "\(n)/\(n)", unit: "quest"))
            } else {
                out.append(Win(.comeback, title: "Comeback quest", detail: "Session \(s.n) of \(n) · +\(xp) XP",
                               value: "\(s.n)/\(n)", unit: "quest"))
            }
        }

        // Heavier (or more reps) than the last time each lift was logged.
        if let w = heavier(r, weights: weights) { out.append(w) }

        // Week goal met by this session, shield earned.
        let target = max(1, targetPerWeek)
        let week = Progression.weekStart(r.startedAt, cal)
        var counts: [Date: Int] = [:]
        for x in all where x.startedAt <= r.startedAt { counts[Progression.weekStart(x.startedAt, cal), default: 0] += 1 }
        if counts[week] == target {
            out.append(Win(.weekGoal, title: "Week goal hit", detail: "\(target) session\(target == 1 ? "" : "s") this week · chest open",
                           value: "\(target)/\(target)", unit: "week"))
            var without = counts
            without[week] = target - 1
            let after = StreakRun.evaluate(counts: counts, target: target, through: week, calendar: cal)
            let before = StreakRun.evaluate(counts: without, target: target, through: week, calendar: cal)
            if after.shields > before.shields {
                out.append(Win(.shield, title: "Streak shield earned", detail: "\(after.current) weeks in a row · saves a missed week",
                               value: "\(after.shields)", unit: after.shields == 1 ? "shield" : "shields"))
            }
        }

        // Every set done.
        if r.totalSets > 0, r.exercises.allSatisfy({ $0.setsDone >= $0.setsPlanned }) {
            let month = cal.dateInterval(of: .month, for: r.startedAt)
            let full = all.filter { x in
                x.startedAt <= r.startedAt && month?.contains(x.startedAt) == true
                    && x.totalSets > 0 && x.exercises.allSatisfy { $0.setsDone >= $0.setsPlanned }
            }.count
            out.append(Win(.allSets, title: "Every set done", detail: full == 1 ? "First full session this month" : "\(full) full sessions this month",
                           value: "\(r.totalSets)", unit: "sets"))
        }

        // More sets than the last time this workout was done.
        if let prev = earlier.last(where: { $0.sessionId == r.sessionId || $0.title == r.title }), r.totalSets > prev.totalSets {
            out.append(Win(.moreSets, title: "More than last time", detail: "\(r.title) · \(prev.totalSets) → \(r.totalSets) sets",
                           value: "+\(r.totalSets - prev.totalSets)", unit: "sets"))
        }

        // A move never done before (not on a first session ever: everything is new then).
        if !earlier.isEmpty {
            let seen = Set(earlier.flatMap { $0.exercises.filter { $0.setsDone > 0 }.map(\.exerciseId) })
            let new = Set(r.exercises.filter { $0.setsDone > 0 && !seen.contains($0.exerciseId) }.map(\.exerciseId))
            if let id = r.exercises.first(where: { new.contains($0.exerciseId) })?.exerciseId {
                let name = Exercise.find(id)?.name ?? "A new move"
                out.append(Win(.newMove, title: new.count == 1 ? "New move" : "\(new.count) new moves",
                               detail: new.count == 1 ? "First time: \(name)" : "First time: \(name) and more",
                               value: "\(new.count)", unit: "new"))
            }
        }

        // Feeling good after training lately.
        let recent = feels.suffix(5)
        let good = recent.filter(\.feltGood).count
        if recent.count >= 3, good >= 3 {
            out.append(Win(.feel, title: "Training lifts you", detail: "Felt good after \(good) of your last \(recent.count) sessions",
                           value: "\(good)/\(recent.count)", unit: "felt good"))
        }

        // Plain wins, always there.
        let number = earlier.count + 1
        let minutes = max(1, r.durationSec / 60)
        let muscles = r.muscleHeat.filter { $0.value > 0.05 }.count
        var plain = [
            Win(.sessionCount, title: "Session #\(number)", detail: number == 1 ? "Your first one. It starts here" : "You showed up again",
                value: "#\(number)", unit: "sessions"),
            Win(.minutes, title: "\(minutes) min for you", detail: "Time you gave yourself today", value: "\(minutes)", unit: "min"),
        ]
        if muscles > 0 {
            plain.append(Win(.muscles, title: "\(muscles) muscles worked", detail: "Every one a bit stronger", value: "\(muscles)", unit: "muscles"))
        }
        plain.append(Win(.sets, title: "\(r.totalSets) sets done", detail: "Each one counts", value: "\(r.totalSets)", unit: "sets"))

        var picked: [Win] = []
        for w in out + plain where picked.count < count && !picked.contains(where: { $0.kind == w.kind }) {
            // Never two "sets" numbers side by side.
            if w.kind == .sets, picked.contains(where: { $0.kind == .allSets }) { continue }
            picked.append(w)
        }
        return picked
    }

    /// The lift with the biggest gain over the last day it was logged before this session: kg, else reps.
    static func heavier(_ r: WorkoutRecord, weights: [WeightEntry]) -> Win? {
        let from = r.startedAt.addingTimeInterval(-600), to = r.endedAt.addingTimeInterval(600)
        let ids = Set(r.exercises.filter { $0.setsDone > 0 }.map(\.exerciseId))
        var best: (gain: Double, win: Win)?
        for id in ids {
            let today = weights.filter { $0.exerciseId == id && $0.date >= from && $0.date <= to && $0.kg > 0 }
            guard let top = today.max(by: { ($0.kg, $0.reps ?? 0) < ($1.kg, $1.reps ?? 0) }) else { continue }
            let before = weights.filter { $0.exerciseId == id && $0.date < from && $0.kg > 0 }
            guard let lastDay = before.max(by: { $0.date < $1.date })?.date else { continue }
            let cal = Calendar(identifier: .gregorian)
            let prev = before.filter { cal.isDate($0.date, inSameDayAs: lastDay) }
            guard let p = prev.max(by: { ($0.kg, $0.reps ?? 0) < ($1.kg, $1.reps ?? 0) }) else { continue }
            let name = Exercise.find(id)?.name ?? "Your lift"
            let allTime = before.map(\.kg).max() ?? 0
            if top.kg > p.kg + 0.001 {
                let gain = (top.kg - p.kg) / p.kg
                let detail = (top.kg > allTime + 0.001 ? "New best · " : "Heavier than last time · ")
                    + "\(LoadAdvisor.formatKg(p.kg)) → \(LoadAdvisor.formatKg(top.kg)) kg"
                if gain > (best?.gain ?? 0) {
                    best = (gain, Win(.heavier, title: name, detail: detail, value: "+\(LoadAdvisor.formatKg(top.kg - p.kg))", unit: "kg"))
                }
            } else if abs(top.kg - p.kg) < 0.001, let a = top.reps, let b = p.reps, a > b {
                let gain = Double(a - b) / Double(max(1, b)) / 4 // a rep counts less than a load step
                if gain > (best?.gain ?? 0) {
                    best = (gain, Win(.heavier, title: name, detail: "\(b) → \(a) reps at \(LoadAdvisor.formatKg(top.kg)) kg",
                                      value: "+\(a - b)", unit: "reps"))
                }
            }
        }
        return best?.win
    }
}
