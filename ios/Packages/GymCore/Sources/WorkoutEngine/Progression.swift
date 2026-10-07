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
