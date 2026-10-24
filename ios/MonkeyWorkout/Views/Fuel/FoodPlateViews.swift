import SwiftUI
import WorkoutEngine

// Plain foods in Just ate (#710, mix of A + B + C from `log-foods/proposals.png`): search finds foods (A), they go
// on a plate with live totals and one Log button (B), a plate can be saved as a usual and logged in one tap (C).

/// B · The plate being built: foods with ½-step amounts, totals, a milk nudge for cereal, Log and Save as usual.
struct FoodPlateCard: View {
    @Binding var plate: [FoodServing]
    /// The meal it goes to.
    let slot: FuelSlot
    let log: () -> Void
    let saveUsual: () -> Void
    @State private var store = FuelStore.shared

    var body: some View {
        let own = store.saved.foods
        let t = FoodServing.totals(plate, own: own)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(slot.kind.emoji) \(slot.title.uppercased()) PLATE").font(Theme.label(10)).tracking(1.2).opacity(0.9)
                Spacer()
                Button { withAnimation(.snappy) { plate = [] } } label: {
                    Text("CLEAR").font(Theme.label(10)).padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.25)))
                }
                .buttonStyle(.plain)
            }
            if !store.prefs.noNumbers {
                HStack(spacing: 5) {
                    number("\(Int(t.macros.protein.rounded()))", "G PROTEIN")
                    number("\(Int(t.macros.carbs.rounded()))", "G CARBS")
                    number("\(Int(t.macros.kcal.rounded()))", "KCAL")
                    if t.caffeineMg > 0 { number("\(t.caffeineMg)", "MG ☕") }
                }
            }
            ForEach(plate) { item in
                if let food = FoodBook.food(item.foodId, own: own) { row(food, item) }
            }
            if FoodBook.wantsMilk(plate), let milk = FoodBook.food("milk") {
                Button { add("milk", 0.5) } label: {
                    HStack {
                        Text("🥛 With milk? ½ glass, +\(Int(milk.macros(grams: milk.portion.g / 2).protein.rounded())) g protein")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                        Spacer()
                        Text("ADD").font(Theme.label(11))
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FuelPalette.violet))
                }
                .buttonStyle(.plain)
            }
            Button(action: log) {
                Text("Log \(slot.title.lowercased())").font(Theme.display(17))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Theme.lime))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("fuel.plate.log")
            Button(action: saveUsual) {
                Label("Save as a usual", systemImage: "star.fill").font(Theme.label(12))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.25)))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(FuelPalette.meal(slot.kind)))
    }

    private func number(_ v: String, _ unit: String) -> some View {
        VStack(spacing: 1) {
            Text(v).font(Theme.display(18)).monospacedDigit()
            Text(unit).font(Theme.label(8)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.22)))
    }

    private func row(_ food: Food, _ item: FoodServing) -> some View {
        HStack(spacing: 9) {
            Text(food.emoji).font(.system(size: 20)).frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.2)))
            VStack(alignment: .leading, spacing: 1) {
                Text(food.name).font(Theme.display(14)).lineLimit(1).minimumScaleFactor(0.75)
                Text("\(FoodPlate.amount(item.servings)) × \(food.portion.label)").font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.85)
            }
            Spacer(minLength: 4)
            step("minus", "Less \(food.name)") { add(food.id, -0.5) }
            step("plus", "More \(food.name)") { add(food.id, 0.5) }
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.black.opacity(0.18)))
    }

    private func step(_ symbol: String, _ label: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Image(systemName: symbol).font(.system(size: 13, weight: .black))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(symbol == "plus" ? Theme.lime : .black.opacity(0.3)))
                .foregroundStyle(symbol == "plus" ? Theme.ink : .white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func add(_ id: String, _ by: Double) {
        withAnimation(.snappy) { plate = FoodPlate.adding(id, by, to: plate) }
    }
}

enum FoodPlate {
    /// "½", "1", "1½".
    static func amount(_ s: Double) -> String {
        let whole = Int(s)
        let half = s - Double(whole) >= 0.5
        return whole == 0 ? "½" : half ? "\(whole)½" : "\(whole)"
    }

    /// Adds (or with a negative step takes off) servings; under ½ removes the food.
    static func adding(_ id: String, _ by: Double, to plate: [FoodServing]) -> [FoodServing] {
        var p = plate
        if let i = p.firstIndex(where: { $0.foodId == id }) {
            let n = p[i].servings + by
            if n < 0.5 { p.remove(at: i) } else { p[i].servings = n }
        } else if by > 0 {
            p.append(FoodServing(foodId: id, servings: by < 1 ? by : 1))
        }
        return p
    }

    /// "Coffee, Cornflakes ×2, Milk ½".
    static func names(_ items: [FoodServing], own: [Food]) -> String {
        items.compactMap { i in
            FoodBook.food(i.foodId, own: own).map { i.servings == 1 ? $0.name : "\($0.name) ×\(amount(i.servings))" }
        }
        .joined(separator: ", ")
    }
}

/// B · One-tap food chips: on the plate in lime.
struct FoodChips: View {
    let ids: [String]
    @Binding var plate: [FoodServing]
    @State private var store = FuelStore.shared

    var body: some View {
        let own = store.saved.foods
        FlowLayout(spacing: 6) {
            ForEach(ids.compactMap { FoodBook.food($0, own: own) }) { f in
                let on = plate.contains { $0.foodId == f.id }
                Button {
                    Haptics.undo()
                    withAnimation(.snappy) { plate = on ? plate.filter { $0.foodId != f.id } : FoodPlate.adding(f.id, 1, to: plate) }
                } label: {
                    Text("\(f.emoji) \(FoodPlate.short(f.name))").font(Theme.label(12)).lineLimit(1)
                        .foregroundStyle(on ? Theme.ink : .white)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Theme.lime : Theme.cardStrong))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

extension FoodPlate {
    /// "Milk (semi-skimmed)" → "Milk" for chips.
    static func short(_ name: String) -> String {
        String(name.split(separator: "(").first ?? Substring(name)).trimmingCharacters(in: .whitespaces)
    }
}

/// C · Saved plates, one tap logs one. Hold for Delete.
struct UsualStrip: View {
    let kind: MealKind?
    let had: (FoodUsual) -> Void
    @State private var store = FuelStore.shared

    var body: some View {
        let own = store.saved.foods
        let list = store.usuals.sorted { ($0.kind == kind ? 0 : 1) < ($1.kind == kind ? 0 : 1) }
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR USUALS").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted).padding(.top, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, u in
                        let t = FoodServing.totals(u.items, own: own)
                        Button { had(u) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .top) {
                                    Text(u.emoji(own: own)).font(.system(size: 20))
                                    Spacer(minLength: 2)
                                    Text("I HAD IT").font(Theme.label(9)).foregroundStyle(Theme.ink)
                                        .padding(.horizontal, 6).padding(.vertical, 4)
                                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.lime))
                                }
                                Text(u.name).font(Theme.display(14)).lineLimit(1)
                                Text(FoodPlate.names(u.items, own: own)).font(.system(size: 10, weight: .bold, design: .rounded))
                                    .opacity(0.85).lineLimit(2)
                                if !store.prefs.noNumbers {
                                    Text("\(Int(t.macros.protein.rounded())) g P\(t.caffeineMg > 0 ? " · \(t.caffeineMg) mg ☕" : "")")
                                        .font(Theme.label(10)).opacity(0.9)
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(10)
                            .frame(width: 170, alignment: .topLeading)
                            .frame(minHeight: 104, alignment: .topLeading)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Self.colours[i % Self.colours.count]))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { store.deleteUsual(u.id) } label: { Label("Delete usual", systemImage: "trash") }
                        }
                        .accessibilityLabel("I had \(u.name): \(FoodPlate.names(u.items, own: own))")
                    }
                }
            }
        }
    }

    private static let colours: [LinearGradient] = [FuelPalette.hot, FuelPalette.mint, FuelPalette.violet, FuelPalette.coach]
}
