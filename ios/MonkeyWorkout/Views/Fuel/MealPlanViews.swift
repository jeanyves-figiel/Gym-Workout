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
                                Text("\(s.kind.emoji) \(s.title.uppercased()) · \(s.time)\(m.leftover ? " · LEFTOVERS" : "")\(m.pinned ? " · 📌" : "")")
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
                    FuelTile(emoji: "🛒", label: "Groceries", title: "\(items.count - bought) to buy",
                             detail: "\(bought) in the basket · for \(store.saved.plan.filter { !$0.leftover }.count) meals", gradient: FuelPalette.hot)
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
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: MealPlanner.shareText(items)) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share the list")
                }
            }
        }
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
                        Text(i.amount).font(Theme.label(12)).foregroundStyle(Theme.muted).multilineTextAlignment(.trailing)
                    }
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
