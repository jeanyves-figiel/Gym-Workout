import SwiftUI
import WorkoutEngine

// Meal plan and groceries (#496): the coming days filled with recipes that fit each day's training, the member's
// picks kept, batch dinners turned into next-day lunches; one grocery list by aisle, minus what's at home.

struct MealPlanView: View {
    @Environment(AppModel.self) private var model
    @State private var store = FuelStore.shared
    @State private var swapping: (key: String, slot: FuelSlot, plan: FuelPlan)?

    var body: some View {
        let cal = Calendar.current
        let days: [Date] = (0..<store.saved.planDays).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: Date())) }
        let plans = days.map { model.fuelPlan(on: $0) }
        let items = model.groceries()
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                options
                Button { withAnimation(.snappy) { model.planMeals() } } label: {
                    Label(store.saved.plan.isEmpty ? "PLAN MY DAYS" : "RE-PLAN (KEEPS YOUR PICKS)", systemImage: "wand.and.stars")
                }
                .buttonStyle(LimeButtonStyle())
                if !store.saved.plan.isEmpty {
                    BasketCard(items: items) { withAnimation(.snappy) { model.planMeals() } }
                    let byKey = Dictionary(zip(days.map { store.key($0) }, plans), uniquingKeysWith: { a, _ in a })
                    if let swap = CheaperSwap.find(plans: byKey, store: store) { swapTip(swap) }
                }
                ForEach(Array(zip(days, plans)), id: \.0) { pair in
                    day(pair.0, plan: pair.1)
                }
                NavigationLink { GroceriesView() } label: {
                    FuelTile(emoji: "🛒", label: "Groceries", title: items.isEmpty ? "Nothing to buy yet" : "\(items.count) items to buy",
                             detail: "By aisle, minus what you have", gradient: FuelPalette.hot) {
                        Image(systemName: "chevron.right").font(.system(size: 15, weight: .heavy))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Meal plan")
        .sheet(isPresented: Binding(get: { swapping != nil }, set: { if !$0 { swapping = nil } })) {
            if let s = swapping { SwapMealSheet(key: s.key, slot: s.slot, plan: s.plan) }
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PLAN").font(Theme.label(10)).tracking(1.2).opacity(0.85)
            HStack(spacing: 6) {
                ForEach([3, 5, 7], id: \.self) { n in
                    option("\(n) days", on: store.saved.planDays == n) { store.setPlanOptions(days: n) }
                }
            }
            HStack(spacing: 6) {
                option("Lunch & dinner", on: store.saved.mainOnly) { store.setPlanOptions(mainOnly: true) }
                option("Every meal", on: !store.saved.mainOnly) { store.setPlanOptions(mainOnly: false) }
            }
            Stepper(value: Binding(get: { store.saved.people }, set: { store.setPlanOptions(people: $0) }), in: 1...8) {
                Text("For \(store.saved.people) \(store.saved.people == 1 ? "person" : "people")").font(Theme.display(16))
            }
            Text("Meals follow each day's training, your diet and favourites, use what you have first, and don't repeat within 3 days. Batch dinners become next day's lunch.")
                .font(.caption.weight(.semibold)).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.violet))
    }

    private func option(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(on ? Theme.ink : .white)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(Capsule().fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(.black.opacity(0.25))))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func swapTip(_ swap: CheaperSwap) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("💡 Save \(BudgetFormat.money(swap.saves))").font(Theme.display(15))
                Text("\(swap.from.emoji) \(swap.from.name) → \(swap.to.emoji) \(swap.to.name), \(model.fuelDayLabel(swap.meal.day))")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button {
                withAnimation(.snappy) {
                    store.pin(PlannedMeal(day: swap.meal.day, slot: swap.meal.slot, kind: swap.meal.kind, recipeId: swap.to.id,
                                          servings: swap.meal.servings))
                }
            } label: {
                Text("SWAP").font(Theme.label(12)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.lime))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
    }

    private func day(_ d: Date, plan: FuelPlan) -> some View {
        let key = store.key(d)
        let meals = store.saved.plan.filter { $0.day == key }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.fuelDayLabel(key)).font(Theme.display(19))
                Text("\(FuelPalette.loadEmoji(plan.load)) \(plan.headline)").font(Theme.label(12)).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer()
            }
            if meals.isEmpty {
                Text("Nothing planned").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            ForEach(plan.slots.filter { s in meals.contains { $0.slot == s.id } }) { s in
                if let m = meals.first(where: { $0.slot == s.id }), let r = RecipeBook.recipe(m.recipeId, own: store.saved.recipes) {
                    HStack(spacing: 8) {
                        NavigationLink(value: r) {
                            VStack(alignment: .leading, spacing: 4) {
                                let cost = m.leftover ? 0 : MealPlanner.cost(r, servings: m.servings, prices: store.saved.prices)
                                Text("\(s.kind.emoji) \(s.title.uppercased()) · \(s.time)\(m.leftover ? " · LEFTOVERS ♻️" : "")\(m.pinned ? " · 📌" : "") · \(BudgetFormat.money(cost))")
                                    .font(Theme.label(10)).foregroundStyle(Theme.muted)
                                RecipeRow(recipe: r)
                            }
                        }
                        .buttonStyle(.plain)
                        Menu {
                            Button("Swap", systemImage: "arrow.triangle.2.circlepath") { swapping = (key, s, plan) }
                            Button("Remove", systemImage: "trash", role: .destructive) { store.unplan(m.id) }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
                                .frame(width: 36, height: 36).background(Circle().fill(Theme.cardStrong))
                        }
                        .accessibilityLabel("Change \(s.title)")
                    }
                }
            }
        }
    }
}

/// Other recipes for one planned meal; the pick is kept on re-plan.
struct SwapMealSheet: View {
    let key: String
    let slot: FuelSlot
    let plan: FuelPlan
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared

    var body: some View {
        let ideas = RecipeBook.ideas(for: slot, load: plan.load, prefs: store.prefs, favourites: store.saved.favourites,
                                     own: store.saved.recipes, day: key + "swap", count: 12)
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(ideas) { r in
                        Button {
                            store.pin(PlannedMeal(day: key, slot: slot.id, kind: slot.kind, recipeId: r.id, servings: store.saved.people))
                            dismiss()
                        } label: { RecipeRow(recipe: r) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Swap \(slot.title.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
    }
}

struct GroceriesView: View {
    @Environment(AppModel.self) private var model
    @State private var store = FuelStore.shared
    @State private var pricing: Food?

    var body: some View {
        let items = model.groceries()
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if items.isEmpty {
                    VStack(spacing: 12) {
                        Text("🛒").font(.system(size: 50))
                        Text("Plan some meals and the list fills itself.").font(.headline).multilineTextAlignment(.center)
                        NavigationLink { MealPlanView() } label: { Text("OPEN MEAL PLAN") }
                            .buttonStyle(LimeButtonStyle())
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    let bought = items.filter { store.saved.bought.contains($0.id) }.count
                    BasketCard(items: items) { withAnimation(.snappy) { model.planMeals() } }
                    Text("\(items.count - bought) to buy · \(bought) in the basket · tap a price to change it")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                    let spare = items.filter { $0.food.perishable && $0.spare >= 50 }.sorted { $0.spare > $1.spare }.prefix(2)
                    ForEach(Array(spare)) { i in
                        Text("♻️ \(Int(i.spare)) g \(i.food.name.lowercased()) left over after the plan: add a meal with it, or freeze it.")
                            .font(.caption.weight(.semibold)).foregroundStyle(.white)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                    }
                    ForEach(MealPlanner.aisles, id: \.id) { a in
                        let group = items.filter { $0.aisle == a.id }
                        if !group.isEmpty {
                            Text("\(a.emoji) \(a.label)").font(Theme.display(17)).padding(.top, 4)
                            ForEach(group) { i in row(i) }
                        }
                    }
                    if bought > 0 {
                        Button { withAnimation { store.stockBought(items) } } label: {
                            Label("PUT \(bought) IN WHAT I HAVE", systemImage: "refrigerator.fill")
                        }
                        .buttonStyle(LimeButtonStyle())
                    }
                }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Groceries")
        .sheet(item: $pricing) { PriceSheet(food: $0).presentationDetents([.medium]) }
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: MealPlanner.shareText(items)) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share the list")
                }
            }
        }
    }

    private func packText(_ i: GroceryItem) -> String {
        guard let packs = i.packs, let size = i.food.pack else { return i.amount }
        let unit = i.food.group == .drink ? "ml" : "g"
        let pack = size >= 1000 ? String(format: "%g %@", size / 1000, unit == "ml" ? "l" : "kg") : "\(Int(size)) \(unit)"
        return "\(Int(i.grams.rounded())) \(unit) needed · \(packs)× \(pack)"
    }

    private func row(_ i: GroceryItem) -> some View {
        let on = store.saved.bought.contains(i.id)
        return Button { withAnimation(.snappy) { store.toggleBought(i.id) } } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(on ? Theme.lime : Theme.muted)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(i.food.emoji) \(i.food.name)").font(.body.weight(.bold)).strikethrough(on)
                        Spacer()
                        if let cost = i.cost {
                            Button { pricing = i.food } label: {
                                Text(BudgetFormat.short(cost)).font(Theme.display(15)).monospacedDigit()
                                    .foregroundStyle(store.saved.prices[i.food.id] != nil ? Theme.lime : .white)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Price \(BudgetFormat.money(cost)), change")
                        }
                    }
                    Text(packText(i)).font(Theme.label(11)).foregroundStyle(Theme.muted)
                    Text(i.meals.prefix(3).joined(separator: " · ") + (i.meals.count > 3 ? " +\(i.meals.count - 3)" : ""))
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted).lineLimit(2)
                }
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .opacity(on ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
