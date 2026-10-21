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

    /// CHF a week per person for every meal; `share` = part of the week's 21 main meals planned (#558).
    func weekly(people: Int, share: Double) -> Double {
        let base: Double = switch self {
        case .saver: 50
        case .normal: 75
        case .treat: 110
        }
        return (base * Double(people) * max(0.1, min(1, share)) / 5).rounded() * 5
    }
}

/// Where the member shops: the currency and how local grocery prices compare with the Swiss estimates.
/// `factor` = local money for what costs CHF 1 in a Swiss supermarket (exchange rate × price level, 2026 averages).
struct FuelMarket: Identifiable, Hashable {
    let id: String
    let currency: String
    let label: String
    let factor: Double

    static let all: [FuelMarket] = [
        .init(id: "CH", currency: "CHF", label: "Switzerland", factor: 1),
        .init(id: "DE", currency: "EUR", label: "Germany", factor: 0.62),
        .init(id: "FR", currency: "EUR", label: "France", factor: 0.72),
        .init(id: "IT", currency: "EUR", label: "Italy", factor: 0.68),
        .init(id: "AT", currency: "EUR", label: "Austria", factor: 0.72),
        .init(id: "ES", currency: "EUR", label: "Spain", factor: 0.58),
        .init(id: "NL", currency: "EUR", label: "Netherlands", factor: 0.65),
        .init(id: "BE", currency: "EUR", label: "Belgium", factor: 0.70),
        .init(id: "LI", currency: "CHF", label: "Liechtenstein", factor: 1),
        .init(id: "GB", currency: "GBP", label: "United Kingdom", factor: 0.55),
        .init(id: "US", currency: "USD", label: "United States", factor: 0.85),
        .init(id: "CA", currency: "CAD", label: "Canada", factor: 1.05),
        .init(id: "AU", currency: "AUD", label: "Australia", factor: 1.15),
        .init(id: "SE", currency: "SEK", label: "Sweden", factor: 7.2),
        .init(id: "NO", currency: "NOK", label: "Norway", factor: 8.5),
        .init(id: "DK", currency: "DKK", label: "Denmark", factor: 5.0),
        .init(id: "PL", currency: "PLN", label: "Poland", factor: 2.6),
        .init(id: "CZ", currency: "CZK", label: "Czechia", factor: 15),
        .init(id: "JP", currency: "JPY", label: "Japan", factor: 120),
    ]

    /// The member's pick, else the phone's region, else its currency, else Switzerland.
    static func current(_ picked: String?) -> FuelMarket {
        if let picked, let m = all.first(where: { $0.id == picked }) { return m }
        if let region = Locale.current.region?.identifier, let m = all.first(where: { $0.id == region }) { return m }
        if let code = Locale.current.currency?.identifier, let m = all.first(where: { $0.currency == code }) { return m }
        return all[0]
    }

    /// Slider and level steps in this money.
    var step: Double { max(1, (5 * factor).rounded()) }
}

/// Amounts are kept in CHF (the price estimates' money) and shown in the member's money.
@MainActor
enum BudgetFormat {
    static var market: FuelMarket { FuelMarket.current(FuelStore.shared.saved.market) }

    static func local(_ chf: Double) -> Double { chf * market.factor }
    static func toCHF(_ local: Double) -> Double { local / market.factor }

    /// "CHF 74", "€4.90".
    static func money(_ chf: Double) -> String {
        let v = local(chf)
        return v.formatted(.currency(code: market.currency).precision(.fractionLength(v >= 100 || market.factor >= 5 ? 0 : 2)))
    }

    /// Number only ("4.90").
    static func short(_ chf: Double) -> String {
        let v = local(chf)
        return v >= 100 || market.factor >= 5 ? "\(Int(v.rounded()))" : String(format: "%.2f", v)
    }

    /// Whole amount in local money, rounded to the slider step.
    static func whole(_ chf: Double) -> Double { (local(chf) / market.step).rounded() * market.step }
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
        let budget = weekly.map { $0 * Double(store.planSpan) / 7 }
        let meals = store.saved.plan.count
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.planSpan > 7 ? "PLAN BASKET" : "WEEK BASKET").font(Theme.label(10)).tracking(1.2).opacity(0.85)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(BudgetFormat.money(basket.cost.rounded())).font(Theme.display(32)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                        if let budget { Text("/ \(Int(BudgetFormat.local(budget).rounded()))").font(Theme.display(17)).opacity(0.75) }
                    }
                    Text("\(store.planSpan) days · \(store.saved.people) \(store.saved.people == 1 ? "person" : "people") · \(meals) meals")
                        .font(Theme.label(11)).opacity(0.9)
                    if let budget {
                        let over = basket.cost - budget
                        Text(over > 0 ? "\(BudgetFormat.money(over.rounded())) over budget" : "\(BudgetFormat.money((-over).rounded())) under budget")
                            .font(Theme.label(11)).foregroundStyle(over > 0 ? Color(hex: 0xFFE14D) : .white)
                    }
                }
                Spacer(minLength: 0)
                UsedRing(used: basket.used)
            }
            HStack(spacing: 6) {
                chip("💰 Cheaper", on: false) {
                    // 15 % under what the plan costs now, then re-plan (picks stay).
                    let now = basket.cost * 7 / Double(max(1, store.planSpan))
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
    private var market: FuelMarket { FuelMarket.current(store.saved.market) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    ForEach(BudgetLevel.allCases) { level in
                        let v = BudgetFormat.whole(level.weekly(people: store.saved.people, share: store.mealShare))
                        let on = limit && abs(v - amount) < 0.5
                        Button {
                            amount = v
                            limit = true
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(level.emoji) \(level.label)").font(Theme.label(13))
                                Text(v.formatted(.currency(code: market.currency).precision(.fractionLength(0)))).font(Theme.label(11)).opacity(0.8)
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
                    Text("\(amount.formatted(.currency(code: market.currency).precision(.fractionLength(0)))) a week")
                        .font(Theme.display(30)).monospacedDigit()
                    Slider(value: $amount, in: (20 * market.factor).rounded()...(400 * market.factor).rounded(), step: market.step)
                        .tint(Theme.lime)
                    Text("For \(store.saved.people) \(store.saved.people == 1 ? "person" : "people"), \(Int((store.mealShare * 21).rounded())) meals a week. Prices are estimates for \(market.label); change one from the grocery list.")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                Menu {
                    ForEach(FuelMarket.all) { m in
                        Button("\(m.label) · \(m.currency)") {
                            let chf = BudgetFormat.toCHF(amount)
                            store.setMarket(m.id)
                            amount = BudgetFormat.whole(chf)
                        }
                    }
                } label: {
                    Label("Prices for \(market.label) · \(market.currency)", systemImage: "globe.europe.africa.fill")
                        .font(Theme.label(13)).foregroundStyle(Theme.lime)
                }
                Spacer()
                Button("SAVE AND RE-PLAN") {
                    store.setBudget(limit ? BudgetFormat.toCHF(amount) : nil)
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
                amount = BudgetFormat.whole(store.saved.budget ?? BudgetLevel.normal.weekly(people: store.saved.people, share: store.mealShare))
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
                Text("Estimate: \(BudgetFormat.money(food.price ?? 0)) per \(food.group == .drink ? "litre" : "kg")")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                TextField("Your price, \(BudgetFormat.market.currency) per \(food.group == .drink ? "litre" : "kg")", text: $text)
                    .keyboardType(.decimalPad)
                    .card(padding: 14)
                if BudgetFormat.market.id == "CH" {
                    HStack(spacing: 8) {
                        ShopLink(name: "Migros", food: food)
                        ShopLink(name: "Coop", food: food)
                    }
                }
                Spacer()
                Button("SAVE") {
                    store.setPrice(food.id, Double(text.replacingOccurrences(of: ",", with: ".")).map(BudgetFormat.toCHF))
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

/// Opens the retailer's online shop search for a food (no API: a plain link, nothing is sent from the app).
struct ShopLink: View {
    let name: String
    let food: Food

    static func url(_ name: String, _ food: Food) -> URL? {
        let q = food.name.replacingOccurrences(of: #"\s*\(.*\)"#, with: "", options: .regularExpression)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return switch name {
        case "Migros": URL(string: "https://www.migros.ch/en/search?query=\(q)")
        default: URL(string: "https://www.coop.ch/en/search/?text=\(q)")
        }
    }

    var body: some View {
        if let url = Self.url(name, food) {
            Link(destination: url) {
                Label("Find at \(name)", systemImage: "arrow.up.right.square")
                    .font(Theme.label(13)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Capsule().fill(name == "Migros" ? Color(hex: 0xFF8A3D) : Color(hex: 0xFF5A4D)))
            }
        }
    }
}
