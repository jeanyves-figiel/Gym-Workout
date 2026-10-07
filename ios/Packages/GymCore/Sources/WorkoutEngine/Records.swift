import Foundation

/// What was actually done for one planned exercise.
public struct ExerciseRecord: Codable, Hashable, Sendable, Identifiable {
    public var uid: String
    public var exerciseId: String
    public var category: Category
    public var setsDone: Int
    public var setsPlanned: Int
    /// Reps per set used for volume (planned estimate when not logged).
    public var reps: Double?
    public var weightKg: Double?
    public var id: String { uid }

    public var volumeKg: Double {
        guard let w = weightKg, let r = reps, w > 0 else { return 0 }
        return Double(setsDone) * r * w
    }

    /// Epley estimated one-rep max for the logged set.
    public var estimatedOneRepMax: Double? {
        guard let w = weightKg, let r = reps, w > 0, r >= 1, r <= 12 else { return nil }
        return w * (1 + r / 30)
    }
}

/// A completed training session — the unit of history.
public struct WorkoutRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var durationSec: Int
    public var sessionId: String
    public var week: Int
    public var deload: Bool
    public var focus: Focus
    public var title: String
    public var exercises: [ExerciseRecord]
    public var kcal: Double?
    public var avgHeartRate: Double?
    public var maxHeartRate: Double?
    /// Muscle raw value → load (sets × weight), for history heat maps.
    public var muscleLoad: [String: Double]

    public var totalSets: Int { exercises.reduce(0) { $0 + $1.setsDone } }
    public var volumeKg: Double { exercises.reduce(0) { $0 + $1.volumeKg } }
    public var endedAt: Date { startedAt.addingTimeInterval(TimeInterval(durationSec)) }
    public var categories: Set<Category> { Set(exercises.filter { $0.setsDone > 0 }.map(\.category)) }

    public var muscleHeat: [Muscle: Double] {
        var out: [Muscle: Double] = [:]
        for (k, v) in muscleLoad { if let m = Muscle(rawValue: k) { out[m] = v } }
        let mx = out.values.max() ?? 1
        return out.mapValues { $0 / max(mx, 1e-9) }
    }

    /// Builds a record from a planned session and what was completed.
    public static func build(
        session: Session, week: Int, deload: Bool,
        setsDone: [String: Int], weights: [String: Double],
        startedAt: Date, endedAt: Date, bodyMassKg: Double?,
        id: UUID = UUID()
    ) -> WorkoutRecord {
        var exercises: [ExerciseRecord] = []
        var load: [Muscle: Double] = [:]
        for b in session.blocks {
            for it in b.items {
                let e = Exercise.get(it.exerciseId)
                let done = min(setsDone[it.uid] ?? 0, max(1, it.prescription.sets))
                let rec = ExerciseRecord(
                    uid: it.uid, exerciseId: e.id, category: e.category, setsDone: done,
                    setsPlanned: it.prescription.sets, reps: it.prescription.repsEstimate, weightKg: weights[e.id])
                exercises.append(rec)
                guard done > 0, b.kind != .warmup, b.kind != .mobility, b.kind != .cooldown else { continue }
                for (m, w) in e.muscleWeights { load[m, default: 0] += Double(done) * w }
            }
        }
        let duration = max(0, Int(endedAt.timeIntervalSince(startedAt)))
        return WorkoutRecord(
            id: id, startedAt: startedAt, durationSec: duration, sessionId: session.id, week: week, deload: deload,
            focus: session.focus, title: session.focus.label, exercises: exercises,
            kcal: Energy.estimate(session: session, durationSec: duration, bodyMassKg: bodyMassKg),
            avgHeartRate: nil, maxHeartRate: nil,
            muscleLoad: Dictionary(uniqueKeysWithValues: load.map { ($0.key.rawValue, $0.value) }))
    }
}

extension Prescription {
    /// Mean of the numbers in a rep range ("5–8" → 6.5, "12–15 / side" → 13.5); nil for time-based work.
    public var repsEstimate: Double? {
        // Time-based prescriptions ("30–45 s", "4 min") have no rep count.
        if reps.contains("min") || reps.range(of: #"\d\s?s\b"#, options: .regularExpression) != nil { return nil }
        var nums: [Double] = []
        var cur = ""
        for ch in reps {
            if ch.isNumber { cur.append(ch) } else if !cur.isEmpty { nums.append(Double(cur)!); cur = "" }
        }
        if !cur.isEmpty { nums.append(Double(cur)!) }
        guard !nums.isEmpty else { return nil }
        let take = Array(nums.prefix(2))
        return take.reduce(0, +) / Double(take.count)
    }
}

/// Energy estimate from MET values × body mass × time (used when Health has no measured energy).
public enum Energy {
    static func met(_ b: Block) -> Double {
        switch b.kind {
        case .warmup: 4
        case .power: 6
        case .strength: b.title.contains("circuit") ? 6 : 5
        case .mobility: 2.5
        case .cardio: b.title.contains("Zone 2") ? 7 : 9
        case .cooldown: 2.3
        }
    }

    public static func estimate(session: Session, durationSec: Int, bodyMassKg: Double?) -> Double? {
        guard let kg = bodyMassKg, kg > 0, durationSec > 0 else { return nil }
        let total = Double(session.blocks.reduce(0) { $0 + max(1, $1.targetMin) })
        let avgMet = session.blocks.reduce(0.0) { $0 + met($1) * Double(max(1, $1.targetMin)) } / total
        return (avgMet * kg * Double(durationSec) / 3600).rounded()
    }
}
