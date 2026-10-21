import APIClient
import Foundation
import WorkoutEngine

/// Fuel (#496): a day's training as the nutrition engine sees it, and the plan built from it.
extension AppModel {
    /// Hour the member usually trains: median start of the last 20 workouts, else 18:00.
    var usualTrainingHour: Int {
        let cal = planCalendar
        let hours = history.prefix(20).map { cal.component(.hour, from: $0.startedAt) }.sorted()
        guard !hours.isEmpty else { return 18 }
        return hours[hours.count / 2]
    }

    /// Done and planned training on a day: workouts, logged and tracked sports, climbs; planned sessions, climbing
    /// days, sport days and trips for today on.
    func fuelActivities(on date: Date) -> [FuelActivity] {
        let cal = planCalendar
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        func onDay(_ d: Date) -> Bool { d >= start && d < end }
        var out: [FuelActivity] = []
        for r in state.history where onDay(r.startedAt) {
            out.append(FuelActivity(id: r.id.uuidString, kind: .gym, title: r.title, start: r.startedAt, minutes: r.durationSec / 60,
                                    kcal: r.kcal, done: true))
        }
        for s in sportLogs where onDay(s.start) {
            out.append(FuelActivity(id: s.id.uuidString, kind: .sport(s.sport), title: s.sport.label, start: s.start, minutes: s.minutes,
                                    effort: s.effort, done: true))
        }
        for c in climbLogs where onDay(c.start) {
            out.append(FuelActivity(id: c.id.uuidString, kind: .sport(.climbing), title: "Climbing", start: c.start, minutes: c.minutes,
                                    effort: c.effort, done: true))
        }
        // Other apps' sessions from Health (Watch, Strava…), unless already logged here at about the same time.
        let snapshot = health?.snapshot
        var healthSessions: [(UUID, Sport, Date, Date, Double?, Int?)] = []
        for e in snapshot?.recentSports ?? [] { healthSessions.append((e.id, e.sport, e.start, e.end, e.kcal, e.effort)) }
        for e in snapshot?.recentClimbs ?? [] { healthSessions.append((e.id, Sport.climbing, e.start, e.end, nil, e.effort)) }
        for (id, sport, s, e, kcal, effort) in healthSessions where onDay(s) {
            guard !out.contains(where: { abs($0.start.timeIntervalSince(s)) < 20 * 60 }) else { continue }
            out.append(FuelActivity(id: id.uuidString, kind: .sport(sport), title: sport.label, start: s,
                                    minutes: max(0, Int(e.timeIntervalSince(s) / 60)), kcal: kcal, effort: effort, done: true))
        }
        guard start >= cal.startOfDay(for: Date()) else { return out.sorted { $0.start < $1.start } }

        // Planned: at the usual hour, after anything already done today.
        let key = PlanCalendar.key(start, cal)
        guard let week = calendarWeeks(count: 3).first(where: { $0.days.contains(key) }),
              let wd = week.days.firstIndex(of: key).map({ $0 + 1 }) else { return out.sorted { $0.start < $1.start } }
        var at = cal.date(bySettingHour: usualTrainingHour, minute: 0, second: 0, of: start) ?? start
        if let last = out.map(\.end).max(), last > at { at = last.addingTimeInterval(60 * 60) }
        if Calendar.current.isDateInToday(start), at < Date() { at = Date().addingTimeInterval(30 * 60) }
        let gymDone = out.contains { if case .gym = $0.kind { return true } else { return false } }
        if !gymDone {
            for s in week.plan.sessions where s.weekday == wd && !doneIds.contains(s.id) {
                out.append(FuelActivity(id: s.id, kind: .gym, title: s.title, start: at, minutes: s.estMin, done: false))
                at = at.addingTimeInterval(Double(s.estMin + 60) * 60)
            }
        }
        var sports: [Sport] = []
        if let trip = week.trips[wd] { sports.append(trip.sport) }
        if week.climbing.contains(wd) { sports.append(.climbing) }
        for d in profile?.sportDays(on: start, calendar: cal) ?? [] where d.weekday == wd { sports.append(d.sport) }
        for sport in Set(sports).sorted(by: { $0.rawValue < $1.rawValue })
        where !out.contains(where: { $0.sport == sport }) {
            let minutes = [Sport.snowboard, .ski, .crossCountrySki, .hike, .mountaineering].contains(sport) ? 240 : sport == .climbing ? 120 : 75
            out.append(FuelActivity(id: "plan-\(sport.rawValue)", kind: .sport(sport), title: sport.label,
                                    start: [Sport.snowboard, .ski, .hike, .mountaineering].contains(sport) ? (cal.date(bySettingHour: 9, minute: 30, second: 0, of: start) ?? at) : at,
                                    minutes: minutes, done: false))
        }
        return out.sorted { $0.start < $1.start }
    }

    var fuelWeightKg: Double? { body.weightKg ?? health?.snapshot.weightKg }

    /// A race or event today or in the next two days: My sports' event dates and Hyrox ready race days.
    func fuelEvent(on date: Date) -> FuelEvent? {
        let cal = planCalendar
        let day = cal.startOfDay(for: date)
        var events: [(Sport, String, Date)] = (profile?.otherSports ?? []).compactMap { p in p.event.map { (p.sport, "\(p.sport.label) event", $0) } }
        for r in activeProgramme?.races ?? [] { events.append((.hyrox, profile?.hyrox?.raceName ?? "Hyrox", r)) }
        let soon = events.compactMap { e -> FuelEvent? in
            let days = cal.dateComponents([.day], from: day, to: cal.startOfDay(for: e.2)).day ?? -1
            return (0...2).contains(days) ? FuelEvent(sport: e.0, name: e.1, days: days) : nil
        }
        return soon.min { $0.days < $1.days }
    }

    var fuelLeanKg: Double? { health?.snapshot.leanKg ?? measurements.last?.leanKg }

    /// Cached per day (`AppModel+Cache`), except today's and yesterday's: today's coming sessions are placed after
    /// the current time.
    func fuelPlan(on date: Date) -> FuelPlan {
        let cal = planCalendar
        let day = cal.startOfDay(for: date)
        let steps: Int = Calendar.current.isDateInToday(day) ? MoveStore.shared.today.steps
            : MoveStore.shared.saved.days.first { $0.day == day }?.steps ?? 0
        let today = cal.startOfDay(for: Date())
        let followsClock = day == today || cal.date(byAdding: .day, value: 1, to: day) == today
        // Reading `saved` keeps a view that gets a cached plan observing the Fuel settings.
        _ = FuelStore.shared.saved.prefs
        let key = FuelPlanKey(derived: derivedKey, steps: steps, fuel: FuelStore.shared.version)
        if !followsClock, let c = derived.fuelPlans[day], c.key == key { return c.value }
        let plan = makeFuelPlan(day: day, steps: steps, calendar: cal)
        if !followsClock {
            if derived.fuelPlans.count > 64 { derived.fuelPlans = [:] }
            derived.fuelPlans[day] = (key, plan)
        }
        return plan
    }

    private func makeFuelPlan(day: Date, steps: Int, calendar cal: Calendar) -> FuelPlan {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: day).map { fuelActivities(on: $0) } ?? []
        let input = FuelDayInput(day: day, weightKg: fuelWeightKg, leanKg: fuelLeanKg, female: body.sex == .female,
                                 activities: fuelActivities(on: day), steps: steps, tomorrow: tomorrow, trainingGoal: profile?.goal,
                                 event: fuelEvent(on: day))
        var plan = Fuel.plan(input, prefs: FuelStore.shared.prefs, calendar: cal)
        Supplements.apply(FuelStore.shared.stack, to: &plan, prefs: FuelStore.shared.prefs, calendar: cal)
        return plan
    }

    /// The 7 days up to `now`, with what was tapped.
    func fuelWeek(now: Date = Date()) -> [FuelWeekDay] {
        let cal = planCalendar
        return (0..<7).reversed().compactMap { i in
            cal.date(byAdding: .day, value: -i, to: cal.startOfDay(for: now)).map { d in
                FuelWeekDay(day: d, plan: fuelPlan(on: d), log: FuelStore.shared.log(d))
            }
        }
    }

    /// Fills the plan's days (from today) with recipes and keeps the member's picks; each day gets the meals its
    /// block's pattern asks for (#558).
    func planMeals(now: Date = Date()) {
        let store = FuelStore.shared
        let cal = planCalendar
        store.restartIfOver(now: now)
        let schedule = store.schedule
        let dates = schedule.days(from: now, cal)
        let days = dates.map { (key: PlanCalendar.key($0, cal), plan: fuelPlan(on: $0)) }
        let meals = MealPlanner.plan(days: days, prefs: store.prefs, favourites: store.saved.favourites, own: store.saved.recipes,
                                     have: store.pantryIds, kept: store.saved.plan, servings: store.saved.people,
                                     daySlots: dates.map { schedule.kinds(on: $0, cal) }, shopping: store.shopping)
        store.setPlan(meals)
    }

    /// A repeating plan tops itself up when a day with meals in the coming week isn't planned yet.
    func topUpMealPlan(now: Date = Date()) {
        let store = FuelStore.shared
        let cal = planCalendar
        let schedule = store.schedule
        guard schedule.repeatWeeks != nil, !store.saved.plan.isEmpty else { return }
        let last = store.saved.plan.map(\.day).max() ?? ""
        let due = schedule.days(from: now, cal).prefix(8).contains { PlanCalendar.key($0, cal) > last && !schedule.kinds(on: $0, cal).isEmpty }
        if due { planMeals(now: now) }
    }

    /// "Tue 21" for a day key.
    func fuelDayLabel(_ key: String) -> String {
        let cal = planCalendar
        guard let d = PlanCalendar.date(key, cal) else { return key }
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        return d.formatted(.dateTime.weekday(.abbreviated).day())
    }

    func groceries() -> [GroceryItem] {
        let store = FuelStore.shared
        let today = PlanCalendar.key(Date(), planCalendar)
        return MealPlanner.groceries(store.saved.plan.filter { $0.day >= today }, recipes: store.saved.recipes, foods: store.saved.foods,
                                     have: store.saved.pantry, prices: store.saved.prices, dayLabel: fuelDayLabel)
    }

    /// Foods seen on a photo of the fridge, a cupboard, shopping or a receipt (Pro).
    func scanFood(jpeg: Data) async throws -> [Food] {
        #if DEBUG
        if demo { return ["egg", "milk", "spinach", "chicken-breast", "greek-yogurt"].compactMap { FoodBook.food($0) } }
        #endif
        let catalog = FoodBook.catalog.map { GymScanItem(id: $0.id, label: String($0.name.prefix(60))) }
        return try await api.foodScan(jpeg: jpeg, catalog: catalog).items.compactMap { FoodBook.food($0) }
    }

    /// A barcode: a food from the catalog when one was scanned before, else Open Food Facts (only the code is sent).
    func lookUpBarcode(_ code: String) async -> Food? {
        let digits = code.filter(\.isNumber)
        guard digits.count >= 8 else { return nil }
        if let known = FuelStore.shared.saved.foods.first(where: { $0.barcode == digits }) { return known }
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json?fields=product_name,nutriments,allergens_tags,ingredients_analysis_tags,serving_quantity") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("MonkeyWorkout iOS - contact@monkeygrade.cloud", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return Food.openFoodFacts(data, barcode: digits)
    }
}
