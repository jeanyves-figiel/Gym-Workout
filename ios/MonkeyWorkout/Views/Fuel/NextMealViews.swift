import SwiftUI
import WorkoutEngine

// Next meal and Just ate (#578, designs A + B from `meal-plan-pattern/proposals4.png`): with a meal plan, the Day
// look's plate card shows the planned recipe (Ate it · Swap · Something else) and the meal after it; a lime + on
// Fuel logs what was just eaten in two taps: a planned meal, a recent recipe, a search, or portions by hand.

/// The next meal's planned recipe, big, with what to do about it.
struct PlannedPlateCard: View {
    let slot: FuelSlot
    let recipe: Recipe
    let meal: PlannedMeal
    let plan: FuelPlan
    let log: FuelDayLog
    let day: Date
    let open: (FuelSlot) -> Void
    @State private var store = FuelStore.shared
    @State private var swapping = false

    var body: some View {
        let eaten = log.ticks[slot.id] != nil
        let future = Calendar.current.startOfDay(for: day) > Calendar.current.startOfDay(for: Date())
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("NEXT MEAL · \(slot.title.uppercased()) · \(slot.time)").font(Theme.label(10)).tracking(1.2).opacity(0.85)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if meal.pinned { Text("📌").font(.system(size: 12)) }
                if meal.leftover { Text("♻️").font(.system(size: 12)) }
            }
            NavigationLink(value: recipe) {
                HStack(spacing: 12) {
                    Text(recipe.emoji).font(.system(size: 30))
                        .frame(width: 58, height: 58)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recipe.name).font(Theme.display(20)).lineLimit(2).minimumScaleFactor(0.75)
                            .multilineTextAlignment(.leading)
                        Text(detail).font(.system(size: 12, weight: .bold, design: .rounded)).opacity(0.9).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if eaten {
                action("Eaten · Undo", symbol: "arrow.uturn.backward", lime: false) {
                    store.update(day, plan: plan) { $0.untick(slot.id) }
                }
            } else {
                HStack(spacing: 6) {
                    if !future {
                        action("Ate it", symbol: "checkmark", lime: true) {
                            Haptics.success()
                            store.update(day, plan: plan) { $0.tick(slot, recipe: recipe) }
                        }
                    }
                    action("Swap", symbol: "arrow.triangle.2.circlepath", lime: false) { swapping = true }
                    action("Other", symbol: "pencil", lime: false) { open(slot) }
                        .accessibilityLabel("Something else")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.violet))
        .sheet(isPresented: $swapping) { SwapMealSheet(key: store.key(day), slot: slot, plan: plan) }
    }

    private var detail: String {
        var parts: [String] = []
        if !store.prefs.noNumbers { parts.append("\(recipe.protein) g protein") }
        if recipe.minutes > 0 && !meal.leftover { parts.append("\(recipe.minutes) min") }
        if meal.leftover { parts.append("Leftovers") }
        return parts.joined(separator: " · ")
    }

    private func action(_ title: String, symbol: String, lime: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol).font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.75)
                .foregroundStyle(lime ? Theme.ink : .white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(lime ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(.black.opacity(0.25))))
        }
        .buttonStyle(.plain)
    }
}

/// The planned meal after the next one, small.
struct ThenMealCard: View {
    let slot: FuelSlot
    let recipe: Recipe
    let meal: PlannedMeal

    var body: some View {
        NavigationLink(value: recipe) {
            HStack(spacing: 10) {
                Text(recipe.emoji).font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.2)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("THEN · \(slot.title.uppercased()) · \(slot.time)").font(Theme.label(9)).tracking(1).opacity(0.85)
                    Text(recipe.name).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.75)
                    if recipe.tags.contains(.batch) && slot.kind == .dinner {
                        Text("Batch · tomorrow's lunch ♻️").font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.85)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy))
            }
            .foregroundStyle(slot.kind == .breakfast || slot.kind == .lunch || slot.kind == .pre ? Theme.ink : .white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(FuelPalette.meal(slot.kind)))
        }
        .buttonStyle(.plain)
    }
}

/// The lime + on Fuel: opens Just ate. Sits on the side the Ask Coach bubble isn't on.
struct JustAteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus").font(.system(size: 24, weight: .black)).foregroundStyle(Theme.ink)
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Theme.lime))
                .shadow(color: Theme.lime.opacity(0.45), radius: 12)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Just ate")
        .accessibilityHint("Log a meal or snack")
    }
}

/// Log what was just eaten: a planned meal, a recent or favourite recipe, a search, or portions by hand.
struct JustAteSheet: View {
    let plan: FuelPlan
    let day: Date
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared
    @State private var query = ""
    /// Meal the ideas are for; nil = the open meal nearest now.
    @State private var picked: String?

    // Just ate (#574, design A + C rows from `just-ate/proposals.png`): the open meal nearest now with ideas for it
    // (planned recipe first), chips for the other open meals, today's ticked meals with Undo, named hand portions.
    var body: some View {
        let log = store.log(day)
        let open = plan.slots.filter { log.ticks[$0.id] == nil }
        let slot = open.first { $0.id == picked } ?? nearest(open)
        let done = plan.slots.filter { log.ticks[$0.id] != nil }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Search recipes and shakes", text: $query)
                        .font(Theme.label(15)).padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                        .submitLabel(.search)
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        if let slot {
                            hero(slot)
                            MineStrip(plan: plan, day: day) { eat($0, into: slot) }
                            if open.count > 1 {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) { ForEach(open) { chip($0, on: $0.id == slot.id) } }
                                }
                            }
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                                ForEach(Array(ideas(for: slot).enumerated()), id: \.element.recipe.id) { i, idea in
                                    tile(idea.recipe, note: idea.planned ? "PLANNED" : nil, index: i) { eat(idea.recipe, into: slot) }
                                }
                            }
                        } else {
                            Text("Every meal today is ticked. Search or count by hand to add more.")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                            MineStrip(plan: plan, day: day) { eat($0, into: nil) }
                        }
                        if !done.isEmpty {
                            label("TODAY")
                            ForEach(done) { s in doneRow(s, recipe: log.ticks[s.id]?.recipeId.flatMap { RecipeBook.recipe($0, own: store.recipeLookup) }) }
                        }
                    } else {
                        let found = search(query)
                        if found.isEmpty {
                            Text("No recipe found. Count it by hand below.").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                        }
                        ForEach(found) { r in row(r, note: nil, gradient: nil) { eat(r, into: nil) } }
                    }
                    label("OR BY HAND")
                    HStack(spacing: 6) {
                        ForEach(Portions.Kind.allCases) { k in hand(k, count: log.eaten[k]) }
                    }
                    Text("Each tap adds a portion to today. Hold to take one off.")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Just ate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var nowMinute: Int {
        let cal = Calendar.current
        return isToday ? cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date()) : 12 * 60
    }

    private func nearest(_ slots: [FuelSlot]) -> FuelSlot? {
        slots.min { abs($0.minute - nowMinute) < abs($1.minute - nowMinute) }
    }

    private func hero(_ s: FuelSlot) -> some View {
        let now = isToday && abs(s.minute - nowMinute) <= 90
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(now ? "NOW" : s.time) · \(plan.headline.uppercased())").font(Theme.label(10)).tracking(1).opacity(0.85).lineLimit(1)
            Text("\(s.kind.emoji) \(s.title)").font(Theme.display(22)).lineLimit(1).minimumScaleFactor(0.7)
            Text("~\(s.protein) g protein · \(s.carbs) g carbs for it").font(.caption.weight(.bold)).opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(FuelPalette.meal(s.kind)))
        .accessibilityElement(children: .combine)
    }

    private func chip(_ s: FuelSlot, on: Bool) -> some View {
        Button { withAnimation(.snappy) { picked = s.id } } label: {
            Text("\(s.kind.emoji) \(s.title)").font(Theme.label(12)).lineLimit(1)
                .foregroundStyle(on ? Theme.ink : .white)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Theme.lime : Theme.cardStrong))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Six ideas for a meal: its planned recipe, recent and favourite recipes that suit it, then fresh ideas.
    private func ideas(for s: FuelSlot) -> [(recipe: Recipe, planned: Bool)] {
        let key = store.key(day)
        var out: [(recipe: Recipe, planned: Bool)] = []
        if let m = store.saved.plan.first(where: { $0.day == key && $0.slot == s.id }),
           let r = RecipeBook.recipe(m.recipeId, own: store.recipeLookup) { out.append((r, true)) }
        let suits = { (r: Recipe) in r.slots.contains(s.recipeKind) || r.slots.contains(s.kind) }
        let more = recents().filter(suits)
            + RecipeBook.ideas(for: s, load: plan.load, prefs: store.prefs, favourites: store.saved.favourites,
                               own: store.saved.recipes, day: key + "ate", count: 8)
        for r in more where !out.contains(where: { $0.recipe.id == r.id }) && out.count < 6 { out.append((r, false)) }
        return out
    }

    private static let tileColours: [LinearGradient] = [FuelPalette.mint, FuelPalette.hot, FuelPalette.violet, FuelPalette.coach]

    private func tile(_ r: Recipe, note: String?, index: Int, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top) {
                    Text(r.emoji).font(.system(size: 24))
                    Spacer(minLength: 2)
                    Image(systemName: "plus").font(.system(size: 13, weight: .black)).foregroundStyle(Theme.ink)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.lime))
                }
                if let note { Text(note).font(Theme.label(9)).tracking(1).opacity(0.9) }
                Text(r.name).font(Theme.display(14)).lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.leading)
                Text("\(r.kcal) kcal · \(r.protein) g P").font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(index < 4 ? AnyShapeStyle(Self.tileColours[index]) : AnyShapeStyle(Theme.card)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I ate \(r.name)")
    }

    private func doneRow(_ s: FuelSlot, recipe: Recipe?) -> some View {
        HStack(spacing: 10) {
            Text(recipe?.emoji ?? s.kind.emoji).font(.system(size: 20)).frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.2)))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(s.title) · \(s.time)").font(Theme.display(14)).lineLimit(1)
                Text("\(recipe?.name ?? "Ticked") ✓").font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.85).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                withAnimation(.snappy) { store.update(day, plan: plan) { $0.untick(s.id) } }
            } label: {
                Text("UNDO").font(Theme.label(11)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo \(s.title)")
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(FuelPalette.meal(s.kind)).opacity(0.75))
    }

    private func label(_ t: String) -> some View {
        Text(t).font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted).padding(.top, 8)
    }

    private func row(_ r: Recipe, note: String?, gradient: LinearGradient?, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 10) {
                Text(r.emoji).font(.system(size: 22)).frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.black.opacity(0.2)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name).font(Theme.display(15)).lineLimit(1).minimumScaleFactor(0.75)
                    if let note { Text(note).font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.85) }
                }
                Spacer(minLength: 4)
                Image(systemName: "plus").font(.system(size: 15, weight: .black))
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.lime))
                    .foregroundStyle(Theme.ink)
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(gradient.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Theme.card)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("I ate \(r.name)")
    }

    private func hand(_ k: Portions.Kind, count: Int) -> some View {
        VStack(spacing: 2) {
            Text(k.emoji).font(.system(size: 22))
            Text("\(count)").font(Theme.display(17)).monospacedDigit()
            Text(k.food.uppercased()).font(Theme.label(9)).tracking(0.5).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FuelPalette.portion(k)))
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.success()
            store.update(day, plan: plan) { $0.eaten[k] += 1 }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            store.update(day, plan: plan) { $0.eaten[k] = max(0, $0.eaten[k] - 1) }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(k.food), \(k.label.lowercased()): \(count). Add one")
        .accessibilityAction(named: "Take one off") { store.update(day, plan: plan) { $0.eaten[k] = max(0, $0.eaten[k] - 1) } }
    }

    /// Ticks the meal it belongs to: the given slot, else the open slot nearest now that suits the recipe.
    private func eat(_ r: Recipe, into slot: FuelSlot?) {
        let now = nowMinute
        let ticks = store.log(day).ticks
        let open = plan.slots.filter { ticks[$0.id] == nil }
        let suits = open.filter { r.slots.contains($0.recipeKind) || r.slots.contains($0.kind) }
        let pool = !suits.isEmpty ? suits : !open.isEmpty ? open : plan.slots
        guard let target = slot ?? pool.min(by: { abs($0.minute - now) < abs($1.minute - now) }) else { return }
        Haptics.success()
        store.update(day, plan: plan) { $0.tick(target, recipe: r) }
        dismiss()
    }

    /// Recipes ticked in the last 2 weeks, newest first, then favourites.
    private func recents() -> [Recipe] {
        let cal = Calendar.current
        var ids: [String] = []
        for i in 0..<14 {
            guard let d = cal.date(byAdding: .day, value: -i, to: day) else { continue }
            for t in store.log(d).ticks.values { if let id = t.recipeId, !ids.contains(id) { ids.append(id) } }
        }
        ids += store.saved.favourites.sorted().filter { !ids.contains($0) }
        return ids.compactMap { RecipeBook.recipe($0, own: store.recipeLookup) }.prefix(8).map { $0 }
    }

    private func search(_ q: String) -> [Recipe] {
        let words = q.lowercased().split(separator: " ")
        return (Supplements.recipes(store.stack) + store.saved.recipes + RecipeBook.catalog)
            .filter { r in words.allSatisfy { r.name.lowercased().contains($0) } }
            .prefix(12).map { $0 }
    }
}
