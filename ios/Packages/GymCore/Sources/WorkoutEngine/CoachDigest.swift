import Foundation

/// What Coach sees of the member's own training (#1010): recent workouts, lift trends, how often they train and the
/// body weight trend, as short plain lines. No ids, no names: only the member's numbers, built on the device and
/// capped so the chat request stays small.
public enum CoachDigest {
    /// Most lines sent; each line at most `lineLimit` characters (the server checks the same caps).
    public static let maxLines = 24
    public static let lineLimit = 160

    /// All lines, most useful first: totals, recent workouts, lift trends, body weight.
    /// `records`: any order. `weights`: body weight points, any order (logged + Health).
    public static func lines(records: [WorkoutRecord], weights: [BodyMeasurements.Point] = [], now: Date = Date(),
                             calendar cal: Calendar = .current, name: (String) -> String? = { Exercise.find($0)?.name }) -> [String] {
        let done = records.filter { $0.totalSets > 0 && $0.startedAt <= now }.sorted { $0.startedAt > $1.startedAt }
        var out: [String] = []
        if let t = totals(done, now: now) { out.append(t) }
        out += sessions(done, now: now, calendar: cal, name: name)
        out += lifts(done, now: now, name: name)
        if let w = bodyWeight(weights, now: now, calendar: cal) { out.append(w) }
        return Array(out.map { String($0.prefix(lineLimit)) }.prefix(maxLines))
    }

    /// "Workouts: 9 in the last 28 days (2.3 per week), 7 in the 28 days before." Nil with no history.
    static func totals(_ done: [WorkoutRecord], now: Date) -> String? {
        guard let last = done.first else { return nil }
        let day = 86_400.0
        let recent = done.filter { now.timeIntervalSince($0.startedAt) < 28 * day }.count
        let before = done.filter { (28 * day ..< 56 * day).contains(now.timeIntervalSince($0.startedAt)) }.count
        let ago = Int(now.timeIntervalSince(last.startedAt) / day)
        let lastText = ago == 0 ? "today" : ago == 1 ? "yesterday" : "\(ago) days ago"
        return "Workouts: \(recent) in the last 28 days (\(num(Double(recent) / 4)) per week), \(before) in the 28 days before; "
            + "\(done.count) logged in all; last one \(lastText)."
    }

    /// The last 8 workouts, newest first: date, title, minutes, sets, volume and the heaviest work sets.
    static func sessions(_ done: [WorkoutRecord], now: Date, calendar cal: Calendar, name: (String) -> String?) -> [String] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.dateFormat = "EEE d MMM"
        return done.prefix(8).map { r in
            let ago = cal.dateComponents([.day], from: cal.startOfDay(for: r.startedAt), to: cal.startOfDay(for: now)).day ?? 0
            let when = f.string(from: r.startedAt) + (ago == 0 ? " (today)" : ago == 1 ? " (yesterday)" : "")
            var head = "\(when): \(r.title), \(max(1, r.durationSec / 60)) min, \(r.totalSets) sets"
            if r.volumeKg > 0 { head += ", \(Int(r.volumeKg.rounded())) kg volume" }
            if r.deload { head += ", deload week" }
            let top = r.exercises
                .filter { $0.setsDone > 0 && ($0.weightKg ?? 0) > 0 }
                .sorted { $0.volumeKg > $1.volumeKg }
                .prefix(3)
                .compactMap { e -> String? in
                    guard let n = name(e.exerciseId), let w = e.weightKg else { return nil }
                    let reps = e.reps.map { "x\(num($0))" } ?? ""
                    return "\(n) \(e.setsDone)\(reps) at \(num(w)) kg"
                }
            return top.isEmpty ? head + "." : head + "; " + top.joined(separator: ", ") + "."
        }
    }

    /// Up to 6 lifts trained most in the last 8 weeks: estimated 1RM in the last 2 weeks vs 3 to 6 weeks ago, and best.
    static func lifts(_ done: [WorkoutRecord], now: Date, name: (String) -> String?) -> [String] {
        let day = 86_400.0
        var count: [String: Int] = [:], recent: [String: Double] = [:], before: [String: Double] = [:], best: [String: Double] = [:]
        for r in done {
            let age = now.timeIntervalSince(r.startedAt)
            for e in r.exercises where e.setsDone > 0 {
                guard let rm = e.estimatedOneRepMax else { continue }
                best[e.exerciseId] = max(best[e.exerciseId] ?? 0, rm)
                if age < 56 * day { count[e.exerciseId, default: 0] += 1 }
                if age < 14 * day { recent[e.exerciseId] = max(recent[e.exerciseId] ?? 0, rm) }
                if (21 * day ..< 42 * day).contains(age) { before[e.exerciseId] = max(before[e.exerciseId] ?? 0, rm) }
            }
        }
        let picks = count.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(6).map(\.key)
        return picks.compactMap { id in
            guard let n = name(id), let top = best[id] else { return nil }
            var parts: [String] = []
            if let latest = recent[id] { parts.append("est. 1RM \(num(latest)) kg in the last 2 weeks") }
            if let then = before[id] { parts.append("\(num(then)) kg 3 to 6 weeks ago") }
            parts.append("best \(num(top)) kg")
            return "\(n): " + parts.joined(separator: ", ") + "."
        }
    }

    /// "Body weight: 66 kg on 31 Oct; 67.2 kg about 30 days before (-1.2 kg)." Nil with no points.
    static func bodyWeight(_ points: [BodyMeasurements.Point], now: Date, calendar cal: Calendar) -> String? {
        let pts = points.filter { $0.date <= now && $0.value > 0 }.sorted { $0.date < $1.date }
        guard let last = pts.last else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.dateFormat = "d MMM"
        var line = "Body weight: \(num(last.value)) kg on \(f.string(from: last.date))"
        let monthAgo = last.date.addingTimeInterval(-30 * 86_400)
        if let then = pts.last(where: { $0.date <= monthAgo }) ?? pts.first, then.date < last.date {
            let diff = last.value - then.value
            let days = Int(last.date.timeIntervalSince(then.date) / 86_400)
            line += "; \(num(then.value)) kg \(days) days before (\(diff >= 0 ? "+" : "")\(num(diff)) kg)"
        }
        return line + "."
    }

    /// 66 → "66", 32.25 → "32.3".
    static func num(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }
}
