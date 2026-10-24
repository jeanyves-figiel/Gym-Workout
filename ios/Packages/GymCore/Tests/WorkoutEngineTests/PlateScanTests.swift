import Foundation
import Testing
@testable import WorkoutEngine

// #723: a cooked plate from a photo logs its foods by weight, sized and shared.
@Suite struct PlateScanTests {
    private func sauce() -> Food {
        var f = Food(id: "scan-teriyaki-sauce", name: "Teriyaki sauce", emoji: "🥫", group: .sauce,
                     per100: Macros(protein: 1, carbs: 40, fat: 0, kcal: 170), portion: Food.Serving(g: 100, label: "1 serving"), base: .vegan)
        f.caffeine = 0
        return f
    }

    @Test func sizeAndShareScaleTheGrams() throws {
        let chicken = try #require(FoodBook.food("chicken-breast"))
        var plate = PlateScan(dish: "Chicken bowl", items: [.init(food: chicken, grams: 150), .init(food: sauce(), grams: 15, sure: false)])
        #expect(plate.items[1].on == false)
        #expect(plate.servings.map(\.foodId) == ["chicken-breast"])
        let full = plate.totals.macros.protein
        plate.items[0].size = .l
        #expect(abs(plate.totals.macros.protein - full * 1.5) < 0.01)
        plate.share = .half
        #expect(abs(plate.totals.macros.protein - full * 0.75) < 0.01)
        #expect(plate.name == "Chicken bowl")
    }

    @Test func smallAmountsStayByWeightAndCount() throws {
        let s = sauce()
        let serving = FoodServing(foodId: s.id, grams: 15, of: s)
        #expect(serving.servings == 0.15)
        #expect(serving.byWeight)
        #expect(!FoodServing(foodId: "coffee", servings: 1.5).byWeight)
        let t = FoodServing.totals([serving], own: [s])
        #expect(abs(t.macros.carbs - 6) < 0.01)
    }

    @Test func caffeineFromTheScanCounts() throws {
        var coffee = sauce()
        coffee.id = "scan-coffee"
        coffee.per100 = Macros(protein: 0.1, kcal: 1)
        coffee.caffeine = 40
        let plate = PlateScan(dish: "", items: [.init(food: coffee, grams: 200)])
        #expect(plate.totals.caffeineMg == 80)
        #expect(plate.name == "Teriyaki sauce")
    }
}
