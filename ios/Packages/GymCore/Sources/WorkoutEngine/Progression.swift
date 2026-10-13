import Foundation

/// A logged weight (from the in-session weight log).
public struct WeightEntry: Sendable, Hashable {
    public let exerciseId: String
    public let date: Date
    public let kg: Double
    public let reps: Int?

    public init(exerciseId: String, date: Date, kg: Double, reps: Int? = nil) {
        self.exerciseId = exerciseId
        self.date = date
        self.kg = kg
        self.reps = reps
    }
}

public struct PersonalRecord: Sendable, Hashable, Identifiable {
    public let exerciseId: String
    public let kg: Double
    public let date: Date
    public var id: String { exerciseId }
}

public struct WeekBucket: Sendable, Hashable, Identifiable {
    public let weekStart: Date
    public var workouts: Int
    public var minutes: Int
    public var volumeKg: Double
    public var id: Date { weekStart }
}

public struct ProgressStats: Sendable {
    public var totalWorkouts = 0
    public var totalMinutes = 0
    public var totalVolumeKg = 0.0
    public var totalSets = 0
    public var currentStreakWeeks = 0
    public var bestStreakWeeks = 0
    public var thisWeek = 0
    /// Last 12 weeks, oldest first.
    public var weeks: [WeekBucket] = []
    /// Start-of-day → workouts that day (for the calendar heat map).
    public var days: [Date: Int] = [:]
    public var personalRecords: [PersonalRecord] = []
    /// Normalised muscle load over the last 28 days.
    public var muscleBalance: [Muscle: Double] = [:]
}

public enum Progression {
    /// ISO-8601 calendar (weeks start Monday).
    public static func calendar(_ tz: TimeZone = .current) -> Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = tz
        return c
    }

    public static func weekStart(_ d: Date, _ cal: Calendar) -> Date {
        cal.dateInterval(of: .weekOfYear, for: d)!.start
    }

    public static func stats(
        records: [WorkoutRecord], weights: [WeightEntry], targetPerWeek: Int,
        now: Date = Date(), calendar cal: Calendar = Progression.calendar()
    ) -> ProgressStats {
        var s = ProgressStats()
        let sorted = records.sorted { $0.startedAt < $1.startedAt }
        s.totalWorkouts = sorted.count
        s.totalMinutes = sorted.reduce(0) { $0 + $1.durationSec / 60 }
        s.totalVolumeKg = sorted.reduce(0) { $0 + $1.volumeKg }
        s.totalSets = sorted.reduce(0) { $0 + $1.totalSets }

        // Weekly buckets & streaks.
        var perWeek: [Date: WeekBucket] = [:]
        for r in sorted {
            let w = weekStart(r.startedAt, cal)
            var b = perWeek[w] ?? WeekBucket(weekStart: w, workouts: 0, minutes: 0, volumeKg: 0)
            b.workouts += 1
            b.minutes += r.durationSec / 60
            b.volumeKg += r.volumeKg
            perWeek[w] = b
            s.days[cal.startOfDay(for: r.startedAt), default: 0] += 1
        }
        let thisWeek = weekStart(now, cal)
        s.thisWeek = perWeek[thisWeek]?.workouts ?? 0
        s.weeks = (0..<12).reversed().map { i in
            let w = cal.date(byAdding: .weekOfYear, value: -i, to: thisWeek)!
            return perWeek[w] ?? WeekBucket(weekStart: w, workouts: 0, minutes: 0, volumeKg: 0)
        }
        let target = max(1, targetPerWeek)
        let met = { (w: Date) in (perWeek[w]?.workouts ?? 0) >= target }
        // Current streak: completed past weeks meeting target, plus this week if already met.
        var streak = met(thisWeek) ? 1 : 0
        var w = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeek)!
        while met(w) {
            streak += 1
            w = cal.date(byAdding: .weekOfYear, value: -1, to: w)!
        }
        s.currentStreakWeeks = streak
        if let first = sorted.first {
            var best = 0, run = 0
            var cursor = weekStart(first.startedAt, cal)
            while cursor <= thisWeek {
                run = met(cursor) ? run + 1 : 0
                best = max(best, run)
                cursor = cal.date(byAdding: .weekOfYear, value: 1, to: cursor)!
            }
            s.bestStreakWeeks = best
        }

        // PRs: heaviest logged weight per exercise.
        var best: [String: PersonalRecord] = [:]
        for e in weights.sorted(by: { $0.date < $1.date }) where e.kg > (best[e.exerciseId]?.kg ?? 0) {
            best[e.exerciseId] = PersonalRecord(exerciseId: e.exerciseId, kg: e.kg, date: e.date)
        }
        s.personalRecords = best.values.sorted { $0.date > $1.date }

        // Muscle balance, last 28 days.
        let from = now.addingTimeInterval(-28 * 86_400)
        var load: [Muscle: Double] = [:]
        for r in sorted where r.startedAt >= from {
            for (k, v) in r.muscleLoad { if let m = Muscle(rawValue: k) { load[m, default: 0] += v } }
        }
        let mx = load.values.max() ?? 1
        s.muscleBalance = load.mapValues { $0 / max(mx, 1e-9) }
        return s
    }

    /// Number of times a weight entry beat the previous best for its exercise (first log doesn't count).
    public static func prCount(_ weights: [WeightEntry]) -> [(Date, Int)] {
        var best: [String: Double] = [:]
        var out: [(Date, Int)] = []
        var n = 0
        for e in weights.sorted(by: { $0.date < $1.date }) {
            if let b = best[e.exerciseId], e.kg > b {
                n += 1
                out.append((e.date, n))
            }
            best[e.exerciseId] = max(best[e.exerciseId] ?? 0, e.kg)
        }
        return out
    }

    /// Best estimated 1RM per week for one exercise (from history records), oldest first.
    public static func oneRepMaxTrend(_ exerciseId: String, records: [WorkoutRecord], calendar cal: Calendar = Progression.calendar()) -> [(Date, Double)] {
        var perWeek: [Date: Double] = [:]
        for r in records {
            for e in r.exercises where e.exerciseId == exerciseId && e.setsDone > 0 {
                if let orm = e.estimatedOneRepMax {
                    let w = weekStart(r.startedAt, cal)
                    perWeek[w] = max(perWeek[w] ?? 0, orm)
                }
            }
        }
        return perWeek.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}

// MARK: - Period stats (Progress live tiles, #218)

public enum StatPeriod: String, CaseIterable, Sendable, Identifiable {
    case week, month, all
    public var id: String { rawValue }
}

public enum StatMetric: String, CaseIterable, Sendable, Identifiable {
    case sessions, minutes, volume, sets, days
    public var id: String { rawValue }
}

public struct PeriodTotals: Sendable, Hashable {
    public var workouts = 0
    public var minutes = 0
    public var volumeKg = 0.0
    public var sets = 0
    public var activeDays = 0

    public init() {}

    public func value(_ m: StatMetric) -> Double {
        switch m {
        case .sessions: Double(workouts)
        case .minutes: Double(minutes)
        case .volume: volumeKg
        case .sets: Double(sets)
        case .days: Double(activeDays)
        }
    }
}

public struct PeriodBucket: Sendable, Hashable, Identifiable {
    public let start: Date
    public var totals: PeriodTotals
    public var id: Date { start }
}

public struct PeriodSummary: Sendable {
    public let period: StatPeriod
    /// This week / this month / everything.
    public var current: PeriodTotals
    /// Last week / last month; nil for All.
    public var previous: PeriodTotals?
    /// Trend buckets, oldest first, the last one is the current week / month:
    /// 8 weeks for Week, 6 months for Month, up to 12 months (since the first workout) for All.
    public var buckets: [PeriodBucket]

    /// Change vs the previous period; nil for All.
    public func delta(_ m: StatMetric) -> Double? {
        previous.map { current.value(m) - $0.value(m) }
    }

    /// Index of the best bucket for a metric (nil when every bucket is 0).
    public func best(_ m: StatMetric) -> Int? {
        guard let i = buckets.indices.max(by: { buckets[$0].totals.value(m) < buckets[$1].totals.value(m) }),
              buckets[i].totals.value(m) > 0 else { return nil }
        return i
    }
}

extension Progression {
    static func totals(_ records: [WorkoutRecord], _ cal: Calendar) -> PeriodTotals {
        var t = PeriodTotals()
        t.workouts = records.count
        t.minutes = records.reduce(0) { $0 + $1.durationSec / 60 }
        t.volumeKg = records.reduce(0) { $0 + $1.volumeKg }
        t.sets = records.reduce(0) { $0 + $1.totalSets }
        t.activeDays = Set(records.map { cal.startOfDay(for: $0.startedAt) }).count
        return t
    }

    public static func periodSummary(
        records: [WorkoutRecord], period: StatPeriod,
        now: Date = Date(), calendar cal: Calendar = Progression.calendar()
    ) -> PeriodSummary {
        let unit: Calendar.Component = period == .week ? .weekOfYear : .month
        let thisStart = cal.dateInterval(of: unit, for: now)!.start
        let count: Int
        switch period {
        case .week: count = 8
        case .month: count = 6
        case .all:
            let first = records.map(\.startedAt).min() ?? now
            let firstMonth = cal.dateInterval(of: .month, for: first)!.start
            let months = cal.dateComponents([.month], from: firstMonth, to: thisStart).month ?? 0
            count = min(12, max(1, months + 1))
        }
        let starts = (0..<count).reversed().map { cal.date(byAdding: unit, value: -$0, to: thisStart)! }
        let buckets = starts.map { s in
            let e = cal.date(byAdding: unit, value: 1, to: s)!
            return PeriodBucket(start: s, totals: totals(records.filter { $0.startedAt >= s && $0.startedAt < e }, cal))
        }
        switch period {
        case .all:
            return PeriodSummary(period: period, current: totals(records, cal), previous: nil, buckets: buckets)
        case .week, .month:
            let prevStart = cal.date(byAdding: unit, value: -1, to: thisStart)!
            let prev = totals(records.filter { $0.startedAt >= prevStart && $0.startedAt < thisStart }, cal)
            return PeriodSummary(period: period, current: buckets.last!.totals, previous: prev, buckets: buckets)
        }
    }
}
