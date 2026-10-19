import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct FuelTests {
    private let cal = Progression.calendar()
    private var day: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 19))! }

    private func gym(_ minutes: Int, hour: Int = 18) -> FuelActivity {
        FuelActivity(id: "g\(minutes)", kind: .gym, title: "Gym", start: cal.date(byAdding: .hour, value: hour, to: day)!, minutes: minutes, done: false)
    }

    @Test func loadFollowsTraining() {
        #expect(Fuel.load([], weightKg: 75) == .rest)
        #expect(Fuel.load([gym(60)], weightKg: 75) == .normal)
        #expect(Fuel.load([gym(100)], weightKg: 75) == .big)
    }

    @Test func bigDayNeedsMoreCarbsAndWater() {
        let prefs = FuelPrefs(goal: .maintain, meals: 4)
        let rest = Fuel.plan(FuelDayInput(day: day, weightKg: 75), prefs: prefs, calendar: cal)
        let big = Fuel.plan(FuelDayInput(day: day, weightKg: 75, activities: [gym(100)]), prefs: prefs, calendar: cal)
        #expect(big.carbs > rest.carbs)
        #expect(big.glasses > rest.glasses)
        #expect(big.protein >= rest.protein)
        #expect(!rest.estimated)
        #expect(big.slots.contains { $0.afterTraining || $0.kind == .recovery })
        #expect(big.slots.map(\.minute) == big.slots.map(\.minute).sorted())
    }

    @Test func proteinFollowsGoal() {
        let input = FuelDayInput(day: day, weightKg: 80)
        let lose = Fuel.plan(input, prefs: FuelPrefs(goal: .lose), calendar: cal)
        let keep = Fuel.plan(input, prefs: FuelPrefs(goal: .maintain), calendar: cal)
        #expect(lose.protein > keep.protein)
        #expect(Fuel.plan(FuelDayInput(day: day), prefs: FuelPrefs(), calendar: cal).estimated)
    }

    @Test func eventTwoDaysOutCarbLoads() {
        let input = FuelDayInput(day: day, weightKg: 70, event: FuelEvent(sport: .run, name: "Marathon", days: 1))
        let normal = Fuel.plan(FuelDayInput(day: day, weightKg: 70), prefs: FuelPrefs(goal: .perform), calendar: cal)
        let loading = Fuel.plan(input, prefs: FuelPrefs(goal: .perform), calendar: cal)
        #expect(loading.carbs > normal.carbs)
        #expect(!(loading.event?.pointers ?? []).isEmpty)
    }

    @Test func logTicksAndXP() {
        let plan = Fuel.plan(FuelDayInput(day: day, weightKg: 75, activities: [gym(60)]), prefs: FuelPrefs(), calendar: cal)
        var log = FuelDayLog()
        let slot = plan.slots[0]
        log.tick(slot)
        #expect(log.ticks[slot.id] != nil)
        #expect(log.eaten == slot.portions)
        log.untick(slot.id)
        #expect(log.eaten.total == 0)
        log.glasses = plan.glasses
        #expect(log.waterHit(plan))
        let week = [FuelWeekDay(day: day, plan: plan, log: log)]
        #expect(FuelWeek.xp(week) == FuelWeek.waterXP)
    }
}

@Suite struct RecipeCatalogTests {
    @Test func catalogsDecodeAndLink() {
        #expect(RecipeBook.catalog.count >= 190)
        #expect(FoodBook.catalog.count >= 200)
        #expect(Set(RecipeBook.catalog.map(\.id)).count == RecipeBook.catalog.count)
        #expect(Set(FoodBook.catalog.map(\.id)).count == FoodBook.catalog.count)
        for r in RecipeBook.catalog {
            #expect(r.steps.count >= 4, "\(r.id)")
            for k in r.keys ?? [] { #expect(FoodBook.food(k) != nil, "\(r.id) → \(k)") }
            for k in (r.amounts ?? [:]).keys { #expect((r.keys ?? []).contains(k), "\(r.id) amount \(k)") }
        }
        for kind in MealKind.allCases { #expect(RecipeBook.catalog.contains { $0.slots.contains(kind) }, "\(kind)") }
    }

    @Test func dietAndAllergensFilter() {
        let vegan = FuelPrefs(diet: .vegan, avoid: [.nuts])
        let list = RecipeBook.list(RecipeFilter(), prefs: vegan, favourites: [], own: [])
        #expect(!list.isEmpty)
        #expect(list.allSatisfy { $0.base == .vegan && !$0.contains.contains(.nuts) })
    }

    @Test func ingredientScales() {
        let r = Recipe(name: "Test", slots: [.lunch], minutes: 10, servings: 2, protein: 30, carbs: 40, fat: 10, kcal: 370, veg: 1,
                       base: .vegan, contains: [], tags: [], cuisine: "", ingredients: ["200 g rice"], steps: ["Cook."])
        #expect(r.ingredient("200 g rice", servings: 4) == "400 g rice")
    }

    @Test func findsFoodsInText() {
        let found = FoodBook.find(in: "2 chicken breasts, some broccoli and rice").map(\.id)
        #expect(found.contains("chicken-breast"))
        #expect(found.contains("broccoli"))
    }
}

@Suite struct PantryPlannerTests {
    private let cal = Progression.calendar()

    @Test func pantryMealGetsClose() {
        let have = ["chicken-breast", "rice", "broccoli", "olive-oil"].map { PantryItem(foodId: $0) }
        let target = Macros(protein: 40, carbs: 60, fat: 15)
        let meal = Pantry.meal(target: target, have: have, prefs: FuelPrefs())
        #expect(!meal.items.isEmpty)
        #expect(meal.closeness > 0.5)
        #expect(abs(meal.totals.protein - 40) < 20)
    }

    @Test func recipesFromWhatYouHave() {
        let have: Set<String> = Set(["egg", "rice", "spinach", "chicken-breast", "broccoli", "oats", "milk", "banana"])
        let out = Pantry.recipes(have: have, prefs: FuelPrefs(), own: [])
        #expect(!out.isEmpty)
        #expect(out.allSatisfy { $0.missing.count <= 2 })
    }

    @Test func planKeepsPinsAndBuildsGroceries() {
        let prefs = FuelPrefs(meals: 4)
        let days: [(key: String, plan: FuelPlan)] = (0..<5).map { i in
            let d = cal.date(byAdding: .day, value: i, to: cal.date(from: DateComponents(year: 2026, month: 10, day: 19))!)!
            return (PlanCalendar.key(d, cal), Fuel.plan(FuelDayInput(day: d, weightKg: 75), prefs: prefs, calendar: cal))
        }
        let first = days[0].plan.slots.first { $0.kind == .lunch } ?? days[0].plan.slots[0]
        let pinnedId = RecipeBook.catalog.first { $0.slots.contains(first.recipeKind) }!.id
        let pin = PlannedMeal(day: days[0].key, slot: first.id, kind: first.kind, recipeId: pinnedId, pinned: true)
        let meals = MealPlanner.plan(days: days, prefs: prefs, favourites: [], own: [], have: [], kept: [pin])
        #expect(meals.contains { $0.id == pin.id && $0.recipeId == pinnedId })
        #expect(meals.count >= 5)
        let items = MealPlanner.groceries(meals, recipes: [], foods: [], have: [], dayLabel: { $0 })
        #expect(!items.isEmpty)
        #expect(items.allSatisfy { $0.grams > 0 })
        #expect(!MealPlanner.shareText(items).isEmpty)
    }

    private func week(_ prefs: FuelPrefs) -> [(key: String, plan: FuelPlan)] {
        (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: cal.date(from: DateComponents(year: 2026, month: 10, day: 19))!)!
            return (PlanCalendar.key(d, cal), Fuel.plan(FuelDayInput(day: d, weightKg: 75), prefs: prefs, calendar: cal))
        }
    }

    @Test func budgetMakesThePlanCheaper() {
        let prefs = FuelPrefs(meals: 4)
        let days = week(prefs)
        let kinds: Set<MealKind> = [.lunch, .dinner]
        let free = MealPlanner.plan(days: days, prefs: prefs, favourites: [], own: [], have: [], kept: [], servings: 2, slots: kinds)
        let tight = MealPlanner.plan(days: days, prefs: prefs, favourites: [], own: [], have: [], kept: [], servings: 2, slots: kinds,
                                     shopping: .init(budget: 40))
        func cost(_ m: [PlannedMeal]) -> Double {
            MealPlanner.basket(MealPlanner.groceries(m, recipes: [], foods: [], have: [], dayLabel: { $0 })).cost
        }
        #expect(cost(tight) < cost(free))
        #expect(cost(free) > 0)
    }

    @Test func lessWasteUsesMoreOfThePacks() {
        let prefs = FuelPrefs(meals: 4)
        let days = week(prefs)
        let kinds: Set<MealKind> = [.lunch, .dinner]
        let plain = MealPlanner.plan(days: days, prefs: prefs, favourites: [], own: [], have: [], kept: [], slots: kinds)
        let lean = MealPlanner.plan(days: days, prefs: prefs, favourites: [], own: [], have: [], kept: [], slots: kinds,
                                    shopping: .init(lessWaste: true))
        func used(_ m: [PlannedMeal]) -> Double {
            MealPlanner.basket(MealPlanner.groceries(m, recipes: [], foods: [], have: [], dayLabel: { $0 })).used
        }
        #expect(used(lean) >= used(plain))
        let items = MealPlanner.groceries(lean, recipes: [], foods: [], have: [], dayLabel: { $0 })
        #expect(items.allSatisfy { $0.packs != nil && $0.cost != nil })
    }

    @Test func ownPriceWins() {
        let r = RecipeBook.catalog.first { ($0.amounts?["chicken-breast"] ?? 0) > 0 }!
        let base = MealPlanner.cost(r, servings: 1)
        let pricey = MealPlanner.cost(r, servings: 1, prices: ["chicken-breast": 200])
        #expect(pricey > base)
    }
}
