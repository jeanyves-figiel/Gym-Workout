import SwiftUI
import WorkoutEngine

// Meal plan budget and less waste (#496, design C + B from `nutrition-pointers/section-budget.png`): a Basket card
// on the plan (cost against the weekly budget, how much of the fresh food bought gets eaten, Cheaper / Less waste /
// Budget), prices and spare per grocery line, and a cheaper swap for the priciest meal.

enum BudgetLevel: String, CaseIterable, Identifiable {
    case saver, normal, treat

    var id: String { rawValue }
    var label: String {
        switch self {
        case .saver: "Saver"
        case .normal: "Normal"
        case .treat: "Treat"
        }
    }
    var emoji: String {
        switch self {
        case .saver: "💰"
        case .normal: "🛒"
        case .treat: "✨"
        }
    }

    /// CHF a week per person for every meal (lunch and dinner only: 60 %).
    func weekly(people: Int, mainOnly: Bool) -> Double {
        let base: Double = switch self {
        case .saver: 50
        case .normal: 75
        case .treat: 110
        }
        return (base * Double(people) * (mainOnly ? 0.6 : 1) / 5).rounded() * 5
    }
}

enum BudgetFormat {
    static func chf(_ v: Double) -> String { v >= 100 ? "CHF \(Int(v.rounded()))" : String(format: "CHF %.2f", v) }
    static func short(_ v: Double) -> String { v >= 100 ? "\(Int(v.rounded()))" : String(format: "%.2f", v) }
}

/// Top of the meal plan: the week basket.
struct BasketCard: View {
    let items: [GroceryItem]
    let replan: () -> Void
    @State private var store = FuelStore.shared
    @State private var editing = false

    var body: some View {
        let basket = MealPlanner.basket(items)
        let weekly = store.saved.budget
        let budget = weekly.map { $0 * Double(store.saved.planDays) / 7 }
        let meals = store.saved.plan.count
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("WEEK BASKET").font(Theme.label(10)).tracking(1.2).opacity(0.85)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("CHF \(Int(basket.cost.rounded()))").font(Theme.display(32)).monospacedDigit()
                        if let budget { Text("/ \(Int(budget.rounded()))").font(Theme.display(17)).opacity(0.75) }
                    }
                    Text("\(store.saved.planDays) days · \(store.saved.people) \(store.saved.people == 1 ? "person" : "people") · \(meals) meals")
                        .font(Theme.label(11)).opacity(0.9)
                    if let budget {
                        let over = basket.cost - budget
                        Text(over > 0 ? "CHF \(Int(over.rounded())) over budget" : "CHF \(Int((-over).rounded())) under budget")
                            .font(Theme.label(11)).foregroundStyle(over > 0 ? Color(hex: 0xFFE14D) : .white)
                    }
                }
                Spacer(minLength: 0)
                UsedRing(used: basket.used)
            }
            HStack(spacing: 6) {
                chip("💰 Cheaper", on: false) {
                    // 15 % under what the plan costs now, then re-plan (picks stay).
                    let now = basket.cost * 7 / Double(max(1, store.saved.planDays))
                    store.setBudget(max(10, (min(now, store.saved.budget ?? now) * 0.85 / 5).rounded() * 5))
                    replan()
                }
                chip("♻️ Less waste", on: store.saved.lessWaste) {
                    store.setPlanOptions(lessWaste: !store.saved.lessWaste)
                    replan()
                }
                chip("✏️ Budget", on: false) { editing = true }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.gradient(0x7A3DFF, 0xFF3DA8)))
        .sheet(isPresented: $editing) { BudgetSheet(replan: replan).presentationDetents([.medium]) }
        .accessibilityElement(children: .contain)
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.label(12)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(Capsule().fill(on || title.hasPrefix("💰") ? Theme.lime : Color.white.opacity(0.85)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Share of the fresh food bought that the plan eats.
private struct UsedRing: View {
    let used: Double

    var body: some View {
        ZStack {
            Circle().stroke(.black.opacity(0.3), lineWidth: 8)
            Circle().trim(from: 0, to: min(1, max(0.02, used)))
                .stroke(Theme.lime, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((used * 100).rounded()))%").font(Theme.display(17)).monospacedDigit()
                Text("PACKS USED").font(Theme.label(7))
            }
        }
        .frame(width: 74, height: 74)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((used * 100).rounded())) percent of fresh packs used")
    }
}

/// Weekly budget: a level or an amount, or no limit.
struct BudgetSheet: View {
    let replan: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared
    @State private var amount: Double = 75
    @State private var limit = true

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    ForEach(BudgetLevel.allCases) { level in
                        let v = level.weekly(people: store.saved.people, mainOnly: store.saved.mainOnly)
                        let on = limit && abs(v - amount) < 0.5
                        Button {
                            amount = v
                            limit = true
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(level.emoji) \(level.label)").font(Theme.label(13))
                                Text("CHF \(Int(v))").font(Theme.label(11)).opacity(0.8)
                            }
                            .foregroundStyle(on ? Theme.ink : .white)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.card)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                Toggle(isOn: $limit) { Text("Weekly budget").font(Theme.display(17)) }
                    .tint(Theme.lime)
                if limit {
                    Text("CHF \(Int(amount)) a week").font(Theme.display(30)).monospacedDigit()
                    Slider(value: $amount, in: 20...400, step: 5).tint(Theme.lime)
                    Text("For \(store.saved.people) \(store.saved.people == 1 ? "person" : "people"), \(store.saved.mainOnly ? "lunch and dinner" : "every meal"). Prices are Swiss supermarket averages; change one from the grocery list.")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("SAVE AND RE-PLAN") {
                    store.setBudget(limit ? amount : nil)
                    replan()
                    dismiss()
                }
                .buttonStyle(LimeButtonStyle())
            }
            .padding(16)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .onAppear {
                limit = store.saved.budget != nil
                amount = store.saved.budget ?? BudgetLevel.normal.weekly(people: store.saved.people, mainOnly: store.saved.mainOnly)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// The priciest planned meal and a cheaper recipe for the same slot with about as much protein.
struct CheaperSwap {
    let meal: PlannedMeal
    let from: Recipe
    let to: Recipe
    let saves: Double

    @MainActor
    static func find(plans: [String: FuelPlan], store: FuelStore) -> CheaperSwap? {
        let own = store.saved.recipes
        let priced = store.saved.plan.filter { !$0.pinned && !$0.leftover }.compactMap { m -> (PlannedMeal, Recipe, Double)? in
            guard let r = RecipeBook.recipe(m.recipeId, own: own) else { return nil }
            return (m, r, MealPlanner.cost(r, servings: m.servings, prices: store.saved.prices))
        }
        guard let top = priced.max(by: { $0.2 < $1.2 }), let plan = plans[top.0.day],
              let slot = plan.slots.first(where: { $0.id == top.0.slot }) else { return nil }
        let ideas = RecipeBook.ideas(for: slot, load: plan.load, prefs: store.prefs, favourites: store.saved.favourites,
                                     own: own, day: top.0.day + "cheap", count: 20)
        let options = ideas.filter { $0.id != top.1.id && Double($0.protein) >= Double(top.1.protein) * 0.8 }
            .map { ($0, MealPlanner.cost($0, servings: top.0.servings, prices: store.saved.prices)) }
        guard let best = options.min(by: { $0.1 < $1.1 }), top.2 - best.1 >= 1 else { return nil }
        return CheaperSwap(meal: top.0, from: top.1, to: best.0, saves: top.2 - best.1)
    }
}

/// Price per kg for one food, set from the grocery list.
struct PriceSheet: View {
    let food: Food
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(food.emoji) \(food.name)").font(Theme.display(22))
                Text("Estimate: CHF \(BudgetFormat.short(food.price ?? 0)) per \(food.group == .drink ? "litre" : "kg")")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                TextField("Your price, CHF per \(food.group == .drink ? "litre" : "kg")", text: $text)
                    .keyboardType(.decimalPad)
                    .card(padding: 14)
                Spacer()
                Button("SAVE") {
                    store.setPrice(food.id, Double(text.replacingOccurrences(of: ",", with: ".")))
                    dismiss()
                }
                .buttonStyle(LimeButtonStyle())
                if store.saved.prices[food.id] != nil {
                    Button("Use the estimate") {
                        store.setPrice(food.id, nil)
                        dismiss()
                    }
                    .font(Theme.label(14)).frame(maxWidth: .infinity)
                }
            }
            .padding(16)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .onAppear { text = store.saved.prices[food.id].map { BudgetFormat.short($0) } ?? "" }
        }
        .preferredColorScheme(.dark)
    }
}
