import Foundation

// Lift Lab (#499, design C from `expert-lifters/proposals.png`): one lift's numbers for lifters who push it: rep
// records, heavy sets and test-day attempts. The e1RM trend comes from `Progression.oneRepMaxTrend`.

public struct RepRecord: Hashable, Sendable, Identifiable {
    public var reps: Int
    public var kg: Double
    public var date: Date
    public var id: Int { reps }
}

public enum LiftLab {
    public static let recordReps = [1, 2, 3, 5, 8, 10, 12]

    /// Heaviest load done for at least `reps` reps, per rep count, with the day it was first done. Logs of other
    /// exercises are ignored; successful PR attempts count.
    public static func repRecords(exerciseId: String, logs: [SetLog], attempts: [PRAttempt]) -> [RepRecord] {
        var sets: [(Date, Double, Int)] = logs.compactMap { l in
            guard l.exerciseId == exerciseId, l.kg > 0, let r = l.reps, r > 0 else { return nil }
            return (l.date, l.kg, r)
        }
        sets += attempts.filter { $0.exerciseId == exerciseId && $0.success && $0.kg > 0 }.map { ($0.date, $0.kg, $0.reps) }
        return recordReps.compactMap { n in
            let fit = sets.filter { $0.2 >= n }
            guard let best = fit.map(\.1).max() else { return nil }
            let first = fit.filter { $0.1 == best }.map(\.0).min() ?? Date()
            return RepRecord(reps: n, kg: best, date: first)
        }
    }

    /// Sets at ≥ 85% of `oneRepMax` since `since`.
    public static func heavySets(exerciseId: String, logs: [SetLog], oneRepMax: Double, since: Date) -> Int {
        guard oneRepMax > 0 else { return 0 }
        return logs.filter { $0.exerciseId == exerciseId && $0.date >= since && ($0.reps ?? 0) > 0 && $0.kg >= oneRepMax * 0.85 }.count
    }

    /// Best estimated 1RM over the logs since `since` (Epley, 1-12 reps).
    public static func oneRepMax(exerciseId: String, logs: [SetLog], since: Date) -> Double? {
        logs.filter { $0.exerciseId == exerciseId && $0.date >= since }.compactMap(\.estimatedOneRepMax).max()
    }
}
