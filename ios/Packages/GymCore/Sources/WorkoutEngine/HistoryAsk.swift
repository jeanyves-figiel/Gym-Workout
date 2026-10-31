import Foundation

/// Ask your history (#868, design A + C from `ai-epic/c1.png`): "Best bench this year?", "Am I squatting more than in June?",
/// "How many workouts in October?", "Weekly volume?" answered from the workouts logged on the phone: a number, a mini chart
/// and one sentence. The on-device model calls these as tools and words the answer; without it `answer` parses the question
/// itself. Nothing leaves the phone.
public struct HistoryAnswer: Equatable, Sendable {
    public enum Kind: String, Sendable { case best, compare, count, volume, none }

    public struct Bar: Equatable, Sendable {
        public var label: String
        public var value: Double
    }

    public var kind: Kind
    /// "Best bench press this year"
    public var title: String
    /// "15 Oct · 4×3"
    public var detail: String
    /// "85", "+9", "18"
    public var value: String
    /// "kg", "workouts", "t"
    public var unit: String
    /// Mini chart, oldest first; the last bar is the answer.
    public var bars: [Bar]
    /// "Apr → Oct · +12 kg"
    public var caption: String
    /// The answer in one or two sentences, used when the model can't word it.
    public var sentence: String
    /// The exercise asked about: the card opens it.
    public var exerciseId: String?
    /// Plain facts for the on-device model.
    public var facts: [String]
}

/// A stretch of time named in a question: "this year", "June", "last 6 weeks".
public struct HistoryPeriod: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case week, month, year, span, all }

    public var kind: Kind
    /// "this year", "June", "October 2025"
    public var label: String
    public var start: Date
    public var end: Date

    public func contains(_ d: Date) -> Bool { d >= start && d < end }

    public static func all(now: Date) -> HistoryPeriod {
        HistoryPeriod(kind: .all, label: "ever", start: .distantPast, end: now.addingTimeInterval(1))
    }

    /// The same stretch just before (last month for a month); nil for spans and all time.
    func previous(_ cal: Calendar) -> HistoryPeriod? {
        let unit: Calendar.Component
        switch kind {
        case .week: unit = .weekOfYear
        case .month: unit = .month
        case .year: unit = .year
        case .span, .all: return nil
        }
        guard let d = cal.date(byAdding: unit, value: -1, to: start), let i = cal.dateInterval(of: unit, for: d) else { return nil }
        return HistoryPeriod(kind: kind, label: HistoryAsk.label(kind, i.start, cal), start: i.start, end: i.end)
    }
}

/// One question tile under the Insights ask bar (#938).
public struct HistoryStarter: Hashable, Sendable {
    public enum Kind: String, Sendable { case best, compare, count, volume }
    public let kind: Kind
    public let title: String
    public let question: String
}

public enum HistoryAsk {
    // MARK: Questions

    /// The answer to a question about the member's workouts; nil when it isn't one (the Coach chat takes it).
    public static func answer(_ question: String, records: [WorkoutRecord], now: Date = Date(), calendar cal: Calendar = Progression.calendar()) -> HistoryAnswer? {
        let words = tokens(question)
        let text = " " + words.joined(separator: " ") + " "
        let found = periods(words, now: now, cal)
        if text.contains(" volume ") || text.contains(" tonnage ") || text.contains(" tonnes ") {
            return volume(weeks: 6, records: records, now: now, calendar: cal)
        }
        let id = exercise(in: question, records: records)
        let counting = text.contains(" how many ") || text.contains(" how often ")
            || (id == nil && ["workouts", "workout", "sessions", "session", "trained", "train", "gym"].contains(where: { text.contains(" \($0) ") }) && !found.isEmpty)
        if counting && id == nil {
            return count(period: found.first ?? month(now, cal), records: records, now: now, calendar: cal)
        }
        guard let id else { return nil }
        let comparing = ["more", "less", "than", "vs", "versus", "compared", "since", "stronger", "weaker", "better", "up"]
            .contains { text.contains(" \($0) ") }
        if found.count >= 2 {
            return compare(exerciseId: id, then: found[0], now: found[1], records: records, calendar: cal)
        }
        if let p = found.first, comparing, p.kind != .all {
            let current = month(now, cal)
            return compare(exerciseId: id, then: p, now: p == current ? (p.previous(cal) ?? current) : current, records: records, calendar: cal)
        }
        return best(exerciseId: id, period: found.first ?? .all(now: now), records: records, now: now, calendar: cal)
    }

    /// Chips under the ask bar: the member's most logged main lift, a month back, this month, volume.
    public static func starters(records: [WorkoutRecord], now: Date = Date(), calendar cal: Calendar = Progression.calendar()) -> [String] {
        starterTiles(records: records, now: now, calendar: cal).map(\.question)
    }

    /// Question tiles under the ask bar (#938): kind (BEST, COMPARE, COUNT, VOLUME), a short title and the question asked.
    public static func starterTiles(records: [WorkoutRecord], now: Date = Date(), calendar cal: Calendar = Progression.calendar()) -> [HistoryStarter] {
        var out: [HistoryStarter] = []
        if let id = topLift(records) {
            let n = short(Exercise.get(id).name).lowercased()
            let cap = n.prefix(1).uppercased() + n.dropFirst()
            out.append(HistoryStarter(kind: .best, title: "\(cap) this year", question: "Best \(n) this year?"))
            if let m = cal.date(byAdding: .month, value: -4, to: now) {
                let month = monthNames[cal.component(.month, from: m) - 1].capitalized
                out.append(HistoryStarter(kind: .compare, title: "\(cap) vs \(month)", question: "\(cap) vs \(month)?"))
            }
        }
        out.append(HistoryStarter(kind: .count, title: "Workouts this month", question: "Workouts this month?"))
        out.append(HistoryStarter(kind: .volume, title: "Weekly volume", question: "Weekly volume?"))
        return out
    }

    // MARK: Tools

    /// Heaviest set of one exercise in a period, with the best of each month as the chart.
    public static func best(exerciseId id: String, period: HistoryPeriod, records: [WorkoutRecord], now: Date = Date(), calendar cal: Calendar = Progression.calendar()) -> HistoryAnswer {
        let name = short(Exercise.get(id).name)
        let title = "Best \(name.lowercased()) \(phrase(period))"
        guard let top = topSet(id, in: period, records) else {
            return none(title, "No \(name.lowercased()) logged \(period.kind == .all ? "yet" : phrase(period)).", id: id)
        }
        let lastMonth = cal.dateInterval(of: .month, for: min(period.end.addingTimeInterval(-1), now))?.start ?? now
        let bars = monthlyTop(id, upTo: lastMonth, count: 7, records, cal)
        var caption = ""
        if let first = bars.first(where: { $0.value > 0 }), let last = bars.last(where: { $0.value > 0 }), first.label != last.label {
            caption = "\(first.label) → \(last.label) · \(signed(last.value - first.value)) kg"
        }
        let sets = "\(top.sets)×\(top.reps.map { String(Int($0.rounded())) } ?? "–")"
        let day = dayLabel(top.date, cal)
        return HistoryAnswer(
            kind: .best, title: title, detail: "\(day) · \(sets)", value: kg(top.kg), unit: "kg", bars: bars, caption: caption,
            sentence: "\(kg(top.kg)) kg on \(day), \(sets).",
            exerciseId: id,
            facts: ["\(name) heaviest set \(period.label): \(kg(top.kg)) kg × \(top.reps.map { String(Int($0.rounded())) } ?? "?") on \(day)"]
                + bars.filter { $0.value > 0 }.map { "\(name) best in \($0.label): \(kg($0.value)) kg" })
    }

    /// One exercise's heaviest set in two periods: the change, both numbers, the months between as the chart.
    public static func compare(exerciseId id: String, then a: HistoryPeriod, now b: HistoryPeriod, records: [WorkoutRecord], calendar cal: Calendar = Progression.calendar()) -> HistoryAnswer {
        let name = short(Exercise.get(id).name)
        let title = "\(name) · \(a.label.capitalizedFirst) vs \(b.label.capitalizedFirst)"
        let ta = topSet(id, in: a, records), tb = topSet(id, in: b, records)
        guard let ta, let tb else {
            let missing = ta == nil ? a.label : b.label
            return none(title, "No \(name.lowercased()) logged in \(missing) to compare.", id: id)
        }
        let delta = tb.kg - ta.kg
        let monthsApart = max(1, (cal.dateComponents([.month], from: a.start, to: b.start).month ?? 0) + 1)
        let bars = monthlyTop(id, upTo: cal.dateInterval(of: .month, for: b.start)?.start ?? b.start, count: min(7, max(2, monthsApart)), records, cal)
        let verdict = delta > 0 ? "Yes, \(signed(delta)) kg" : delta < 0 ? "Not yet, \(signed(delta)) kg" : "Same weight"
        return HistoryAnswer(
            kind: .compare, title: title, detail: "top set \(a.label) \(kg(ta.kg)) kg · \(b.label) \(kg(tb.kg)) kg",
            value: signed(delta), unit: "kg", bars: bars, caption: "\(a.label.capitalizedFirst) \(kg(ta.kg)) → \(b.label.capitalizedFirst) \(kg(tb.kg)) kg",
            sentence: "\(verdict): \(kg(tb.kg)) kg \(phrase(b)) vs \(kg(ta.kg)) kg \(phrase(a)).",
            exerciseId: id,
            facts: ["\(name) heaviest set \(a.label): \(kg(ta.kg)) kg", "\(name) heaviest set \(b.label): \(kg(tb.kg)) kg", "Change: \(signed(delta)) kg"])
    }

    /// Workouts in a period vs the one before, hours, longest streak of training days.
    public static func count(period: HistoryPeriod, records: [WorkoutRecord], now: Date = Date(), calendar cal: Calendar = Progression.calendar()) -> HistoryAnswer {
        let inside = records.filter { period.contains($0.startedAt) }
        let n = inside.count
        let hours = Double(inside.reduce(0) { $0 + $1.durationSec }) / 3600
        let streak = longestStreak(inside.map(\.startedAt), cal)
        var bars: [HistoryAnswer.Bar] = []
        var p: HistoryPeriod? = period
        for _ in 0..<4 {
            guard let q = p else { break }
            bars.insert(.init(label: short(q, cal), value: Double(records.filter { q.contains($0.startedAt) }.count)), at: 0)
            p = q.previous(cal)
        }
        var sentence = "\(n) workout\(n == 1 ? "" : "s") \(phrase(period))"
        if let prev = period.previous(cal) {
            let m = records.filter { prev.contains($0.startedAt) }.count
            let d = n - m
            sentence += d == 0 ? ", same as \(prev.label)" : ", \(abs(d)) \(d > 0 ? "more" : "fewer") than \(prev.label)"
        }
        sentence += "."
        if streak > 1 { sentence += " Longest streak \(streak) days." }
        return HistoryAnswer(
            kind: .count, title: period.kind == .month ? period.label.capitalizedFirst : "Workouts \(period.label)",
            detail: "\(n) workout\(n == 1 ? "" : "s") · \(Int(hours.rounded())) h", value: String(n), unit: "workouts",
            bars: bars, caption: bars.count > 1 ? bars.map(\.label).joined(separator: " · ") : "",
            sentence: sentence, exerciseId: nil,
            facts: [sentence] + bars.map { "\($0.label): \(Int($0.value)) workouts" })
    }

    /// Weight moved per week (sets × reps × kg), last `weeks` weeks, this week last.
    public static func volume(weeks: Int, records: [WorkoutRecord], now: Date = Date(), calendar cal: Calendar = Progression.calendar()) -> HistoryAnswer {
        var bars: [HistoryAnswer.Bar] = []
        for back in stride(from: weeks - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .weekOfYear, value: -back, to: now), let w = cal.dateInterval(of: .weekOfYear, for: d) else { continue }
            let kg = records.filter { w.contains($0.startedAt) }.reduce(0) { $0 + $1.volumeKg }
            bars.append(.init(label: dayLabel(w.start, cal), value: kg / 1000))
        }
        let this = bars.last?.value ?? 0
        let earlier = bars.dropLast().map(\.value)
        let avg = earlier.isEmpty ? 0 : earlier.reduce(0, +) / Double(earlier.count)
        let t = String(format: "%.1f", this)
        let vs = avg > 0 ? " vs \(String(format: "%.1f", avg)) t a week before" : ""
        return HistoryAnswer(
            kind: .volume, title: "Weekly volume", detail: "this week · sets × reps × kg", value: t, unit: "t", bars: bars,
            caption: bars.count > 1 ? "\(bars.first!.label) → this week" : "",
            sentence: "\(t) t this week\(vs).", exerciseId: nil,
            facts: bars.map { "Week of \($0.label): \(String(format: "%.1f", $0.value)) t" })
    }

    // MARK: Reading the question

    /// The logged exercise the question names ("bench", "squatting", "deadlifts"); the most logged main lift wins a tie.
    public static func exercise(in question: String, records: [WorkoutRecord]) -> String? {
        let asked = Set(tokens(question).filter { !stopWords.contains($0) }.map(stem))
        guard !asked.isEmpty else { return nil }
        var logged: [String: Int] = [:]
        for r in records { for e in r.exercises where e.setsDone > 0 && (e.weightKg ?? 0) > 0 { logged[e.exerciseId, default: 0] += 1 } }
        var best: (id: String, score: Double, main: Bool, n: Int)?
        for (id, n) in logged {
            let e = Exercise.get(id)
            let core = Set(tokens(e.name).map(stem)).subtracting(kitWords)
            guard !core.isEmpty else { continue }
            let hit = core.intersection(asked)
            guard !hit.isEmpty else { continue }
            let score = Double(hit.count) / Double(core.count)
            if let b = best, (b.score, b.main ? 1 : 0, b.n) >= (score, e.main ? 1 : 0, n) { continue }
            best = (id, score, e.main, n)
        }
        return best?.id
    }

    /// Periods named in the question, in the order they appear.
    public static func periods(in question: String, now: Date = Date(), calendar cal: Calendar = Progression.calendar()) -> [HistoryPeriod] {
        periods(tokens(question), now: now, cal)
    }

    static func periods(_ w: [String], now: Date, _ cal: Calendar) -> [HistoryPeriod] {
        var out: [HistoryPeriod] = []
        var i = 0
        while i < w.count {
            let next = i + 1 < w.count ? w[i + 1] : ""
            if ["this", "last", "past", "previous"].contains(w[i]), let unit = units[next] {
                let back = w[i] == "this" ? 0 : 1
                if let d = cal.date(byAdding: unit.0, value: -back, to: now), let iv = cal.dateInterval(of: unit.0, for: d) {
                    out.append(HistoryPeriod(kind: unit.1, label: "\(w[i] == "this" ? "this" : "last") \(next)", start: iv.start, end: iv.end))
                }
                i += 2
                continue
            }
            if ["last", "past"].contains(w[i]), let n = Int(next), n > 0, n < 100, i + 2 < w.count, let unit = units[w[i + 2]] ?? units[w[i + 2] + "s"] ?? plural[w[i + 2]].flatMap({ units[$0] }) {
                if let s = cal.date(byAdding: unit.0, value: -n, to: now) {
                    out.append(HistoryPeriod(kind: .span, label: "last \(n) \(w[i + 2])", start: s, end: now.addingTimeInterval(1)))
                }
                i += 3
                continue
            }
            if let m = monthIndex(w[i]) {
                var year = cal.component(.year, from: now)
                if let y = Int(next), (2000...2100).contains(y) { year = y; i += 1 } else if m > cal.component(.month, from: now) { year -= 1 }
                if let d = cal.date(from: DateComponents(year: year, month: m, day: 1)), let iv = cal.dateInterval(of: .month, for: d) {
                    out.append(HistoryPeriod(kind: .month, label: label(.month, iv.start, cal, now: now), start: iv.start, end: iv.end))
                }
            } else if let y = Int(w[i]), (2000...2100).contains(y), let d = cal.date(from: DateComponents(year: y, month: 1, day: 1)),
                      let iv = cal.dateInterval(of: .year, for: d) {
                out.append(HistoryPeriod(kind: .year, label: "in \(y)", start: iv.start, end: iv.end))
            } else if ["ever", "alltime"].contains(w[i]) || (w[i] == "all" && next == "time") {
                out.append(.all(now: now))
            }
            i += 1
        }
        return out
    }

    // MARK: Helpers

    static let monthNames = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
    private static let units: [String: (Calendar.Component, HistoryPeriod.Kind)] = [
        "week": (.weekOfYear, .week), "month": (.month, .month), "year": (.year, .year),
        "weeks": (.weekOfYear, .week), "months": (.month, .month), "years": (.year, .year),
    ]
    private static let plural: [String: String] = ["wk": "weeks", "wks": "weeks", "mo": "months"]
    private static let stopWords: Set<String> = Set([
        "i", "me", "my", "am", "is", "are", "was", "were", "do", "did", "does", "how", "what", "whats", "when", "which", "best", "good",
        "more", "less", "than", "in", "on", "at", "the", "a", "an", "this", "last", "past", "year", "month", "week", "vs", "versus",
        "compared", "to", "ever", "much", "many", "heaviest", "max", "top", "since", "so", "far", "lift", "lifted", "weight", "kg", "set",
        "pr", "record", "stronger", "weaker", "better", "up", "now", "today", "all", "time", "of", "for", "with", "and", "or", "it",
        "have", "has", "been", "getting", "progress", "workout", "workouts", "session", "sessions", "train", "trained", "volume",
        "months", "weeks", "years", "lifts", "sets", "records", "prs", "doing", "going", "lifting", "training",
    ]).union(monthNames)
    /// Words that name the kit, not the movement: "bench" asks for the bench press, barbell or dumbbell.
    private static let kitWords: Set<String> = ["barbell", "dumbbell", "machine", "cable", "smith", "kettlebell", "band", "weighted", "assisted", "with", "and", "on", "the", "of"]

    static func tokens(_ s: String) -> [String] {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    /// "squatting" → "squat", "deadlifts" → "deadlift", "pressing" → "press".
    static func stem(_ w: String) -> String {
        var t = w
        if t.hasSuffix("ing"), t.count > 5 {
            t.removeLast(3)
            if let a = t.last, t.count > 3, t.dropLast().last == a, a != "s", a != "l" { t.removeLast() }
        }
        if t.hasSuffix("s"), !t.hasSuffix("ss"), t.count > 3 { t.removeLast() }
        return t
    }

    private static func monthIndex(_ w: String) -> Int? {
        if let i = monthNames.firstIndex(of: w) { return i + 1 }
        if w.count == 3 || w == "sept", let i = monthNames.firstIndex(where: { $0.hasPrefix(w) }) { return i + 1 }
        return nil
    }

    /// "this year", "in June", "last 6 weeks", "ever".
    static func phrase(_ p: HistoryPeriod) -> String {
        ["this ", "last ", "in ", "week of", "ever"].contains { p.label.hasPrefix($0) } ? p.label : "in \(p.label)"
    }

    static func month(_ d: Date, _ cal: Calendar) -> HistoryPeriod {
        let iv = cal.dateInterval(of: .month, for: d) ?? DateInterval(start: d, duration: 1)
        return HistoryPeriod(kind: .month, label: "this month", start: iv.start, end: iv.end)
    }

    static func label(_ kind: HistoryPeriod.Kind, _ start: Date, _ cal: Calendar, now: Date? = nil) -> String {
        let m = monthNames[cal.component(.month, from: start) - 1].capitalized
        let y = cal.component(.year, from: start)
        switch kind {
        case .month:
            return now.map { cal.component(.year, from: $0) } == y || now == nil ? m : "\(m) \(y)"
        case .year: return "in \(y)"
        case .week: return "week of \(dayLabel(start, cal))"
        case .span, .all: return ""
        }
    }

    private static func short(_ p: HistoryPeriod, _ cal: Calendar) -> String {
        switch p.kind {
        case .month: String(monthNames[cal.component(.month, from: p.start) - 1].prefix(3)).capitalized
        case .year: String(cal.component(.year, from: p.start))
        default: dayLabel(p.start, cal)
        }
    }

    /// "Barbell bench press" → "Bench press".
    static func short(_ name: String) -> String {
        for kit in ["Barbell ", "Dumbbell "] where name.hasPrefix(kit) {
            let rest = name.dropFirst(kit.count)
            return rest.prefix(1).uppercased() + rest.dropFirst()
        }
        return name
    }

    static func dayLabel(_ d: Date, _ cal: Calendar) -> String {
        "\(cal.component(.day, from: d)) \(String(monthNames[cal.component(.month, from: d) - 1].prefix(3)).capitalized)"
    }

    private struct TopSet { var kg: Double; var reps: Double?; var sets: Int; var date: Date }

    private static func topSet(_ id: String, in p: HistoryPeriod, _ records: [WorkoutRecord]) -> TopSet? {
        var best: TopSet?
        for r in records where p.contains(r.startedAt) {
            for e in r.exercises where e.exerciseId == id && e.setsDone > 0 {
                guard let w = e.weightKg, w > 0 else { continue }
                if let b = best, b.kg > w || (b.kg == w && b.date >= r.startedAt) { continue }
                best = TopSet(kg: w, reps: e.reps, sets: e.setsDone, date: r.startedAt)
            }
        }
        return best
    }

    private static func monthlyTop(_ id: String, upTo last: Date, count: Int, _ records: [WorkoutRecord], _ cal: Calendar) -> [HistoryAnswer.Bar] {
        var out: [HistoryAnswer.Bar] = []
        for back in stride(from: count - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .month, value: -back, to: last), let iv = cal.dateInterval(of: .month, for: d) else { continue }
            let p = HistoryPeriod(kind: .month, label: "", start: iv.start, end: iv.end)
            out.append(.init(label: short(p, cal), value: topSet(id, in: p, records)?.kg ?? 0))
        }
        // Drop empty months before the first logged one.
        while out.count > 1, out.first?.value == 0 { out.removeFirst() }
        return out
    }

    private static func topLift(_ records: [WorkoutRecord]) -> String? {
        var n: [String: Int] = [:]
        for r in records { for e in r.exercises where e.setsDone > 0 && (e.weightKg ?? 0) > 0 { n[e.exerciseId, default: 0] += 1 } }
        return n.max { a, b in
            let am = Exercise.get(a.key).main, bm = Exercise.get(b.key).main
            return am != bm ? !am : a.value != b.value ? a.value < b.value : a.key > b.key
        }?.key
    }

    private static func longestStreak(_ dates: [Date], _ cal: Calendar) -> Int {
        let days = Set(dates.map { cal.startOfDay(for: $0) }).sorted()
        var best = days.isEmpty ? 0 : 1, run = 1
        for (a, b) in zip(days, days.dropFirst()) {
            run = cal.dateComponents([.day], from: a, to: b).day == 1 ? run + 1 : 1
            best = max(best, run)
        }
        return best
    }

    private static func none(_ title: String, _ sentence: String, id: String?) -> HistoryAnswer {
        HistoryAnswer(kind: .none, title: title, detail: "", value: "–", unit: "", bars: [], caption: "", sentence: sentence, exerciseId: id, facts: [sentence])
    }

    static func kg(_ v: Double) -> String { WorkoutRecap.kg(v) }
    static func signed(_ v: Double) -> String { (v > 0 ? "+" : v < 0 ? "−" : "±") + kg(abs(v)) }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
