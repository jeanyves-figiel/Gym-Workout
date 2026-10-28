import Foundation

// Plateau explainer (#875, epic #865 C2, design A + C from `ai-epic/c2.png`): rules find a stalled lift and its likely
// causes; the on-device Coach words the why. The fix is a set style (#499) the member applies in a tap.

/// Why a lift may have stopped going up, from the flat weeks vs the same span before them.
public enum PlateauCause: Hashable, Sendable {
    /// Sets of the lift per week fell by `percent`.
    case volumeDrop(percent: Int)
    /// Workouts done vs planned in the flat weeks.
    case skipped(done: Int, planned: Int)
    /// More workouts without lifting (climbing, runs, mobility) than before.
    case otherTraining(extra: Int)
    /// Last night under `Plateaus.shortSleep` hours.
    case shortSleep(hours: Double)
    /// Nothing else changed: same sets and reps every week.
    case sameScheme

    /// One fact for the on-device Coach.
    public var fact: String {
        switch self {
        case .volumeDrop(let p): "Sets of this lift per week dropped \(p)% vs the weeks before."
        case .skipped(let done, let planned): "Only \(done) of \(planned) planned workouts done in those weeks."
        case .otherTraining(let n): "\(n) more workouts without lifting (other sports) than the weeks before."
        case .shortSleep(let h): "Slept \(String(format: "%.1f", h)) h last night."
        case .sameScheme: "Same sets, reps and rest every week."
        }
    }

    /// Few words after "likely:" on the finish screen.
    public var short: String {
        switch self {
        case .volumeDrop: "less volume"
        case .skipped: "skipped sessions"
        case .otherTraining: "more other training"
        case .shortSleep: "short sleep"
        case .sameScheme: "same sets every week"
        }
    }
}

/// A lift whose weekly best estimated 1RM stayed flat for 3 weeks or more, why, and the set style to try.
public struct StalledLift: Hashable, Sendable, Identifiable {
    public var exerciseId: String
    public var weeks: Int
    /// Best estimated 1RM so far.
    public var kg: Double
    /// Monday of the first flat week.
    public var since: Date
    public var causes: [PlateauCause]
    /// Set style to switch to; nil when the lift has no set styles or all were tried.
    public var fix: SetStyle?
    public var id: String { exerciseId }
}

public enum Plateaus {
    /// Sleep under this counts as short (as `Readiness.minSleep`).
    public static let shortSleep = 6.0
    /// The lift must have been done this recently to count.
    static let recentDays = 14

    /// The stalled lift, when its weekly bests stayed within 1 % of the best before them for 3+ weeks and it was done
    /// in the last 2 weeks. `style`: the set style the member uses now; `sleepHours`: last night, from Apple Health.
    public static func stalled(
        _ exerciseId: String, records: [WorkoutRecord], sessionsPerWeek: Int, sleepHours: Double? = nil,
        style: SetStyle = .straight, now: Date = Date(), calendar cal: Calendar = Progression.calendar()
    ) -> StalledLift? {
        let rs = records.filter { !$0.deload && $0.startedAt <= now }
        let trend = Progression.oneRepMaxTrend(exerciseId, records: rs, calendar: cal)
        guard let last = trend.last, let cutoff = cal.date(byAdding: .day, value: -recentDays, to: now), last.0 >= Progression.weekStart(cutoff, cal),
              let weeks = Growth.flatWeeks(trend, since: .distantPast) else { return nil }
        let since = trend[trend.count - weeks].0
        let best = trend.map(\.1).max() ?? last.1
        let span = max(1, cal.dateComponents([.day], from: since, to: now).day ?? 7 * weeks)
        guard let before = cal.date(byAdding: .day, value: -span, to: since) else { return nil }
        let flat = rs.filter { $0.startedAt >= since }
        let prior = rs.filter { $0.startedAt >= before && $0.startedAt < since }

        var causes: [PlateauCause] = []
        func sets(_ rs: [WorkoutRecord]) -> Int {
            rs.flatMap(\.exercises).filter { $0.exerciseId == exerciseId }.reduce(0) { $0 + $1.setsDone }
        }
        let setsNow = sets(flat), setsBefore = sets(prior)
        if setsBefore > 0, Double(setsNow) <= Double(setsBefore) * 0.85 {
            causes.append(.volumeDrop(percent: Int(((1 - Double(setsNow) / Double(setsBefore)) * 100).rounded())))
        }
        let planned = max(1, sessionsPerWeek) * weeks
        let lifting = flat.filter { $0.categories.contains(.strength) }.count
        if Double(lifting) < Double(planned) * 0.75 { causes.append(.skipped(done: lifting, planned: planned)) }
        func other(_ rs: [WorkoutRecord]) -> Int { rs.filter { !$0.categories.contains(.strength) }.count }
        let extra = other(flat) - other(prior)
        if extra >= 2 { causes.append(.otherTraining(extra: extra)) }
        if let h = sleepHours, h > 0, h < shortSleep { causes.append(.shortSleep(hours: h)) }
        if causes.isEmpty { causes.append(.sameScheme) }

        return StalledLift(exerciseId: exerciseId, weeks: weeks, kg: best, since: since, causes: causes,
                           fix: fix(for: exerciseId, causes: causes, current: style))
    }

    /// Less volume: top set + back-offs brings sets back; otherwise heavier work (clusters, % of 1RM, AMRAP).
    static func fix(for exerciseId: String, causes: [PlateauCause], current: SetStyle) -> SetStyle? {
        guard let e = Exercise.find(exerciseId), ProSets.eligible(e) else { return nil }
        let lessVolume = causes.contains { if case .volumeDrop = $0 { true } else { false } }
        let order: [SetStyle] = lessVolume ? [.topBackoff, .cluster, .percent, .amrap] : [.cluster, .topBackoff, .percent, .amrap]
        return order.first { $0 != current }
    }

    /// Stalled lifts of one workout, longest flat first.
    public static func stalled(
        in record: WorkoutRecord, records: [WorkoutRecord], sessionsPerWeek: Int, sleepHours: Double? = nil,
        styles: [String: SetStyle] = [:], now: Date = Date(), calendar cal: Calendar = Progression.calendar()
    ) -> [StalledLift] {
        let ids = record.exercises.filter { $0.setsDone > 0 && $0.category == .strength }.map(\.exerciseId)
        return Array(Set(ids)).sorted().compactMap {
            stalled($0, records: records, sessionsPerWeek: sessionsPerWeek, sleepHours: sleepHours,
                    style: styles[$0] ?? .straight, now: now, calendar: cal)
        }
        .sorted { $0.weeks != $1.weeks ? $0.weeks > $1.weeks : $0.exerciseId < $1.exerciseId }
    }
}
