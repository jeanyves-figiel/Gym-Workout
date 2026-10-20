import Foundation

// Water through the day (#520, designs A + B + C from `nutrition-pointers/water-reminders.png`): the day's glasses
// spread over the waking hours, more in the 2 h before training and the hour after, less before bed. Reminders
// land on that pace, and only when the member is behind (or at the interval they picked).

public enum WaterRemind: String, Codable, CaseIterable, Sendable, Identifiable {
    case off, behind, every2h, hourly
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off: "Off"
        case .behind: "When behind"
        case .every2h: "Every 2 h"
        case .hourly: "Every hour"
        }
    }

    /// Minutes between checks.
    public var interval: Int { self == .hourly ? 60 : 120 }
}

/// Member settings for water reminders. Sleep hours come from Fuel's wake and sleep times.
public struct WaterPrefs: Codable, Equatable, Sendable {
    public var remind: WaterRemind
    /// No reminder during a planned or running training.
    public var quietWorkouts: Bool

    public init(remind: WaterRemind = .behind, quietWorkouts: Bool = true) {
        self.remind = remind
        self.quietWorkouts = quietWorkouts
    }
}

/// One reminder for later today.
public struct WaterNudge: Hashable, Sendable {
    /// Minutes after midnight.
    public var minute: Int
    public var title: String
    public var body: String
}

/// A stretch of the day on the pace chart.
public struct WaterBucket: Hashable, Sendable, Identifiable {
    /// Minutes after midnight.
    public var start: Int
    public var glasses: Double
    /// A training starts or runs in it.
    public var training: Bool
    public var id: Int { start }
}

public enum WaterPace {
    static let step = 30

    public static func clock(_ m: Int) -> String { String(format: "%02d:%02d", m / 60 % 24, m % 60) }

    /// Weight of each 30-min step from waking to sleep.
    static func steps(_ plan: FuelPlan, prefs: FuelPrefs, calendar cal: Calendar) -> [(minute: Int, weight: Double)] {
        let wake = max(4 * 60, min(12 * 60, prefs.wake))
        let sleep = max(wake + 8 * 60, min(27 * 60, prefs.sleep))
        let start = cal.startOfDay(for: plan.day)
        let acts = plan.activities.map { a -> (Int, Int) in
            let s = Int(a.start.timeIntervalSince(start) / 60)
            return (s, s + a.minutes)
        }
        return stride(from: wake, to: sleep, by: step).map { m in
            var w = 1.0
            if acts.contains(where: { m >= $0.0 - 120 && m < $0.0 }) { w = 2 }
            if acts.contains(where: { m >= $0.1 && m < $0.1 + 60 }) { w = 2.5 }
            if m >= sleep - 120 { w = 0.3 }
            return (m, w)
        }
    }

    /// Glasses to have had by `minute` to stay on pace.
    public static func expected(by minute: Int, plan: FuelPlan, prefs: FuelPrefs, calendar cal: Calendar = Progression.calendar()) -> Int {
        let s = steps(plan, prefs: prefs, calendar: cal)
        let total = s.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return 0 }
        let done = s.reduce(0.0) { acc, x in
            if x.minute + step <= minute { return acc + x.weight }
            if x.minute < minute { return acc + x.weight * Double(minute - x.minute) / Double(step) }
            return acc
        }
        return min(plan.glasses, Int((Double(plan.glasses) * done / total).rounded()))
    }

    /// The day in 2-hour stretches for the pace chart.
    public static func buckets(_ plan: FuelPlan, prefs: FuelPrefs, calendar cal: Calendar = Progression.calendar()) -> [WaterBucket] {
        let s = steps(plan, prefs: prefs, calendar: cal)
        let total = s.reduce(0) { $0 + $1.weight }
        guard total > 0, let first = s.first?.minute else { return [] }
        let start = cal.startOfDay(for: plan.day)
        let acts = plan.activities.map { a -> (Int, Int) in
            let m = Int(a.start.timeIntervalSince(start) / 60)
            return (m, m + a.minutes)
        }
        var out: [WaterBucket] = []
        for x in s {
            let b = first + (x.minute - first) / 120 * 120
            let g = Double(plan.glasses) * x.weight / total
            if out.last?.start == b { out[out.count - 1].glasses += g } else {
                out.append(WaterBucket(start: b, glasses: g, training: acts.contains { $0.0 < b + 120 && $0.1 > b }))
            }
        }
        return out
    }

    /// Reminders for the rest of the day after `now` (minutes), given `glasses` so far. Recomputed each time a
    /// glass is logged, so "behind" holds for the glasses known now.
    public static func nudges(_ plan: FuelPlan, glasses: Int, prefs: FuelPrefs, water: WaterPrefs, now: Int,
                              quiet: (Int) -> Bool = { _ in false }, calendar cal: Calendar = Progression.calendar()) -> [WaterNudge] {
        guard water.remind != .off, glasses < plan.glasses else { return [] }
        let wake = max(4 * 60, min(12 * 60, prefs.wake))
        let sleep = max(wake + 8 * 60, min(27 * 60, prefs.sleep))
        let start = cal.startOfDay(for: plan.day)
        let acts = plan.activities.sorted { $0.start < $1.start }.map { a -> (start: Int, end: Int, title: String) in
            let m = Int(a.start.timeIntervalSince(start) / 60)
            return (m, m + a.minutes, a.title)
        }
        var out: [WaterNudge] = []
        for m in stride(from: wake + water.remind.interval, through: sleep - 60, by: water.remind.interval) where m > now {
            guard !quiet(m % (24 * 60)) else { continue }
            if water.quietWorkouts, acts.contains(where: { m >= $0.start && m < $0.end }) { continue }
            let aim = expected(by: m, plan: plan, prefs: prefs, calendar: cal)
            if water.remind == .behind && aim <= glasses { continue }
            var body = "\(glasses) of \(plan.glasses) so far. Aim for \(max(aim, glasses + 1)) by \(clock(m))."
            if let a = acts.first(where: { $0.start > m && $0.start - m <= 180 }) {
                body += " \(a.title) at \(clock(a.start)), so start topping up."
            } else if acts.contains(where: { m >= $0.end && m - $0.end <= 90 }) {
                body += " Top up after your training."
            }
            out.append(WaterNudge(minute: m, title: "Time for a glass 💧", body: body))
        }
        return Array(out.prefix(12))
    }
}
