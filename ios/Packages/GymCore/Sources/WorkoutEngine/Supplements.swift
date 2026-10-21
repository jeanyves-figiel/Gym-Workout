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

/// When a supplement is taken across days (#572, designs A + C): times a day, which days, how long, on/off cycles
/// and a loading phase. Pointers only: the member sets it from their label or their coach.
public struct SupplementRhythm: Codable, Hashable, Sendable {
    /// One take in the day: at a moment of the day, or at a set clock time.
    public struct Intake: Codable, Hashable, Sendable {
        public var timing: SupplementTiming
        /// Minutes after midnight; overrides `timing`.
        public var minute: Int?
        /// Servings per take: 2 capsules = 2.
        public var servings: Double

        public init(timing: SupplementTiming, minute: Int? = nil, servings: Double = 1) {
            self.timing = timing
            self.minute = minute
            self.servings = max(0.5, servings)
        }
    }

    public enum Days: Codable, Hashable, Sendable {
        case everyDay, trainingDays
        /// Calendar weekdays, 1 = Sunday.
        case weekdays([Int])
        case everyN(Int)
    }

    public enum Length: Codable, Hashable, Sendable {
        case ongoing
        case weeks(Int)
        /// Last day taken.
        case until(Date)
    }

    public struct Cycle: Codable, Hashable, Sendable {
        public var onWeeks: Int
        public var offWeeks: Int
        public init(onWeeks: Int, offWeeks: Int) { self.onWeeks = max(1, onWeeks); self.offWeeks = max(1, offWeeks) }
    }

    /// The quick plans (design C): tiles that fill the rhythm; "My own" is anything else.
    public enum Quick: String, CaseIterable, Sendable, Identifiable {
        case daily, twice, training, load, cycle
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .daily: "Daily"
            case .twice: "Twice a day"
            case .training: "Training days"
            case .load: "Load, then daily"
            case .cycle: "Cycle"
            }
        }
        public var detail: String {
            switch self {
            case .daily: "1× a day, every day"
            case .twice: "Breakfast + dinner"
            case .training: "Only when you train"
            case .load: "4× a day for 7 days, then 1×"
            case .cycle: "8 weeks on · 4 off"
            }
        }
    }

    public var intakes: [Intake]
    public var days: Days
    /// First day.
    public var start: Date
    public var length: Length
    public var cycle: Cycle?
    /// First days at `loadTimes` takes a day (spread over breakfast, lunch, dinner, bed).
    public var loadDays: Int
    public var loadTimes: Int
    /// A reminder at each take.
    public var remind: Bool

    public init(intakes: [Intake], days: Days = .everyDay, start: Date, length: Length = .ongoing, cycle: Cycle? = nil,
                loadDays: Int = 0, loadTimes: Int = 4, remind: Bool = false) {
        self.intakes = intakes.isEmpty ? [Intake(timing: .breakfast)] : intakes
        self.days = days
        self.start = start
        self.length = length
        self.cycle = cycle
        self.loadDays = max(0, loadDays)
        self.loadTimes = min(4, max(2, loadTimes))
        self.remind = remind
    }

    public static func quick(_ q: Quick, kind: SupplementKind, start: Date) -> SupplementRhythm {
        let first = Intake(timing: kind.timing)
        switch q {
        case .daily: return SupplementRhythm(intakes: [first], start: start)
        case .twice:
            return SupplementRhythm(intakes: [Intake(timing: kind.timing.aroundTraining ? kind.timing : .breakfast), Intake(timing: .evening)],
                                    start: start)
        case .training:
            return SupplementRhythm(intakes: [Intake(timing: kind.timing.aroundTraining ? kind.timing : .afterTraining)], days: .trainingDays,
                                    start: start)
        case .load: return SupplementRhythm(intakes: [first], start: start, loadDays: 7, loadTimes: 4)
        case .cycle: return SupplementRhythm(intakes: [first], start: start, cycle: Cycle(onWeeks: 8, offWeeks: 4))
        }
    }

    /// The quick plan this rhythm is, if any (length, servings and reminders aside).
    public func quick(_ kind: SupplementKind) -> Quick? {
        var me = self
        me.intakes = intakes.map { Intake(timing: $0.timing, minute: $0.minute) }
        return Quick.allCases.first { q in
            var r = SupplementRhythm.quick(q, kind: kind, start: start)
            r.length = length
            r.remind = remind
            return r == me
        }
    }

    static let loadTimings: [SupplementTiming] = [.breakfast, .lunch, .evening, .bedtime]

    /// The takes on a day, or none when the day isn't in the schedule.
    public func intakes(on day: Date, training: Bool, calendar cal: Calendar) -> [Intake] {
        let d = cal.startOfDay(for: day)
        let first = cal.startOfDay(for: start)
        guard d >= first || start == .distantPast else { return [] }
        let n = start == .distantPast ? 0 : (cal.dateComponents([.day], from: first, to: d).day ?? 0)
        switch length {
        case .ongoing: break
        case .weeks(let w): if n >= w * 7 { return [] }
        case .until(let last): if d > cal.startOfDay(for: last) { return [] }
        }
        if let c = cycle, start != .distantPast, (n / 7) % (c.onWeeks + c.offWeeks) >= c.onWeeks { return [] }
        switch days {
        case .everyDay: break
        case .trainingDays: if !training { return [] }
        case .weekdays(let w): if !w.contains(cal.component(.weekday, from: d)) { return [] }
        case .everyN(let k): if k > 1 && n % k != 0 { return [] }
        }
        if n < loadDays {
            return Self.loadTimings.prefix(loadTimes).map { Intake(timing: $0, servings: intakes.first?.servings ?? 1) }
        }
        return intakes
    }

    /// "Week 3 of 12 · ends Mon 12 Jan", "Break until Tue 3 Feb", nil when ongoing with no cycle.
    public func courseLine(now: Date, calendar cal: Calendar) -> String? {
        guard start != .distantPast else { return nil }
        let d = cal.startOfDay(for: now), first = cal.startOfDay(for: start)
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.setLocalizedDateFormatFromTemplate("EEE d MMM")
        if d < first { return "Starts \(fmt.string(from: first))" }
        let n = cal.dateComponents([.day], from: first, to: d).day ?? 0
        var parts: [String] = []
        if n < loadDays { parts.append("Loading day \(n + 1) of \(loadDays)") }
        if let c = cycle {
            let period = c.onWeeks + c.offWeeks, w = (n / 7) % period
            if w < c.onWeeks {
                let off = cal.date(byAdding: .day, value: (n / 7 - w + c.onWeeks) * 7, to: first) ?? d
                parts.append("On week \(w + 1) of \(c.onWeeks) · break from \(fmt.string(from: off))")
            } else {
                let back = cal.date(byAdding: .day, value: (n / 7 - w + period) * 7, to: first) ?? d
                parts.append("Break · back \(fmt.string(from: back))")
            }
        }
        switch length {
        case .ongoing: break
        case .weeks(let w):
            let end = cal.date(byAdding: .day, value: w * 7 - 1, to: first) ?? d
            parts.append(n >= w * 7 ? "Course done" : "Week \(n / 7 + 1) of \(w) · ends \(fmt.string(from: end))")
        case .until(let last): parts.append(d > cal.startOfDay(for: last) ? "Course done" : "Until \(fmt.string(from: last))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Takes a day after loading, for the big number.
    public var perDay: Int { intakes.count }

    /// "Every day", "Mon, Wed, Fri", "Every 2 days", "Training days".
    public func daysLabel(calendar cal: Calendar) -> String {
        switch days {
        case .everyDay: return "Every day"
        case .trainingDays: return "Training days"
        case .everyN(let k): return k <= 1 ? "Every day" : "Every \(k) days"
        case .weekdays(let w):
            if Set(w) == [2, 3, 4, 5, 6] { return "Mon–Fri" }
            if Set(w) == [1, 7] { return "Weekends" }
            let order = (0..<7).map { (cal.firstWeekday - 1 + $0) % 7 + 1 }
            return order.filter(w.contains).map { cal.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
        }
    }

    /// One line for the stack and Coach: "2× a day · Mon–Fri · 12 weeks · 8 on / 4 off".
    public func summary(calendar cal: Calendar) -> String {
        var parts = ["\(perDay)× a day", daysLabel(calendar: cal)]
        if loadDays > 0 { parts.insert("\(loadTimes)× for \(loadDays) days, then", at: 0) }
        switch length {
        case .ongoing: break
        case .weeks(let w): parts.append("\(w) weeks")
        case .until(let d):
            let fmt = DateFormatter()
            fmt.calendar = cal
            fmt.setLocalizedDateFormatFromTemplate("d MMM")
            parts.append("until \(fmt.string(from: d))")
        }
        if let c = cycle { parts.append("\(c.onWeeks) on / \(c.offWeeks) off") }
        return parts.joined(separator: " · ")
    }
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
    /// Times a day, days, course length, cycle and loading (#572). Nil on older saves: `timing` + `restDays`.
    public var rhythm: SupplementRhythm?

    public init(id: String = UUID().uuidString, name: String, kind: SupplementKind, timing: SupplementTiming? = nil, dose: String,
                caffeineMg: Int = 0, creatineG: Double = 0, proteinG: Double = 0, carbsG: Double = 0, fatG: Double = 0,
                restDays: Bool = false, rhythm: SupplementRhythm? = nil) {
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
        self.rhythm = rhythm
    }

    public var emoji: String { kind.emoji }

    /// The schedule in force: the saved one, or the one older saves meant.
    public var schedule: SupplementRhythm {
        rhythm ?? SupplementRhythm(intakes: [.init(timing: timing)], days: restDays ? .everyDay : .trainingDays, start: .distantPast)
    }

    /// Which amounts the editor asks for: the ones that fit the type, plus any already set.
    public var asksCaffeine: Bool { [.preWorkout, .caffeine, .other].contains(kind) || caffeineMg > 0 }
    public var asksCreatine: Bool { [.creatine, .preWorkout, .other].contains(kind) || creatineG > 0 }
    public var asksProtein: Bool { [.protein, .mealReplacement, .hotMeal, .preWorkout, .other].contains(kind) || proteinG > 0 }

    /// Switches the type: the name, serving and amounts follow the new type unless the member changed them
    /// (fixes "Meal shake" staying the name of a Creatine with 40 g protein).
    public func switching(to k: SupplementKind) -> Supplement {
        let old = kind.preset, new = k.preset
        var s = self
        s.kind = k
        if name.trimmingCharacters(in: .whitespaces).isEmpty || name == old.name { s.name = new.name }
        if dose.trimmingCharacters(in: .whitespaces).isEmpty || dose == old.dose { s.dose = new.dose }
        if caffeineMg == old.caffeineMg && creatineG == old.creatineG && proteinG == old.proteinG && carbsG == old.carbsG && fatG == old.fatG {
            (s.caffeineMg, s.creatineG, s.proteinG, s.carbsG, s.fatG) = (new.caffeineMg, new.creatineG, new.proteinG, new.carbsG, new.fatG)
        }
        if timing == kind.timing { s.timing = k.timing }
        if restDays == old.restDays { s.restDays = new.restDays }
        if let r = rhythm, let q = r.quick(kind) { s.rhythm = SupplementRhythm.quick(q, kind: k, start: r.start) }
        return s
    }

    /// One serving scaled: what a take of `servings` adds.
    func scaled(_ servings: Double) -> Supplement {
        guard servings != 1 else { return self }
        var s = self
        s.caffeineMg = Int((Double(caffeineMg) * servings).rounded())
        s.creatineG *= servings
        s.proteinG *= servings
        s.carbsG *= servings
        s.fatG *= servings
        let n = servings.rounded() == servings ? "\(Int(servings))" : String(format: "%.1f", servings)
        s.dose = dose.isEmpty ? "\(n) servings" : "\(n) × \(dose)"
        return s
    }

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

    /// The first take keeps the key older logs used.
    public static func tickId(_ s: Supplement, take: Int = 0) -> String { take == 0 ? "supp-\(s.id)" : "supp-\(s.id)-\(take + 1)" }

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
        let training = !acts.isEmpty
        return stack.flatMap { s -> [SupplementDose] in
            s.schedule.intakes(on: plan.day, training: training, calendar: cal).enumerated().compactMap { i, take -> SupplementDose? in
                var m: Int
                var reason: String
                switch take.timing {
                case .beforeTraining, .duringTraining, .afterTraining:
                    if let a = acts.first {
                        switch take.timing {
                        case .beforeTraining: m = minute(a.start) - 30; reason = "30 min before \(a.title)"
                        case .duringTraining: m = minute(a.start); reason = "Sip during \(a.title)"
                        default:
                            let last = acts.last ?? a
                            m = minute(last.end) + 15; reason = "After \(last.title)"
                        }
                    } else {
                        m = breakfast; reason = "Rest day: with breakfast"
                    }
                case .breakfast: m = breakfast; reason = "With breakfast"
                case .lunch: m = meal(.lunch) ?? 12 * 60 + 30; reason = "With lunch"
                case .evening: m = meal(.dinner) ?? 19 * 60; reason = "With dinner"
                case .bedtime: m = prefs.sleep - 30; reason = "Before bed"
                }
                if let fixed = take.minute { m = fixed; reason = "At \(clock(fixed))" }
                m = max(0, m)
                let one = s.scaled(take.servings)
                // A meal shake takes over the meal at its time.
                var replaces: String?
                if s.isMeal, take.minute == nil, let k = [SupplementTiming.breakfast: MealKind.breakfast, .lunch: .lunch, .evening: .dinner][take.timing],
                   let sl = slot(k) {
                    replaces = sl.id
                    reason = "Your \(k.label.lowercased())"
                }
                return SupplementDose(id: tickId(s, take: i), supplement: one, minute: m, reason: reason,
                                      late: one.caffeineMg > 0 && m > cutoff, replaces: replaces)
            }
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
