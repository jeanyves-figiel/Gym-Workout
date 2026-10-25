import SwiftUI
import WorkoutEngine

// Fuel home (#733, mix of A "Fuel Tank" + C "Magic Snap" from `fuel-redesign/a.png`, `c.png`): what's left today in one
// tank card, one LOG button, the next meal, then the Kitchen squares. One look for everyone; "Hands" is the no-numbers
// setting.

/// Today's tank: load, headline, how fuelled, and protein / carbs / water / caffeine squares. Water adds a glass with a
/// tap (hold for pace and reminders); caffeine opens the stack.
struct FuelTankCard: View {
    let plan: FuelPlan
    let log: FuelDayLog
    let day: Date
    @State private var store = FuelStore.shared
    @State private var water = false
    @State private var stack = false

    var body: some View {
        let prefs = store.prefs
        let fuelled = log.fuelled(plan)
        let grams = log.eatenGrams(plan)
        let caffeine = Supplements.caffeineTaken(plan.supplements, log: log)
        let future = Calendar.current.startOfDay(for: day) > Calendar.current.startOfDay(for: Date())
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(FuelPalette.loadEmoji(plan.load)).font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.2)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(dayLabel) · \(plan.load.label.uppercased())").font(Theme.label(10)).tracking(1.2).opacity(0.85).lineLimit(1)
                    Text(plan.headline).font(Theme.display(19)).lineLimit(2).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int((fuelled * 100).rounded()))%").font(Theme.display(30)).monospacedDigit()
                    Text("FUELLED").font(Theme.label(9)).opacity(0.85)
                }
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 6) {
                FuelStat(value: prefs.noNumbers ? "\(log.eaten.palms)/\(plan.portions.palms)" : "\(grams.protein)/\(plan.protein)",
                         label: prefs.noNumbers ? "Protein ✋" : "Protein g",
                         progress: Double(log.eaten.palms) / Double(max(1, plan.portions.palms)))
                FuelStat(value: prefs.noNumbers ? "\(log.eaten.cups)/\(plan.portions.cups)" : "\(grams.carbs)/\(plan.carbs)",
                         label: prefs.noNumbers ? "Carbs ✊" : "Carbs g",
                         progress: Double(log.eaten.cups) / Double(max(1, plan.portions.cups)), bar: Color(hex: 0xFFD23D))
                FuelStat(value: "\(log.glasses)/\(plan.glasses)", label: "Water 💧",
                         progress: Double(log.glasses) / Double(max(1, plan.glasses)), bar: Color(hex: 0x9BEBFF))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if future { water = true } else { store.update(day, plan: plan) { $0.glasses += 1 } }
                    }
                    .onLongPressGesture { water = true }
                    .sensoryFeedback(.increase, trigger: log.glasses)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Water, \(log.glasses) of \(plan.glasses) glasses")
                    .accessibilityHint("Adds a glass. Hold for pace and reminders.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("fuel.tank.water")
                Button { stack = true } label: {
                    FuelStat(value: "\(caffeine)", label: "Caffeine mg",
                             progress: Double(caffeine) / Double(Supplements.caffeineGuideMg), bar: Color(hex: 0xFF9F1C))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Caffeine, \(caffeine) of \(Supplements.caffeineGuideMg) milligrams")
            }
            if plan.estimated && !prefs.noNumbers {
                Text("Add your weight in Body & Health for exact numbers.").font(.caption2.weight(.bold)).opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(FuelPalette.load(plan.load)))
        .sheet(isPresented: $water) { WaterSheet(plan: plan, glasses: log.glasses, day: day) }
        .sheet(isPresented: $stack) { FuelStackSheet(plan: plan, day: day) }
    }

    private var dayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "TODAY" }
        if cal.isDateInTomorrow(day) { return "TOMORROW" }
        if cal.isDateInYesterday(day) { return "YESTERDAY" }
        return day.formatted(.dateTime.weekday(.wide)).uppercased()
    }
}

/// The one way in to logging: opens the Log sheet (Magic Snap first, search, usuals, by hand).
struct FuelLogButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "camera.fill").font(.system(size: 19, weight: .black))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.black.opacity(0.12)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("LOG WHAT I ATE").font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.7)
                    Text("Snap · search · usual · by hand").font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.75)
                }
                Spacer(minLength: 4)
                Image(systemName: "plus").font(.system(size: 22, weight: .black))
            }
            .foregroundStyle(Theme.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.lime))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log what I ate")
        .accessibilityIdentifier("fuel.log")
    }
}

/// The next meal: the planned recipe (Ate it / Swap / Other) and the one after it, else the plate to aim for with ideas.
struct FuelNextCard: View {
    let plan: FuelPlan
    let log: FuelDayLog
    let day: Date
    let open: (FuelSlot) -> Void
    @State private var store = FuelStore.shared

    var body: some View {
        let cal = Calendar.current
        let now = cal.isDateInToday(day) ? cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date()) : 0
        let next = plan.next(after: now)
        let key = store.key(day)
        let plannedSlots = plan.slots.filter { s in s.minute >= now - 30 && store.saved.plan.contains { $0.day == key && $0.slot == s.id } }
        if let first = plannedSlots.first, let meal = store.saved.plan.first(where: { $0.day == key && $0.slot == first.id }),
           let recipe = RecipeBook.recipe(meal.recipeId, own: store.recipeLookup) {
            PlannedPlateCard(slot: first, recipe: recipe, meal: meal, plan: plan, log: log, day: day, open: open)
            if plannedSlots.count > 1, let m = store.saved.plan.first(where: { $0.day == key && $0.slot == plannedSlots[1].id }),
               let r = RecipeBook.recipe(m.recipeId, own: store.recipeLookup) {
                ThenMealCard(slot: plannedSlots[1], recipe: r, meal: m)
            }
        } else if let next {
            VStack(alignment: .leading, spacing: 8) {
                Button { open(next) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("NEXT · \(next.title.uppercased())").font(Theme.label(10)).tracking(1.2).opacity(0.85)
                            Spacer()
                            Text(next.time).font(Theme.label(12))
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy))
                        }
                        PlateBar(portions: next.portions)
                        Text(next.hint).font(.system(size: 12, weight: .bold, design: .rounded)).opacity(0.9)
                            .multilineTextAlignment(.leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                FuelIdeaChips(slot: next, plan: plan)
                if cal.isDateInToday(day) { FuelSlotActions(slot: next, day: day) }
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.violet))
        }
    }
}

/// Kitchen (#733): What I have, Meal plan, Groceries and My stack as square cards with live numbers, then Recipes,
/// Fuel week, Learn and Settings as chips.
struct FuelKitchen: View {
    let plan: FuelPlan
    let day: Date
    let settings: () -> Void
    @Environment(AppModel.self) private var model
    @State private var store = FuelStore.shared
    @State private var stack = false

    var body: some View {
        let today = store.key(Date())
        let coming = store.saved.plan.filter { $0.day >= today }
        let days = Set(coming.map(\.day)).count
        let pantry = store.saved.pantry.count
        let ready = pantry == 0 ? 0 : Pantry.recipes(have: store.pantryIds, prefs: store.prefs, own: store.saved.recipes, missing: 0).count
        let groceries = coming.isEmpty ? [] : model.groceries()
        let doses = plan.supplements
        let log = store.log(day)
        let taken = doses.filter { log.ticks[$0.id] != nil }.count
        let due = doses.first { log.ticks[$0.id] == nil }
        VStack(alignment: .leading, spacing: 8) {
            Text("KITCHEN").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted).padding(.top, 2)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                NavigationLink(value: FuelRoute.pantry) {
                    square("🧊", "What I have", pantry > 0 ? "\(pantry)" : nil,
                           pantry == 0 ? "Snap or type your fridge" : ready > 0 ? "\(ready) recipe\(ready == 1 ? "" : "s") ready" : "foods at home",
                           FuelPalette.mint)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fuel.pantry")
                NavigationLink(value: FuelRoute.mealPlan) {
                    square("🗓️", "Meal plan", days > 0 ? "\(days)" : nil, days > 0 ? "day\(days == 1 ? "" : "s") planned" : "Plan your week",
                           FuelPalette.violet)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fuel.plan")
                NavigationLink(value: FuelRoute.groceries) {
                    square("🛒", "Groceries", groceries.isEmpty ? nil : "\(groceries.count)",
                           groceries.isEmpty ? "Fills from your plan" : "\(BudgetFormat.money(MealPlanner.basket(groceries).cost.rounded())) basket",
                           FuelPalette.hot)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fuel.buy")
                Button { stack = true } label: {
                    square("💊", "My stack", doses.isEmpty ? nil : "\(taken)/\(doses.count)",
                           store.stack.isEmpty ? "Add your supplements"
                               : due.map { "\($0.supplement.name) \(Supplements.clock($0.minute))" } ?? (doses.isEmpty ? "Nothing today" : "All taken ✓"),
                           FuelPalette.coach)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fuel.supplements")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(.recipes(nil), "📖 Recipes", id: "fuel.recipes")
                    chip(.week, "📈 Fuel week", id: "fuel.week")
                    chip(.learn, "🎓 Learn", id: "fuel.learn")
                    Button(action: settings) { chipLabel("⚙️ Settings") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Your fuel settings")
                }
            }
            .scrollClipDisabled()
        }
        .sheet(isPresented: $stack) { FuelStackSheet(plan: plan, day: day) }
    }

    private func square(_ emoji: String, _ title: String, _ number: String?, _ detail: String, _ g: LinearGradient) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(emoji).font(.system(size: 18))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.2)))
                Spacer(minLength: 4)
                if let number { Text(number).font(Theme.display(26)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6) }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.display(15)).lineLimit(1).minimumScaleFactor(0.8)
                Text(detail).font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.75)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(g))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func chip(_ route: FuelRoute, _ text: String, id: String) -> some View {
        NavigationLink(value: route) { chipLabel(text) }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
    }

    private func chipLabel(_ text: String) -> some View {
        Text(text).font(Theme.label(12)).lineLimit(1).foregroundStyle(.white)
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
    }
}

/// My stack and the caffeine meter in a sheet, from the Kitchen square or the caffeine square; add tile and quick squares under it (#742).
struct FuelStackSheet: View {
    let plan: FuelPlan
    let day: Date
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    FuelStackCard(plan: plan, log: store.log(day), day: day)
                    // The empty card is itself the add tile.
                    if !store.stack.isEmpty { SupplementAddPanel() }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("My stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
            .fuelDestinations()
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }
}
