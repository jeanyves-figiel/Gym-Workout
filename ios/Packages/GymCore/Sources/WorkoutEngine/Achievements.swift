import Foundation

public enum BadgeTier: Int, Sendable, Comparable {
    case bronze = 1, silver, gold
    public static func < (a: BadgeTier, b: BadgeTier) -> Bool { a.rawValue < b.rawValue }
}

public struct Badge: Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let tier: BadgeTier
    public let current: Double
    public let target: Double
    public let unlockedAt: Date?

    public var unlocked: Bool { unlockedAt != nil }
    public var progress: Double { min(1, current / max(target, 1e-9)) }
}

/// Milestones computed from history + weight logs. Pure and deterministic.
public enum Achievements {
    private struct Def: Sendable {
        let id, title, detail, symbol: String
        let tier: BadgeTier
        let target: Double
        /// Cumulative metric after each record (sorted by date).
        let metric: Metric
    }

    private enum Metric: Sendable {
        case workouts, volume, minutes, streak, prs, shoulderSets, stretchSessions
        case anyRecord(@Sendable (WorkoutRecord) -> Bool)
        case cycleComplete
    }

    private static let defs: [Def] = [
        Def(id: "first", title: "First rep", detail: "Complete your first session", symbol: "figure.walk", tier: .bronze, target: 1, metric: .workouts),
        Def(id: "w10", title: "Committed", detail: "10 sessions", symbol: "10.circle.fill", tier: .bronze, target: 10, metric: .workouts),
        Def(id: "w25", title: "Regular", detail: "25 sessions", symbol: "25.circle.fill", tier: .silver, target: 25, metric: .workouts),
        Def(id: "w50", title: "Dedicated", detail: "50 sessions", symbol: "50.circle.fill", tier: .silver, target: 50, metric: .workouts),
        Def(id: "w100", title: "Centurion", detail: "100 sessions", symbol: "crown.fill", tier: .gold, target: 100, metric: .workouts),
        Def(id: "s2", title: "On a roll", detail: "Hit your weekly target 2 weeks in a row", symbol: "flame", tier: .bronze, target: 2, metric: .streak),
        Def(id: "s4", title: "Consistent", detail: "4-week streak", symbol: "flame.fill", tier: .silver, target: 4, metric: .streak),
        Def(id: "s8", title: "Unbreakable", detail: "8-week streak", symbol: "bolt.shield.fill", tier: .gold, target: 8, metric: .streak),
        Def(id: "v10", title: "Ten tonnes", detail: "Lift 10 000 kg total", symbol: "scalemass", tier: .bronze, target: 10_000, metric: .volume),
        Def(id: "v50", title: "Heavy lifter", detail: "Lift 50 000 kg total", symbol: "scalemass.fill", tier: .silver, target: 50_000, metric: .volume),
        Def(id: "v100", title: "Hundred tonnes", detail: "Lift 100 000 kg total", symbol: "trophy.fill", tier: .gold, target: 100_000, metric: .volume),
        Def(id: "h10", title: "Ten hours", detail: "10 h of training", symbol: "clock.fill", tier: .bronze, target: 600, metric: .minutes),
        Def(id: "h50", title: "Time invested", detail: "50 h of training", symbol: "hourglass", tier: .gold, target: 3000, metric: .minutes),
        Def(id: "pr1", title: "New best", detail: "Beat a previous weight", symbol: "arrow.up.right.circle.fill", tier: .bronze, target: 1, metric: .prs),
        Def(id: "pr10", title: "PR hunter", detail: "Beat 10 previous bests", symbol: "chart.line.uptrend.xyaxis", tier: .silver, target: 10, metric: .prs),
        Def(id: "shoulders", title: "Bulletproof shoulders", detail: "100 shoulder-health sets", symbol: "shield.lefthalf.filled", tier: .silver, target: 100, metric: .shoulderSets),
        Def(id: "supple", title: "Supple", detail: "Finish every stretch in 10 sessions", symbol: "figure.cooldown", tier: .silver, target: 10, metric: .stretchSessions),
        Def(id: "complete", title: "Complete athlete", detail: "Warm-up, power, strength, mobility, cardio and stretching in one session",
            symbol: "star.circle.fill", tier: .silver, target: 1, metric: .anyRecord { r in r.categories.isSuperset(of: Set(Category.allCases)) }),
        Def(id: "deload", title: "Smart recovery", detail: "Train through a deload week", symbol: "leaf.fill", tier: .bronze, target: 1,
            metric: .anyRecord { $0.deload }),
        Def(id: "cycle", title: "Full cycle", detail: "Train in all 4 weeks of a mesocycle", symbol: "arrow.triangle.2.circlepath.circle.fill",
            tier: .gold, target: 1, metric: .cycleComplete),
        Def(id: "early", title: "Early bird", detail: "Start a session before 7:00", symbol: "sunrise.fill", tier: .bronze, target: 1,
            metric: .anyRecord { r in Calendar.current.component(.hour, from: r.startedAt) < 7 }),
        Def(id: "long", title: "Long haul", detail: "A single session of 75 min or more", symbol: "timer", tier: .bronze, target: 1,
            metric: .anyRecord { $0.durationSec >= 75 * 60 }),
    ]

    public static func evaluate(
        records: [WorkoutRecord], weights: [WeightEntry], targetPerWeek: Int,
        calendar cal: Calendar = Progression.calendar()
    ) -> [Badge] {
        let sorted = records.sorted { $0.startedAt < $1.startedAt }
        let prs = Progression.prCount(weights)
        let target = max(1, targetPerWeek)

        // Running values after each record.
        var workouts = 0, minutes = 0.0, volume = 0.0, shoulder = 0.0, stretch = 0.0
        var weekCounts: [Date: Int] = [:]
        var cycleWeeks: Set<Int> = []
        var timeline: [(date: Date, workouts: Double, volume: Double, minutes: Double, streak: Double, shoulder: Double, stretch: Double, cycle: Bool)] = []
        for r in sorted {
            workouts += 1
            minutes += Double(r.durationSec) / 60
            volume += r.volumeKg
            shoulder += Double(r.exercises.filter { Exercise.find($0.exerciseId)?.pattern == .shoulderHealth }.reduce(0) { $0 + $1.setsDone })
            let stretches = r.exercises.filter { $0.category == .stretch }
            if !stretches.isEmpty && stretches.allSatisfy({ $0.setsDone >= $0.setsPlanned }) { stretch += 1 }
            weekCounts[Progression.weekStart(r.startedAt, cal), default: 0] += 1
            if r.week == 1 { cycleWeeks = [] }
            cycleWeeks.insert(r.week)
            timeline.append((r.startedAt, Double(workouts), volume, minutes,
                             Double(streak(endingAt: r.startedAt, counts: weekCounts, target: target, cal: cal)),
                             shoulder, stretch, cycleWeeks.isSuperset(of: [1, 2, 3, 4])))
        }

        return defs.map { d in
            var current = 0.0
            var unlocked: Date?
            switch d.metric {
            case let .anyRecord(pred):
                if let hit = sorted.first(where: pred) { current = 1; unlocked = hit.startedAt }
            case .prs:
                current = Double(prs.last?.1 ?? 0)
                unlocked = prs.first { Double($0.1) >= d.target }?.0
            default:
                func value(_ t: (date: Date, workouts: Double, volume: Double, minutes: Double, streak: Double, shoulder: Double, stretch: Double, cycle: Bool)) -> Double {
                    switch d.metric {
                    case .workouts: t.workouts
                    case .volume: t.volume
                    case .minutes: t.minutes
                    case .streak: t.streak
                    case .shoulderSets: t.shoulder
                    case .stretchSessions: t.stretch
                    case .cycleComplete: t.cycle ? 1 : 0
                    default: 0
                    }
                }
                current = timeline.map(value).max() ?? 0
                unlocked = timeline.first { value($0) >= d.target }?.date
            }
            return Badge(id: d.id, title: d.title, detail: d.detail, symbol: d.symbol, tier: d.tier,
                         current: min(current, d.target), target: d.target, unlockedAt: unlocked)
        }
    }

    /// Consecutive weeks meeting the target, ending with the week containing `date`
    /// (that week counts only if already met).
    private static func streak(endingAt date: Date, counts: [Date: Int], target: Int, cal: Calendar) -> Int {
        var w = Progression.weekStart(date, cal)
        var n = 0
        while (counts[w] ?? 0) >= target {
            n += 1
            w = cal.date(byAdding: .weekOfYear, value: -1, to: w)!
        }
        return n
    }
}
