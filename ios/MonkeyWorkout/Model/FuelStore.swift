import Foundation
import WorkoutEngine

/// Fuel (#496): settings, what was tapped each day, favourite and own recipes, what the member has at home, the meal
/// plan and the grocery list. Stays on the device (Application Support, protected until first unlock); never sent
/// to the server.
@MainActor @Observable
final class FuelStore {
    static let shared = FuelStore()

    struct Saved: Codable {
        var prefs = FuelPrefs()
        /// Setup sheet seen (or skipped).
        var setUp = false
        /// Day key → log.
        var logs: [String: FuelDayLog] = [:]
        /// Day key → XP earned that day (protein + water targets).
        var hits: [String: Int] = [:]
        var favourites: Set<String> = []
        var recipes: [Recipe] = []
        var pantry: [PantryItem] = []
        /// Barcode-scanned products.
        var foods: [Food] = []
        var plan: [PlannedMeal] = []
        /// People per planned meal.
        var people = 1
        /// Days the planner fills (3, 5 or 7).
        var planDays = 5
        /// Only lunch and dinner (false = every slot of the day).
        var mainOnly = true
        /// Grocery lines ticked in the shop.
        var bought: Set<String> = []
        /// Refuel reminder sent (day key).
        var nudged: String?
        /// Meal plan budget, CHF a week for everyone fed; nil = no limit.
        var budget: Double?
        /// Plan to finish fresh packs (spinach bag, feta…) across meals.
        var lessWaste = true
        /// The member's own prices, CHF per kg (or litre), by food id.
        var prices: [String: Double] = [:]
        /// `FuelMarket` id picked by the member (currency + local price level); nil = the phone's region.
        var market: String?
        /// The member's supplements (#514); optional so older saves still load.
        var supplements: [Supplement]?
    }

    private(set) var saved = Saved()
    /// Glasses tapped today go to Apple Health as dietary water.
    @ObservationIgnored weak var health: HealthManager?

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("fuel.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.url), let s = try? JSONDecoder().decode(Saved.self, from: data) { saved = s }
    }

    private var cal: Calendar { Progression.calendar() }
    func key(_ d: Date) -> String { PlanCalendar.key(d, cal) }

    var prefs: FuelPrefs { saved.prefs }
    /// XP Fuel adds to the level.
    var xp: Int { saved.hits.values.reduce(0, +) }

    func log(_ day: Date) -> FuelDayLog { saved.logs[key(day)] ?? FuelDayLog() }

    func setPrefs(_ p: FuelPrefs) {
        var s = saved
        s.prefs = p
        s.setUp = true
        save(s)
    }

    func markSetUp() {
        guard !saved.setUp else { return }
        var s = saved
        s.setUp = true
        save(s)
    }

    /// Changes a day's log; XP follows the day's targets (only today and earlier days earn).
    func update(_ day: Date, plan: FuelPlan, _ change: (inout FuelDayLog) -> Void) {
        var s = saved
        let k = key(day)
        var log = s.logs[k] ?? FuelDayLog()
        let glasses = log.glasses
        change(&log)
        if log.glasses > glasses, cal.isDateInToday(day), let health {
            let ml = Double((log.glasses - glasses) * s.prefs.glassMl)
            Task { await health.saveWater(ml: ml) }
        }
        s.logs[k] = log.isEmpty ? nil : log
        if cal.startOfDay(for: day) <= cal.startOfDay(for: Date()) {
            let earned = (log.proteinHit(plan) ? FuelWeek.proteinXP : 0) + (log.waterHit(plan) ? FuelWeek.waterXP : 0)
            s.hits[k] = earned > 0 ? earned : nil
        }
        save(s)
    }

    var stack: [Supplement] { saved.supplements ?? [] }

    func saveSupplement(_ x: Supplement) {
        var s = saved
        var list = s.supplements ?? []
        if let i = list.firstIndex(where: { $0.id == x.id }) { list[i] = x } else { list.append(x) }
        s.supplements = list
        save(s)
    }

    func deleteSupplement(_ id: String) {
        var s = saved
        s.supplements?.removeAll { $0.id == id }
        save(s)
    }

    func toggleFavourite(_ id: String) {
        var s = saved
        if s.favourites.contains(id) { s.favourites.remove(id) } else { s.favourites.insert(id) }
        save(s)
    }

    func saveRecipe(_ r: Recipe) {
        var s = saved
        s.recipes.removeAll { $0.id == r.id }
        s.recipes.insert(r, at: 0)
        save(s)
    }

    func deleteRecipe(_ id: String) {
        var s = saved
        s.recipes.removeAll { $0.id == id }
        s.favourites.remove(id)
        s.plan.removeAll { $0.recipeId == id }
        save(s)
    }

    // MARK: What I have

    var pantryIds: Set<String> { Set(saved.pantry.map(\.foodId)) }

    func add(_ foods: [Food]) {
        var s = saved
        for f in foods {
            if f.barcode != nil, !s.foods.contains(where: { $0.id == f.id }) { s.foods.append(f) }
            if !s.pantry.contains(where: { $0.foodId == f.id }) { s.pantry.append(PantryItem(foodId: f.id)) }
        }
        save(s)
    }

    func setGrams(_ id: String, _ grams: Double?) {
        var s = saved
        guard let i = s.pantry.firstIndex(where: { $0.foodId == id }) else { return }
        s.pantry[i].grams = grams.map { max(0, $0) }
        save(s)
    }

    func remove(_ id: String) {
        var s = saved
        s.pantry.removeAll { $0.foodId == id }
        save(s)
    }

    func clearPantry() {
        var s = saved
        s.pantry = []
        save(s)
    }

    // MARK: Meal plan and groceries

    func setPlan(_ meals: [PlannedMeal]) {
        var s = saved
        s.plan = meals
        // A new plan starts a fresh list; lines still in it stay ticked.
        save(s)
    }

    func setPlanOptions(people: Int? = nil, days: Int? = nil, mainOnly: Bool? = nil, lessWaste: Bool? = nil) {
        var s = saved
        if let people { s.people = max(1, min(8, people)) }
        if let days { s.planDays = days }
        if let mainOnly { s.mainOnly = mainOnly }
        if let lessWaste { s.lessWaste = lessWaste }
        save(s)
    }

    /// Weekly budget in CHF (nil = no limit).
    func setBudget(_ chf: Double?) {
        var s = saved
        s.budget = chf.map { max(10, min(1000, $0)) }
        save(s)
    }

    func setMarket(_ id: String?) {
        var s = saved
        s.market = id
        save(s)
    }

    /// The member's price for a food (CHF per kg); nil goes back to the estimate.
    func setPrice(_ foodId: String, _ chf: Double?) {
        var s = saved
        s.prices[foodId] = chf.flatMap { $0 > 0 ? $0 : nil }
        save(s)
    }

    var shopping: MealPlanner.Shopping {
        MealPlanner.Shopping(budget: saved.budget, lessWaste: saved.lessWaste, prices: saved.prices)
    }

    func pin(_ meal: PlannedMeal) {
        var s = saved
        var m = meal
        m.pinned = true
        m.leftover = false
        s.plan.removeAll { $0.id == m.id }
        s.plan.append(m)
        save(s)
    }

    func unplan(_ id: String) {
        var s = saved
        s.plan.removeAll { $0.id == id }
        save(s)
    }

    func toggleBought(_ id: String) {
        var s = saved
        if s.bought.contains(id) { s.bought.remove(id) } else { s.bought.insert(id) }
        save(s)
    }

    /// Bought lines go into What I have, with their amounts.
    func stockBought(_ items: [GroceryItem]) {
        var s = saved
        for i in items where s.bought.contains(i.id) {
            if let j = s.pantry.firstIndex(where: { $0.foodId == i.food.id }) {
                s.pantry[j].grams = s.pantry[j].grams.map { $0 + i.grams }
            } else {
                s.pantry.append(PantryItem(foodId: i.food.id, grams: i.grams))
            }
        }
        s.bought = []
        save(s)
    }

    /// A glass tapped on the Watch (day key from the Watch, so a late sync lands on the right day).
    func addGlass(dayKey: String, plan: FuelPlan) {
        guard let day = PlanCalendar.date(dayKey, cal) else { return }
        update(day, plan: plan) { $0.glasses += 1 }
    }

    func markNudged(_ day: Date) {
        var s = saved
        s.nudged = key(day)
        save(s)
    }

    #if DEBUG
    /// Demo screens: a counted morning, a few favourites, a stocked fridge and a planned week. Not saved.
    func demo(layout: FuelLayout, now: Date = Date()) {
        var s = Saved()
        s.setUp = true
        s.prefs = FuelPrefs(goal: .build, meals: 5, layout: layout)
        let k = key(now)
        s.logs[k] = FuelDayLog(glasses: 6, eaten: Portions(palms: 3, cups: 3, fists: 2, thumbs: 2),
                               ticks: ["breakfast": FuelTick(added: Portions()),
                                       "supp-demo-huel": FuelTick(added: Portions(palms: 2, cups: 1, fists: 0, thumbs: 1))])
        for i in 1...6 {
            guard let d = cal.date(byAdding: .day, value: -i, to: now) else { continue }
            s.logs[key(d)] = FuelDayLog(glasses: [10, 7, 11, 9, 6, 12][i - 1], eaten: Portions(palms: [7, 5, 7, 6, 4, 7][i - 1], cups: 7, fists: 5, thumbs: 4))
            s.hits[key(d)] = [15, 5, 15, 10, 0, 15][i - 1]
        }
        s.favourites = Set(RecipeBook.catalog.prefix(4).map(\.id))
        s.pantry = ["egg", "rice", "chicken-breast", "broccoli", "greek-yogurt", "oats", "banana", "olive-oil", "spinach", "milk"]
            .filter { FoodBook.food($0) != nil }.map { PantryItem(foodId: $0) }
        s.supplements = [
            Supplement(id: "demo-huel", name: "Huel Black Edition", kind: .mealReplacement, dose: "1 bottle", proteinG: 40, carbsG: 24, fatG: 17,
                       restDays: true),
            Supplement(id: "demo-boost", name: "KaEx Boost+", kind: .preWorkout, dose: "1 sachet in 300 ml water",
                       caffeineMg: 105, creatineG: 3, proteinG: 3.5),
            Supplement(id: "demo-whey", name: "Whey shake", kind: .protein, dose: "1 scoop in milk", proteinG: 24, restDays: true),
            Supplement(id: "demo-d", name: "Vitamin D", kind: .vitaminD, dose: "1 capsule", restDays: true),
        ]
        s.logs[k]?.ticks["supp-demo-d"] = FuelTick(added: Portions())
        saved = s
    }

    func demoPlan(_ meals: [PlannedMeal]) { saved.plan = meals }
    #endif

    func signOut() {
        save(Saved())
        try? FileManager.default.removeItem(at: Self.url)
    }

    private func save(_ s: Saved) {
        saved = s
        // Today's water and meals on the Watch and the Home Screen widgets.
        WatchSync.shared.push()
        guard let data = try? JSONEncoder().encode(s) else { return }
        let url = Self.url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
