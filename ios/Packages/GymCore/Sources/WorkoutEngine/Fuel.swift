import Foundation

// Fuel (#496): nutrition pointers from the day's training. Everything here is general guidance, not medical advice;
// nothing is counted unless the member taps it, and all of it stays on the device.

/// What the member eats for. Nil in prefs = taken from the training goal.
public enum FuelGoal: String, Codable, CaseIterable, Sendable, Identifiable {
    case lose, maintain, build, perform
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .lose: "Lose fat"
        case .maintain: "Stay as I am"
        case .build: "Build muscle"
        case .perform: "Perform"
        }
    }

    public var detail: String {
        switch self {
        case .lose: "More protein, a bit less carbs and fat, never under-fuel training"
        case .maintain: "Balanced plate, carbs follow training"
        case .build: "Protein at every meal, enough carbs to grow"
        case .perform: "Carbs around sessions, fast recovery"
        }
    }

    /// Training goal → fuel goal when the member hasn't picked one.
    public static func from(_ goal: Goal) -> FuelGoal {
        switch goal {
        case .build, .strength: .build
        case .climbing, .endurance, .athletic: .perform
        case .balanced: .maintain
        }
    }
}

public enum FuelDiet: String, Codable, CaseIterable, Sendable, Identifiable {
    case omnivore, pescatarian, vegetarian, vegan, halal
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .omnivore: "Omnivore"
        case .pescatarian: "Pescatarian"
        case .vegetarian: "Vegetarian"
        case .vegan: "Vegan"
        case .halal: "Halal"
        }
    }

    public var emoji: String {
        switch self {
        case .omnivore: "🍗"
        case .pescatarian: "🐟"
        case .vegetarian: "🥚"
        case .vegan: "🌱"
        case .halal: "☪️"
        }
    }
}

/// Things a recipe can contain that a member may avoid.
public enum Allergen: String, Codable, CaseIterable, Sendable, Identifiable {
    case lactose, gluten, nuts, peanuts, eggs, soy, fish, shellfish, sesame, alcohol
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .lactose: "Lactose"
        case .gluten: "Gluten"
        case .nuts: "Nuts"
        case .peanuts: "Peanuts"
        case .eggs: "Eggs"
        case .soy: "Soy"
        case .fish: "Fish"
        case .shellfish: "Shellfish"
        case .sesame: "Sesame"
        case .alcohol: "Alcohol"
        }
    }
}

/// The three ways to look at a day (#496, designs A + B + C), member picks the default.
public enum FuelLayout: String, Codable, CaseIterable, Sendable, Identifiable {
    case dashboard, timeline, portions
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .dashboard: "Day"
        case .timeline: "Timeline"
        case .portions: "Portions"
        }
    }

    public var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .timeline: "clock.fill"
        case .portions: "hand.raised.fill"
        }
    }
}

/// Member settings for Fuel. All optional to change; defaults work with no setup.
public struct FuelPrefs: Codable, Equatable, Sendable {
    /// Nil = from the training goal.
    public var goal: FuelGoal?
    public var diet: FuelDiet
    public var avoid: Set<Allergen>
    /// 3…6 meals and snacks a day.
    public var meals: Int
    /// Minutes after midnight.
    public var wake: Int
    public var sleep: Int
    /// Hides grams, %, kcal and weight everywhere in Fuel (portions and plates stay).
    public var noNumbers: Bool
    public var layout: FuelLayout
    /// Refuel reminder after training, max 2 a day.
    public var nudges: Bool
    /// Glass size in ml.
    public var glassMl: Int

    public init(goal: FuelGoal? = nil, diet: FuelDiet = .omnivore, avoid: Set<Allergen> = [], meals: Int = 4,
                wake: Int = 7 * 60, sleep: Int = 23 * 60, noNumbers: Bool = false, layout: FuelLayout = .dashboard,
                nudges: Bool = true, glassMl: Int = 250) {
        self.goal = goal
        self.diet = diet
        self.avoid = avoid
        self.meals = meals
        self.wake = wake
        self.sleep = sleep
        self.noNumbers = noNumbers
        self.layout = layout
        self.nudges = nudges
        self.glassMl = glassMl
    }

    public func goal(training: Goal?) -> FuelGoal { goal ?? training.map(FuelGoal.from) ?? .maintain }
}

/// One training on a day: a gym workout, a sport or a climb, done or planned.
public struct FuelActivity: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: Codable, Hashable, Sendable {
        case gym
        case sport(Sport)
    }

    public var id: String
    public var kind: Kind
    public var title: String
    /// Planned sessions without a time use the member's usual training hour.
    public var start: Date
    public var minutes: Int
    /// From the Watch / Health when known.
    public var kcal: Double?
    /// 1…10, when rated.
    public var effort: Int?
    public var done: Bool

    public init(id: String, kind: Kind, title: String, start: Date, minutes: Int, kcal: Double? = nil, effort: Int? = nil, done: Bool) {
        self.id = id
        self.kind = kind
        self.title = title
        self.start = start
        self.minutes = max(0, minutes)
        self.kcal = kcal
        self.effort = effort
        self.done = done
    }

    public var end: Date { start.addingTimeInterval(Double(minutes) * 60) }

    /// Sweaty endurance work needs more fluid and carbs than lifting.
    public var endurance: Bool {
        switch kind {
        case .gym: false
        case .sport(let s): s.load.cardio >= 0.5
        }
    }

    public var sport: Sport? {
        if case .sport(let s) = kind { return s }
        return nil
    }

    /// Energy estimate: measured kcal, else MET × kg × hours (gym ≈ MET 5, scaled by effort).
    public func energy(weightKg: Double) -> Double {
        if let kcal, kcal > 0 { return kcal }
        let met: Double = switch kind {
        case .gym: 5
        case .sport(let s): s.met
        }
        let scale = effort.map { 0.6 + Double(max(1, min(10, $0))) * 0.07 } ?? 1
        return met * scale * weightKg * Double(minutes) / 60
    }
}

/// How hard the day is, from rest to big.
public enum FuelLoad: Int, Codable, Comparable, CaseIterable, Sendable {
    case rest = 1, normal, big

    public static func < (a: FuelLoad, b: FuelLoad) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .rest: "Rest day"
        case .normal: "Training day"
        case .big: "Big day"
        }
    }

    public var short: String {
        switch self {
        case .rest: "Rest"
        case .normal: "Normal"
        case .big: "Big"
        }
    }

    public var carbLabel: String {
        switch self {
        case .rest: "Lower"
        case .normal: "Medium"
        case .big: "High"
        }
    }
}

/// Hand portions (no scale needed): palm = protein, cupped hand = carbs, fist = veg, thumb = fats.
public struct Portions: Codable, Hashable, Sendable {
    public var palms: Int
    public var cups: Int
    public var fists: Int
    public var thumbs: Int

    public init(palms: Int = 0, cups: Int = 0, fists: Int = 0, thumbs: Int = 0) {
        self.palms = palms
        self.cups = cups
        self.fists = fists
        self.thumbs = thumbs
    }

    public enum Kind: String, CaseIterable, Codable, Sendable, Identifiable {
        case palms, cups, fists, thumbs
        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .palms: "Palms"
            case .cups: "Cupped hands"
            case .fists: "Fists"
            case .thumbs: "Thumbs"
            }
        }

        public var food: String {
            switch self {
            case .palms: "Protein"
            case .cups: "Carbs"
            case .fists: "Veg"
            case .thumbs: "Fats"
            }
        }

        public var emoji: String {
            switch self {
            case .palms: "✋"
            case .cups: "🤲"
            case .fists: "✊"
            case .thumbs: "👍"
            }
        }

        public var examples: String {
            switch self {
            case .palms: "Meat, fish, eggs, tofu, skyr, cottage cheese"
            case .cups: "Rice, pasta, potatoes, oats, bread, fruit"
            case .fists: "Any vegetables or salad"
            case .thumbs: "Oil, butter, nuts, cheese, avocado"
            }
        }
    }

    public subscript(_ k: Kind) -> Int {
        get {
            switch k {
            case .palms: palms
            case .cups: cups
            case .fists: fists
            case .thumbs: thumbs
            }
        }
        set {
            switch k {
            case .palms: palms = max(0, newValue)
            case .cups: cups = max(0, newValue)
            case .fists: fists = max(0, newValue)
            case .thumbs: thumbs = max(0, newValue)
            }
        }
    }

    public var total: Int { palms + cups + fists + thumbs }

    /// Rough grams per portion, used to turn grams into hands and back.
    public static let proteinPerPalm = 25.0
    public static let carbsPerCup = 25.0
    public static let fatPerThumb = 9.0

    public static func from(protein: Double, carbs: Double, fat: Double, veg: Int) -> Portions {
        Portions(palms: Int((protein / proteinPerPalm).rounded()), cups: Int((carbs / carbsPerCup).rounded()),
                 fists: veg, thumbs: Int((fat / fatPerThumb).rounded()))
    }
}

public enum MealKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case breakfast, lunch, dinner, snack, pre, recovery, bedtime
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        case .pre: "Pre-workout"
        case .recovery: "Recovery"
        case .bedtime: "Before bed"
        }
    }

    public var emoji: String {
        switch self {
        case .breakfast: "🥣"
        case .lunch: "🥗"
        case .dinner: "🍲"
        case .snack: "🍎"
        case .pre: "⚡"
        case .recovery: "💪"
        case .bedtime: "🌙"
        }
    }

    /// Share of the day's protein and carbs a slot gets before normalising.
    var proteinWeight: Double {
        switch self {
        case .breakfast, .lunch, .dinner, .recovery: 1
        case .bedtime: 0.8
        case .snack: 0.45
        case .pre: 0.3
        }
    }

    var carbWeight: Double {
        switch self {
        case .breakfast, .lunch, .dinner: 1
        case .recovery: 1.2
        case .pre: 0.7
        case .snack: 0.4
        case .bedtime: 0.2
        }
    }

    var fatWeight: Double {
        switch self {
        case .breakfast, .lunch, .dinner: 1
        case .snack, .bedtime: 0.5
        case .recovery: 0.4
        case .pre: 0.15
        }
    }

    var vegFists: Int {
        switch self {
        case .lunch, .dinner: 2
        case .breakfast, .recovery: 1
        case .snack, .pre, .bedtime: 0
        }
    }
}

/// One meal or snack on the day's timeline.
public struct FuelSlot: Codable, Hashable, Sendable, Identifiable {
    /// "lunch", "pre-1"…: stable for the day so ticks survive a re-plan.
    public var id: String
    public var kind: MealKind
    /// Minutes after midnight.
    public var minute: Int
    /// Main meal that also covers recovery (eaten within 2 h after training).
    public var afterTraining: Bool
    public var protein: Int
    public var carbs: Int
    public var fat: Int
    public var portions: Portions
    /// What to aim for, in words.
    public var hint: String

    public var time: String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    /// Kind used to pick recipes: a main meal right after training wants recovery food.
    public var recipeKind: MealKind { afterTraining ? .recovery : kind }
    public var title: String { afterTraining ? "\(kind.label) · recovery" : kind.label }
}

/// Today's targets and plan.
public struct FuelPlan: Codable, Hashable, Sendable {
    public var day: Date
    public var goal: FuelGoal
    public var load: FuelLoad
    public var activities: [FuelActivity]
    /// Training energy (not steps), kcal.
    public var trainingKcal: Int
    public var protein: Int
    public var carbs: Int
    public var fat: Int
    public var kcal: Int
    public var waterMl: Int
    public var glasses: Int
    public var portions: Portions
    public var slots: [FuelSlot]
    /// Weight was missing: numbers use a typical body.
    public var estimated: Bool
    public var tips: [String]
    /// Race or event within 2 days.
    public var event: FuelEvent?
    /// The member's supplements placed on the day (#514).
    public var supplements: [SupplementDose] = []

    /// "Legs + Hyrox", or the load when nothing is planned.
    public var headline: String {
        let names = activities.map(\.title)
        return names.isEmpty ? load.label : names.prefix(2).joined(separator: " + ")
    }

    /// Next slot from `minute` (now), for "next meal" cards.
    public func next(after minute: Int) -> FuelSlot? { slots.first { $0.minute >= minute - 30 } ?? slots.last }
}

/// A race or event coming up (#496): carb loading before long ones, race-morning pointers on the day.
public struct FuelEvent: Codable, Hashable, Sendable {
    public var sport: Sport
    public var name: String
    /// 0 = the event is today, 1 = tomorrow, 2 = in two days.
    public var days: Int

    public init(sport: Sport, name: String, days: Int) {
        self.sport = sport
        self.name = name
        self.days = days
    }

    /// Long or hard enough that topping up glycogen pays off.
    public var loads: Bool { sport.load.cardio >= 0.5 }

    public var title: String {
        switch days {
        case 0: "\(name) today"
        case 1: "\(name) tomorrow"
        default: "\(name) in \(days) days"
        }
    }

    public var pointers: [String] {
        if days == 0 {
            return ["Breakfast 3 h before the start: carbs you know well (oats, toast with honey, rice), a little protein, low fat and fibre.",
                    "Top up 30 to 60 min before with a banana or a bar and a glass of water.",
                    "Nothing new today: no new foods, gels or drinks you haven't tried in training.",
                    "Afterwards: the recovery meal within 2 h, and extra water with some salt."]
        }
        var out = ["Carb up: carbs at every meal and snack (rice, pasta, potatoes, bread, fruit), a bit less fat to make room."]
        out.append(days == 1 ? "Go easy on fibre and big salads tonight so your stomach is calm tomorrow." : "Keep training light so the carbs stay in your muscles.")
        out.append("Drink steadily all day: pale yellow is the goal.")
        return out
    }
}

/// Inputs for one day.
public struct FuelDayInput: Sendable {
    public var day: Date
    public var weightKg: Double?
    public var leanKg: Double?
    public var female: Bool
    public var activities: [FuelActivity]
    public var steps: Int
    /// Tomorrow's load (planned), for the "tomorrow" card and carb timing.
    public var tomorrow: [FuelActivity]
    public var trainingGoal: Goal?
    public var event: FuelEvent?

    public init(day: Date, weightKg: Double? = nil, leanKg: Double? = nil, female: Bool = false, activities: [FuelActivity] = [],
                steps: Int = 0, tomorrow: [FuelActivity] = [], trainingGoal: Goal? = nil, event: FuelEvent? = nil) {
        self.event = event
        self.day = day
        self.weightKg = weightKg
        self.leanKg = leanKg
        self.female = female
        self.activities = activities
        self.steps = steps
        self.tomorrow = tomorrow
        self.trainingGoal = trainingGoal
    }
}

public enum Fuel {
    /// Used when no weight is known.
    public static let typicalKg = 75.0
    public static let typicalFemaleKg = 64.0
    /// Protein g/kg by goal.
    public static func proteinPerKg(_ g: FuelGoal) -> Double {
        switch g {
        case .lose: 2.2
        case .maintain: 1.6
        case .build: 2.0
        case .perform: 1.8
        }
    }

    /// Carbs g/kg by load, shifted by goal.
    public static func carbsPerKg(_ load: FuelLoad, goal: FuelGoal) -> Double {
        let base: Double = switch load {
        case .rest: 3
        case .normal: 4.5
        case .big: 6.5
        }
        let shift: Double = switch goal {
        case .lose: -1
        case .maintain: 0
        case .build: 0.5
        case .perform: 1
        }
        return max(2, base + shift)
    }

    public static func fatPerKg(_ goal: FuelGoal) -> Double { goal == .lose ? 0.7 : 0.9 }

    /// Rest under 150 kcal of training; big from 600 kcal or 90 min, or two sessions of 45+ min.
    public static func load(_ activities: [FuelActivity], weightKg: Double) -> FuelLoad {
        let kcal = activities.reduce(0.0) { $0 + $1.energy(weightKg: weightKg) }
        let minutes = activities.reduce(0) { $0 + $1.minutes }
        if activities.isEmpty || (kcal < 150 && minutes < 25) { return .rest }
        if kcal >= 600 || minutes >= 90 || activities.filter({ $0.minutes >= 45 }).count >= 2 { return .big }
        return .normal
    }

    /// Body weight protein is based on: lean mass when measured (so a high body fat doesn't inflate it), else weight.
    static func proteinBase(weight: Double, lean: Double?) -> Double {
        guard let lean, lean > 20, lean < weight else { return weight }
        return min(weight, lean * 1.25)
    }

    public static func plan(_ input: FuelDayInput, prefs: FuelPrefs, calendar cal: Calendar = Progression.calendar()) -> FuelPlan {
        let estimated = input.weightKg == nil
        let kg = input.weightKg ?? (input.female ? typicalFemaleKg : typicalKg)
        let goal = prefs.goal(training: input.trainingGoal)
        let acts = input.activities.sorted { $0.start < $1.start }
        let load = Self.load(acts, weightKg: kg)
        let tomorrow = Self.load(input.tomorrow, weightKg: kg)
        let trainingKcal = Int(acts.reduce(0.0) { $0 + $1.energy(weightKg: kg) }.rounded())

        var protein = proteinPerKg(goal) * proteinBase(weight: kg, lean: input.leanKg)
        if load == .big { protein += 0.2 * kg }
        var carbs = carbsPerKg(load, goal: goal) * kg
        // Big day tomorrow: top the glycogen up tonight.
        if tomorrow == .big && load < .big { carbs += 1 * kg }
        // Carb loading (1–2 days before a long endurance event): 8 g/kg, whatever the goal.
        if let e = input.event, e.days >= 1, e.loads { carbs = max(carbs, 8 * kg) }
        let fat = fatPerKg(goal) * kg * (input.event.map { $0.days >= 1 && $0.loads } == true ? 0.8 : 1)
        protein = (protein / 5).rounded() * 5
        carbs = (carbs / 10).rounded() * 10
        let fatG = (fat / 5).rounded() * 5
        let kcal = Int((4 * protein + 4 * carbs + 9 * fatG).rounded())

        // Water: 35 ml/kg, +500 ml per training hour (750 for sweaty endurance), +250 per 5,000 steps.
        var water = 35 * kg
        for a in acts { water += Double(a.minutes) / 60 * (a.endurance ? 750 : 500) }
        water += Double(input.steps / 5000) * 250
        let glassMl = max(100, prefs.glassMl)
        let glasses = max(4, Int((water / Double(glassMl)).rounded()))
        let waterMl = glasses * glassMl

        let slots = timeline(acts, protein: protein, carbs: carbs, fat: fatG, load: load, prefs: prefs, day: input.day, calendar: cal)
        let vegFists = slots.reduce(0) { $0 + $1.portions.fists }
        let portions = Portions(palms: Int((protein / Portions.proteinPerPalm).rounded()),
                                cups: max(2, Int((carbs / Portions.carbsPerCup).rounded())),
                                fists: max(4, vegFists),
                                thumbs: max(2, Int((fatG * 0.6 / Portions.fatPerThumb).rounded())))

        return FuelPlan(day: cal.startOfDay(for: input.day), goal: goal, load: load, activities: acts, trainingKcal: trainingKcal,
                        protein: Int(protein), carbs: Int(carbs), fat: Int(fatG), kcal: kcal, waterMl: waterMl, glasses: glasses,
                        portions: portions, slots: slots, estimated: estimated,
                        tips: (input.event.map { [$0.title + ": " + $0.pointers[0]] } ?? []) + tips(load: load, tomorrow: tomorrow, goal: goal, acts: acts, prefs: prefs),
                        event: input.event)
    }

    /// Meals placed around the day's training: main meals, a pre-workout snack 60–90 min before, recovery within
    /// 2 h after (the next main meal when it is close, else a recovery snack), then snacks / bedtime to the member's count.
    static func timeline(_ acts: [FuelActivity], protein: Double, carbs: Double, fat: Double, load: FuelLoad, prefs: FuelPrefs,
                         day: Date, calendar cal: Calendar) -> [FuelSlot] {
        let wake = max(4 * 60, min(12 * 60, prefs.wake))
        let sleep = max(wake + 10 * 60, min(27 * 60, prefs.sleep))
        struct Draft { var id: String; var kind: MealKind; var minute: Int; var after = false }
        var drafts = [
            Draft(id: "breakfast", kind: .breakfast, minute: wake + 30),
            Draft(id: "lunch", kind: .lunch, minute: max(wake + 4 * 60, 12 * 60 + 30)),
            Draft(id: "dinner", kind: .dinner, minute: min(sleep - 2 * 60 - 30, max(wake + 9 * 60, 19 * 60))),
        ]
        let start = cal.startOfDay(for: day)
        func minute(_ d: Date) -> Int { Int(d.timeIntervalSince(start) / 60) }
        // Main meals inside a training move after it first, so they become its recovery meal (#524).
        for a in acts {
            let s = minute(a.start), e = minute(a.end)
            for j in drafts.indices where drafts[j].minute > s - 20 && drafts[j].minute < e { drafts[j].minute = e + 30 }
        }
        for (i, a) in acts.enumerated() {
            let s = minute(a.start), e = minute(a.end)
            // Pre: only when the last main meal is more than 2 h before.
            let lastMain = drafts.filter { $0.minute <= s }.map(\.minute).max()
            if s - (lastMain ?? wake) > 120, s - 75 > wake {
                drafts.append(Draft(id: "pre-\(i)", kind: .pre, minute: s - 75))
            }
            if let j = drafts.indices.first(where: { [MealKind.breakfast, .lunch, .dinner].contains(drafts[$0].kind) && drafts[$0].minute >= e && drafts[$0].minute - e <= 120 }) {
                drafts[j].after = true
                drafts[j].minute = max(drafts[j].minute, e + 30)
            } else if e + 30 < sleep {
                drafts.append(Draft(id: "recovery-\(i)", kind: .recovery, minute: e + 30))
            }
        }
        // Meals still inside a training move after it; a recovery snack already there is the same meal (#524).
        for a in acts {
            let s = minute(a.start), e = minute(a.end)
            for j in drafts.indices where drafts[j].minute > s - 20 && drafts[j].minute < e {
                drafts[j].minute = e + 30
                drafts[j].after = true
            }
        }
        drafts.removeAll { d in d.kind == .recovery && drafts.contains { $0.kind != .recovery && $0.after && abs($0.minute - d.minute) < 60 } }
        let wanted = max(3, min(6, prefs.meals))
        let extras: [(String, MealKind, Int)] = [("snack-pm", .snack, 16 * 60), ("bedtime", .bedtime, sleep - 60), ("snack-am", .snack, 10 * 60)]
        for (id, kind, m) in extras where drafts.count < wanted {
            guard m > wake + 60, m < sleep, !drafts.contains(where: { abs($0.minute - m) < 90 }) else { continue }
            drafts.append(Draft(id: id, kind: kind, minute: m))
        }
        drafts.sort { $0.minute < $1.minute }

        let pw = drafts.reduce(0.0) { $0 + ($1.after ? MealKind.recovery.proteinWeight : $1.kind.proteinWeight) }
        let cw = drafts.reduce(0.0) { $0 + ($1.after ? MealKind.recovery.carbWeight : $1.kind.carbWeight) }
        let fw = drafts.reduce(0.0) { $0 + $1.kind.fatWeight }
        return drafts.map { d in
            let k = d.after ? MealKind.recovery : d.kind
            let p = protein * k.proteinWeight / max(pw, 0.1)
            let c = carbs * k.carbWeight / max(cw, 0.1)
            let f = fat * d.kind.fatWeight / max(fw, 0.1)
            let veg = d.kind.vegFists
            return FuelSlot(id: d.id, kind: d.kind, minute: d.minute, afterTraining: d.after,
                            protein: Int((p / 5).rounded() * 5), carbs: Int((c / 5).rounded() * 5), fat: Int((f / 5).rounded() * 5),
                            portions: Portions.from(protein: p, carbs: c, fat: f * 0.6, veg: veg),
                            hint: hint(d.kind, after: d.after, load: load))
        }
    }

    static func hint(_ kind: MealKind, after: Bool, load: FuelLoad) -> String {
        if after { return "Protein + carbs to refuel: rice, potatoes or pasta with a palm or two of protein" }
        switch kind {
        case .breakfast: return load == .big ? "Big day: oats or bread plus protein, fruit" : "Protein to start: eggs, skyr or a shake, plus fruit"
        case .lunch: return load == .rest ? "Plate half veg, a palm of protein, a cup of carbs" : "Real meal with carbs: you train later"
        case .dinner: return load == .rest ? "Lighter carbs, plenty of veg and protein" : "Protein, carbs and veg to recover overnight"
        case .snack: return "Fruit + protein: yogurt, nuts, a shake"
        case .pre: return "Easy carbs, little fat and fibre: banana, toast with honey, a bar"
        case .recovery: return "Within an hour: protein + carbs, e.g. milk shake and a banana"
        case .bedtime: return "Slow protein: skyr, cottage cheese, quark"
        }
    }

    static func tips(load: FuelLoad, tomorrow: FuelLoad, goal: FuelGoal, acts: [FuelActivity], prefs: FuelPrefs) -> [String] {
        var out: [String] = []
        switch load {
        case .big: out.append("Big day: carbs at every meal, and don't skip the recovery meal.")
        case .normal: out.append("Training day: carbs before and after, protein spread over the day.")
        case .rest: out.append("Rest day: keep protein high, lighter carbs, lots of veg.")
        }
        if acts.contains(where: \.endurance) { out.append("Long sweaty session: drink before, sip during, add a pinch of salt after.") }
        if tomorrow == .big && load < .big { out.append("Big day tomorrow: an extra cup of carbs at dinner tonight.") }
        if goal == .lose { out.append("Losing fat: protein first at each meal keeps you full. Never cut the meal after training.") }
        if goal == .build { out.append("Building: a palm of protein at every meal, and a slow protein before bed.") }
        if prefs.diet == .vegan { out.append("Vegan: mix beans, lentils, tofu and grains so every meal has complete protein.") }
        return out
    }
}
