import Foundation

/// Brands of meal replacements and supplements with their variants (#599, design B): picked once, saved to the
/// member's stack, then one tap in Just ate or a meal plan meal. Amounts per serving are typical label values (≈):
/// recipes change, so the member checks or scans their own label.
public struct ProductBrand: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let variants: [Supplement]
}

public enum ProductCatalog {
    private static func v(_ brand: String, _ id: String, _ name: String, _ kind: SupplementKind, _ dose: String,
                          p: Double = 0, c: Double = 0, f: Double = 0, caffeine: Int = 0, creatine: Double = 0) -> Supplement {
        Supplement(id: "\(brand)-\(id)", name: name, kind: kind, dose: dose, caffeineMg: caffeine, creatineG: creatine,
                   proteinG: p, carbsG: c, fatG: f, restDays: true)
    }

    public static let brands: [ProductBrand] = [
        ProductBrand(id: "huel", name: "Huel", variants: [
            v("huel", "black", "Huel Black Edition", .mealReplacement, "90 g powder in 500 ml water", p: 40, c: 24, f: 17),
            v("huel", "powder", "Huel Powder", .mealReplacement, "100 g powder in 500 ml water", p: 30, c: 37, f: 13),
            v("huel", "rtd", "Huel Ready-to-drink", .mealReplacement, "1 bottle (500 ml)", p: 22, c: 39, f: 17),
            v("huel", "black-rtd", "Huel Black Ready-to-drink", .mealReplacement, "1 bottle (500 ml)", p: 35, c: 22, f: 19),
            v("huel", "hot", "Huel Hot & Savoury", .hotMeal, "1 pot with boiling water", p: 24, c: 45, f: 14),
            v("huel", "protein", "Huel Complete Protein", .protein, "1 scoop (35 g)", p: 20, c: 7, f: 3),
        ]),
        ProductBrand(id: "yfood", name: "yfood", variants: [
            v("yfood", "drink", "yfood Smart Meal drink", .mealReplacement, "1 bottle (500 ml)", p: 30, c: 45, f: 22),
            v("yfood", "powder", "yfood Smart Meal powder", .mealReplacement, "1 serving (100 g) in water", p: 30, c: 33, f: 15),
        ]),
        ProductBrand(id: "saturo", name: "Saturo", variants: [
            v("saturo", "drink", "Saturo drink", .mealReplacement, "1 bottle (500 ml)", p: 25, c: 55, f: 20),
            v("saturo", "protein", "Saturo High Protein", .mealReplacement, "1 bottle (500 ml)", p: 40, c: 30, f: 18),
        ]),
        ProductBrand(id: "jimmyjoy", name: "Jimmy Joy", variants: [
            v("jimmyjoy", "plenny", "Plenny Shake", .mealReplacement, "1 serving (100 g) in water", p: 20, c: 45, f: 15),
            v("jimmyjoy", "plenny-active", "Plenny Shake Active", .mealReplacement, "1 serving (100 g) in water", p: 30, c: 38, f: 14),
            v("jimmyjoy", "plenny-drink", "Plenny Drink", .mealReplacement, "1 bottle (500 ml)", p: 20, c: 50, f: 15),
        ]),
        ProductBrand(id: "soylent", name: "Soylent", variants: [
            v("soylent", "drink", "Soylent drink", .mealReplacement, "1 bottle (414 ml)", p: 20, c: 36, f: 24),
        ]),
        ProductBrand(id: "kaex", name: "KaEx", variants: [
            v("kaex", "boost", "KaEx Boost+", .preWorkout, "1 sachet in 300 ml water", caffeine: 150),
        ]),
        ProductBrand(id: "myprotein", name: "Myprotein", variants: [
            v("myprotein", "impact", "Impact Whey", .protein, "1 scoop (25 g)", p: 21, c: 1, f: 2),
            v("myprotein", "creatine", "Creatine Monohydrate", .creatine, "1 scoop (5 g)", creatine: 5),
        ]),
        ProductBrand(id: "esn", name: "ESN", variants: [
            v("esn", "designer", "Designer Whey", .protein, "1 scoop (30 g)", p: 23, c: 2, f: 1),
            v("esn", "creatine", "Ultrapure Creatine", .creatine, "1 scoop (5 g)", creatine: 5),
        ]),
    ]

    /// Brands and variants whose names contain every word of the query.
    public static func search(_ q: String) -> [ProductBrand] {
        let words = q.lowercased().split(separator: " ")
        guard !words.isEmpty else { return brands }
        return brands.compactMap { b in
            let hit = b.variants.filter { s in words.allSatisfy { "\(b.name) \(s.name)".lowercased().contains($0) } }
            return hit.isEmpty ? nil : ProductBrand(id: b.id, name: b.name, variants: hit)
        }
    }

    /// A variant ready for the member's stack: its own id, `servings` per take, scheduled or only when picked.
    public static func mine(_ variant: Supplement, servings: Double = 1, onDemand: Bool) -> Supplement {
        var s = variant.scaled(servings)
        s.id = UUID().uuidString
        s.onDemand = onDemand ? true : nil
        return s
    }
}
