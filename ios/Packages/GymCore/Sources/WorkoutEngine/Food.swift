import Foundation

// "What I have" (#496): the member types, picks or scans the food they have; the app builds the meal that gets
// closest to their targets from it, and finds recipes they can (almost) make.

public enum FoodGroup: String, Codable, CaseIterable, Sendable, Identifiable {
    case protein, dairy, grain, legume, veg, fruit, fat, sauce, snack, drink
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .protein: "Meat, fish & eggs"
        case .dairy: "Dairy"
        case .grain: "Grains & bread"
        case .legume: "Beans & tofu"
        case .veg: "Vegetables"
        case .fruit: "Fruit"
        case .fat: "Nuts, seeds & oils"
        case .sauce: "Sauces & spreads"
        case .snack: "Snacks & bars"
        case .drink: "Drinks"
        }
    }

    public var emoji: String {
        switch self {
        case .protein: "🍗"
        case .dairy: "🧀"
        case .grain: "🍞"
        case .legume: "🫘"
        case .veg: "🥦"
        case .fruit: "🍎"
        case .fat: "🥜"
        case .sauce: "🫙"
        case .snack: "🍫"
        case .drink: "🥛"
        }
    }
}

public struct Macros: Codable, Hashable, Sendable {
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var kcal: Double

    public init(protein: Double = 0, carbs: Double = 0, fat: Double = 0, kcal: Double? = nil) {
        self.protein = max(0, protein)
        self.carbs = max(0, carbs)
        self.fat = max(0, fat)
        self.kcal = kcal ?? (4 * max(0, protein) + 4 * max(0, carbs) + 9 * max(0, fat))
    }

    public static func + (a: Macros, b: Macros) -> Macros {
        Macros(protein: a.protein + b.protein, carbs: a.carbs + b.carbs, fat: a.fat + b.fat, kcal: a.kcal + b.kcal)
    }

    public static func - (a: Macros, b: Macros) -> Macros {
        Macros(protein: a.protein - b.protein, carbs: a.carbs - b.carbs, fat: a.fat - b.fat, kcal: max(0, a.kcal - b.kcal))
    }

    public func scaled(_ f: Double) -> Macros { Macros(protein: protein * f, carbs: carbs * f, fat: fat * f, kcal: kcal * f) }
}

extension FuelDiet {
    /// A food or recipe with this main source and these allergens suits the diet and avoid list.
    public func allows(base: RecipeBase, contains: [Allergen], avoid: Set<Allergen>) -> Bool {
        if !avoid.isDisjoint(with: contains) { return false }
        switch self {
        case .omnivore: return true
        case .pescatarian: return [.vegan, .vegetarian, .fish].contains(base)
        case .vegetarian: return [.vegan, .vegetarian].contains(base)
        case .vegan: return base == .vegan
        case .halal: return base != .pork && !contains.contains(.alcohol)
        }
    }
}

public struct Food: Codable, Hashable, Sendable, Identifiable {
    public struct Serving: Codable, Hashable, Sendable {
        public var g: Double
        public var label: String
        public init(g: Double, label: String) {
            self.g = g
            self.label = label
        }
    }

    public var id: String
    public var name: String
    public var emoji: String
    public var group: FoodGroup
    public var per100: Macros
    public var portion: Serving
    public var base: RecipeBase
    public var contains: [Allergen]
    public var aliases: [String]
    /// Shop aisle for the grocery list: meat-fish, dairy-eggs, fruit-veg, bakery, pantry, frozen, drinks, snacks.
    public var aisle: String?
    /// Scanned barcode (Open Food Facts), kept on the device.
    public var barcode: String?
    /// Swiss supermarket average, CHF per kg (per litre for drinks and liquids), for the meal plan budget (#496).
    public var price: Double?
    /// Usual pack size in g (ml), so the grocery list buys whole packs and the planner can use them up.
    public var pack: Double?
    /// Caffeine, mg per 100 g (ml): coffee, tea, cola, energy drinks (#710), so a logged mug joins the caffeine meter.
    public var caffeine: Double?

    /// Caffeine in this many grams, mg.
    public func caffeineMg(grams: Double) -> Int { Int(((caffeine ?? 0) * grams / 100).rounded()) }

    /// Goes off within a week once bought or opened: what "less waste" plans around.
    public var perishable: Bool { ["fruit-veg", "meat-fish", "dairy-eggs", "bakery"].contains(aisle ?? "pantry") }

    public init(id: String, name: String, emoji: String, group: FoodGroup, per100: Macros, portion: Serving, base: RecipeBase,
                contains: [Allergen] = [], aliases: [String] = [], barcode: String? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.group = group
        self.per100 = per100
        self.portion = portion
        self.base = base
        self.contains = contains
        self.aliases = aliases
        self.barcode = barcode
    }

    public func macros(grams: Double) -> Macros { per100.scaled(grams / 100) }

    public func fits(_ prefs: FuelPrefs) -> Bool { prefs.diet.allows(base: base, contains: contains, avoid: prefs.avoid) }

    /// Mostly protein (per kcal), mostly carbs, etc.: what role it plays on a plate.
    public var role: Role {
        let p = per100.protein * 4, c = per100.carbs * 4, f = per100.fat * 9
        let total = max(1, p + c + f)
        if group == .veg { return .veg }
        if group == .sauce || (group == .drink && per100.protein < 3) { return .extra }
        if p / total >= 0.35 && per100.protein >= 7 { return .protein }
        if f / total >= 0.6 { return .fat }
        if c / total >= 0.5 { return .carbs }
        return .extra
    }

    public enum Role: String, Sendable { case protein, carbs, veg, fat, extra }

    /// Product from Open Food Facts (`/api/v2/product/<code>.json`), per 100 g (ml for drinks). Nil when the product is
    /// missing or has no values at all; a missing protein or fat (common on beer and soft drinks) counts as 0 (#573).
    /// Drinks (beverage categories) stay drinks, alcohol is flagged.
    public static func openFoodFacts(_ data: Data, barcode: String) -> Food? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let product = root["product"] as? [String: Any] else { return nil }
        let n = product["nutriments"] as? [String: Any] ?? [:]
        func value(_ key: String) -> Double? {
            if let d = n[key] as? Double { return d }
            if let i = n[key] as? Int { return Double(i) }
            if let s = n[key] as? String { return Double(s) }
            return nil
        }
        let p = value("proteins_100g"), c = value("carbohydrates_100g"), f = value("fat_100g"), kcal = value("energy-kcal_100g")
        guard p != nil || c != nil || f != nil || kcal != nil else { return nil }
        let categories = product["categories_tags"] as? [String] ?? []
        let alcoholic = categories.contains { ["en:alcoholic-beverages", "en:beers", "en:wines", "en:ciders", "en:spirits"].contains($0) }
            || (value("alcohol_100g") ?? value("alcohol") ?? 0) >= 0.5
        let drink = alcoholic || categories.contains("en:beverages")
        var name = (product["product_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Scanned product"
        if let brand = (product["brands"] as? String)?.split(separator: ",").first.map({ $0.trimmingCharacters(in: .whitespaces) }),
           !brand.isEmpty, !FoodBook.fold(name).contains(FoodBook.fold(brand)) {
            name = "\(brand) \(name)"
        }
        let tags = (product["allergens_tags"] as? [String] ?? []).joined(separator: " ")
        var contains: [Allergen] = []
        let map: [(String, Allergen)] = [("milk", .lactose), ("gluten", .gluten), ("nuts", .nuts), ("peanuts", .peanuts), ("eggs", .eggs),
                                         ("soybeans", .soy), ("fish", .fish), ("crustaceans", .shellfish), ("molluscs", .shellfish),
                                         ("sesame", .sesame)]
        for (tag, a) in map where tags.contains(tag) && !contains.contains(a) { contains.append(a) }
        if alcoholic { contains.append(.alcohol) }
        let analysis = (product["ingredients_analysis_tags"] as? [String] ?? [])
        let base: RecipeBase = analysis.contains("en:vegan") || (drink && !contains.contains(.lactose)) ? .vegan
            : analysis.contains("en:vegetarian") || drink ? .vegetarian
            : contains.contains(.fish) || contains.contains(.shellfish) ? .fish : .poultry
        let qty = (product["serving_quantity"] as? Double) ?? (product["serving_quantity"] as? String).flatMap(Double.init) ?? (drink ? 330 : 100)
        let emoji = !drink ? "🏷️" : categories.contains("en:beers") ? "🍺" : categories.contains("en:wines") ? "🍷"
            : alcoholic ? "🥃" : "🥤"
        let food = Food(id: "bar-\(barcode)", name: String(name.prefix(40)), emoji: emoji, group: drink ? .drink : .snack,
                        per100: Macros(protein: p ?? 0, carbs: c ?? 0, fat: f ?? 0, kcal: kcal),
                        portion: Serving(g: max(10, min(1000, qty)), label: drink ? "1 bottle" : "1 serving"), base: base, contains: contains,
                        aliases: [], barcode: barcode)
        var out = food
        if drink {
            out.aisle = "drinks"
            return out
        }
        out.group = switch food.role {
        case .protein: .protein
        case .carbs: .grain
        case .fat: .fat
        case .veg: .veg
        case .extra: .snack
        }
        return out
    }
}

public enum FoodBook {
    public static let catalog: [Food] = {
        // A content pack from the server (#583) when one was fetched for this build, else the bundled file.
        ContentPacks.shared.load("foods", bundled: Bundle.module.url(forResource: "Foods", withExtension: "json"),
                                 decode: { try JSONDecoder().decode([Food].self, from: $0) }, valid: { !$0.isEmpty }) ?? []
    }()

    public static func food(_ id: String, own: [Food] = []) -> Food? {
        own.first { $0.id == id } ?? catalog.first { $0.id == id }
    }

    /// "Appenzeller Bier" → "appenzeller-bier": an id for a food the photo scan found that isn't on the list.
    public static func slug(_ name: String) -> String {
        let s = fold(name).map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }.reduce(into: "") { $0.append($1) }
        let out = String(s.split(separator: "-").joined(separator: "-").prefix(34))
        return out.isEmpty ? "food" : out
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    /// Foods named in free text: typed ("eggs, rice and some spinach"), or read by the camera from a receipt or label.
    /// Longest names first so "sweet potato" wins over "potato".
    /// A label with an alcohol strength ("5.2% vol", "alc. 4,8 %") is a drink's: only drinks match on it (#573: an
    /// Appenzeller beer label read as cheese).
    public static func find(in text: String, own: [Food] = []) -> [Food] {
        let words = " " + fold(text).map { $0.isLetter || $0.isNumber ? $0 : " " }.reduce(into: "") { $0.append($1) } + " "
        var hits: [(Food, Int)] = []
        var used = words
        let drinkLabel = isDrinkLabel(text)
        let names = (own + catalog).filter { !drinkLabel || $0.group == .drink }
            .flatMap { f in ([f.name] + f.aliases).map { (f, fold($0)) } }
            .filter { $0.1.count >= 3 }
            .sorted { $0.1.count > $1.1.count }
        for (f, name) in names where !hits.contains(where: { $0.0.id == f.id }) {
            let clean = name.map { $0.isLetter || $0.isNumber ? $0 : " " }.reduce(into: "") { $0.append($1) }
            for variant in [clean, clean + "s", clean + "es"] {
                if let r = used.range(of: " \(variant) ") {
                    hits.append((f, used.distance(from: used.startIndex, to: r.lowerBound)))
                    used.replaceSubrange(r, with: " " + String(repeating: "_", count: variant.count) + " ")
                    break
                }
            }
        }
        return hits.sorted { $0.1 < $1.1 }.map(\.0)
    }

    static func isDrinkLabel(_ text: String) -> Bool {
        let t = fold(text)
        return t.range(of: #"\d+([.,]\d+)?\s*%\s*(vol|alc|abv)"#, options: .regularExpression) != nil
            || t.range(of: #"\b(alc|alk)\.?\s*\d+([.,]\d+)?\s*%"#, options: .regularExpression) != nil
    }

    /// Search box: name or alias contains every word.
    /// "Or it's…" (#573): the closest other foods for a scan item Monkey wasn't sure of. Name words first, then the same
    /// group by values per 100 g.
    public static func guesses(for food: Food, own: [Food] = [], count: Int = 3) -> [Food] {
        func words(_ s: String) -> Set<String> { Set(fold(s).split { !$0.isLetter }.filter { $0.count >= 4 }.map(String.init)) }
        let mine = words(food.name)
        let named = (own + catalog).filter { f in
            guard f.id != food.id else { return false }
            let theirs = words(([f.name] + f.aliases).joined(separator: " "))
            return mine.contains { theirs.contains($0) || theirs.contains($0 + "s") }
        }
        .sorted { ($0.group == food.group ? 0 : 1) < ($1.group == food.group ? 0 : 1) }
        func gap(_ f: Food) -> Double {
            abs(f.per100.protein - food.per100.protein) + abs(f.per100.carbs - food.per100.carbs)
                + abs(f.per100.fat - food.per100.fat) + abs(f.per100.kcal - food.per100.kcal) / 10
        }
        let near = catalog.filter { $0.group == food.group && $0.id != food.id }.sorted { gap($0) < gap($1) }
        var out: [Food] = []
        for f in named + near where !out.contains(where: { $0.id == f.id }) && out.count < count { out.append(f) }
        return out
    }

    /// Plurals match the singular ("cereals" finds cornflakes, "eggs" finds egg) (#710).
    public static func search(_ query: String, own: [Food] = []) -> [Food] {
        let q = fold(query).split(separator: " ").map(String.init)
        guard !q.isEmpty else { return [] }
        func stems(_ w: String) -> [String] {
            var out = [w]
            if w.count > 3, w.hasSuffix("es") { out.append(String(w.dropLast(2))) }
            if w.count > 3, w.hasSuffix("s") { out.append(String(w.dropLast())) }
            return out
        }
        return (own + catalog).filter { f in
            let hay = fold(([f.name] + f.aliases).joined(separator: " "))
            return q.allSatisfy { stems($0).contains { hay.contains($0) } }
        }
    }
}

/// One food the member has. `grams` nil = enough for a meal.
public struct PantryItem: Codable, Hashable, Sendable, Identifiable {
    public var foodId: String
    public var grams: Double?
    public var added: Date

    public init(foodId: String, grams: Double? = nil, added: Date = Date()) {
        self.foodId = foodId
        self.grams = grams
        self.added = added
    }

    public var id: String { foodId }
}

/// A meal built from what the member has.
public struct PantryMeal: Hashable, Sendable {
    public struct Item: Hashable, Sendable, Identifiable {
        public var food: Food
        public var grams: Double
        public var id: String { food.id }
        public var macros: Macros { food.macros(grams: grams) }
    }

    public var items: [Item]
    public var target: Macros
    public var totals: Macros
    /// 0…1, how close to the target (1 = spot on).
    public var closeness: Double
    /// What's still missing and a food that would fill it.
    public var gaps: [Gap]

    public struct Gap: Hashable, Sendable {
        public var what: String
        public var grams: Int
        public var add: Food?
    }
}

/// A recipe and how much of it the member has.
public struct PantryRecipe: Hashable, Sendable, Identifiable {
    public var recipe: Recipe
    public var have: [String]
    public var missing: [String]
    public var id: String { recipe.id }
    public var coverage: Double { Double(have.count) / Double(max(1, have.count + missing.count)) }
}

public enum Pantry {
    /// Builds the meal from `foods` closest to `target` (protein first, then carbs, then fat): one or two protein foods,
    /// a carb, veg and a fat, amounts tuned in 5 g steps up to what the member has (or 3 portions).
    public static func meal(target: Macros, have: [PantryItem], own: [Food] = [], prefs: FuelPrefs) -> PantryMeal {
        let foods: [(Food, Double?)] = have.compactMap { i in FoodBook.food(i.foodId, own: own).map { ($0, i.grams) } }
            .filter { $0.0.fits(prefs) }
        func pick(_ role: Food.Role, _ n: Int, by key: (Food) -> Double) -> [(Food, Double?)] {
            Array(foods.filter { $0.0.role == role }.sorted { key($0.0) > key($1.0) }.prefix(n))
        }
        let proteins = pick(.protein, 2) { $0.per100.protein / max(1, $0.per100.kcal) }
        let carbs = pick(.carbs, 2) { $0.per100.carbs }
        let veg = pick(.veg, 2) { $0.per100.kcal }
        let fats = pick(.fat, 1) { $0.per100.fat }
        var chosen = proteins + carbs + fats
        // Nothing protein-led at home: dairy or legumes with some protein can carry it.
        if proteins.isEmpty {
            chosen += Array(foods.filter { $0.0.role == .extra && $0.0.per100.protein >= 5 }.sorted { $0.0.per100.protein > $1.0.per100.protein }.prefix(1))
        }
        let caps = chosen.map { min($0.1 ?? .infinity, $0.0.portion.g * 3) }
        var grams = chosen.indices.map { min(chosen[$0].0.portion.g * 0.5, caps[$0]) }
        // Veg is fixed: one fist (~100 g) each, it barely moves the macros.
        let vegItems = veg.map { PantryMeal.Item(food: $0.0, grams: min($0.1 ?? 100, 100)) }
        let vegMacros = vegItems.reduce(Macros()) { $0 + $1.macros }

        func total(_ g: [Double]) -> Macros {
            zip(chosen, g).reduce(vegMacros) { $0 + $1.0.0.macros(grams: $1.1) }
        }
        func error(_ m: Macros) -> Double {
            let p = (m.protein - target.protein) / max(target.protein, 10)
            let c = (m.carbs - target.carbs) / max(target.carbs, 10)
            let f = (m.fat - target.fat) / max(target.fat, 5)
            return 3 * p * p + c * c + 0.7 * f * f
        }
        var best = error(total(grams))
        var improved = true
        var rounds = 0
        while improved && rounds < 400 {
            improved = false
            rounds += 1
            for i in grams.indices {
                for step in [25.0, 5.0, -5.0, -25.0] {
                    let g = grams[i] + step
                    guard g >= 0, g <= caps[i] else { continue }
                    var trial = grams
                    trial[i] = g
                    let e = error(total(trial))
                    if e < best - 1e-9 {
                        best = e
                        grams = trial
                        improved = true
                    }
                }
            }
        }
        var items = zip(chosen, grams).compactMap { c, g -> PantryMeal.Item? in
            let r = (g / 5).rounded() * 5
            return r >= 10 ? PantryMeal.Item(food: c.0, grams: r) : nil
        }
        items += vegItems
        let totals = items.reduce(Macros()) { $0 + $1.macros }
        func near(_ a: Double, _ t: Double) -> Double { t <= 0 ? 1 : min(a, t) / max(a, t) }
        let closeness = (3 * near(totals.protein, target.protein) + near(totals.carbs, target.carbs) + near(totals.fat, target.fat)) / 5

        var gaps: [PantryMeal.Gap] = []
        let haveIds = Set(have.map(\.foodId))
        func filler(_ role: Food.Role, staples: [String]) -> Food? {
            staples.compactMap { FoodBook.food($0) }.first { $0.fits(prefs) && $0.role == role && !haveIds.contains($0.id) }
        }
        let pShort = target.protein - totals.protein
        if pShort >= max(8, target.protein * 0.15) {
            gaps.append(.init(what: "protein", grams: Int(pShort.rounded()),
                              add: filler(.protein, staples: ["greek-yogurt", "skyr", "egg", "chicken-breast", "tofu", "canned-tuna", "cottage-cheese", "lentils", "protein-powder"])))
        }
        let cShort = target.carbs - totals.carbs
        if cShort >= max(15, target.carbs * 0.25) {
            gaps.append(.init(what: "carbs", grams: Int(cShort.rounded()),
                              add: filler(.carbs, staples: ["rice", "oats", "banana", "potato", "pasta", "bread", "wholegrain-bread"])))
        }
        return PantryMeal(items: items, target: target, totals: totals, closeness: closeness, gaps: gaps)
    }

    /// Recipes the member can make (or nearly: at most `missing` foods short), most complete first, then the ones
    /// whose protein is closest to `protein`.
    public static func recipes(have: Set<String>, prefs: FuelPrefs, own: [Recipe], slot: MealKind? = nil, protein: Int? = nil,
                               missing allowed: Int = 2) -> [PantryRecipe] {
        (own + RecipeBook.catalog).compactMap { r -> PantryRecipe? in
            guard let keys = r.keys, !keys.isEmpty, r.fits(prefs), slot.map({ r.slots.contains($0) }) ?? true else { return nil }
            let got = keys.filter { have.contains($0) }
            let miss = keys.filter { !have.contains($0) }
            guard !got.isEmpty, miss.count <= allowed else { return nil }
            return PantryRecipe(recipe: r, have: got, missing: miss)
        }
        .sorted { a, b in
            if a.missing.count != b.missing.count { return a.missing.count < b.missing.count }
            if let protein { return abs(a.recipe.protein - protein) < abs(b.recipe.protein - protein) }
            return a.coverage > b.coverage
        }
    }
}
