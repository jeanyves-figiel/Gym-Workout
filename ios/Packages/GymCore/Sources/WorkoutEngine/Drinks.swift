import Foundation

// MARK: - Drinks and good times weeks (#1039, mix A + B + C from `drinks-log/{a,b,c}.png`)

/// What the member had. `standard`: standard drinks (10 g alcohol) in a usual serving.
public enum DrinkKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case beer, wine, cocktail, shot
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .beer: "Beer"
        case .wine: "Wine"
        case .cocktail: "Cocktail"
        case .shot: "Shot"
        }
    }

    public var emoji: String {
        switch self {
        case .beer: "🍺"
        case .wine: "🍷"
        case .cocktail: "🍸"
        case .shot: "🥃"
        }
    }

    /// A 33 cl beer, a 15 cl glass of wine or a 4 cl shot ≈ 1; a cocktail ≈ 1.5.
    public var standard: Double { self == .cocktail ? 1.5 : 1 }

    /// "beer", "2 pints", "prosecco" → a kind (Coach, #1039). Unknown words count as beer: one standard drink.
    public static func from(_ words: String?) -> DrinkKind {
        let w = (words ?? "").lowercased()
        if ["wine", "prosecco", "champagne", "rosé", "rose", "vino", "sekt", "cava"].contains(where: { w.contains($0) }) { return .wine }
        if ["cocktail", "mojito", "spritz", "margarita", "gin tonic", "g&t", "long drink"].contains(where: { w.contains($0) }) { return .cocktail }
        if ["shot", "vodka", "tequila", "whisk", "rum", "gin", "schnapps", "jäger", "liquor", "spirit"].contains(where: { w.contains($0) }) { return .shot }
        return .beer
    }
}

/// Drinks tapped in (+1) or logged by Coach. On the device only.
public struct DrinkEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var kind: DrinkKind
    public var count: Int

    public init(id: UUID = UUID(), date: Date, kind: DrinkKind, count: Int = 1) {
        self.id = id
        self.date = date
        self.kind = kind
        self.count = max(1, count)
    }

    public var standard: Double { kind.standard * Double(count) }
}

/// A week (or a few days) of holiday drinks planned ahead (A): training runs lighter, more water, earlier nights.
public struct GoodTimesPeriod: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Day keys (`PlanCalendar.key`), inclusive.
    public var start: String
    public var end: String
    public var note: String?

    public init(id: UUID = UUID(), start: String, end: String, note: String? = nil) {
        self.id = id
        self.start = min(start, end)
        self.end = max(start, end)
        self.note = note
    }

    public func covers(_ day: String) -> Bool { start <= day && day <= end }
}

public enum Drinks {
    /// From this many standard drinks in one night: a heavy night (binge level in most health guides).
    public static let heavyNight = 5.0
    /// Hours after the last drink with no workout at all.
    public static let noTrainingHours = 12.0
    /// Glasses added to the water target the day after, at most.
    public static let maxWaterBonus = 4
    /// Extra glasses each day of a good times week.
    public static let goodTimesWater = 3
    /// A week counts as heavy from this many standard drinks, or two heavy nights.
    public static let heavyWeek = 15.0
    /// Heavy weeks out of the last 4 before the app shares where to find support, once, kindly.
    public static let supportFrom = 3

    /// Factual, shown once on the drinks card.
    public static let guide = "Most health guides: up to about 10 standard drinks a week, a few alcohol-free days, and no more than 4 in one go."
    public static let supportLine = "A few big weeks in a row. If you'd like to cut back, a doctor or a free helpline can help, no judgement."

    public static func total(_ entries: [DrinkEntry]) -> Double { entries.reduce(0) { $0 + $1.standard } }

    /// Drinks since yesterday noon: "last night" for the morning verdict, tonight's tally in the evening.
    public static func lastNight(_ entries: [DrinkEntry], now: Date, calendar cal: Calendar) -> [DrinkEntry] {
        let from = cal.startOfDay(for: now).addingTimeInterval(-12 * 3600)
        return entries.filter { $0.date >= from && $0.date <= now }
    }

    /// Tonight's tally (B): since 06:00 today, or since 06:00 yesterday before then (the night isn't over).
    public static func tonight(_ entries: [DrinkEntry], now: Date, calendar cal: Calendar) -> [DrinkEntry] {
        var from = cal.date(bySettingHour: 6, minute: 0, second: 0, of: now) ?? now
        if from > now { from = from.addingTimeInterval(-86_400) }
        return entries.filter { $0.date >= from && $0.date <= now }
    }

    public static func hoursSinceLast(_ entries: [DrinkEntry], now: Date) -> Double? {
        entries.filter { $0.date <= now }.map(\.date).max().map { now.timeIntervalSince($0) / 3600 }
    }

    /// Readiness points for last night's standard drinks.
    public static func points(_ standard: Double) -> Int {
        switch standard {
        case ..<0.5: 0
        case ..<3: -5
        case ..<5: -10
        case ..<8: -15
        default: -20
        }
    }

    /// Extra water today: one glass per two drinks last night (max 4), plus 3 on a good times day.
    public static func waterBonus(lastNight standard: Double, goodTimes: Bool) -> Int {
        min(maxWaterBonus, Int((standard / 2).rounded())) + (goodTimes ? goodTimesWater : 0)
    }

    /// Weeks (Monday on) among the 4 before this one with `heavyWeek` drinks or two heavy nights.
    public static func heavyWeeks(_ entries: [DrinkEntry], now: Date, calendar cal: Calendar) -> Int {
        let monday = Progression.weekStart(now, cal)
        return (1...4).filter { w in
            guard let from = cal.date(byAdding: .day, value: -7 * w, to: monday),
                  let to = cal.date(byAdding: .day, value: 7, to: from) else { return false }
            let week = entries.filter { $0.date >= from && $0.date < to }
            let nights = Dictionary(grouping: week) { e in cal.startOfDay(for: e.date.addingTimeInterval(-6 * 3600)) }
            return total(week) >= heavyWeek || nights.values.filter { total($0) >= heavyNight }.count >= 2
        }.count
    }

    public static func showsSupport(_ entries: [DrinkEntry], now: Date, calendar cal: Calendar) -> Bool {
        heavyWeeks(entries, now: now, calendar: cal) >= supportFrom
    }

    /// One morning-after step (C).
    public struct Step: Hashable, Sendable, Identifiable {
        public enum Kind: String, Sendable { case rest, walk, water, breakfast, breathe, sleep }
        public var kind: Kind
        public var title: String
        public var value: String
        public var id: String { kind.rawValue }
    }

    /// What helps after `standard` drinks last night. Kind words, no shaming, nothing heavy within `noTrainingHours`.
    public static func morningAfter(standard: Double, hoursSince: Double?, extraGlasses: Int) -> [Step] {
        guard standard >= 0.5 else { return [] }
        var out: [Step] = []
        if let h = hoursSince, h < noTrainingHours {
            out.append(Step(kind: .rest, title: "No workout until \(Int((noTrainingHours - h).rounded(.up))) h from now", value: "Rest"))
        } else if standard >= 3 {
            out.append(Step(kind: .walk, title: "Easy day: 20 min walk + stretch", value: "20′"))
        }
        if extraGlasses > 0 { out.append(Step(kind: .water, title: "Water +\(extraGlasses) before noon", value: "+\(extraGlasses)")) }
        out.append(Step(kind: .breakfast, title: "Eggs, toast and a pinch of salt", value: "🍳"))
        if standard >= 3 { out.append(Step(kind: .breathe, title: "5 min breathe in Mind", value: "5′")) }
        if standard >= heavyNight { out.append(Step(kind: .sleep, title: "Early night, no PR tries today", value: "😴")) }
        return out
    }

    /// Advice tiles of a good times week (A).
    public static let goodTimesRules = [
        "Workouts lighter: 1 RPE easier, a set less, no PR tries",
        "Water +\(goodTimesWater) glasses a day, one between drinks",
        "Protein and salty breakfasts, a real meal before going out",
        "Wind down by 22:30 on the nights off",
    ]
}
