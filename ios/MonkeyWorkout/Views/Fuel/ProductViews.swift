import SwiftUI
import WorkoutEngine

/// Brands and their variants (#599, design B): Huel Black, yfood… with typical label amounts, a serving size, then the
/// pick goes back to the caller (saved straight to Mine from Just ate and the meal plan, or opened in the supplement
/// editor to give it a schedule).
struct ProductCatalogSheet: View {
    /// Button title: "Save to Mine" or "Next".
    var action = "Save to Mine"
    let picked: (Supplement, Double) -> Void
    /// "Not listed": the member types their own.
    var own: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var brand: String?
    @State private var variant: Supplement?
    @State private var servings = 1.0

    private static let colours: [LinearGradient] = [FuelPalette.hot, FuelPalette.violet, FuelPalette.mint, FuelPalette.coach,
                                                     FuelPalette.water, FuelPalette.protein]

    var body: some View {
        let brands = ProductCatalog.search(query)
        let open = brands.first { $0.id == brand } ?? (query.isEmpty ? nil : brands.first)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Brand or product", text: $query)
                        .font(Theme.label(15)).padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                        .submitLabel(.search)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach(Array(brands.enumerated()), id: \.element.id) { i, b in
                            Button { withAnimation(.snappy) { brand = b.id; variant = nil } } label: {
                                Text(b.name).font(Theme.display(18)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .bottomLeading)
                                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Self.colours[i % Self.colours.count]))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Theme.lime, lineWidth: open?.id == b.id ? 3 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(open?.id == b.id ? .isSelected : [])
                        }
                    }
                    if let open {
                        Text("\(open.name.uppercased()) · VARIANTS").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted).padding(.top, 8)
                        ForEach(open.variants) { s in row(s, on: variant?.id == s.id) }
                    }
                    if let variant {
                        servingsPicker
                        let one = ProductCatalog.mine(variant, servings: servings, onDemand: true)
                        Button {
                            picked(variant, servings)
                            dismiss()
                        } label: {
                            Text("\(action) · \(one.kcal > 0 ? "\(one.kcal) kcal" : one.dose)").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LimeButtonStyle())
                    }
                    if let own {
                        Button {
                            dismiss()
                            own()
                        } label: {
                            Text("Not listed? Add my own").font(Theme.label(13)).foregroundStyle(Theme.lime)
                                .frame(maxWidth: .infinity).padding(12)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("≈ typical label values: recipes change, so check your label. You can scan it after saving.")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add a product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ s: Supplement, on: Bool) -> some View {
        Button { withAnimation(.snappy) { variant = s } } label: {
            HStack(spacing: 10) {
                Text(s.emoji).font(.system(size: 20)).frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SupplementsView.gradient(s.kind)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(Theme.display(15)).lineLimit(1).minimumScaleFactor(0.75)
                    Text(Self.line(s)).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Theme.lime).lineLimit(1)
                }
                Spacer(minLength: 4)
                if on { Image(systemName: "checkmark").font(.system(size: 14, weight: .black)).foregroundStyle(Theme.lime) }
            }
            .foregroundStyle(.white)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.lime, lineWidth: on ? 2 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var servingsPicker: some View {
        HStack(spacing: 4) {
            ForEach([0.5, 1, 1.5, 2], id: \.self) { n in
                Button { servings = n } label: {
                    Text(n == 1 ? "1 serving" : n == 0.5 ? "½" : n == 1.5 ? "1½" : "2")
                        .font(Theme.label(12)).foregroundStyle(servings == n ? Theme.ink : .white)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(servings == n ? Theme.lime : Theme.cardStrong))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(servings == n ? .isSelected : [])
            }
        }
        .padding(.top, 4)
    }

    /// "400 kcal · 40 P · 24 C · 17 F", "150 mg caffeine", "5 g creatine".
    static func line(_ s: Supplement) -> String {
        if s.kcal > 0 && (s.carbsG > 0 || s.fatG > 0) {
            return "\(s.kcal) kcal · \(Int(s.proteinG.rounded())) P · \(Int(s.carbsG.rounded())) C · \(Int(s.fatG.rounded())) F"
        }
        guard let first = s.contents.first else { return s.dose }
        return String(first.drop { c in !c.isNumber })
    }
}

/// The member's products in Just ate (#599, design A): meal shakes fill the meal, other supplements tick today's take
/// (or count as an extra one), "+" adds one from a brand.
struct MineStrip: View {
    let plan: FuelPlan
    let day: Date
    /// A meal product picked: fills the meal.
    let eat: (Recipe) -> Void
    @State private var store = FuelStore.shared
    @State private var adding = false

    var body: some View {
        let log = store.log(day)
        let meals = store.stack.filter(\.isMeal)
        let doses = plan.supplements.filter { !$0.supplement.isMeal && !log.taken($0) }
        let extras = store.stack.filter { !$0.isMeal && $0.whenPicked }
        VStack(alignment: .leading, spacing: 6) {
            Text("MINE").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted).padding(.top, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(meals) { s in
                        tile(s.emoji, s.name, "\(s.kcal) kcal · \(Int(s.proteinG.rounded())) g P", SupplementsView.gradient(s.kind)) { eat(s.recipe) }
                    }
                    ForEach(doses) { d in
                        tile(d.supplement.emoji, d.supplement.name, d.time, SupplementsView.gradient(d.supplement.kind)) {
                            Haptics.success()
                            store.update(day, plan: plan) { $0.tick(d) }
                        }
                    }
                    ForEach(extras) { s in
                        tile(s.emoji, s.name, ProductCatalogSheet.line(s), SupplementsView.gradient(s.kind)) {
                            Haptics.success()
                            let cal = Calendar.current
                            let minute = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
                            store.update(day, plan: plan) { log in
                                let dose = Supplements.extra(s, log: log, minute: minute)
                                log.tick(dose)
                            }
                        }
                    }
                    Button { adding = true } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 20, weight: .black))
                            Text("Shake or\nsupplement").font(Theme.label(10)).multilineTextAlignment(.center)
                        }
                        .foregroundStyle(Theme.lime)
                        .frame(width: 104, height: 96)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.lime, style: StrokeStyle(lineWidth: 1.5, dash: [5])))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a shake or supplement")
                }
            }
        }
        .sheet(isPresented: $adding) {
            ProductCatalogSheet { v, n in store.saveSupplement(ProductCatalog.mine(v, servings: n, onDemand: true)) }
        }
    }

    private func tile(_ emoji: String, _ name: String, _ note: String, _ fill: LinearGradient, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Text(emoji).font(.system(size: 20))
                    Spacer(minLength: 2)
                    Image(systemName: "plus").font(.system(size: 11, weight: .black)).foregroundStyle(Theme.ink)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.lime))
                }
                Spacer(minLength: 0)
                Text(name).font(Theme.display(13)).lineLimit(2).minimumScaleFactor(0.75).multilineTextAlignment(.leading)
                Text(note).font(.system(size: 10, weight: .bold, design: .rounded)).opacity(0.9).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .padding(9)
            .frame(width: 118, height: 96, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I had \(name)")
    }
}
