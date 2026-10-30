import Foundation
import Testing
@testable import WorkoutEngine

// #710: coffee and cereals logged from Just ate count toward the day.
@Suite struct FoodLogTests {
    private let cal = Progression.calendar()
    private var day: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 24))! }
    private var plan: FuelPlan { Fuel.plan(FuelDayInput(day: day, weightKg: 75), prefs: FuelPrefs(), calendar: cal) }

    @Test func searchFindsCoffeeAndCereals() {
        #expect(FoodBook.search("coffee").contains { $0.id == "coffee" })
        #expect(FoodBook.search("cereals").contains { $0.id == "cornflakes" })
        #expect(FoodBook.search("eggs").contains { $0.id == "egg" || $0.id == "eggs" })
    }

    @Test func coffeeHasCaffeine() throws {
        let coffee = try #require(FoodBook.food("coffee"))
        #expect(coffee.caffeineMg(grams: coffee.portion.g) == 80)
    }

    @Test func eatenGramsFollowPortions() {
        var log = FuelDayLog()
        #expect(log.eatenGrams(plan).protein == 0 && log.eatenGrams(plan).carbs == 0)
        log.eaten = plan.portions
        let full = log.eatenGrams(plan)
        #expect(full.protein == plan.protein && full.carbs == plan.carbs)
        log.eaten.palms = plan.portions.palms / 2
        #expect(log.eatenGrams(plan).protein <= plan.protein / 2 + 1)
    }

    @Test func breakfastFoodsCountAndStack() throws {
        let breakfast = try #require(plan.slots.first { $0.kind == .breakfast })
        var log = FuelDayLog()
        log.log([FoodServing(foodId: "coffee"), FoodServing(foodId: "cornflakes", servings: 2)], at: breakfast)
        log.log([FoodServing(foodId: "milk")], at: breakfast)
        let foods = try #require(log.foods(at: breakfast.id))
        #expect(foods.items.map(\.foodId) == ["coffee", "cornflakes", "milk"])
        #expect(log.foodCaffeineMg == 80)
        #expect(log.eaten.cups >= 2)
        #expect(log.foodMacros.protein > 12)
        #expect(log.fuelled(plan) > 0)
        log.setFoods([], key: foods.key)
        #expect(log.eaten.total == 0 && log.foodCaffeineMg == 0)
    }

    @Test func smallItemsAddUpAcrossMeals() throws {
        let slots = plan.slots
        var log = FuelDayLog()
        // 3 × 250 ml milk = 25.5 g protein: one palm once the total passes half a palm.
        for s in slots.prefix(3) { log.log([FoodServing(foodId: "milk")], at: s) }
        #expect(log.eaten.palms == 1)
    }

    @Test func foodsNextToRecipeKeepTheRecipe() throws {
        let breakfast = try #require(plan.slots.first { $0.kind == .breakfast })
        let r = try #require(RecipeBook.catalog.first { $0.slots.contains(.breakfast) })
        var log = FuelDayLog()
        log.tick(breakfast, recipe: r)
        log.log([FoodServing(foodId: "coffee")], at: breakfast)
        #expect(log.ticks[breakfast.id]?.recipeId == r.id)
        #expect(log.foods(at: breakfast.id)?.key == FuelDayLog.foodKey(breakfast.id))
    }

    @Test func recipeAfterFoodsKeepsTheFoods() throws {
        // #819: foods logged first, then a recipe on the same meal: both stay.
        let breakfast = try #require(plan.slots.first { $0.kind == .breakfast })
        let r = try #require(RecipeBook.catalog.first { $0.slots.contains(.breakfast) })
        var log = FuelDayLog()
        log.log([FoodServing(foodId: "coffee")], at: breakfast)
        log.tick(breakfast, recipe: r)
        #expect(log.ticks[breakfast.id]?.recipeId == r.id)
        #expect(log.foods(at: breakfast.id)?.items.map(\.foodId) == ["coffee"])
        #expect(log.foodCaffeineMg == 80)
    }

    @Test func oldLogsDecode() throws {
        let json = #"{"glasses":2,"eaten":{"palms":1,"cups":0,"fists":0,"thumbs":0},"ticks":{"b":{"recipeId":"x","added":{"palms":1,"cups":0,"fists":0,"thumbs":0}}}}"#
        let log = try JSONDecoder().decode(FuelDayLog.self, from: Data(json.utf8))
        #expect(log.foodCaffeineMg == 0 && log.ticks["b"]?.foods == nil)
    }
}

@Suite struct FoodQuickTests {
    @Test func quickChipsExist() {
        for k in MealKind.allCases { for id in FoodBook.quick(for: k) { #expect(FoodBook.food(id) != nil, "\(id)") } }
    }

    @Test func cerealWantsMilk() {
        #expect(FoodBook.wantsMilk([FoodServing(foodId: "cornflakes")]))
        #expect(!FoodBook.wantsMilk([FoodServing(foodId: "cornflakes"), FoodServing(foodId: "milk")]))
        #expect(!FoodBook.wantsMilk([FoodServing(foodId: "coffee")]))
    }
}
