import Foundation

/// One logged set (or a legacy one-weight-per-exercise log), independent of the API model.
public struct SetLog: Sendable, Hashable {
    public var date: Date
    public var exerciseId: String
    public var sessionId: String?
    /// 0-based set number within the session; nil for legacy logs.
    public var setIndex: Int?
    public var kg: Double
    public var reps: Int?
    /// Reps in reserve.
    public var rir: Int?

    public init(date: Date, exerciseId: String, sessionId: String? = nil, setIndex: Int? = nil, kg: Double, reps: Int? = nil, rir: Int? = nil) {
        self.date = date
        self.exerciseId = exerciseId
        self.sessionId = sessionId
        self.setIndex = setIndex
        self.kg = kg
        self.reps = reps
        self.rir = rir
    }

    /// Epley estimated one-rep max (1–12 reps only, where the formula is reasonable).
    public var estimatedOneRepMax: Double? { LoadAdvisor.epley(kg: kg, reps: reps) }
}

/// Everything logged for one exercise in one session (same session id, same day).
public struct ExerciseSession: Sendable, Hashable, Identifiable {
    public var date: Date
    public var sessionId: String?
    /// Mesocycle week (1…4) when known.
    public var week: Int?
    public var deload: Bool
    /// Ordered by set index.
    public var sets: [SetLog]

    public init(date: Date, sessionId: String?, week: Int?, deload: Bool, sets: [SetLog]) {
        self.date = date
        self.sessionId = sessionId
        self.week = week
        self.deload = deload
        self.sets = sets
    }

    public var id: String { "\(sessionId ?? "-")@\(Int(date.timeIntervalSince1970))" }
    public var topKg: Double { sets.map(\.kg).max() ?? 0 }
    public var bestOneRepMax: Double? { sets.compactMap(\.estimatedOneRepMax).max() }
    public var volumeKg: Double { sets.reduce(0) { $0 + $1.kg * Double($1.reps ?? 0) } }
}

/// Prescribed rep range, e.g. "8–10" → 8…10, "5" → 5…5.
public struct RepRange: Sendable, Hashable {
    public var low: Int
    public var high: Int

    public init(low: Int, high: Int) {
        self.low = min(low, high)
        self.high = max(low, high)
    }
}

extension Prescription {
    /// First two integers of the reps text; nil for time-based work ("30–45 s", "4 min").
    public var repRange: RepRange? {
        guard repsEstimate != nil else { return nil }
        var nums: [Int] = []
        var cur = 0
        var inNumber = false
        for ch in reps {
            if ch.isASCII, let d = ch.wholeNumberValue {
                cur = cur * 10 + d
                inNumber = true
            } else if inNumber {
                nums.append(cur)
                cur = 0
                inNumber = false
            }
        }
        if inNumber { nums.append(cur) }
        guard let first = nums.first, first > 0 else { return nil }
        return RepRange(low: first, high: nums.count > 1 ? nums[1] : first)
    }

    /// Target reps in reserve from "RPE n" (RIR = 10 − RPE).
    public var targetRIR: Int? {
        guard let i = intensity, let r = i.range(of: #"RPE\s*(\d+)"#, options: .regularExpression) else { return nil }
        // The match is "RPE", optional spaces, then digits only.
        let digits: Substring = i[r].drop { !($0.isASCII && $0.isNumber) }
        guard let rpe = Int(digits) else { return nil }
        return max(0, 10 - rpe)
    }
}

/// What to load next time.
public struct LoadSuggestion: Sendable, Hashable {
    public enum Action: String, Sendable {
        case increase, hold, decrease, deload
    }

    public var kg: Double
    /// Target reps per set.
    public var reps: Int?
    public var action: Action
    /// Top load of the session the suggestion is based on.
    public var basisKg: Double
    public var reason: String

    public init(kg: Double, reps: Int?, action: Action, basisKg: Double, reason: String) {
        self.kg = kg
        self.reps = reps
        self.action = action
        self.basisKg = basisKg
        self.reason = reason
    }

    public var deltaKg: Double { kg - basisKg }
}

/// Double progression within the prescribed rep range, mesocycle-aware.
///
/// - Every working set reached the top of the range → add one increment (two when every set had ≥ 4 RIR,
///   except in the base week of a mesocycle) and restart at the bottom of the range.
/// - Even the best set fell short of the bottom of the range → −5 %.
/// - Otherwise hold the load and aim for one more rep per set.
/// - Deload week → −10 % of the last regular load. Deload sessions are never used as the basis.
public enum LoadAdvisor {
    /// Smallest sensible jump and the granularity loads are rounded to.
    public struct Steps: Sendable, Hashable {
        public var increment: Double
        public var granularity: Double
    }

    public static func steps(for e: Exercise, kg: Double) -> Steps {
        let eq = Set(e.equipment)
        if eq.contains(.barbell) || eq.contains(.trapBar) || eq.contains(.smith) || eq.contains(.landmine) {
            return Steps(increment: 2.5, granularity: 2.5)
        }
        if eq.contains(.dumbbells) {
            return kg < 10 ? Steps(increment: 1, granularity: 1) : Steps(increment: 2, granularity: 1)
        }
        if eq.contains(.kettlebells) { return Steps(increment: 4, granularity: 2) }
        // Machines, cables and added load on bodyweight moves.
        return Steps(increment: 2.5, granularity: 1.25)
    }

    public static func round(_ kg: Double, to step: Double, _ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Double {
        guard step > 0 else { return kg }
        return max(0, (kg / step).rounded(rule) * step)
    }

    public static func epley(kg: Double, reps: Int?) -> Double? {
        guard let r = reps, kg > 0, r >= 1, r <= 12 else { return nil }
        return kg * (1 + Double(r) / 30)
    }

    /// Generated session ids look like "w3s2" → week 3.
    static func weekOf(sessionId id: String?) -> Int? {
        guard let id, id.hasPrefix("w"), let s = id.firstIndex(of: "s") else { return nil }
        return Int(id[id.index(after: id.startIndex)..<s])
    }

    /// Groups one exercise's logs into sessions, oldest first. Per-set logs win over legacy single-weight logs
    /// of the same session; a re-logged set keeps its latest value.
    public static func sessions(
        _ logs: [SetLog], exerciseId: String, records: [WorkoutRecord] = [], calendar cal: Calendar = Progression.calendar()
    ) -> [ExerciseSession] {
        var groups: [String: [SetLog]] = [:]
        for l in logs where l.exerciseId == exerciseId {
            let key = "\(l.sessionId ?? "")|\(cal.startOfDay(for: l.date).timeIntervalSince1970)"
            groups[key, default: []].append(l)
        }
        var out: [ExerciseSession] = []
        for group in groups.values {
            let chrono = group.sorted { $0.date < $1.date }
            var bySet: [Int: SetLog] = [:]
            for l in chrono { if let i = l.setIndex { bySet[i] = l } }
            let sets: [SetLog]
            if bySet.isEmpty {
                sets = chrono.last.map { [$0] } ?? []
            } else {
                sets = bySet.keys.sorted().compactMap { bySet[$0] }
            }
            guard let first = chrono.first else { continue }
            let sid = first.sessionId
            let rec = records.first { $0.sessionId == sid && cal.isDate($0.startedAt, inSameDayAs: first.date) }
            let week = rec?.week ?? weekOf(sessionId: sid)
            let deload = rec?.deload ?? (week == Generator.mesocycleWeeks)
            out.append(ExerciseSession(date: first.date, sessionId: sid, week: week, deload: deload, sets: sets))
        }
        return out.sorted { $0.date < $1.date }
    }

    /// Suggested load for the next session of `exercise`, or nil when nothing was logged yet.
    /// `history` is oldest first (see `sessions`); `week`/`deload` describe the session about to be trained.
    public static func suggest(
        exercise e: Exercise, prescription p: Prescription, week: Int, deload: Bool, history: [ExerciseSession]
    ) -> LoadSuggestion? {
        let logged = history.filter { !$0.sets.isEmpty }
        guard let latest = logged.last else { return nil }
        // Deload loads say nothing about capacity: progress from the last regular session.
        let basis = logged.last { !$0.deload } ?? latest
        let kg = basis.topKg
        let range = p.repRange
        let s = steps(for: e, kg: kg)

        if deload {
            var target = round(kg * 0.9, to: s.granularity)
            if kg > 0 && target >= kg { target = max(0, kg - s.granularity) }
            return LoadSuggestion(kg: target, reps: range?.low, action: .deload, basisKg: kg,
                                  reason: "Deload week: −10 % from \(formatKg(kg)) kg")
        }

        let working = basis.sets.filter { $0.kg >= kg - 0.001 }
        let reps = working.compactMap(\.reps)
        guard let range, !working.isEmpty, reps.count == working.count, let minReps = reps.min(), let maxReps = reps.max() else {
            return LoadSuggestion(kg: kg, reps: range?.low, action: .hold, basisKg: kg, reason: "Repeat last load: \(formatKg(kg)) kg")
        }

        if minReps >= range.high {
            let rirs = working.compactMap(\.rir)
            let baseWeek = week % Generator.mesocycleWeeks == 1
            let easy = !baseWeek && rirs.count == working.count && (rirs.min() ?? 0) >= 4
            var target = round(kg + s.increment * (easy ? 2 : 1), to: s.granularity)
            if target <= kg { target = kg + s.granularity }
            return LoadSuggestion(kg: target, reps: range.low, action: .increase, basisKg: kg,
                                  reason: "All sets hit \(range.high) reps at \(formatKg(kg)) kg → +\(formatKg(target - kg)) kg")
        }
        if maxReps < range.low {
            var target = round(kg * 0.95, to: s.granularity)
            if kg > 0 && target >= kg { target = max(0, kg - s.granularity) }
            return LoadSuggestion(kg: target, reps: range.low, action: .decrease, basisKg: kg,
                                  reason: "Below \(range.low) reps at \(formatKg(kg)) kg → −5 %")
        }
        let target = min(range.high, max(range.low, minReps + 1))
        return LoadSuggestion(kg: kg, reps: target, action: .hold, basisKg: kg,
                              reason: "Hold \(formatKg(kg)) kg, aim for \(target) reps on every set")
    }

    /// "80", "82.5", "1.25".
    public static func formatKg(_ kg: Double) -> String {
        var s = String(format: "%.2f", kg)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
