import Foundation

// Supplements in Fuel (#514): the member's stack placed on the day's timeline, a caffeine meter that knows their
// bedtime, and what the supplements add to the day's numbers (protein counts, creatine days get an extra glass).
// A meal replacement (Huel…) stands in for the meal at its time: ticking it fills that meal with its macros.
// Pointers only: amounts come from the member's label, never a dose recommendation.

public enum SupplementKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case mealReplacement, hotMeal, preWorkout, creatine, protein, caffeine, electrolytes, vitaminD, omega3, magnesium, other
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .mealReplacement: "Meal shake"
        case .hotMeal: "Instant hot meal"
        case .preWorkout: "Pre-workout"
        case .creatine: "Creatine"
        case .protein: "Protein powder"
        case .caffeine: "Coffee / caffeine"
        case .electrolytes: "Electrolytes"
        case .vitaminD: "Vitamin D"
        case .omega3: "Omega-3"
        case .magnesium: "Magnesium"
        case .other: "Other"
        }
    }

    public var emoji: String {
        switch self {
        case .mealReplacement: "🥤"
        case .hotMeal: "🍲"
        case .preWorkout: "⚡"
        case .creatine: "💪"
        case .protein: "🥛"
        case .caffeine: "☕"
        case .electrolytes: "🧂"
        case .vitaminD: "☀️"
        case .omega3: "🐟"
        case .magnesium: "🌙"
        case .other: "💊"
        }
    }

    public var timing: SupplementTiming {
        switch self {
        case .preWorkout, .caffeine: .beforeTraining
        case .protein: .afterTraining
        case .electrolytes: .duringTraining
        case .mealReplacement, .creatine, .vitaminD, .omega3, .other: .breakfast
        case .hotMeal: .lunch
        case .magnesium: .bedtime
        }
    }

    /// Typical label amounts, prefilled and editable.
    public var preset: Supplement {
        switch self {
        case .mealReplacement: Supplement(name: "Meal shake", kind: self, dose: "1 bottle or serving", proteinG: 40, carbsG: 24, fatG: 17,
                                          restDays: true)
        case .hotMeal: Supplement(name: "Instant hot meal", kind: self, dose: "1 pot with boiling water", proteinG: 24, carbsG: 45, fatG: 14,
                                  restDays: true)
        case .preWorkout: Supplement(name: "Pre-workout", kind: self, dose: "1 scoop", caffeineMg: 150)
        case .creatine: Supplement(name: "Creatine", kind: self, dose: "1 scoop", creatineG: 5, restDays: true)
        case .protein: Supplement(name: "Whey shake", kind: self, dose: "1 scoop", proteinG: 24, restDays: true)
        case .caffeine: Supplement(name: "Coffee", kind: self, dose: "1 cup", caffeineMg: 80, restDays: true)
        case .electrolytes: Supplement(name: "Electrolytes", kind: self, dose: "1 tab in 500 ml")
        case .vitaminD: Supplement(name: "Vitamin D", kind: self, dose: "1 capsule", restDays: true)
        case .omega3: Supplement(name: "Omega-3", kind: self, dose: "2 capsules", restDays: true)
        case .magnesium: Supplement(name: "Magnesium", kind: self, dose: "1 capsule", restDays: true)
        case .other: Supplement(name: "", kind: self, dose: "", restDays: true)
        }
    }
}

/// When in the day a supplement goes.
public enum SupplementTiming: String, Codable, CaseIterable, Sendable, Identifiable {
    case beforeTraining, duringTraining, afterTraining, breakfast, lunch, evening, bedtime
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .beforeTraining: "30 min before training"
        case .duringTraining: "During training"
        case .afterTraining: "After training"
        case .breakfast: "With breakfast"
        case .lunch: "With lunch"
        case .evening: "With dinner"
        case .bedtime: "Before bed"
        }
    }

    public var aroundTraining: Bool { [.beforeTraining, .duringTraining, .afterTraining].contains(self) }
}

/// One product in the member's stack, with what the label says per serving.
public struct Supplement: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: SupplementKind
    public var timing: SupplementTiming
    /// Free text from the label: "1 sachet in 300 ml water".
    public var dose: String
    public var caffeineMg: Int
    public var creatineG: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    /// Also on days without training (at the rest-day time of `timing`).
    public var restDays: Bool

    public init(id: String = UUID().uuidString, name: String, kind: SupplementKind, timing: SupplementTiming? = nil, dose: String,
                caffeineMg: Int = 0, creatineG: Double = 0, proteinG: Double = 0, carbsG: Double = 0, fatG: Double = 0,
                restDays: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.timing = timing ?? kind.timing
        self.dose = dose
        self.caffeineMg = max(0, caffeineMg)
        self.creatineG = max(0, creatineG)
        self.proteinG = max(0, proteinG)
        self.carbsG = max(0, carbsG)
        self.fatG = max(0, fatG)
        self.restDays = restDays
    }

    public var emoji: String { kind.emoji }

    /// Takes the place of a meal: ticking it fills that meal.
    public var isMeal: Bool { kind == .mealReplacement || kind == .hotMeal }

    public var kcal: Int { Int((4 * proteinG + 4 * carbsG + 9 * fatG).rounded()) }

    /// What a tick adds: full macros for a meal shake, else protein palms only.
    public var portions: Portions {
        isMeal ? Portions.from(protein: proteinG, carbs: carbsG, fat: fatG * 0.6, veg: 0)
            : Portions(palms: Int((proteinG / Portions.proteinPerPalm).rounded()))
    }

    /// "⚡ 105 mg caffeine · 💪 3 g creatine".
    public var contents: [String] {
        var out: [String] = []
        if caffeineMg > 0 { out.append("⚡ \(caffeineMg) mg caffeine") }
        if creatineG > 0 { out.append("💪 \(Supplements.grams(creatineG)) creatine") }
        if proteinG > 0 { out.append("🥛 \(Supplements.grams(proteinG)) protein") }
        if isMeal && kcal > 0 { out.append("🍚 \(Supplements.grams(carbsG)) carbs · \(Supplements.grams(fatG)) fat · \(kcal) kcal") }
        return out
    }
}

/// A supplement placed on one day.
public struct SupplementDose: Codable, Hashable, Sendable, Identifiable {
    /// "supp-<supplement id>": the tick key in the day's log.
    public var id: String
    public var supplement: Supplement
    /// Minutes after midnight.
    public var minute: Int
    /// "30 min before Legs", "with breakfast".
    public var reason: String
    /// Taken after the member's caffeine cut-off.
    public var late: Bool
    /// Meal slot a meal shake stands in for.
    public var replaces: String?

    public var time: String { String(format: "%02d:%02d", minute / 60 % 24, minute % 60) }
}

public enum Supplements {
    /// Upper guide for healthy adults, mg a day.
    public static let caffeineGuideMg = 400
    /// No caffeine within this many hours of bedtime (same as the Learn card).
    public static let caffeineHoursBeforeSleep = 6

    public static func tickId(_ s: Supplement) -> String { "supp-\(s.id)" }

    /// Minute of the last caffeine for the member's bedtime.
    public static func caffeineCutoff(_ prefs: FuelPrefs) -> Int { prefs.sleep - caffeineHoursBeforeSleep * 60 }

    public static func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60 % 24, minute % 60) }

    static func grams(_ g: Double) -> String { g.rounded() == g ? "\(Int(g)) g" : String(format: "%.1f g", g) }

    /// The stack placed on the day: around the first training, or at the rest-day time when there's none.
    public static func schedule(_ stack: [Supplement], plan: FuelPlan, prefs: FuelPrefs,
                                calendar cal: Calendar = Progression.calendar()) -> [SupplementDose] {
        let start = cal.startOfDay(for: plan.day)
        func minute(_ d: Date) -> Int { Int(d.timeIntervalSince(start) / 60) }
        let acts = plan.activities.sorted { $0.start < $1.start }
        let slot: (MealKind) -> FuelSlot? = { k in plan.slots.first { $0.kind == k } }
        let meal: (MealKind) -> Int? = { slot($0)?.minute }
        let breakfast = meal(.breakfast) ?? prefs.wake + 30
        let cutoff = caffeineCutoff(prefs)
        return stack.compactMap { s -> SupplementDose? in
            var m: Int
            var reason: String
            switch s.timing {
            case .beforeTraining, .duringTraining, .afterTraining:
                if let a = acts.first {
                    switch s.timing {
                    case .beforeTraining: m = minute(a.start) - 30; reason = "30 min before \(a.title)"
                    case .duringTraining: m = minute(a.start); reason = "Sip during \(a.title)"
                    default:
                        let last = acts.last ?? a
                        m = minute(last.end) + 15; reason = "After \(last.title)"
                    }
                } else {
                    guard s.restDays else { return nil }
                    m = breakfast; reason = "Rest day: with breakfast"
                }
            case .breakfast: m = breakfast; reason = "With breakfast"
            case .lunch: m = meal(.lunch) ?? 12 * 60 + 30; reason = "With lunch"
            case .evening: m = meal(.dinner) ?? 19 * 60; reason = "With dinner"
            case .bedtime: m = prefs.sleep - 30; reason = "Before bed"
            }
            if !s.timing.aroundTraining && !s.restDays && acts.isEmpty { return nil }
            m = max(0, m)
            // A meal shake takes over the meal at its time.
            var replaces: String?
            if s.isMeal, let k = [SupplementTiming.breakfast: MealKind.breakfast, .lunch: .lunch, .evening: .dinner][s.timing], let sl = slot(k) {
                replaces = sl.id
                reason = "Your \(k.label.lowercased())"
            }
            return SupplementDose(id: tickId(s), supplement: s, minute: m, reason: reason, late: s.caffeineMg > 0 && m > cutoff,
                                  replaces: replaces)
        }
        .sorted { $0.minute < $1.minute }
    }

    /// Adds the day's stack to the plan: doses on the plan, one more glass on creatine days, caffeine pointers first.
    public static func apply(_ stack: [Supplement], to plan: inout FuelPlan, prefs: FuelPrefs, calendar cal: Calendar = Progression.calendar()) {
        let doses = schedule(stack, plan: plan, prefs: prefs, calendar: cal)
        plan.supplements = doses
        if doses.contains(where: { $0.supplement.creatineG > 0 }) {
            plan.glasses += 1
            plan.waterMl += max(100, prefs.glassMl)
        }
        plan.tips = pointers(doses, prefs: prefs) + plan.tips
    }

    /// Caffeine planned for the day, mg.
    public static func caffeine(_ doses: [SupplementDose]) -> Int { doses.reduce(0) { $0 + $1.supplement.caffeineMg } }

    /// Caffeine already ticked, mg.
    public static func caffeineTaken(_ doses: [SupplementDose], log: FuelDayLog) -> Int {
        doses.filter { log.ticks[$0.id] != nil }.reduce(0) { $0 + $1.supplement.caffeineMg }
    }

    /// Protein from ticked supplements, g.
    public static func proteinTaken(_ doses: [SupplementDose], log: FuelDayLog) -> Double {
        doses.filter { log.ticks[$0.id] != nil }.reduce(0) { $0 + $1.supplement.proteinG }
    }

    /// Sleep and caffeine warnings, then creatine water.
    public static func pointers(_ doses: [SupplementDose], prefs: FuelPrefs) -> [String] {
        var out: [String] = []
        let cutoff = clock(caffeineCutoff(prefs)), sleep = clock(prefs.sleep)
        for d in doses where d.late {
            out.append("\(d.supplement.name) at \(d.time) has \(d.supplement.caffeineMg) mg caffeine, after your \(cutoff) cut-off for \(sleep) sleep. Take half, or a caffeine-free one.")
        }
        let total = caffeine(doses)
        if total > caffeineGuideMg {
            out.append("\(total) mg caffeine planned today, over the \(caffeineGuideMg) mg guide. Skip a coffee.")
        }
        if doses.contains(where: { $0.supplement.creatineG > 0 }) {
            out.append("Creatine day: one extra glass of water is in your target.")
        }
        return out
    }

    public typealias LabelAmounts = (caffeineMg: Int, creatineG: Double, proteinG: Double, carbsG: Double, fatG: Double)

    /// Amounts read off a label (live text) per serving. Nil when nothing was found.
    public static func parse(label text: String) -> LabelAmounts? {
        let lines = text.lowercased().split(whereSeparator: \.isNewline).map(String.init)
        func amount(_ words: [String]) -> Amount? {
            for (i, line) in lines.enumerated() where words.contains(where: { line.contains($0) }) {
                // The number is on the same line, or the next one on table-style labels.
                for l in [line, i + 1 < lines.count ? lines[i + 1] : ""] {
                    if let v = firstAmount(l) { return v }
                }
            }
            return nil
        }
        let caffeine = amount(["caffeine", "koffein", "caféine", "cafeine", "caffeina", "cafeína"]).map { $0.mg }
        let creatine = amount(["creatine", "kreatin", "créatine", "creatina"]).map { $0.mg / 1000 }
        let protein = amount(["protein", "eiweiss", "eiweiß", "protéines", "proteine", "proteínas", "eaa", "aminosäuren", "amino acids"]).map { $0.mg / 1000 }
        let carbs = amount(["carbohydrate", "kohlenhydrate", "glucides", "carboidrati", "hidratos"]).map { $0.mg / 1000 }
        let fat = amount(["fat", "fett", "lipides", "matières grasses", "grassi", "grasas"]).map { $0.mg / 1000 }
        guard caffeine != nil || creatine != nil || protein != nil || carbs != nil || fat != nil else { return nil }
        func g(_ v: Double?) -> Double { ((v ?? 0) * 10).rounded() / 10 }
        return (Int((caffeine ?? 0).rounded()), g(creatine), g(protein), g(carbs), g(fat))
    }

    /// First "105 mg", "3000mg", "3,5 g" or "24g" on a line, in mg.
    static func firstAmount(_ line: String) -> Amount? {
        let pattern = #"(\d+(?:[.,]\d+)?)\s*(mg|g)\b"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let vr = Range(m.range(at: 1), in: line), let ur = Range(m.range(at: 2), in: line),
              let v = Double(line[vr].replacingOccurrences(of: ",", with: ".")) else { return nil }
        return Amount(mg: line[ur] == "g" ? v * 1000 : v)
    }

    struct Amount { var mg: Double }
}

extension FuelDayLog {
    /// Ticks a supplement: protein counts as palms (25 g each); a meal shake adds its macros and marks its meal eaten.
    public mutating func tick(_ dose: SupplementDose) {
        untick(dose)
        let add = dose.supplement.portions
        if let r = dose.replaces {
            untick(r)
            ticks[r] = FuelTick(added: Portions())
        }
        ticks[dose.id] = FuelTick(added: add)
        for k in Portions.Kind.allCases { eaten[k] += add[k] }
    }

    public mutating func untick(_ dose: SupplementDose) {
        untick(dose.id)
        if let r = dose.replaces, let t = ticks[r], t.recipeId == nil, t.added.total == 0 { ticks[r] = nil }
    }

    public func taken(_ dose: SupplementDose) -> Bool { ticks[dose.id] != nil }
}
