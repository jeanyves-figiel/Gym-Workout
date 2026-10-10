import Foundation

/// What a personal-record attempt goes for (#60).
public enum PRKind: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Heaviest single.
    case oneRepMax
    /// Heaviest load for a fixed number of reps (3RM, 5RM).
    case repMax
    /// Most reps at a chosen load (added load for bodyweight moves).
    case maxReps

    public var id: String { rawValue }
}

/// One set of an attempt: a warm-up step or a try at the target.
public struct PRSet: Codable, Hashable, Sendable {
    public var kg: Double
    public var reps: Int
    public var warmup: Bool
    /// Attempt sets only: completed with good form.
    public var made: Bool

    public init(kg: Double, reps: Int, warmup: Bool = false, made: Bool = true) {
        self.kg = kg
        self.reps = reps
        self.warmup = warmup
        self.made = made
    }
}

/// A finished personal-record attempt. Synced as-is (`/v1/me/pr-attempts`); `exerciseId`, `date`, `kind`, `kg`, `reps`,
/// `success` and `isRecord` are the shareable summary.
public struct PRAttempt: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var exerciseId: String
    public var date: Date
    public var kind: PRKind
    /// Rep target for `.repMax` (and 1 for `.oneRepMax`); nil for `.maxReps`.
    public var targetReps: Int?
    /// Result: heaviest made load (1RM / rep max) or the load used (max reps).
    public var kg: Double
    /// Result reps: the target reps when made, or the reps done for max reps.
    public var reps: Int
    /// At least one attempt was made.
    public var success: Bool
    /// Beat the previous best of the same kind.
    public var isRecord: Bool
    /// Best before this attempt (kg for 1RM / rep max, reps for max reps).
    public var previousBest: Double?
    public var sets: [PRSet]

    public init(
        id: UUID = UUID(), exerciseId: String, date: Date, kind: PRKind, targetReps: Int?, kg: Double, reps: Int,
        success: Bool, isRecord: Bool, previousBest: Double?, sets: [PRSet]
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.date = date
        self.kind = kind
        self.targetReps = targetReps
        self.kg = kg
        self.reps = reps
        self.success = success
        self.isRecord = isRecord
        self.previousBest = previousBest
        self.sets = sets
    }

    /// Log session id for the made attempt sets, so they show up in exercise history.
    public var sessionId: String { PRPlanner.sessionPrefix + id.uuidString }

    /// "1RM", "5RM", "Max reps".
    public var label: String { PRPlanner.label(kind, reps: targetReps) }

    /// Estimated 1RM of the result.
    public var estimatedOneRepMax: Double? { success ? PRPlanner.oneRepMax(kg: kg, reps: reps) : nil }
}

/// One step of the suggested warm-up ramp.
public struct RampStep: Hashable, Sendable {
    public var kg: Double
    public var reps: Int
}

/// Suggested attempt: target load/reps, ramp and safety cue.
public struct PRPlan: Hashable, Sendable {
    public var kind: PRKind
    public var kg: Double
    /// Target reps (1 for 1RM, N for N-RM, rep goal for max reps).
    public var reps: Int
    /// Best so far for this kind (kg, or reps for max reps); nil when none yet.
    public var best: Double?
    public var estimatedOneRepMax: Double?
    public var ramp: [RampStep]
    public var safety: String
    /// One-line reason for the target.
    public var basis: String
}

/// Targets, warm-up ramps and record bookkeeping for PR attempts.
public enum PRPlanner {
    /// Log session ids of PR attempts start with this; load suggestions ignore those sessions.
    public static let sessionPrefix = "pr-"
    /// Attempts per session for 1RM / rep max.
    public static let maxAttempts = 3
    public static let repMaxChoices = [3, 5]

    private static let bodyweightGear: Set<Equipment> = [.pullupBar, .dipStation, .rings, .trx, .mat, .bench, .plyoBox, .abWheel, .bands, .backExtension]

    /// Strength moves counted in reps; time-based holds can't be attempted.
    public static func eligible(_ e: Exercise) -> Bool { e.category == .strength && e.unit != .sec }

    /// Bodyweight moves (no external load unless "weighted") only support max reps.
    public static func isBodyweight(_ e: Exercise) -> Bool {
        Set(e.equipment).isSubset(of: bodyweightGear) && !e.id.hasPrefix("weighted")
    }

    public static func kinds(for e: Exercise) -> [PRKind] {
        guard eligible(e) else { return [] }
        return isBodyweight(e) ? [.maxReps] : PRKind.allCases
    }

    public static func label(_ kind: PRKind, reps: Int?) -> String {
        switch kind {
        case .oneRepMax: "1RM"
        case .repMax: "\(reps ?? 5)RM"
        case .maxReps: "Max reps"
        }
    }

    public static func isPRSession(_ sessionId: String?) -> Bool { sessionId?.hasPrefix(sessionPrefix) ?? false }

    // MARK: Bests

    /// Heaviest load done for at least `reps` reps, from logged sets and made attempts.
    public static func bestKg(forReps reps: Int, logs: [SetLog], attempts: [PRAttempt]) -> Double? {
        let fromLogs = logs.filter { ($0.reps ?? 0) >= reps && $0.kg > 0 }.map(\.kg)
        let fromAttempts = attempts.filter { $0.success && $0.reps >= reps && $0.kg > 0 }.map(\.kg)
        return (fromLogs + fromAttempts).max()
    }

    /// Most reps done at `kg` or more.
    public static func bestReps(atKg kg: Double, logs: [SetLog], attempts: [PRAttempt]) -> Int? {
        let fromLogs = logs.filter { $0.kg >= kg - 0.001 }.compactMap(\.reps)
        let fromAttempts = attempts.filter { $0.success && $0.kg >= kg - 0.001 }.map(\.reps)
        return (fromLogs + fromAttempts).filter { $0 > 0 }.max()
    }

    /// Epley, except a single is its own 1RM (Epley would add 3 % to a true max).
    public static func oneRepMax(kg: Double, reps: Int?) -> Double? {
        reps == 1 && kg > 0 ? kg : LoadAdvisor.epley(kg: kg, reps: reps)
    }

    /// Best 1RM estimate across logged sets and made attempts.
    public static func estimatedOneRepMax(logs: [SetLog], attempts: [PRAttempt]) -> Double? {
        (logs.compactMap { oneRepMax(kg: $0.kg, reps: $0.reps) } + attempts.compactMap(\.estimatedOneRepMax)).max()
    }

    /// The best for a kind before an attempt (kg, or reps for max reps).
    public static func best(_ kind: PRKind, reps: Int, kg: Double, logs: [SetLog], attempts: [PRAttempt]) -> Double? {
        switch kind {
        case .oneRepMax: bestKg(forReps: 1, logs: logs, attempts: attempts)
        case .repMax: bestKg(forReps: reps, logs: logs, attempts: attempts)
        case .maxReps: bestReps(atKg: kg, logs: logs, attempts: attempts).map(Double.init)
        }
    }

    /// Best result per kind (1RM, each rep max, max reps) from attempts that were records, newest record wins.
    public static func records(_ attempts: [PRAttempt]) -> [PRAttempt] {
        var byLabel: [String: PRAttempt] = [:]
        for a in attempts.sorted(by: { $0.date < $1.date }) where a.success && a.isRecord { byLabel[a.label] = a }
        return byLabel.values.sorted { ($0.kind.order, $0.targetReps ?? 0) < ($1.kind.order, $1.targetReps ?? 0) }
    }

    // MARK: Plan

    /// Suggested target, ramp and safety cue. `kg` is the chosen load for max reps (default: last top set or 0).
    public static func plan(
        exercise e: Exercise, kind: PRKind, reps targetReps: Int = 5, kg chosenKg: Double? = nil,
        logs allLogs: [SetLog], attempts allAttempts: [PRAttempt]
    ) -> PRPlan {
        let logs = allLogs.filter { $0.exerciseId == e.id }
        let attempts = allAttempts.filter { $0.exerciseId == e.id }
        let e1rm = estimatedOneRepMax(logs: logs, attempts: attempts)
        let lastTop = logs.max { $0.date < $1.date }.map { last in
            logs.filter { $0.sessionId == last.sessionId && Calendar.current.isDate($0.date, inSameDayAs: last.date) }.map(\.kg).max() ?? last.kg
        }
        let topKg = logs.map(\.kg).max() ?? 0
        let s = LoadAdvisor.steps(for: e, kg: topKg)
        let safety = safetyCue(e)

        switch kind {
        case .oneRepMax, .repMax:
            let n = kind == .oneRepMax ? 1 : targetReps
            let best = bestKg(forReps: n, logs: logs, attempts: attempts)
            var kg = 0.0
            var basis = "No history yet: pick a load you are confident about"
            if let e1rm {
                kg = LoadAdvisor.round(n == 1 ? e1rm : e1rm / (1 + Double(n) / 30), to: s.granularity, .down)
                basis = "Est. 1RM \(LoadAdvisor.formatKg(e1rm.rounded())) kg"
            }
            if let best {
                let beat = LoadAdvisor.round(best + s.increment, to: s.granularity, .up)
                if beat > kg {
                    kg = beat
                    basis = "Best \(LoadAdvisor.formatKg(best)) kg × \(n) + \(LoadAdvisor.formatKg(beat - best)) kg"
                }
            }
            if let chosenKg { kg = chosenKg }
            return PRPlan(kind: kind, kg: kg, reps: n, best: best, estimatedOneRepMax: e1rm,
                          ramp: ramp(to: kg, kind: kind, exercise: e), safety: safety, basis: basis)
        case .maxReps:
            let kg = chosenKg ?? (isBodyweight(e) ? 0 : (lastTop ?? 0))
            let best = bestReps(atKg: kg, logs: logs, attempts: attempts)
            var goal = (best ?? 0) + 1
            var basis = best.map { "Best \($0) reps at \(LoadAdvisor.formatKg(kg)) kg + 1" } ?? "First test at this load"
            if let e1rm, kg > 0, e1rm > kg {
                let predicted = Int((30 * (e1rm / kg - 1)).rounded(.down))
                if predicted > goal && predicted <= 30 {
                    goal = predicted
                    basis = "Est. 1RM \(LoadAdvisor.formatKg(e1rm.rounded())) kg predicts \(predicted) reps"
                }
            }
            return PRPlan(kind: kind, kg: kg, reps: max(1, goal), best: best.map(Double.init), estimatedOneRepMax: e1rm,
                          ramp: ramp(to: kg, kind: kind, exercise: e), safety: safety, basis: basis)
        }
    }

    /// Warm-up sets toward `kg`: more, lighter steps before a single; fewer before a rep test.
    /// Loads are rounded to the equipment step, never below an empty bar, and strictly increasing.
    public static func ramp(to kg: Double, kind: PRKind, exercise e: Exercise) -> [RampStep] {
        guard kg > 0 else { return [] }
        let pattern: [(Double, Int)] = switch kind {
        case .oneRepMax: [(0.4, 8), (0.55, 5), (0.7, 3), (0.8, 2), (0.9, 1)]
        case .repMax: [(0.4, 8), (0.6, 5), (0.75, 3), (0.85, 1)]
        case .maxReps: [(0.5, 8), (0.7, 3)]
        }
        let s = LoadAdvisor.steps(for: e, kg: kg)
        let eq = Set(e.equipment)
        let floor: Double = eq.contains(.barbell) || eq.contains(.smith) ? 20 : (eq.contains(.trapBar) ? 25 : 0)
        var out: [RampStep] = []
        for (pct, reps) in pattern {
            let w = max(floor, LoadAdvisor.round(kg * pct, to: s.granularity))
            guard w < kg, w > (out.last?.kg ?? -1), w > 0 else { continue }
            out.append(RampStep(kg: w, reps: reps))
        }
        return out
    }

    /// One-line safety reminder for heavy attempts.
    public static func safetyCue(_ e: Exercise) -> String {
        let eq = Set(e.equipment)
        let bar = eq.contains(.barbell) || eq.contains(.smith)
        switch e.pattern {
        case .hPush where bar:
            return "Use a spotter or set the safety arms just below chest height. Never bench a max alone with collars on."
        case .hPush where eq.contains(.dumbbells):
            return "Have a spotter at the wrists, or know how to drop the dumbbells to the sides safely."
        case .squat where bar:
            return "Set the safety pins just below your bottom position and practice bailing. A spotter behind you helps."
        case .vPush where bar:
            return "Press inside a rack with pins at shoulder height so a miss can be racked."
        case .hinge:
            return "Brace hard. If the back rounds or the bar drifts forward, drop it rather than grinding."
        case .vPull, .hPull:
            return "Control the descent and stop if the shoulders shrug up or elbows ache."
        default:
            return "Stop the set the moment form breaks. A failed rep is fine, an injury is not."
        }
    }

    /// The record result for a finished attempt. `previousBest` comes from `best(...)` before the attempt.
    public static func finish(
        exerciseId: String, kind: PRKind, targetReps: Int?, sets: [PRSet], previousBest: Double?, date: Date = Date(), id: UUID = UUID()
    ) -> PRAttempt {
        let tries = sets.filter { !$0.warmup }
        let made = tries.filter(\.made)
        let kg: Double
        let reps: Int
        let isRecord: Bool
        switch kind {
        case .oneRepMax, .repMax:
            let top = made.max { $0.kg < $1.kg }
            kg = top?.kg ?? tries.map(\.kg).max() ?? 0
            reps = top?.reps ?? 0
            isRecord = top.map { t in previousBest.map { t.kg > $0 + 0.001 } ?? true } ?? false
        case .maxReps:
            let top = made.max { $0.reps < $1.reps }
            kg = top?.kg ?? tries.first?.kg ?? 0
            reps = top?.reps ?? 0
            isRecord = top.map { t in t.reps > 0 && (previousBest.map { Double(t.reps) > $0 } ?? true) } ?? false
        }
        return PRAttempt(id: id, exerciseId: exerciseId, date: date, kind: kind, targetReps: kind == .maxReps ? nil : (targetReps ?? 1),
                         kg: kg, reps: reps, success: !made.isEmpty && reps > 0, isRecord: isRecord,
                         previousBest: previousBest, sets: sets)
    }
}

extension PRKind {
    var order: Int {
        switch self {
        case .oneRepMax: 0
        case .repMax: 1
        case .maxReps: 2
        }
    }
}
