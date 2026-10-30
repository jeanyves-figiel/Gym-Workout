import Foundation

// "What can I eat?" (#869, epic #865, designs A + B from `ai-epic/d1.png`): Monkey suggests three meals made only of
// the foods in What I have, aimed at what is left of the day. The server sends foods and grams; the numbers are added
// up here from the app's own food list.

/// One meal idea: pantry foods with grams, minutes and short steps.
public struct MealIdea: Codable, Hashable, Sendable, Identifiable {
    public struct Item: Codable, Hashable, Sendable {
        public var foodId: String
        public var grams: Double

        public init(foodId: String, grams: Double) {
            self.foodId = foodId
            self.grams = grams
        }
    }

    public var name: String
    public var minutes: Int
    public var items: [Item]
    public var steps: [String]
    public var id: String { name }

    public init(name: String, minutes: Int, items: [Item], steps: [String] = []) {
        self.name = name
        self.minutes = minutes
        self.items = items
        self.steps = steps
    }

    /// Items whose food is known (catalog or the member's own), with the food.
    public func foods(own: [Food] = []) -> [(food: Food, grams: Double)] {
        items.compactMap { i in FoodBook.food(i.foodId, own: own).map { (food: $0, grams: i.grams) } }
    }

    public func totals(own: [Food] = []) -> Macros {
        foods(own: own).reduce(Macros(kcal: 0)) { $0 + $1.food.macros(grams: $1.grams) }
    }

    /// What gets logged: each food by weight.
    public func servings(own: [Food] = []) -> [FoodServing] {
        foods(own: own).map { FoodServing(foodId: $0.food.id, grams: $0.grams, of: $0.food) }
    }

    /// The meal word the server takes: pre-workout, recovery and before-bed meals ask for a snack.
    public static func meal(_ kind: MealKind) -> String {
        switch kind {
        case .breakfast, .lunch, .dinner, .snack: kind.rawValue
        case .recovery: "dinner"
        case .pre, .bedtime: "snack"
        }
    }

    /// Protein and carb grams still to eat today (never below 0).
    public static func left(_ plan: FuelPlan, log: FuelDayLog) -> (protein: Int, carbs: Int) {
        let eaten = log.eatenGrams(plan)
        return (max(0, plan.protein - eaten.protein), max(0, plan.carbs - eaten.carbs))
    }
}
