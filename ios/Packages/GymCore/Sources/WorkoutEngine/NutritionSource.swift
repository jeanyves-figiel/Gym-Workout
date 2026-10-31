import Foundation

/// Where a food's numbers come from (#1017).
public struct FoodSource: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Matched to a USDA FoodData Central entry, values within tolerance.
        case usda
        /// Typical European label values for this kind of product (brands differ a little).
        case label
        /// Read from Open Food Facts by barcode (crowd data).
        case openFoodFacts
        /// AI guess, the member's own numbers, or anything else not checked.
        case estimate
    }

    public var kind: Kind
    /// USDA FoodData Central description, when `kind == .usda`.
    public var ref: String?

    public init(kind: Kind, ref: String? = nil) {
        self.kind = kind
        self.ref = ref
    }

    /// Short chip text: "USDA", "LABEL", "OFF", "≈".
    public var chip: String {
        switch kind {
        case .usda: "USDA"
        case .label: "LABEL"
        case .openFoodFacts: "OFF"
        case .estimate: "≈"
        }
    }

    public var title: String {
        switch kind {
        case .usda: "USDA FoodData Central"
        case .label: "Typical label values"
        case .openFoodFacts: "Open Food Facts"
        case .estimate: "Estimate"
        }
    }

    /// Checked against a reference table (not a label average or a guess).
    public var isChecked: Bool { kind == .usda }
}

/// How far a recipe's numbers can be trusted (#1017): per-ingredient sources, recomputed from grams.
public struct RecipeTrust: Hashable, Sendable {
    public struct Line: Hashable, Sendable, Identifiable {
        public var id: String { foodID }
        public var foodID: String
        public var name: String
        public var grams: Double
        public var source: FoodSource
        /// kcal this line adds per serving.
        public var kcal: Int
    }

    public enum Level: Hashable, Sendable {
        /// Every ingredient checked against USDA and totals add up.
        case checked
        /// Totals add up; some ingredients use typical label values.
        case mostlyChecked(labels: Int)
        /// Own recipe, product, or numbers not computed from ingredients.
        case estimate
    }

    public var lines: [Line]
    public var level: Level
    /// Macros recomputed from ingredient grams, per serving.
    public var computed: Macros?

    /// The recipe's stated numbers match the ones recomputed from its ingredient grams:
    /// kcal within 5% (or 10 kcal), protein, carbs and fat within 5% (or 1 g, for rounding).
    public static func addsUp(_ r: Recipe, computed m: Macros) -> Bool {
        func ok(_ a: Int, _ b: Double, floor: Double) -> Bool { abs(Double(a) - b) <= max(floor, b * 0.05) }
        return ok(r.kcal, m.kcal, floor: 10) && ok(r.protein, m.protein, floor: 1)
            && ok(r.carbs, m.carbs, floor: 1) && ok(r.fat, m.fat, floor: 1)
    }

    public static func of(_ r: Recipe, foods: [Food] = []) -> RecipeTrust {
        guard !r.isOwn, let amounts = r.amounts, !amounts.isEmpty, r.servings > 0 else {
            return RecipeTrust(lines: [], level: .estimate, computed: nil)
        }
        var lines: [Line] = []
        var total = Macros(protein: 0, carbs: 0, fat: 0, kcal: 0)
        for key in r.keys ?? Array(amounts.keys).sorted() {
            guard let g = amounts[key] else { continue }
            guard let f = FoodBook.food(key, own: foods) else { return RecipeTrust(lines: [], level: .estimate, computed: nil) }
            let m = f.macros(grams: g)
            total = Macros(protein: total.protein + m.protein, carbs: total.carbs + m.carbs, fat: total.fat + m.fat, kcal: total.kcal + m.kcal)
            lines.append(Line(foodID: f.id, name: f.name, grams: g, source: f.nutritionSource,
                              kcal: Int((m.kcal / Double(r.servings)).rounded())))
        }
        let per = total.scaled(1 / Double(r.servings))
        guard addsUp(r, computed: per) else { return RecipeTrust(lines: lines, level: .estimate, computed: per) }
        let labels = lines.filter { !$0.source.isChecked }.count
        return RecipeTrust(lines: lines, level: labels == 0 ? .checked : .mostlyChecked(labels: labels), computed: per)
    }

    public var checkedCount: Int { lines.filter(\.source.isChecked).count }
}
