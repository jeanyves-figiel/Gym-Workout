import Foundation

/// A cooked plate read from a photo (#723): the dish, each food with the grams Monkey saw, a size per food (S–XL) and
/// how much of the plate was eaten. What it logs is plain foods by weight, so it joins Just ate's plate and usuals.
public struct PlateScan: Hashable, Sendable {
    /// Size of one food against Monkey's estimate.
    public enum Size: Double, CaseIterable, Hashable, Sendable {
        case s = 0.5, m = 1, l = 1.5, xl = 2
        public var label: String {
            switch self {
            case .s: "S"
            case .m: "M"
            case .l: "L"
            case .xl: "XL"
            }
        }
    }

    /// How much of the plate was eaten.
    public enum Share: Double, CaseIterable, Hashable, Sendable {
        case quarter = 0.25, half = 0.5, threeQuarters = 0.75, all = 1
        public var label: String {
            switch self {
            case .quarter: "¼"
            case .half: "½"
            case .threeQuarters: "¾"
            case .all: "All"
            }
        }
    }

    public struct Item: Hashable, Sendable, Identifiable {
        public var food: Food
        /// Monkey's estimate of what is on the plate.
        public var grams: Double
        public var sure: Bool
        public var size: Size
        /// Unsure foods start off; ticking puts them on.
        public var on: Bool
        public var id: String { food.id }

        public init(food: Food, grams: Double, sure: Bool = true) {
            self.food = food
            self.grams = max(1, grams)
            self.sure = sure
            size = .m
            on = sure
        }
    }

    /// "Chicken teriyaki bowl"; empty when the plate is separate foods.
    public var dish: String
    public var items: [Item]
    public var share: Share

    public init(dish: String, items: [Item], share: Share = .all) {
        self.dish = dish
        var seen: Set<String> = []
        self.items = items.filter { seen.insert($0.food.id).inserted }
        self.share = share
    }

    /// Grams of one food eaten: estimate × size × share.
    public func grams(_ item: Item) -> Double { item.grams * item.size.rawValue * share.rawValue }

    /// Name for the log and a saved dish.
    public var name: String {
        dish.isEmpty ? items.filter(\.on).prefix(3).map(\.food.name).joined(separator: ", ") : dish
    }

    /// What gets logged: the ticked foods by weight.
    public var servings: [FoodServing] {
        items.filter(\.on).map { FoodServing(foodId: $0.food.id, grams: grams($0), of: $0.food) }
    }

    /// Totals of the ticked foods, from the foods themselves (scanned ones need no catalog).
    public var totals: (macros: Macros, caffeineMg: Int) {
        var m = Macros(kcal: 0), caf = 0
        for i in items where i.on {
            m = m + i.food.macros(grams: grams(i))
            caf += i.food.caffeineMg(grams: grams(i))
        }
        return (m, caf)
    }
}

extension FoodServing {
    /// A food by weight (#723): any fraction of its portion, so 15 g of sauce stays 15 g.
    public init(foodId: String, grams: Double, of food: Food) {
        self.foodId = foodId
        servings = max(0.01, (grams / max(1, food.portion.g) * 100).rounded() / 100)
    }

    /// True when the amount is not a ½ step (logged by weight), so it shows in grams.
    public var byWeight: Bool { (servings * 2).rounded() != servings * 2 }
}
