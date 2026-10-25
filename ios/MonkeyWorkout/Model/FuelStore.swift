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
        /// Fuel settings saved once (Done on the set-up sheet or any settings change).
        var setUp = false
        /// Set up Fuel card hidden with Later or ✕ (#686); Settings → You → Onboarding keeps the set-up.
        var setupCardHidden: Bool?
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
        /// Days the planner filled before blocks (3, 5 or 7); read only to build `schedule` for older saves.
        var planDays = 5
        /// Only lunch and dinner (false = every slot of the day); older saves, see `planDays`.
        var mainOnly = true
        /// Unused: kept so a save from a test build with one block schedule still loads into `book`.
        var schedule: MealSchedule?
        /// Named meal plans and their dates (#558); nil = older save, built from `planDays` and `mainOnly`.
        var book: MealPlanBook?
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
        /// Water reminders (#520); nil = defaults (remind when behind, quiet during training).
        var water: WaterPrefs?
        /// Plates of plain foods saved from Just ate (#710).
        var usuals: [FoodUsual]?
    }

    private(set) var saved = Saved() {
        didSet { version &+= 1 }
    }
    /// Bumped on every change to `saved`: keys `AppModel`'s Fuel plan cache.
    @ObservationIgnored private(set) var version = 0
    /// Glasses tapped today go to Apple Health as dietary water.
    @ObservationIgnored weak var health: HealthManager?
    /// The day's plan from the app model, for glasses counted outside Fuel (widgets, notification buttons).
    @ObservationIgnored var planFor: ((Date) -> FuelPlan)?

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("fuel.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.url), var s = try? JSONDecoder().decode(Saved.self, from: data) {
            // Older saves get their plan written down once, so its dates stop moving with today and it can be edited
            // or deleted.
            if s.book == nil {
                s.book = Self.legacyBook(s, today: PlanCalendar.key(Date(), Progression.calendar()), cal: Progression.calendar())
                Self.write(s, to: Self.url)
            }
            saved = s
        }
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
        Task { await NotificationManager.shared.scheduleWater() }
    }

    var waterPrefs: WaterPrefs { saved.water ?? WaterPrefs() }

    func setWaterPrefs(_ w: WaterPrefs) {
        var s = saved
        s.water = w
        save(s)
        Task { await NotificationManager.shared.scheduleWater() }
    }

    /// Set up Fuel card on top of Fuel (#686): until the settings are saved once, unless hidden.
    var showsSetupCard: Bool { !saved.setUp && saved.setupCardHidden != true }

    func hideSetupCard(_ hidden: Bool) {
        var s = saved
        s.setupCardHidden = hidden
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
        let water = log.glasses != glasses && cal.isDateInToday(day)
        s.logs[k] = log.isEmpty ? nil : log
        if cal.startOfDay(for: day) <= cal.startOfDay(for: Date()) {
            let earned = (log.proteinHit(plan) ? FuelWeek.proteinXP : 0) + (log.waterHit(plan) ? FuelWeek.waterXP : 0)
            s.hits[k] = earned > 0 ? earned : nil
        }
        save(s)
        // Reminders follow the glasses known now (#520).
        if water { Task { await NotificationManager.shared.scheduleWater() } }
        if cal.isDateInToday(day), stack.contains(where: { $0.rhythm?.remind == true }) {
            Task { await NotificationManager.shared.scheduleSupplements() }
        }
    }

    var stack: [Supplement] { saved.supplements ?? [] }

    /// Own recipes plus the stack's meal shakes and hot meals (#599): for finding a planned or ticked meal, not for ideas.
    var recipeLookup: [Recipe] { saved.recipes + Supplements.recipes(stack) }

    func saveSupplement(_ x: Supplement) {
        var s = saved
        var list = s.supplements ?? []
        if let i = list.firstIndex(where: { $0.id == x.id }) { list[i] = x } else { list.append(x) }
        s.supplements = list
        save(s)
        Task { await NotificationManager.shared.scheduleSupplements() }
    }

    /// Removes it at once and returns what Undo needs to put it back (#717): the supplement and its meal plan meals.
    @discardableResult
    func deleteSupplement(_ id: String) -> (supplement: Supplement, meals: [PlannedMeal])? {
        var s = saved
        let removed = s.supplements?.first { $0.id == id }
        let meals = s.plan.filter { $0.recipeId == Supplements.recipePrefix + id }
        s.supplements?.removeAll { $0.id == id }
        s.plan.removeAll { $0.recipeId == Supplements.recipePrefix + id }
        save(s)
        Task { await NotificationManager.shared.scheduleSupplements() }
        return removed.map { ($0, meals) }
    }

    /// Undo of `deleteSupplement` (#717).
    func restoreSupplement(_ x: Supplement, meals: [PlannedMeal]) {
        var s = saved
        var list = s.supplements ?? []
        if !list.contains(where: { $0.id == x.id }) { list.append(x) }
        s.supplements = list
        s.plan += meals.filter { m in !s.plan.contains { $0.id == m.id } }
        save(s)
        Task { await NotificationManager.shared.scheduleSupplements() }
    }

    // MARK: Plain foods (#710)

    var usuals: [FoodUsual] { saved.usuals ?? [] }

    func saveUsual(_ u: FoodUsual) {
        var s = saved
        var list = s.usuals ?? []
        if let i = list.firstIndex(where: { $0.id == u.id }) { list[i] = u } else { list.insert(u, at: 0) }
        s.usuals = list
        save(s)
    }

    /// Keeps foods a plate scan found that are not on the list (#723), so their logged amounts still add up.
    func keep(_ foods: [Food]) {
        let new = foods.filter { f in FoodBook.food(f.id) == nil && !saved.foods.contains { $0.id == f.id } }
        guard !new.isEmpty else { return }
        var s = saved
        s.foods += new
        save(s)
    }

    func deleteUsual(_ id: String) {
        var s = saved
        s.usuals?.removeAll { $0.id == id }
        save(s)
    }

    /// "☕ Coffee 80": caffeine drinks logged on the day, for the caffeine meter.
    func caffeineDrinks(_ log: FuelDayLog) -> [String] {
        var mg: [String: Int] = [:]
        for t in log.ticks.values {
            for i in t.foods ?? [] {
                guard let f = FoodBook.food(i.foodId, own: saved.foods), (f.caffeine ?? 0) > 0 else { continue }
                mg[f.id, default: 0] += f.caffeineMg(grams: i.grams(f))
            }
        }
        return mg.sorted { $0.key < $1.key }.compactMap { id, v in FoodBook.food(id, own: saved.foods).map { "\($0.emoji) \($0.name) \(v)" } }
    }

    /// Foods logged in the last 2 weeks, newest day first: chips in Just ate.
    func recentFoods(before day: Date) -> [String] {
        var ids: [String] = []
        for i in 0..<14 {
            guard let d = cal.date(byAdding: .day, value: -i, to: day) else { continue }
            for t in log(d).ticks.values { for f in t.foods ?? [] where !ids.contains(f.foodId) { ids.append(f.foodId) } }
        }
        return ids
    }

    func toggleFavourite(_ id: String) {
        var s = saved
        if s.favourites.contains(id) { s.favourites.remove(id) } else { s.favourites.insert(id) }
        save(s)
    }

    func saveRecipe(_ r: Recipe) {
        // Share prompt (#777): a recipe the member just made.
        if r.isOwn, !saved.recipes.contains(where: { $0.id == r.id }) {
            ShareMoments.shared.offer(ShareMoment(id: "recipe-\(r.id)", title: "New meal: \(r.name)", poster: .recipe(r)))
        }
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
            if FoodBook.food(f.id) == nil, !s.foods.contains(where: { $0.id == f.id }) { s.foods.append(f) }
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
        if s.book == nil { s.book = book }
        // A new plan starts a fresh list; lines still in it stay ticked.
        save(s)
    }

    func setPlanOptions(people: Int? = nil, lessWaste: Bool? = nil) {
        var s = saved
        if let people { s.people = max(1, min(8, people)) }
        if let lessWaste { s.lessWaste = lessWaste }
        save(s)
    }

    /// The member's named meal plans and their dates (#558). Older saves get one plan, "My plan", from today with
    /// their length and choice (or their blocks).
    var book: MealPlanBook { saved.book ?? Self.legacyBook(saved, today: key(Date()), cal: cal) }

    /// Fixed ids, so the plan built for an older save is the same one on every read (editing and deleting find it).
    private static let legacyIds = (plan: UUID(uuidString: "6D0E5A2C-0000-4000-8000-000000000001")!,
                                    block: UUID(uuidString: "6D0E5A2C-0000-4000-8000-000000000002")!,
                                    period: UUID(uuidString: "6D0E5A2C-0000-4000-8000-000000000003")!)

    private static func legacyBook(_ s: Saved, today: String, cal: Calendar) -> MealPlanBook {
        let x = s.schedule ?? MealSchedule(start: today, blocks: [MealBlock(id: legacyIds.block, pattern: s.mainOnly ? .lunchDinner : .everyMeal,
                                                                            days: s.planDays)])
        let end = cal.date(byAdding: .day, value: max(0, x.length - 1), to: PlanCalendar.date(x.start, cal) ?? Date())
            .map { PlanCalendar.key($0, cal) }
        return MealPlanBook(plans: [NamedMealPlan(id: legacyIds.plan, name: "My plan", blocks: x.blocks, repeatWeeks: x.repeatWeeks,
                                                  periods: [MealPeriod(id: legacyIds.period, from: x.start,
                                                                       to: x.repeatWeeks == nil ? end : nil)])])
    }

    /// Days from today with meals planned: what the basket buys for and its budget covers.
    var planSpan: Int {
        let today = key(Date())
        return max(1, Set(saved.plan.filter { $0.day >= today }.map(\.day)).count)
    }

    /// Part of a week's 21 main meals the plans hold over the coming weeks, for budget suggestions.
    var mealShare: Double { book.mainPerWeek(from: Date(), cal) / 21 }

    /// Adds or changes a named plan (blocks capped at the longest cycle).
    func savePlan(_ plan: NamedMealPlan) {
        var s = saved
        var b = book
        var p = plan
        while p.length > MealSchedule.maxDays, let last = p.blocks.indices.last {
            let cut = p.length - MealSchedule.maxDays
            if p.blocks[last].days > cut { p.blocks[last].days -= cut } else { p.blocks.removeLast() }
        }
        if let w = p.repeatWeeks, w * 7 < p.length { p.repeatWeeks = nil }
        if let i = b.plans.firstIndex(where: { $0.id == p.id }) { b.plans[i] = p } else { b.plans.append(p) }
        s.book = b
        save(s)
    }

    /// Takes a named plan off; returns the plans and planned meals as they were, for the Undo bar.
    func deleteNamedPlan(_ id: UUID) -> (book: MealPlanBook, plan: [PlannedMeal]) {
        let before = (book: book, plan: saved.plan)
        var s = saved
        var b = before.book
        b.plans.removeAll { $0.id == id }
        s.book = b
        save(s)
        return before
    }

    func restoreBook(_ b: (book: MealPlanBook, plan: [PlannedMeal])) {
        var s = saved
        s.book = b.book
        s.plan = b.plan
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

    /// Pins the same pick to many meals at once (a shake every planned breakfast, #599).
    func pin(_ meals: [PlannedMeal]) {
        var s = saved
        for meal in meals {
            var m = meal
            m.pinned = true
            m.leftover = false
            s.plan.removeAll { $0.id == m.id }
            s.plan.append(m)
        }
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

    /// Glasses from a widget or a notification button.
    func addGlasses(_ n: Int, on day: Date = Date()) {
        guard n > 0, let plan = planFor?(day) else { return }
        update(day, plan: plan) { $0.glasses += n }
    }

    /// Glasses tapped on the water widget while the app was closed (#520).
    func applyWidgetGlasses() {
        guard planFor != nil else { return }
        let taken = WaterQueue.take()
        for (day, dates) in Dictionary(grouping: taken, by: { cal.startOfDay(for: $0) }) { addGlasses(dates.count, on: day) }
    }

    func markNudged(_ day: Date) {
        var s = saved
        s.nudged = key(day)
        save(s)
    }

    #if DEBUG
    /// Demo screens: a counted morning, a few favourites, a stocked fridge and a planned week. Not saved.
    func demo(layout: FuelLayout, setUp: Bool = true, now: Date = Date()) {
        var s = Saved()
        s.setUp = setUp
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
        s.usuals = [FoodUsual(id: "demo-usual", name: "My breakfast",
                              items: ["coffee", "cornflakes", "milk"].map { FoodServing(foodId: $0) }, kind: .breakfast),
                    FoodUsual(id: "demo-quick", name: "Quick one", items: ["banana", "coffee"].map { FoodServing(foodId: $0) }, kind: .snack)]
        saved = s
    }

    func demoPlan(_ meals: [PlannedMeal]) { saved.plan = meals }
    #endif

    func signOut() {
        save(Saved())
        let url = Self.url
        // After the coalesced write, so it doesn't bring the file back.
        Task { @MainActor in Self.queue.async { try? FileManager.default.removeItem(at: url) } }
    }

    /// Writes run in order on one queue, off the main thread (#720).
    nonisolated private static let queue = DispatchQueue(label: "FuelStore.io", qos: .utility)
    @ObservationIgnored private var writeQueued = false

    private func save(_ s: Saved) {
        saved = s
        // Today's water and meals on the Watch and the Home Screen widgets (coalesced: a burst of taps sends once).
        WatchSync.shared.schedulePush()
        // The file too (#720): one encode and write for a burst of taps, written as of the last one.
        guard !writeQueued else { return }
        writeQueued = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.writeQueued = false
            let s = self.saved, url = Self.url
            Self.queue.async { Self.write(s, to: url) }
        }
    }

    nonisolated private static func write(_ s: Saved, to url: URL) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
