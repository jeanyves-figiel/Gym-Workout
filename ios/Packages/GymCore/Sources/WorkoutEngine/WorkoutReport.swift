import Foundation

/// Finish screen charts + lift report (#801, design B + A from `workout-recap/proposals-ba.png`): the volume of the
/// last workouts of the same focus, an est. 1RM line per lift, and every lift of today against the last time it was done.
public struct WorkoutReport: Equatable, Sendable {
    public struct Point: Equatable, Sendable, Identifiable {
        public var date: Date
        public var value: Double
        /// This workout.
        public var today: Bool
        public var id: Date { date }

        public init(date: Date, value: Double, today: Bool = false) {
            self.date = date
            self.value = value
            self.today = today
        }
    }

    /// Today against the last time: the first thing that differs, load first, then reps, then sets.
    public enum Change: Equatable, Sendable {
        case new
        case heavier(Double), lighter(Double)
        case moreReps(Int), fewerReps(Int)
        case moreSets(Int), fewerSets(Int)
        case same

        public var better: Bool? {
            switch self {
            case .heavier, .moreReps, .moreSets: true
            case .lighter, .fewerReps, .fewerSets: false
            case .new, .same: nil
            }
        }

        /// "+2.5 kg", "−1 set", "=", "NEW".
        public var label: String {
            switch self {
            case .new: "NEW"
            case .same: "="
            case let .heavier(kg): "+\(LoadAdvisor.formatKg(kg)) kg"
            case let .lighter(kg): "−\(LoadAdvisor.formatKg(kg)) kg"
            case let .moreReps(n): "+\(n) rep\(n == 1 ? "" : "s")"
            case let .fewerReps(n): "−\(n) rep\(n == 1 ? "" : "s")"
            case let .moreSets(n): "+\(n) set\(n == 1 ? "" : "s")"
            case let .fewerSets(n): "−\(n) set\(n == 1 ? "" : "s")"
            }
        }
    }

    public struct Lift: Equatable, Sendable, Identifiable {
        public var uid: String
        public var exerciseId: String
        public var name: String
        public var category: Category
        public var setsDone: Int
        public var setsPlanned: Int
        public var reps: Int?
        public var kg: Double?
        /// Today's logged sets, by set index (empty when only the record is known).
        public var sets: [SetLog]
        /// The last time this exercise was done before today.
        public var last: ExerciseRecord?
        public var lastDate: Date?
        public var change: Change
        /// Up to `points` sessions, oldest first, today last.
        public var topKg: [Point]
        public var oneRepMax: [Point]
        public var volume: [Point]
        /// Today's est. 1RM beats every earlier one.
        public var newBest: Bool
        public var id: String { uid }

        public init(
            uid: String, exerciseId: String, name: String, category: Category, setsDone: Int, setsPlanned: Int, reps: Int?, kg: Double?,
            sets: [SetLog], last: ExerciseRecord?, lastDate: Date?, change: Change, topKg: [Point], oneRepMax: [Point], volume: [Point],
            newBest: Bool
        ) {
            self.uid = uid
            self.exerciseId = exerciseId
            self.name = name
            self.category = category
            self.setsDone = setsDone
            self.setsPlanned = setsPlanned
            self.reps = reps
            self.kg = kg
            self.sets = sets
            self.last = last
            self.lastDate = lastDate
            self.change = change
            self.topKg = topKg
            self.oneRepMax = oneRepMax
            self.volume = volume
            self.newBest = newBest
        }

        /// "4 × 8 · 80 kg", "2 of 3 sets · 10 reps".
        public var line: String {
            let load = kg.map { " · \(LoadAdvisor.formatKg($0)) kg" } ?? " · body weight"
            if setsDone < setsPlanned { return "\(setsDone) of \(setsPlanned) sets" + (reps.map { " × \($0)" } ?? "") + load }
            return "\(setsDone)" + (reps.map { " × \($0)" } ?? " sets") + load
        }

        /// The sparkline: top kg when the lift has a load, else reps × sets.
        public var trend: [Point] { topKg.count >= 2 ? topKg : volume.count >= 2 ? volume : topKg }
    }

    public var volumeKg: Double
    /// Workouts of the same focus with a load, oldest first, today last.
    public var volume: [Point]
    /// Today against the average of the earlier points (0.08 = +8 %); nil without earlier ones.
    public var volumeVsAverage: Double?
    public var lifts: [Lift]

    public init(volumeKg: Double, volume: [Point], volumeVsAverage: Double?, lifts: [Lift]) {
        self.volumeKg = volumeKg
        self.volume = volume
        self.volumeVsAverage = volumeVsAverage
        self.lifts = lifts
    }

    /// Lifts with a 1RM line, most volume today first, for the chart chips.
    public var charted: [Lift] {
        Array(lifts.filter { !$0.oneRepMax.isEmpty }.sorted { ($0.volume.last?.value ?? 0) > ($1.volume.last?.value ?? 0) }.prefix(4))
    }

    public var isEmpty: Bool { lifts.isEmpty }

    /// Categories that make the lift report (warm-up, mobility, stretch and cardio stay out).
    static let liftCategories: Set<Category> = [.strength, .power]

    /// `history`: every workout, any order (today's record may be in it); `logs`: per-set logs; `points`: chart length.
    public static func build(_ r: WorkoutRecord, history: [WorkoutRecord], logs: [SetLog] = [], points: Int = 8) -> WorkoutReport {
        let earlier = history.filter { $0.id != r.id && $0.startedAt < r.startedAt }.sorted { $0.startedAt < $1.startedAt }

        let sameFocus = earlier.filter { $0.focus == r.focus && $0.volumeKg > 0 }.suffix(max(0, points - 1))
        var volume = sameFocus.map { Point(date: $0.startedAt, value: $0.volumeKg) }
        if r.volumeKg > 0 { volume.append(Point(date: r.startedAt, value: r.volumeKg, today: true)) }
        let before = sameFocus.map(\.volumeKg)
        let vsAverage: Double? = before.isEmpty || r.volumeKg <= 0 ? nil : r.volumeKg / (before.reduce(0, +) / Double(before.count)) - 1

        var seen = Set<String>()
        var lifts: [Lift] = []
        for e in r.exercises where e.setsDone > 0 && liftCategories.contains(e.category) && seen.insert(e.exerciseId).inserted {
            let past = earlier.compactMap { h in
                h.exercises.first { $0.exerciseId == e.exerciseId && $0.setsDone > 0 && liftCategories.contains($0.category) }.map { (date: h.startedAt, rec: $0) }
            }
            let last = past.last
            let series = (past + [(date: r.startedAt, rec: e)]).suffix(points)
            func line(_ value: (ExerciseRecord) -> Double?) -> [Point] {
                series.compactMap { s in value(s.rec).flatMap { $0 > 0 ? Point(date: s.date, value: $0, today: s.date == r.startedAt) : nil } }
            }
            let oneRM = line(\.estimatedOneRepMax)
            let bestBefore = past.compactMap { $0.rec.estimatedOneRepMax }.max()
            let today = todaysSets(e.exerciseId, record: r, logs: logs, from: setsFrom(r, history: history))
            lifts.append(Lift(
                uid: e.uid, exerciseId: e.exerciseId, name: Exercise.find(e.exerciseId)?.name ?? e.exerciseId,
                category: e.category, setsDone: e.setsDone, setsPlanned: e.setsPlanned,
                reps: e.reps.map { Int($0.rounded()) }, kg: e.weightKg.flatMap { $0 > 0 ? $0 : nil },
                sets: today, last: last?.rec, lastDate: last?.date, change: change(e, last: last?.rec),
                topKg: line(\.weightKg), oneRepMax: oneRM,
                volume: line { $0.volumeKg > 0 ? $0.volumeKg : Double($0.setsDone) * ($0.reps ?? 0) },
                newBest: bestBefore.map { b in (e.estimatedOneRepMax ?? 0) > b + 0.25 } ?? false))
        }
        return WorkoutReport(volumeKg: r.volumeKg, volume: volume, volumeVsAverage: vsAverage, lifts: lifts)
    }

    static func change(_ now: ExerciseRecord, last: ExerciseRecord?) -> Change {
        guard let last else { return .new }
        let kg = (now.weightKg ?? 0) - (last.weightKg ?? 0)
        if (now.weightKg ?? 0) > 0, (last.weightKg ?? 0) > 0, abs(kg) >= 0.01 { return kg > 0 ? .heavier(kg) : .lighter(-kg) }
        let reps = Int((now.reps ?? 0).rounded()) - Int((last.reps ?? 0).rounded())
        if reps != 0 { return reps > 0 ? .moreReps(reps) : .fewerReps(-reps) }
        let sets = now.setsDone - last.setsDone
        if sets != 0 { return sets > 0 ? .moreSets(sets) : .fewerSets(-sets) }
        return .same
    }

    /// Earliest set log that can belong to `r` (#817): a run closed and resumed later gets a `startedAt` that
    /// leaves its first sets out, so the window opens at the start of that day, never before the end of an earlier
    /// workout of the same session.
    public static func setsFrom(_ r: WorkoutRecord, history: [WorkoutRecord], calendar: Calendar = .current) -> Date {
        let floor = history.filter { $0.id != r.id && $0.sessionId == r.sessionId && $0.startedAt < r.startedAt }.map(\.endedAt).max()
        let from = min(r.startedAt.addingTimeInterval(-600), calendar.startOfDay(for: r.startedAt))
        guard let floor else { return from }
        return max(from, min(floor, r.startedAt.addingTimeInterval(-60)))
    }

    /// This workout's per-set logs for one exercise (same session, from `from` to an hour after the end).
    static func todaysSets(_ exerciseId: String, record r: WorkoutRecord, logs: [SetLog], from: Date? = nil) -> [SetLog] {
        let from = from ?? r.startedAt.addingTimeInterval(-600), to = r.endedAt.addingTimeInterval(3600)
        var bySet: [Int: SetLog] = [:]
        for l in logs.sorted(by: { $0.date < $1.date })
        where l.exerciseId == exerciseId && l.sessionId == r.sessionId && l.date >= from && l.date <= to {
            if let i = l.setIndex { bySet[i] = l }
        }
        return bySet.keys.sorted().compactMap { bySet[$0] }
    }
}
