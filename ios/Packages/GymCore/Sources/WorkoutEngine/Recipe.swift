import Foundation

/// Main protein source of a recipe, for diet filters.
public enum RecipeBase: String, Codable, CaseIterable, Sendable, Identifiable {
    case vegan, vegetarian, fish, poultry, beef, pork, lamb
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .vegan: "Vegan"
        case .vegetarian: "Vegetarian"
        case .fish: "Fish & seafood"
        case .poultry: "Chicken & turkey"
        case .beef: "Beef"
        case .pork: "Pork"
        case .lamb: "Lamb"
        }
    }
}

public enum RecipeTag: String, Codable, CaseIterable, Sendable, Identifiable {
    case quick
    case highProtein = "high-protein"
    case noCook = "no-cook"
    case batch, budget
    case onTheGo = "on-the-go"
    case lowCarb = "low-carb"
    case highCarb = "high-carb"
    case sweet
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .quick: "Quick"
        case .highProtein: "High protein"
        case .noCook: "No cook"
        case .batch: "Batch cook"
        case .budget: "Budget"
        case .onTheGo: "On the go"
        case .lowCarb: "Low carb"
        case .highCarb: "High carb"
        case .sweet: "Sweet"
        }
    }

    public var emoji: String {
        switch self {
        case .quick: "⏱️"
        case .highProtein: "💪"
        case .noCook: "🥄"
        case .batch: "📦"
        case .budget: "💰"
        case .onTheGo: "🎒"
        case .lowCarb: "🥬"
        case .highCarb: "🍚"
        case .sweet: "🍯"
        }
    }
}

/// A recipe (#496): built-in catalog (`Recipes.json`) or the member's own. Macros are per serving.
public struct Recipe: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var emoji: String
    public var slots: [MealKind]
    public var minutes: Int
    public var servings: Int
    public var protein: Int
    public var carbs: Int
    public var fat: Int
    public var kcal: Int
    /// Fists of vegetables per serving.
    public var veg: Int
    public var base: RecipeBase
    public var contains: [Allergen]
    public var tags: [RecipeTag]
    public var cuisine: String
    /// Amounts for `servings` servings.
    public var ingredients: [String]
    public var steps: [String]
    /// Swap, storage or meal-prep tip.
    public var tip: String?
    /// "easy" or "medium".
    public var difficulty: String?
    public var prep: Int?
    public var cook: Int?
    /// Grams of fibre per serving.
    public var fibre: Int?
    /// Main foods used (`Foods.json` ids), for "What I have" matching.
    public var keys: [String]?
    /// Grams (ml for liquids) of each key for `servings` servings, for the grocery list.
    public var amounts: [String: Double]?
    /// The member's own recipe (editable, never in the catalog).
    public var own: Bool?

    public init(id: String = "own-\(UUID().uuidString.lowercased())", name: String, emoji: String = "🍽️", slots: [MealKind],
                minutes: Int, servings: Int = 1, protein: Int, carbs: Int, fat: Int, kcal: Int? = nil, veg: Int = 0,
                base: RecipeBase, contains: [Allergen] = [], tags: [RecipeTag] = [], cuisine: String = "",
                ingredients: [String] = [], steps: [String] = [], tip: String? = nil, keys: [String]? = nil, own: Bool? = true) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.slots = slots
        self.minutes = max(0, minutes)
        self.servings = max(1, servings)
        self.protein = max(0, protein)
        self.carbs = max(0, carbs)
        self.fat = max(0, fat)
        self.kcal = kcal ?? (4 * max(0, protein) + 4 * max(0, carbs) + 9 * max(0, fat))
        self.veg = max(0, veg)
        self.base = base
        self.contains = contains
        self.tags = tags
        self.cuisine = cuisine
        self.ingredients = ingredients
        self.steps = steps
        self.tip = tip
        self.keys = keys
        self.own = own
    }

    public var isOwn: Bool { own ?? false }

    /// Hand portions per serving.
    public var portions: Portions { Portions.from(protein: Double(protein), carbs: Double(carbs), fat: Double(fat) * 0.6, veg: veg) }

    /// Fits the member's diet and avoid list.
    public func fits(diet: FuelDiet, avoid: Set<Allergen>) -> Bool {
        if !avoid.isDisjoint(with: contains) { return false }
        switch diet {
        case .omnivore: return true
        case .pescatarian: return [.vegan, .vegetarian, .fish].contains(base)
        case .vegetarian: return [.vegan, .vegetarian].contains(base)
        case .vegan: return base == .vegan
        case .halal: return base != .pork && !contains.contains(.alcohol)
        }
    }

    public func fits(_ prefs: FuelPrefs) -> Bool { fits(diet: prefs.diet, avoid: prefs.avoid) }

    /// Ingredient line for `servings` servings: the leading amount is scaled ("120 g salmon" ×2 → "240 g salmon").
    public func ingredient(_ line: String, servings wanted: Int) -> String {
        guard wanted != servings else { return line }
        return Self.scale(line, by: Double(wanted) / Double(max(1, servings)))
    }

    static func scale(_ line: String, by factor: Double) -> String {
        let fractions: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3]
        var digits = ""
        var rest = Substring(line)
        while let c = rest.first, c.isNumber && c.isASCII || c == "." || c == "," {
            digits.append(c == "," ? "." : c)
            rest = rest.dropFirst()
        }
        var value = Double(digits) ?? 0
        if let c = rest.first, let f = fractions[c] {
            value += f
            rest = rest.dropFirst()
        }
        guard value > 0 else { return line }
        let scaled = value * factor
        let text = abs(scaled - scaled.rounded()) < 0.05 ? String(Int(scaled.rounded()))
            : scaled >= 10 ? String(Int(scaled.rounded())) : String(format: "%.1f", scaled)
        return text + rest
    }

    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !q.isEmpty else { return true }
        let hay = ([name, cuisine] + ingredients + tags.map(\.label)).joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return q.split(separator: " ").allSatisfy { hay.contains($0) }
    }
}

/// What the recipe list shows.
public struct RecipeFilter: Equatable, Sendable {
    public var slot: MealKind?
    public var query = ""
    public var tags: Set<RecipeTag> = []
    public var favouritesOnly = false
    public var ownOnly = false
    /// Off = every recipe, also ones outside the member's diet / avoid list.
    public var fitMe = true

    public init(slot: MealKind? = nil, query: String = "", tags: Set<RecipeTag> = [], favouritesOnly: Bool = false,
                ownOnly: Bool = false, fitMe: Bool = true) {
        self.slot = slot
        self.query = query
        self.tags = tags
        self.favouritesOnly = favouritesOnly
        self.ownOnly = ownOnly
        self.fitMe = fitMe
    }
}

public enum RecipeBook {
    /// Built-in catalog, loaded once.
    public static let catalog: [Recipe] = {
        guard let url = Bundle.module.url(forResource: "Recipes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Recipe].self, from: data) else { return [] }
        return list
    }()

    public static func recipe(_ id: String, own: [Recipe] = []) -> Recipe? {
        own.first { $0.id == id } ?? catalog.first { $0.id == id }
    }

    /// Recipes for a filter: own first, then the catalog, favourites on top, then by name.
    public static func list(_ f: RecipeFilter, prefs: FuelPrefs, favourites: Set<String>, own: [Recipe]) -> [Recipe] {
        let all = own + catalog
        return all.filter { r in
            (f.slot.map { r.slots.contains($0) } ?? true)
                && (!f.fitMe || r.fits(prefs))
                && f.tags.isSubset(of: Set(r.tags))
                && (!f.favouritesOnly || favourites.contains(r.id))
                && (!f.ownOnly || r.isOwn)
                && r.matches(f.query)
        }
        .sorted { a, b in
            let fa = favourites.contains(a.id), fb = favourites.contains(b.id)
            if fa != fb { return fa }
            if a.isOwn != b.isOwn { return a.isOwn }
            return a.name < b.name
        }
    }

    /// Ideas for one meal of the day: right slot, fits the member, protein close to the slot's target,
    /// carb-rich on big days and lighter on rest days, favourites up; rotates daily so ideas change.
    public static func ideas(for slot: FuelSlot, load: FuelLoad, prefs: FuelPrefs, favourites: Set<String>, own: [Recipe],
                             day: String, count: Int = 3) -> [Recipe] {
        let kind = slot.recipeKind
        let pool = (own + catalog).filter { $0.slots.contains(kind) && $0.fits(prefs) }
        func score(_ r: Recipe) -> Double {
            var s = -abs(Double(r.protein - slot.protein)) / 10
            if favourites.contains(r.id) { s += 2 }
            if r.isOwn { s += 1 }
            if load == .big && r.tags.contains(.highCarb) { s += 1.5 }
            if load == .rest && r.tags.contains(.lowCarb) { s += 1 }
            if load == .rest && r.tags.contains(.highCarb) { s -= 1 }
            if kind == .pre && (r.fat > 12 || r.minutes > 15) { s -= 2 }
            s += Double(fnv(r.id + day) % 1000) / 400 // daily rotation, stable within the day
            return s
        }
        return Array(pool.map { ($0, score($0)) }.sorted { $0.1 > $1.1 }.prefix(count).map(\.0))
    }

    /// Stable hash (Swift's `hashValue` changes every launch).
    static func fnv(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }
}
