import Foundation

/// One meal put on a day by the planner or picked by the member.
public struct PlannedMeal: Codable, Hashable, Sendable, Identifiable {
    /// Day key (yyyy-MM-dd).
    public var day: String
    /// Slot of that day's timeline ("lunch", "recovery-0"…).
    public var slot: String
    public var kind: MealKind
    public var recipeId: String
    /// People eating it.
    public var servings: Int
    /// Picked by the member: re-planning keeps it.
    public var pinned: Bool
    /// Cooked yesterday as a batch: nothing to buy.
    public var leftover: Bool

    public init(day: String, slot: String, kind: MealKind, recipeId: String, servings: Int = 1, pinned: Bool = false, leftover: Bool = false) {
        self.day = day
        self.slot = slot
        self.kind = kind
        self.recipeId = recipeId
        self.servings = max(1, servings)
        self.pinned = pinned
        self.leftover = leftover
    }

    public var id: String { "\(day)|\(slot)" }
}

/// One line of the grocery list.
public struct GroceryItem: Hashable, Sendable, Identifiable {
    public var food: Food
    /// Still to buy, after what the member has.
    public var grams: Double
    /// Needed in total for the planned meals.
    public var needed: Double
    /// "Tue · Salmon rice bowl"…
    public var meals: [String]
    /// Whole packs to buy (nil without a pack size) and what they cost (nil without a price).
    public var packs: Int?
    public var cost: Double?
    public var id: String { food.id }

    /// Bought but not needed by the plan (g), from rounding up to whole packs.
    public var spare: Double {
        guard let packs, let size = food.pack else { return 0 }
        return max(0, Double(packs) * size - grams)
    }
    public var aisle: String { food.aisle ?? "pantry" }

    /// "240 g · ≈ 2 fillets".
    public var amount: String {
        let g = grams >= 1000 ? String(format: "%.1f kg", grams / 1000) : "\(Int((grams / 5).rounded() * 5)) g"
        let n = grams / max(1, food.portion.g)
        guard n >= 0.75 else { return g }
        let count = n < 1.5 ? "1" : String(Int(n.rounded()))
        let label = food.portion.label.replacingOccurrences(of: "^1 ", with: "", options: .regularExpression)
        return "\(g) · ≈ \(count)× \(label)"
    }
}

/// How often the plan brings meals back (#1015): a few favourites on repeat, no meal twice in 3 days, or new every
/// day for 2 weeks.
public enum MealVariety: String, Codable, CaseIterable, Sendable {
    case same, varied, new

    /// Days before a recipe may come back without a penalty.
    public var gap: Int {
        switch self {
        case .same: 4
        case .varied: 3
        case .new: 14
        }
    }
}

public enum MealPlanner {
    public static let aisles: [(id: String, label: String, emoji: String)] = [
        ("fruit-veg", "Fruit & veg", "🥦"), ("meat-fish", "Meat & fish", "🥩"), ("dairy-eggs", "Dairy & eggs", "🥚"),
        ("bakery", "Bakery", "🍞"), ("pantry", "Pantry", "🥫"), ("frozen", "Frozen", "🧊"), ("drinks", "Drinks", "🥤"),
        ("snacks", "Snacks", "🍫"),
    ]

    /// Fills each day's slots with a recipe: pinned meals stay; a batch dinner gives tomorrow's lunch as leftovers;
    /// recipes using what the member has come first, and nothing repeats within 3 days (except leftovers).
    /// `slots`: which slot kinds to plan (e.g. only main meals); `daySlots` overrides it day by day (same order as
    /// `days`, from a `MealPattern`): a day with none is skipped, and a batch dinner only feeds a day that has lunch.
    /// Budget and waste (#496): `budget` is CHF per week for everyone fed (nil = no limit); `lessWaste` prefers
    /// recipes that finish packs already opened by earlier meals; `prices` overrides CHF/kg per food id.
    public struct Shopping: Equatable, Sendable {
        public var budget: Double?
        public var lessWaste: Bool
        public var prices: [String: Double]
        /// How often meals come back (#1015).
        public var variety: MealVariety

        public init(budget: Double? = nil, lessWaste: Bool = false, prices: [String: Double] = [:], variety: MealVariety = .varied) {
            self.budget = budget
            self.lessWaste = lessWaste
            self.prices = prices
            self.variety = variety
        }
    }

    public static func plan(days: [(key: String, plan: FuelPlan)], prefs: FuelPrefs, favourites: Set<String>, own: [Recipe],
                            have: Set<String>, kept: [PlannedMeal], servings: Int = 1,
                            slots kinds: Set<MealKind> = Set(MealKind.allCases), daySlots: [Set<MealKind>]? = nil,
                            shopping: Shopping = Shopping()) -> [PlannedMeal] {
        func kindsOn(_ i: Int) -> Set<MealKind> { daySlots.map { i < $0.count ? $0[i] : [] } ?? kinds }
        var out: [PlannedMeal] = []
        var recent: [String: Int] = [:] // recipe id → day index last used
        var leftoverFor: [Int: String] = [:] // day index → batch recipe for lunch
        // Grams left in packs opened by meals planned so far (perishables only).
        var open: [String: Double] = [:]
        let slotCount = days.enumerated().reduce(0) { n, d in n + d.element.plan.slots.filter { kindsOn(d.offset).contains($0.kind) }.count }
        // Budget for the days with meals (days no plan covers don't count), spread over the meals (snacks count as half).
        let mealDays = days.indices.filter { i in days[i].plan.slots.contains { kindsOn(i).contains($0.kind) } }.count
        let perMeal = shopping.budget.map { $0 * Double(mealDays) / 7 / Double(max(1, slotCount)) }
        func use(_ r: Recipe) {
            guard shopping.lessWaste, let amounts = r.amounts else { return }
            let factor = Double(servings) / Double(max(1, r.servings))
            for (key, g) in amounts {
                guard let food = FoodBook.food(key), food.perishable, let size = food.pack, size > 0 else { continue }
                var need = g * factor
                let left = open[key] ?? 0
                if left >= need { open[key] = left - need; continue }
                need -= left
                let packs = (need / size).rounded(.up)
                open[key] = packs * size - need
            }
        }
        for (i, d) in days.enumerated() {
            // Pins on a slot the day no longer has (training moved) go to the first slot of the same kind (#819).
            let ids = Set(d.plan.slots.map(\.id))
            var strays = kept.filter { $0.day == d.key && $0.pinned && !ids.contains($0.slot) }
            for slot in d.plan.slots where kindsOn(i).contains(slot.kind) {
                let exact = kept.first(where: { $0.day == d.key && $0.slot == slot.id && $0.pinned })
                let moved = exact == nil ? strays.firstIndex(where: { $0.kind == slot.kind }).map { strays.remove(at: $0) } : nil
                if var k = exact ?? moved {
                    k.slot = slot.id
                    out.append(k)
                    recent[k.recipeId] = i
                    if let r = RecipeBook.recipe(k.recipeId, own: own) { use(r) }
                    continue
                }
                if slot.kind == .lunch, let id = leftoverFor[i] {
                    out.append(PlannedMeal(day: d.key, slot: slot.id, kind: slot.kind, recipeId: id, servings: servings, leftover: true))
                    continue
                }
                var ideas = RecipeBook.ideas(for: slot, load: d.plan.load, prefs: prefs, favourites: favourites, own: own,
                                             day: d.key, count: perMeal != nil || shopping.lessWaste ? 20 : 12)
                // Same meals: the ones already planned for this kind of meal stay in the running every day.
                if shopping.variety == .same {
                    let seen = Set(ideas.map(\.id))
                    let again = Set(out.filter { $0.kind == slot.kind && !$0.leftover }.map(\.recipeId)).subtracting(seen)
                    ideas += again.sorted().compactMap { RecipeBook.recipe($0, own: own) }
                }
                let cap = perMeal.map { slot.kind == .snack || slot.kind == .bedtime || slot.kind == .pre ? $0 / 2 : $0 }
                func total(_ r: Recipe) -> Double {
                    score(r, i, recent, have, variety: shopping.variety)
                        + thrift(r, servings: servings, cap: cap, prices: shopping.prices)
                        + (shopping.lessWaste ? waste(r, servings: servings, open: open) : 0)
                }
                let best = ideas.max { total($0) < total($1) }
                guard let r = best else { continue }
                out.append(PlannedMeal(day: d.key, slot: slot.id, kind: slot.kind, recipeId: r.id, servings: servings))
                recent[r.id] = i
                use(r)
                if slot.kind == .dinner && r.tags.contains(.batch) && i + 1 < days.count && kindsOn(i + 1).contains(.lunch) {
                    leftoverFor[i + 1] = r.id
                }
            }
        }
        return out
    }

    /// CHF for `servings` of a recipe from its ingredient amounts (CHF 3 a serving without amounts or prices).
    public static func cost(_ r: Recipe, servings: Int, prices: [String: Double] = [:], foods own: [Food] = []) -> Double {
        guard let amounts = r.amounts, !amounts.isEmpty else { return 3 * Double(servings) }
        let factor = Double(servings) / Double(max(1, r.servings))
        return amounts.reduce(0.0) { sum, item in
            let price = prices[item.key] ?? FoodBook.food(item.key, own: own)?.price ?? 10
            return sum + item.value * factor / 1000 * price
        }
    }

    /// Over the meal's share of the budget costs points; cheaper earns a little.
    static func thrift(_ r: Recipe, servings: Int, cap: Double?, prices: [String: Double]) -> Double {
        guard let cap, cap > 0 else { return 0 }
        let c = cost(r, servings: servings, prices: prices)
        return c > cap ? -4 * (c - cap) / cap : 0.5 * (cap - c) / cap
    }

    /// Finishing open packs earns points; opening a pack that will mostly be left over costs some.
    static func waste(_ r: Recipe, servings: Int, open: [String: Double]) -> Double {
        guard let amounts = r.amounts else { return 0 }
        let factor = Double(servings) / Double(max(1, r.servings))
        var s = 0.0
        for (key, g) in amounts {
            guard let food = FoodBook.food(key), food.perishable, let size = food.pack, size > 0 else { continue }
            let need = g * factor
            if let left = open[key], left > 0 {
                s += 1.5 * min(1, left / max(1, need))
            } else {
                let spare = (need / size).rounded(.up) * size - need
                s -= 0.6 * spare / size
            }
        }
        return s
    }

    /// Ideas come ranked; this adds variety and pantry use. Earlier idea rank is kept by the small index penalty.
    static func score(_ r: Recipe, _ day: Int, _ recent: [String: Int], _ have: Set<String>, variety: MealVariety = .varied) -> Double {
        var s = 0.0
        if let last = recent[r.id] {
            if day - last < variety.gap { s -= 5 } else if variety == .same { s += 3 }
        }
        let keys = r.keys ?? []
        if !keys.isEmpty { s += 3 * Double(keys.filter { have.contains($0) }.count) / Double(keys.count) }
        s += Double(RecipeBook.fnv(r.id) % 100) / 1000
        return s
    }

    /// Everything the planned meals need, minus what the member has, by aisle. Leftover meals cost nothing;
    /// a pantry item without grams counts as enough.
    public static func groceries(_ meals: [PlannedMeal], recipes own: [Recipe], foods ownFoods: [Food], have: [PantryItem],
                                 prices: [String: Double] = [:], dayLabel: (String) -> String) -> [GroceryItem] {
        var need: [String: Double] = [:]
        var uses: [String: [String]] = [:]
        for m in meals where !m.leftover {
            guard let r = RecipeBook.recipe(m.recipeId, own: own), let amounts = r.amounts else { continue }
            let factor = Double(m.servings) / Double(max(1, r.servings))
            for (key, g) in amounts {
                need[key, default: 0] += g * factor
                let line = "\(dayLabel(m.day)) · \(r.name)"
                if !(uses[key] ?? []).contains(line) { uses[key, default: []].append(line) }
            }
        }
        let stock = Dictionary(have.map { ($0.foodId, $0.grams) }, uniquingKeysWith: { a, _ in a })
        return need.compactMap { key, g -> GroceryItem? in
            guard let food = FoodBook.food(key, own: ownFoods) else { return nil }
            var left = g
            if let s = stock[key] { left = s.map { max(0, g - $0) } ?? 0 }
            guard left >= 1 else { return nil }
            let packs = food.pack.map { Int((left / max(1, $0)).rounded(.up)) }
            let price = prices[key] ?? food.price
            let cost = price.map { p in (packs.map { Double($0) * (food.pack ?? 0) } ?? left) / 1000 * p }
            return GroceryItem(food: food, grams: left, needed: g, meals: uses[key] ?? [], packs: packs, cost: cost)
        }
        .sorted { a, b in
            let ia = aisles.firstIndex { $0.id == a.aisle } ?? 99, ib = aisles.firstIndex { $0.id == b.aisle } ?? 99
            return ia == ib ? a.food.name < b.food.name : ia < ib
        }
    }

    /// The week basket: what the list costs, and how much of the fresh food bought gets eaten (1 = no spare).
    public struct Basket: Equatable, Sendable {
        public var cost: Double
        public var used: Double
        public var items: Int
    }

    public static func basket(_ items: [GroceryItem]) -> Basket {
        let fresh = items.filter { $0.food.perishable && $0.packs != nil }
        let bought = fresh.reduce(0.0) { $0 + $1.grams + $1.spare }
        let needed = fresh.reduce(0.0) { $0 + $1.grams }
        return Basket(cost: items.reduce(0.0) { $0 + ($1.cost ?? 0) }, used: bought > 0 ? needed / bought : 1, items: items.count)
    }

    /// Plain text to share (Notes, Reminders, Messages).
    public static func shareText(_ items: [GroceryItem]) -> String {
        var lines = ["🛒 MonkeyWorkout groceries"]
        for a in aisles {
            let group = items.filter { $0.aisle == a.id }
            guard !group.isEmpty else { continue }
            lines.append("")
            lines.append("\(a.emoji) \(a.label)")
            lines += group.map { "☐ \($0.food.name): \($0.amount)" }
        }
        return lines.joined(separator: "\n")
    }
}

/// Which meals the planner fills on each day of a week (#558): main meals per weekday (Monday first), plus the small
/// slots (snacks, pre-workout, recovery, before bed) on days with a main meal when `extras` is on.
public struct MealPattern: Codable, Hashable, Sendable {
    public static let main: [MealKind] = [.breakfast, .lunch, .dinner]

    /// Main meals per weekday, Monday first (7 entries).
    public var week: [Set<MealKind>]
    /// Snacks, pre-workout, recovery and before bed too.
    public var extras: Bool

    public init(week: [Set<MealKind>], extras: Bool = false) {
        self.week = (0..<7).map { $0 < week.count ? week[$0].intersection(Self.main) : [] }
        self.extras = extras
    }

    public static func every(_ meals: Set<MealKind>, extras: Bool = false) -> MealPattern {
        MealPattern(week: Array(repeating: meals, count: 7), extras: extras)
    }

    public static let everyMeal = every([.breakfast, .lunch, .dinner], extras: true)
    public static let lunchDinner = every([.lunch, .dinner])
    public static let dinners = every([.dinner])
    /// Dinner on weekdays, lunch and dinner at the weekend.
    public static let weekdayDinners = MealPattern(week: Array(repeating: [.dinner], count: 5) + Array(repeating: [.lunch, .dinner], count: 2))

    /// 0 = Monday … 6 = Sunday.
    public static func index(_ day: Date, _ cal: Calendar) -> Int { (cal.component(.weekday, from: day) + 5) % 7 }

    /// Every slot kind the planner fills on a day.
    public func kinds(_ day: Date, _ cal: Calendar) -> Set<MealKind> {
        let m = week[Self.index(day, cal)]
        guard extras, !m.isEmpty else { return m }
        return m.union([.snack, .pre, .recovery, .bedtime])
    }

    /// Main meals a week holds (21 = every meal).
    public var mainPerWeek: Int { week.reduce(0) { $0 + $1.count } }
}

/// One stretch of the meal plan: a pattern for a number of days.
public struct MealBlock: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var pattern: MealPattern
    public var days: Int

    public init(id: UUID = UUID(), pattern: MealPattern, days: Int) {
        self.id = id
        self.pattern = pattern
        self.days = max(1, min(MealSchedule.maxDays, days))
    }
}

/// The meal plan's shape (#558): blocks one after the other from `start`, the whole cycle starting again every
/// `repeatWeeks` weeks (days past the blocks and before the next cycle get nothing planned).
public struct MealSchedule: Codable, Hashable, Sendable {
    /// Longest cycle and how far ahead the planner fills.
    public static let maxDays = 31

    public var start: String
    public var blocks: [MealBlock]
    /// nil = once (or back to back when `loops`).
    public var repeatWeeks: Int?
    /// Without a repeat, starts again as soon as the blocks end (inside a named plan's dates).
    public var loops: Bool

    public init(start: String, blocks: [MealBlock], repeatWeeks: Int? = nil, loops: Bool = false) {
        self.start = start
        self.blocks = blocks
        self.repeatWeeks = repeatWeeks
        self.loops = loops
    }

    /// Days the blocks cover.
    public var length: Int { blocks.reduce(0) { $0 + $1.days } }

    /// Repeat choices that fit the cycle (in weeks).
    public var repeatChoices: [Int] { [1, 2, 3, 4, 6, 8].filter { $0 * 7 >= length } }

    /// The block for a day (nil = nothing planned).
    public func block(on day: Date, _ cal: Calendar) -> MealBlock? {
        guard let first = PlanCalendar.date(start, cal),
              var offset = cal.dateComponents([.day], from: cal.startOfDay(for: first), to: cal.startOfDay(for: day)).day,
              offset >= 0 else { return nil }
        if let weeks = repeatWeeks, weeks > 0 { offset %= weeks * 7 } else if loops, length > 0 { offset %= length }
        for b in blocks {
            if offset < b.days { return b }
            offset -= b.days
        }
        return nil
    }

    public func kinds(on day: Date, _ cal: Calendar) -> Set<MealKind> { block(on: day, cal)?.pattern.kinds(day, cal) ?? [] }

    /// The days to fill from `today`: the rest of the cycle, or (repeating) the next `maxDays`.
    public func days(from today: Date, _ cal: Calendar) -> [Date] {
        let today = cal.startOfDay(for: today)
        let count: Int
        if repeatWeeks != nil {
            count = Self.maxDays
        } else {
            let first = PlanCalendar.date(start, cal).map { cal.startOfDay(for: $0) } ?? today
            let gone = max(0, cal.dateComponents([.day], from: first, to: today).day ?? 0)
            count = max(0, length - gone)
        }
        return (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    /// Main meals a week on average over the cycle, for budgets.
    public var mainPerWeek: Double {
        let span = max(length, (repeatWeeks ?? 0) * 7)
        guard span > 0 else { return 0 }
        let meals = blocks.reduce(0.0) { $0 + Double($1.pattern.mainPerWeek) * Double($1.days) / 7 }
        return meals * 7 / Double(span)
    }
}

/// When a named plan runs: from a day to a day (nil = ongoing), both included.
public struct MealPeriod: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var from: String
    public var to: String?

    public init(id: UUID = UUID(), from: String, to: String? = nil) {
        self.id = id
        self.from = from
        self.to = to
    }

    public func covers(_ key: String) -> Bool { key >= from && (to.map { key <= $0 } ?? true) }
}

/// A meal plan the member named (#558): its blocks and repeat, and the dates it runs. Inside each period the
/// cycle starts on the period's first day and starts again when it ends (or every `repeatWeeks` weeks).
public struct NamedMealPlan: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var blocks: [MealBlock]
    public var repeatWeeks: Int?
    public var periods: [MealPeriod]

    public init(id: UUID = UUID(), name: String, blocks: [MealBlock], repeatWeeks: Int? = nil, periods: [MealPeriod] = []) {
        self.id = id
        self.name = name
        self.blocks = blocks
        self.repeatWeeks = repeatWeeks
        self.periods = periods
    }

    public func cycle(from start: String) -> MealSchedule {
        MealSchedule(start: start, blocks: blocks, repeatWeeks: repeatWeeks, loops: true)
    }

    public var length: Int { blocks.reduce(0) { $0 + $1.days } }
}

/// All the member's named plans; which one runs on a day: the period covering it that started last.
public struct MealPlanBook: Codable, Hashable, Sendable {
    /// How far ahead the planner fills.
    public static let horizon = 31

    public var plans: [NamedMealPlan]

    public init(plans: [NamedMealPlan] = []) { self.plans = plans }

    public func active(on key: String) -> (plan: NamedMealPlan, period: MealPeriod)? {
        plans.flatMap { p in p.periods.filter { $0.covers(key) }.map { (plan: p, period: $0) } }
            .max { $0.period.from < $1.period.from }
    }

    public func kinds(on day: Date, _ cal: Calendar) -> Set<MealKind> {
        guard let a = active(on: PlanCalendar.key(day, cal)) else { return [] }
        return a.plan.cycle(from: a.period.from).kinds(on: day, cal)
    }

    /// The next `horizon` days from today.
    public func days(from today: Date, _ cal: Calendar) -> [Date] {
        let today = cal.startOfDay(for: today)
        return (0..<Self.horizon).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    /// Days in the coming `horizon` with meals to plan.
    public func activeDays(from today: Date, _ cal: Calendar) -> Int { days(from: today, cal).filter { !kinds(on: $0, cal).isEmpty }.count }

    /// Main meals a week on average over the coming `horizon` days, for budgets.
    public func mainPerWeek(from today: Date, _ cal: Calendar) -> Double {
        let main = Set(MealPattern.main)
        let n = days(from: today, cal).reduce(0) { $0 + kinds(on: $1, cal).intersection(main).count }
        return Double(n) * 7 / Double(Self.horizon)
    }
}
