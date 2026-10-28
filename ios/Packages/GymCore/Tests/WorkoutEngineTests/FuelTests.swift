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
        #expect(loading.event?.pointers.isEmpty == false)
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

    /// #573: a beer label is a beer, not cheese; brand or region words alone don't make a food.
    @Test func beerLabelIsBeer() {
        #expect(FoodBook.find(in: "Appenzeller Bier Quöllfrisch hell 4,8% vol").map(\.id) == ["beer"])
        #expect(FoodBook.find(in: "Appenzeller").isEmpty)
        #expect(FoodBook.find(in: "Appenzeller Käse").map(\.id) == ["cheese"])
        #expect(FoodBook.find(in: "Feldschlösschen Original alc. 4.8 %").isEmpty)
        #expect(FoodBook.find(in: "Bière sans alcool").map(\.id) == ["alcohol-free-beer"])
        #expect(FoodBook.find(in: "Coca-Cola Zero").map(\.id) == ["cola-zero"])
        #expect(FoodBook.find(in: "red wine vinegar").map(\.id) == ["balsamic"])
    }

    /// #573: "Or it's…" guesses for an unsure scan item: same group, closest values, never the item itself.
    @Test func scanGuesses() throws {
        let cheese = try #require(FoodBook.food("cheese"))
        let g = FoodBook.guesses(for: cheese)
        #expect(g.count == 3)
        #expect(!g.contains { $0.id == "cheese" })
        #expect(g.first?.group == .dairy)
        let beer = try #require(FoodBook.food("beer"))
        #expect(FoodBook.guesses(for: beer).contains { $0.id == "alcohol-free-beer" })
    }

    /// #573: Open Food Facts beer without protein or fat values still comes back, as an alcoholic drink.
    @Test func openFoodFactsBeer() throws {
        let json = #"{"product":{"product_name":"Quöllfrisch hell","brands":"Appenzeller Bier","categories_tags":["en:beverages","en:alcoholic-beverages","en:beers"],"nutriments":{"carbohydrates_100g":3.4,"energy-kcal_100g":42,"alcohol_100g":4.8},"serving_quantity":330}}"#
        let food = try #require(Food.openFoodFacts(Data(json.utf8), barcode: "7610820000014"))
        #expect(food.group == .drink)
        #expect(food.contains.contains(.alcohol))
        #expect(food.name == "Appenzeller Bier Quöllfrisch hell")
        #expect(food.emoji == "🍺")
        #expect(food.per100.kcal == 42)
        #expect(Food.openFoodFacts(Data(#"{"product":{"product_name":"x","nutriments":{}}}"#.utf8), barcode: "1") == nil)
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
        // #819: a pin on a slot the day no longer has moves to the same kind of meal.
        var stray = pin
        stray.slot = "recovery-9"
        let moved = MealPlanner.plan(days: days, prefs: prefs, favourites: [], own: [], have: [], kept: [stray])
        #expect(moved.contains { $0.day == pin.day && $0.slot != "recovery-9" && $0.recipeId == pinnedId && $0.pinned })
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

    @Test func perDayMealsFollowThePattern() {
        let prefs = FuelPrefs(meals: 4)
        let days = week(prefs) // Mon 19 Oct → Sun 25 Oct 2026
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let schedule = MealSchedule(start: days[0].key, blocks: [MealBlock(pattern: .weekdayDinners, days: 7)])
        let dates = (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }
        let meals = MealPlanner.plan(days: days, prefs: prefs, favourites: [], own: [], have: [], kept: [],
                                     daySlots: dates.map { schedule.kinds(on: $0, cal) })
        for (i, d) in days.enumerated() {
            let kinds = Set(meals.filter { $0.day == d.key }.map(\.kind))
            let allowed: Set<MealKind> = i < 5 ? [.dinner] : [.lunch, .dinner]
            #expect(kinds.isSubset(of: allowed))
        }
        // No batch leftovers on a weekday: those days have no lunch.
        #expect(!meals.contains { $0.leftover && days.prefix(5).map(\.key).contains($0.day) })
    }

    @Test func blocksRunInOrderAndRepeat() {
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let s = MealSchedule(start: PlanCalendar.key(start, cal),
                             blocks: [MealBlock(pattern: .dinners, days: 7), MealBlock(pattern: .everyMeal, days: 7)], repeatWeeks: 3)
        func on(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: start)! }
        #expect(s.kinds(on: on(2), cal) == [.dinner])
        #expect(s.kinds(on: on(9), cal).contains(.breakfast))
        #expect(s.kinds(on: on(16), cal).isEmpty) // week 3: gap before the cycle starts again
        #expect(s.kinds(on: on(21), cal) == [.dinner])
        #expect(s.days(from: on(0), cal).count == MealSchedule.maxDays)
        #expect(MealSchedule(start: s.start, blocks: s.blocks).days(from: on(10), cal).count == 4)
        #expect(s.repeatChoices.first == 2)
        #expect(MealPattern.weekdayDinners.mainPerWeek == 9)
    }

    @Test func namedPlansRunOnTheirDates() {
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        func on(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: start)! }
        func key(_ n: Int) -> String { PlanCalendar.key(on(n), cal) }
        let work = NamedMealPlan(name: "Work weeks", blocks: [MealBlock(pattern: .weekdayDinners, days: 7)],
                                 periods: [MealPeriod(from: key(0))])
        let holiday = NamedMealPlan(name: "Holidays", blocks: [MealBlock(pattern: .everyMeal, days: 7)],
                                    periods: [MealPeriod(from: key(14), to: key(20))])
        let book = MealPlanBook(plans: [work, holiday])
        #expect(book.kinds(on: on(1), cal) == [.dinner])
        #expect(book.kinds(on: on(12), cal) == [.lunch, .dinner]) // Saturday, week 2: the cycle started again
        #expect(book.active(on: key(15))?.plan.name == "Holidays") // later period wins
        #expect(book.kinds(on: on(15), cal).contains(.breakfast))
        #expect(book.active(on: key(21))?.plan.name == "Work weeks")
        #expect(MealPlanBook(plans: [holiday]).kinds(on: on(3), cal).isEmpty)
        #expect(book.days(from: start, cal).count == MealPlanBook.horizon)
    }

    @Test func budgetCountsOnlyDaysWithMeals() {
        let prefs = FuelPrefs(meals: 4)
        let days = week(prefs)
        let kinds: Set<MealKind> = [.lunch, .dinner]
        let shopping = MealPlanner.Shopping(budget: 30)
        // Days no plan covers don't stretch the budget for the days that have meals.
        let short = MealPlanner.plan(days: Array(days.prefix(3)), prefs: prefs, favourites: [], own: [], have: [], kept: [],
                                     daySlots: Array(repeating: kinds, count: 3), shopping: shopping)
        let padded = MealPlanner.plan(days: days, prefs: prefs, favourites: [], own: [], have: [], kept: [],
                                      daySlots: Array(repeating: kinds, count: 3) + Array(repeating: [], count: days.count - 3),
                                      shopping: shopping)
        #expect(short == padded)
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

@Suite struct SupplementTests {
    private let cal = Progression.calendar()
    private var day: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 19))! }
    private let boost = Supplement(id: "boost", name: "Boost", kind: .preWorkout, dose: "1 sachet", caffeineMg: 105, creatineG: 3, proteinG: 3.5)
    private let shake = Supplement(id: "shake", name: "Meal shake", kind: .mealReplacement, dose: "1 bottle", proteinG: 40, carbsG: 24, fatG: 17,
                                   restDays: true)

    private func plan(trainingAt hour: Int?) -> FuelPlan {
        let acts = hour.map { [FuelActivity(id: "g", kind: .gym, title: "Legs", start: cal.date(byAdding: .hour, value: $0, to: day)!,
                                            minutes: 60, done: false)] } ?? []
        return Fuel.plan(FuelDayInput(day: day, weightKg: 75, activities: acts), prefs: FuelPrefs(), calendar: cal)
    }

    @Test func preWorkoutGoesBeforeTrainingAndSkipsRestDays() {
        let doses = Supplements.schedule([boost], plan: plan(trainingAt: 12), prefs: FuelPrefs(), calendar: cal)
        #expect(doses.count == 1)
        #expect(doses.first?.minute == 11 * 60 + 30)
        #expect(doses.first?.late == false)
        #expect(Supplements.schedule([boost], plan: plan(trainingAt: nil), prefs: FuelPrefs(), calendar: cal).isEmpty)
    }

    @Test func lateCaffeineWarns() {
        var p = plan(trainingAt: 20)
        Supplements.apply([boost], to: &p, prefs: FuelPrefs(), calendar: cal)
        #expect(p.supplements.first?.late == true)
        #expect(p.tips.first?.contains("cut-off") == true)
    }

    @Test func creatineAddsAGlass() {
        let base = plan(trainingAt: 18)
        var p = base
        Supplements.apply([boost], to: &p, prefs: FuelPrefs(), calendar: cal)
        #expect(p.glasses == base.glasses + 1)
    }

    @Test func rhythmTwiceADayGivesTwoTicks() {
        var d = Supplement(id: "d", name: "Vitamin D", kind: .vitaminD, dose: "1 capsule", restDays: true)
        d.rhythm = .quick(.twice, kind: .vitaminD, start: day)
        d.rhythm?.intakes[1].servings = 2
        let doses = Supplements.schedule([d], plan: plan(trainingAt: nil), prefs: FuelPrefs(), calendar: cal)
        #expect(doses.map(\.id) == ["supp-d", "supp-d-2"])
        #expect(doses[1].supplement.dose == "2 × 1 capsule")
        #expect(d.schedule.quick(.vitaminD) == .twice)
    }

    @Test func rhythmDaysCourseAndCycle() {
        let c = Supplement(id: "c", name: "Creatine", kind: .creatine, dose: "1 scoop", creatineG: 5)
        var r = SupplementRhythm(intakes: [.init(timing: .breakfast)], days: .everyN(2), start: day, length: .weeks(2))
        #expect(r.intakes(on: day, training: false, calendar: cal).count == 1)
        #expect(r.intakes(on: cal.date(byAdding: .day, value: 1, to: day)!, training: false, calendar: cal).isEmpty)
        #expect(r.intakes(on: cal.date(byAdding: .day, value: 14, to: day)!, training: false, calendar: cal).isEmpty)
        #expect(r.intakes(on: cal.date(byAdding: .day, value: -1, to: day)!, training: false, calendar: cal).isEmpty)
        r = SupplementRhythm(intakes: [.init(timing: .breakfast)], start: day, cycle: .init(onWeeks: 1, offWeeks: 1))
        #expect(r.intakes(on: cal.date(byAdding: .day, value: 8, to: day)!, training: false, calendar: cal).isEmpty)
        #expect(r.intakes(on: cal.date(byAdding: .day, value: 15, to: day)!, training: false, calendar: cal).count == 1)
        r = .quick(.load, kind: .creatine, start: day)
        #expect(r.intakes(on: day, training: false, calendar: cal).count == 4)
        #expect(r.intakes(on: cal.date(byAdding: .day, value: 7, to: day)!, training: false, calendar: cal).count == 1)
        var x = c
        x.rhythm = SupplementRhythm(intakes: [.init(timing: .breakfast, minute: 7 * 60 + 15)], days: .trainingDays, start: day)
        #expect(Supplements.schedule([x], plan: plan(trainingAt: nil), prefs: FuelPrefs(), calendar: cal).isEmpty)
        #expect(Supplements.schedule([x], plan: plan(trainingAt: 18), prefs: FuelPrefs(), calendar: cal).first?.minute == 7 * 60 + 15)
    }

    @Test func switchingTypeRefillsUntouchedFields() {
        let s = SupplementKind.mealReplacement.preset.switching(to: .creatine)
        #expect(s.name == "Creatine")
        #expect(s.proteinG == 0)
        #expect(s.creatineG == 5)
        #expect(s.timing == .breakfast)
        var mine = SupplementKind.mealReplacement.preset
        mine.name = "Huel Black"
        #expect(mine.switching(to: .creatine).name == "Huel Black")
    }

    @Test func mealShakeFillsBreakfast() throws {
        var p = plan(trainingAt: nil)
        Supplements.apply([shake], to: &p, prefs: FuelPrefs(), calendar: cal)
        let dose = p.supplements[0]
        #expect(dose.replaces == "breakfast")
        var log = FuelDayLog()
        log.tick(dose)
        #expect(log.ticks["breakfast"] != nil)
        #expect(log.eaten.palms == 2)
        log.untick(dose)
        #expect(log.ticks.isEmpty)
        #expect(log.eaten.total == 0)
        // #819: a breakfast already logged stays when the shake is ticked and unticked.
        log.log([FoodServing(foodId: "coffee")], at: try #require(p.slots.first { $0.id == "breakfast" }))
        log.tick(dose)
        log.untick(dose)
        #expect(log.ticks["breakfast"]?.foods?.map(\.foodId) == ["coffee"])
    }

    @Test func readsTheLabel() {
        let text = "Creapure Kreatin-Monohydrat 3000 mg\nEssentielle Aminosäuren (EAA) 3500 mg\nKoffein 105 mg"
        let found = Supplements.parse(label: text)
        #expect(found?.caffeineMg == 105)
        #expect(found?.creatineG == 3)
        #expect(found?.proteinG == 3.5)
        #expect(Supplements.parse(label: "Shake well before use") == nil)
    }

    // MARK: Products in meals (#599)

    @Test func onDemandProductIsNeverScheduled() {
        var huel = shake
        huel.onDemand = true
        #expect(Supplements.schedule([huel], plan: plan(trainingAt: nil), prefs: FuelPrefs(), calendar: cal).isEmpty)
        #expect(Supplements.schedule([shake], plan: plan(trainingAt: nil), prefs: FuelPrefs(), calendar: cal).count == 1)
    }

    @Test func mealProductIsARecipeOnlyForMeals() {
        let recipes = Supplements.recipes([shake, boost])
        #expect(recipes.count == 1)
        let r = recipes[0]
        #expect(r.id == "product-shake")
        #expect(r.protein == 40 && r.carbs == 24 && r.fat == 17)
        #expect(r.slots.contains(.breakfast) && r.slots.contains(.dinner))
        #expect(RecipeBook.recipe("product-shake", own: recipes)?.name == "Meal shake")
        // Ticked as a meal it adds the same portions as the scheduled shake.
        #expect(r.portions == shake.portions)
    }

    @Test func extraTakesGetTheirOwnTick() {
        var log = FuelDayLog()
        let whey = Supplement(id: "w", name: "Whey", kind: .protein, dose: "1 scoop", proteinG: 25, onDemand: true)
        log.tick(Supplements.extra(whey, log: log, minute: 600))
        log.tick(Supplements.extra(whey, log: log, minute: 900))
        #expect(log.ticks["supp-w-x1"] != nil && log.ticks["supp-w-x2"] != nil)
        #expect(log.eaten.palms == 2)
    }

    @Test func catalogHasHuelVariantsAndSearches() {
        let huel = ProductCatalog.brands.first { $0.id == "huel" }
        #expect((huel?.variants.count ?? 0) >= 4)
        #expect(ProductCatalog.search("huel black").first?.variants.allSatisfy { $0.name.contains("Black") } == true)
        #expect(ProductCatalog.search("yfood").map(\.id) == ["yfood"])
        #expect(Set(ProductCatalog.brands.flatMap(\.variants).map(\.id)).count == ProductCatalog.brands.flatMap(\.variants).count)
        let mine = ProductCatalog.mine(huel!.variants[0], servings: 1.5, onDemand: true)
        #expect(mine.whenPicked && mine.id != huel!.variants[0].id)
        #expect(mine.proteinG == 60)
    }
}
