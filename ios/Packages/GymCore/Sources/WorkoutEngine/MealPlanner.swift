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
    public var id: String { food.id }
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

public enum MealPlanner {
    public static let aisles: [(id: String, label: String, emoji: String)] = [
        ("fruit-veg", "Fruit & veg", "🥦"), ("meat-fish", "Meat & fish", "🥩"), ("dairy-eggs", "Dairy & eggs", "🥚"),
        ("bakery", "Bakery", "🍞"), ("pantry", "Pantry", "🥫"), ("frozen", "Frozen", "🧊"), ("drinks", "Drinks", "🥤"),
        ("snacks", "Snacks", "🍫"),
    ]

    /// Fills each day's slots with a recipe: pinned meals stay; a batch dinner gives tomorrow's lunch as leftovers;
    /// recipes using what the member has come first, and nothing repeats within 3 days (except leftovers).
    /// `slots`: which slot kinds to plan (e.g. only main meals).
    public static func plan(days: [(key: String, plan: FuelPlan)], prefs: FuelPrefs, favourites: Set<String>, own: [Recipe],
                            have: Set<String>, kept: [PlannedMeal], servings: Int = 1,
                            slots kinds: Set<MealKind> = Set(MealKind.allCases)) -> [PlannedMeal] {
        var out: [PlannedMeal] = []
        var recent: [String: Int] = [:] // recipe id → day index last used
        var leftoverFor: [Int: String] = [:] // day index → batch recipe for lunch
        for (i, d) in days.enumerated() {
            for slot in d.plan.slots where kinds.contains(slot.kind) {
                if let k = kept.first(where: { $0.day == d.key && $0.slot == slot.id && $0.pinned }) {
                    out.append(k)
                    recent[k.recipeId] = i
                    continue
                }
                if slot.kind == .lunch, let id = leftoverFor[i] {
                    out.append(PlannedMeal(day: d.key, slot: slot.id, kind: slot.kind, recipeId: id, servings: servings, leftover: true))
                    continue
                }
                let ideas = RecipeBook.ideas(for: slot, load: d.plan.load, prefs: prefs, favourites: favourites, own: own,
                                             day: d.key, count: 12)
                let best = ideas.max { a, b in score(a, i, recent, have) < score(b, i, recent, have) }
                guard let r = best else { continue }
                out.append(PlannedMeal(day: d.key, slot: slot.id, kind: slot.kind, recipeId: r.id, servings: servings))
                recent[r.id] = i
                if slot.kind == .dinner && r.tags.contains(.batch) && i + 1 < days.count { leftoverFor[i + 1] = r.id }
            }
        }
        return out
    }

    /// Ideas come ranked; this adds variety and pantry use. Earlier idea rank is kept by the small index penalty.
    static func score(_ r: Recipe, _ day: Int, _ recent: [String: Int], _ have: Set<String>) -> Double {
        var s = 0.0
        if let last = recent[r.id], day - last < 3 { s -= 5 }
        let keys = r.keys ?? []
        if !keys.isEmpty { s += 3 * Double(keys.filter { have.contains($0) }.count) / Double(keys.count) }
        s += Double(RecipeBook.fnv(r.id) % 100) / 1000
        return s
    }

    /// Everything the planned meals need, minus what the member has, by aisle. Leftover meals cost nothing;
    /// a pantry item without grams counts as enough.
    public static func groceries(_ meals: [PlannedMeal], recipes own: [Recipe], foods ownFoods: [Food], have: [PantryItem],
                                 dayLabel: (String) -> String) -> [GroceryItem] {
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
            return GroceryItem(food: food, grams: left, needed: g, meals: uses[key] ?? [])
        }
        .sorted { a, b in
            let ia = aisles.firstIndex { $0.id == a.aisle } ?? 99, ib = aisles.firstIndex { $0.id == b.aisle } ?? 99
            return ia == ib ? a.food.name < b.food.name : ia < ib
        }
    }

    /// Plain text to share (Notes, Reminders, Messages).
    public static func shareText(_ items: [GroceryItem]) -> String {
        var lines = ["🛒 MonkeyFit groceries"]
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
