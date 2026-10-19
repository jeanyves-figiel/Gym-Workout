import Foundation

/// A meal marked eaten: the recipe (if one) and the portions it added, so unticking takes the same back.
public struct FuelTick: Codable, Hashable, Sendable {
    public var recipeId: String?
    public var added: Portions

    public init(recipeId: String? = nil, added: Portions) {
        self.recipeId = recipeId
        self.added = added
    }
}

/// What the member tapped on one day. Nothing is required: an empty log only means nothing was counted.
public struct FuelDayLog: Codable, Hashable, Sendable {
    public var glasses: Int
    public var eaten: Portions
    /// Slot id → tick.
    public var ticks: [String: FuelTick]

    public init(glasses: Int = 0, eaten: Portions = Portions(), ticks: [String: FuelTick] = [:]) {
        self.glasses = glasses
        self.eaten = eaten
        self.ticks = ticks
    }

    public var isEmpty: Bool { glasses == 0 && eaten.total == 0 && ticks.isEmpty }

    public mutating func tick(_ slot: FuelSlot, recipe: Recipe? = nil, servings: Int = 1) {
        untick(slot.id)
        var add = recipe?.portions ?? slot.portions
        if recipe != nil && servings > 1 {
            for k in Portions.Kind.allCases { add[k] *= servings }
        }
        ticks[slot.id] = FuelTick(recipeId: recipe?.id, added: add)
        for k in Portions.Kind.allCases { eaten[k] += add[k] }
    }

    public mutating func untick(_ slotId: String) {
        guard let t = ticks.removeValue(forKey: slotId) else { return }
        for k in Portions.Kind.allCases { eaten[k] -= t.added[k] }
    }

    /// 0…1: portions eaten against the day's portions (each kind capped at its target), or ticked meals when
    /// no portions were counted.
    public func fuelled(_ plan: FuelPlan) -> Double {
        let kinds = Portions.Kind.allCases.filter { plan.portions[$0] > 0 }
        if eaten.total > 0, !kinds.isEmpty {
            return kinds.reduce(0.0) { $0 + min(1, Double(eaten[$1]) / Double(plan.portions[$1])) } / Double(kinds.count)
        }
        guard !plan.slots.isEmpty else { return 0 }
        return Double(ticks.keys.filter { id in plan.slots.contains { $0.id == id } }.count) / Double(plan.slots.count)
    }

    public func proteinHit(_ plan: FuelPlan) -> Bool { plan.portions.palms > 0 && eaten.palms >= plan.portions.palms }
    public func waterHit(_ plan: FuelPlan) -> Bool { glasses >= plan.glasses }
}

/// One day of the Fuel week.
public struct FuelWeekDay: Hashable, Sendable, Identifiable {
    public var day: Date
    public var plan: FuelPlan
    public var log: FuelDayLog
    public var id: Date { day }

    public init(day: Date, plan: FuelPlan, log: FuelDayLog) {
        self.day = day
        self.plan = plan
        self.log = log
    }
    public var fuelled: Double { log.fuelled(plan) }
}

public enum FuelWeek {
    /// Days in a row up to today (or yesterday when today isn't hit yet) meeting `hit`.
    public static func streak(_ days: [FuelWeekDay], today: Date, calendar cal: Calendar = Progression.calendar(),
                              hit: (FuelWeekDay) -> Bool) -> Int {
        let byDay = Dictionary(days.map { (cal.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { a, _ in a })
        var d = cal.startOfDay(for: today)
        if let t = byDay[d], !hit(t) { d = cal.date(byAdding: .day, value: -1, to: d) ?? d }
        var n = 0
        while let x = byDay[d], hit(x) {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: d) else { break }
            d = prev
        }
        return n
    }

    public static let proteinXP = 10
    public static let waterXP = 5

    /// XP Fuel adds to the level: 10 for a day at the protein target, 5 for the water target.
    public static func xp(_ days: [FuelWeekDay]) -> Int {
        days.reduce(0) { $0 + ($1.log.proteinHit($1.plan) ? proteinXP : 0) + ($1.log.waterHit($1.plan) ? waterXP : 0) }
    }

    /// Coach line for the week: the most under-fuelled big day, else praise.
    public static func insight(_ days: [FuelWeekDay], calendar cal: Calendar = Progression.calendar()) -> String {
        let counted = days.filter { !$0.log.isEmpty }
        guard !counted.isEmpty else { return "Tap glasses and meals in Fuel to see how you fuel your training." }
        if let worst = counted.filter({ $0.plan.load == .big && $0.fuelled < 0.7 }).min(by: { $0.fuelled < $1.fuelled }) {
            let name = worst.day.formatted(.dateTime.weekday(.wide))
            return "\(name) was a big day but under-fuelled. Plan the recovery meal on big days."
        }
        let water = counted.filter { $0.log.waterHit($0.plan) }.count
        if water * 2 < counted.count { return "Water is the easy win this week: a glass with every meal." }
        return "Well fuelled this week. Keep protein at every meal."
    }
}

/// Short reads in Fuel → Learn.
public struct FuelLearnCard: Hashable, Sendable, Identifiable {
    public let id: String
    public let emoji: String
    public let title: String
    public let summary: String
    public let points: [String]
}

public enum FuelLearn {
    public static let cards: [FuelLearnCard] = [
        .init(id: "protein", emoji: "💪", title: "Protein", summary: "The building block for every training goal.",
              points: ["1.6 to 2.2 g per kg of body weight a day covers almost everyone who trains.",
                       "Spread it over 3 to 5 meals of 20 to 40 g: the body uses it better than one big serving.",
                       "A palm of meat, fish, tofu or a pot of skyr is about 25 g.",
                       "Losing fat? Keep protein high: it protects muscle and keeps you full."]),
        .init(id: "carbs", emoji: "🍚", title: "Carbs and timing", summary: "Fuel for hard sessions, matched to the day.",
              points: ["Carbs refill the glycogen your muscles burn in hard or long sessions.",
                       "More on big days, less on rest days: the Fuel targets do this for you.",
                       "1 to 2 h before training, pick easy carbs with little fat and fibre: banana, toast, rice.",
                       "After training, carbs with protein speed up recovery, especially with two sessions a day."]),
        .init(id: "hydration", emoji: "💧", title: "Hydration", summary: "Small losses already cost performance.",
              points: ["Losing 2 % of body weight in sweat lowers strength and endurance.",
                       "Drink a glass with every meal and one before training.",
                       "Long or hot sessions: sip during, and add salt or an electrolyte drink after.",
                       "Pale yellow urine means you're doing fine."]),
        .init(id: "recovery", emoji: "⚡", title: "Recovery meal", summary: "What to eat after training, and when.",
              points: ["Within about 2 h after training, have 20 to 40 g of protein with carbs.",
                       "Easy options: a rice bowl with chicken or tofu, skyr with fruit and oats, a milk shake and a banana.",
                       "If your next meal is close, make it the recovery meal: no extra snack needed."]),
        .init(id: "caffeine", emoji: "☕", title: "Caffeine", summary: "A proven boost, if timed well.",
              points: ["3 mg per kg about 45 to 60 min before training improves performance for most people.",
                       "Avoid it within 8 h of bedtime: poor sleep costs more than caffeine gives.",
                       "Start lower if you're sensitive, and don't stack coffee with pre-workout drinks."]),
        .init(id: "creatine", emoji: "🧂", title: "Creatine", summary: "The best-studied supplement for strength.",
              points: ["3 to 5 g a day, any time, every day. No loading needed.",
                       "Helps strength, power and muscle gain; safe for healthy adults in studies.",
                       "Weight can go up 1 to 2 kg from water held in muscle: that's expected.",
                       "Check with a doctor first if you have kidney problems."]),
        .init(id: "sleep", emoji: "🌙", title: "Food and sleep", summary: "Recovery happens at night.",
              points: ["A slow protein before bed (skyr, cottage cheese, quark) feeds muscles overnight.",
                       "Big, fatty meals and alcohol late at night make sleep worse.",
                       "Hungry at night on a fat-loss plan? Move some protein to the evening."]),
        .init(id: "alcohol", emoji: "🍷", title: "Alcohol", summary: "What it does to training.",
              points: ["Alcohol slows muscle repair and refuelling, more after hard sessions.",
                       "Drinking after training? Eat the recovery meal first and add water between drinks.",
                       "It also disturbs deep sleep, even at small amounts."]),
        .init(id: "plate", emoji: "🍽️", title: "Build a plate", summary: "No scale needed: use your hand.",
              points: ["Palm = protein, cupped hand = carbs, fist = vegetables, thumb = fats.",
                       "Most main meals: 1 to 2 palms, 1 to 2 cupped hands, 2 fists, 1 to 2 thumbs.",
                       "Big hands, big body: your hand scales the portion for you."]),
        .init(id: "eating-out", emoji: "🍕", title: "Eating out and travel", summary: "Restaurants, takeaway and road days.",
              points: ["Start with the protein: grilled meat or fish, eggs, tofu or beans, then build the plate around it.",
                       "Pick one carb on the plate (rice, potatoes, bread or pasta) and ask for sauces on the side.",
                       "Takeaway: poke bowls, burrito bowls, sushi with sashimi, kebab plates and grilled chicken are easy wins.",
                       "Travel days: pack skyr, nuts, fruit, a sandwich or a protein bar, and refill a water bottle.",
                       "Big day of training and a restaurant at night? Make it the recovery meal: a full plate, no need to skip carbs."]),
        .init(id: "race", emoji: "🏁", title: "Race and event fuelling", summary: "Carb up, race morning, refuel.",
              points: ["Long endurance events (over about 90 min): carb up 1 to 2 days before, about 8 g per kg a day.",
                       "Race morning: carbs you know 3 h before, a small top-up 30 to 60 min before.",
                       "During long events: 30 to 60 g of carbs an hour (gels, bars, drink) after the first hour.",
                       "Fuel shows this automatically when My sports or Hyrox ready has a race date."]),
        .init(id: "vegan", emoji: "🌱", title: "Plant-based athletes", summary: "Everything you need, planned well.",
              points: ["Mix legumes, grains, tofu, tempeh and seitan over the day for complete protein.",
                       "Aim a bit higher on protein (about +10 %): plant protein is a little less digestible.",
                       "Watch B12 (take it), iron, calcium, omega-3 and vitamin D."]),
    ]

    public static let disclaimer = "General guidance for healthy adults, not medical or dietary advice. With a medical condition, an eating disorder, pregnancy or special needs, talk to a doctor or dietitian."
}
