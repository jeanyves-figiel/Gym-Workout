import SwiftUI
import WorkoutEngine

// Fuel (#496): a tab between Progress and Community. Pointers come from the day's training. Home (#733, Fuel Tank +
// Magic Snap): the day's tank, one Log button, the next meal and the Kitchen squares (`FuelHomeViews`).

enum FuelPalette {
    static func gradient(_ a: UInt32, _ b: UInt32) -> LinearGradient {
        LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let hot = gradient(0xFF9F1C, 0xFF3D6E)
    static let violet = gradient(0xB23DFF, 0x3D7BFF)
    static let water = gradient(0x3DD6FF, 0x1E6BFF)
    static let mint = gradient(0x3DFFB0, 0x1E9BFF)
    static let coach = gradient(0xFF3DA8, 0xFF7A3D)
    static let lime = gradient(0xD6FF3D, 0x3DFFB0)
    static let protein = gradient(0xFF6B9A, 0xFF3D6E)
    static let carbs = gradient(0xFFD23D, 0xFF9F1C)
    static let veg = gradient(0x3DFFB0, 0x1ED98A)
    static let fats = gradient(0xB23DFF, 0x7A3DFF)

    static func load(_ l: FuelLoad) -> LinearGradient {
        switch l {
        case .rest: mint
        case .normal: violet
        case .big: hot
        }
    }

    static func portion(_ k: Portions.Kind) -> LinearGradient {
        switch k {
        case .palms: protein
        case .cups: carbs
        case .fists: veg
        case .thumbs: fats
        }
    }

    /// Dark text on the light gradients.
    static func ink(_ k: Portions.Kind) -> Color { k == .cups || k == .fists ? Theme.ink : .white }

    static func meal(_ k: MealKind) -> LinearGradient {
        switch k {
        case .breakfast: carbs
        case .lunch: gradient(0xFFD23D, 0xFF7A3D)
        case .dinner: violet
        case .snack: mint
        case .pre: lime
        case .recovery: coach
        case .bedtime: gradient(0x3D4BFF, 0x8A4DFF)
        }
    }

    static func loadEmoji(_ l: FuelLoad) -> String {
        switch l {
        case .rest: "🌙"
        case .normal: "💪"
        case .big: "🔥"
        }
    }
}

struct FuelView: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var store = FuelStore.shared
    @State private var day = Calendar.current.startOfDay(for: Date())
    /// The date `day` was last set on: on a later date the strip reopens on today, like Train (#547).
    @State private var dayOn = Calendar.current.startOfDay(for: Date())
    @Environment(\.scenePhase) private var scenePhase
    @State private var setup = false
    @State private var slot: FuelSlot?
    @State private var justAte = false
    /// Undo bar after Later / ✕ on the Set up Fuel card (#686).
    @State private var setupLater = false

    private func dropStaleDay() {
        let today = Calendar.current.startOfDay(for: Date())
        guard dayOn != today else { return }
        dayOn = today
        day = today
    }

    var body: some View {
        // Observed so the day re-plans when training, steps or settings change.
        let _ = (health.snapshot.recentSports.count, model.state.history.count, store.saved.prefs)
        let plan = model.fuelPlan(on: day)
        let log = store.log(day)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                FuelDayStrip(day: $day)
                if store.showsSetupCard {
                    FuelSetupCard(setUp: { setup = true }, later: hideSetupCard)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                if let e = plan.event { FuelEventCard(event: e) }
                FuelTankCard(plan: plan, log: log, day: day)
                if Calendar.current.startOfDay(for: day) <= Calendar.current.startOfDay(for: Date()) {
                    FuelLogButton { justAte = true }
                }
                if Calendar.current.isDateInToday(day) { MealIdeasCard(plan: plan, log: log, day: day) }
                FuelNextCard(plan: plan, log: log, day: day, open: { slot = $0 })
                // Fuel with a partner (#1014): invites to answer and copies friends sent.
                PartnerCard(invitesOnly: true)
                FuelCopiesInbox()
                FuelKitchen(plan: plan, day: day, settings: { setup = true })
                Text(FuelLearn.disclaimer)
                    .font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
                    .padding(.top, 4)
            }
            .padding(16)
            .animation(.snappy, value: store.showsSetupCard)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .statusBarScrim()
        .task { await HouseholdStore.shared.refresh() }
        .navigationTitle("Fuel")
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $setup) { NavigationStack { FuelSetupView(sheet: true) } }
        .sheet(item: $slot) { s in FuelSlotSheet(slot: s, plan: plan, day: day) }
        .sheet(isPresented: $justAte) { JustAteSheet(plan: plan, day: day) }
        .overlay(alignment: .bottom) {
            if setupLater {
                FuelSetupLaterBar {
                    withAnimation(.snappy) {
                        store.hideSetupCard(false)
                        setupLater = false
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 76)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: FuelLaunch.shared.justAte, initial: true) { _, open in
            guard open else { return }
            FuelLaunch.shared.justAte = false
            justAte = true
        }
        .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
        .fuelDestinations()
        .onAppear { model.topUpMealPlan() }
        .onChange(of: scenePhase) { if scenePhase == .active { dropStaleDay() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in dropStaleDay() }
        .coachFocus(CoachFocus(screen: "fuel", title: "Fuel", detail: Self.coachDetail(plan, log: log, prefs: store.prefs),
                               starters: CoachFocus.tab(.fuel).starters))
    }

    private func hideSetupCard() {
        withAnimation(.snappy) {
            store.hideSetupCard(true)
            setupLater = true
        }
        Haptics.undo()
        Task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.snappy) { setupLater = false }
        }
    }

    /// Today's targets and what was counted, for Ask Coach (not shown).
    static func coachDetail(_ plan: FuelPlan, log: FuelDayLog, prefs: FuelPrefs) -> String {
        var parts = ["\(plan.headline)", "target ~\(plan.protein) g protein, \(plan.carbs) g carbs, \(plan.fat) g fat, \(plan.glasses) glasses",
                     "counted \(log.eaten.palms)/\(plan.portions.palms) protein palms, \(log.glasses) glasses",
                     "diet \(prefs.diet.rawValue)"]
        if !prefs.avoid.isEmpty { parts.append("avoids " + prefs.avoid.map(\.rawValue).sorted().joined(separator: ", ")) }
        if let e = plan.event { parts.append("event: \(e.title)") }
        // Supplements today and each one's schedule (#572), so Coach can answer "when do I take my creatine?".
        if !plan.supplements.isEmpty {
            parts.append("supplements today: " + plan.supplements.map { "\($0.supplement.name) \($0.time) \($0.supplement.dose)\(log.taken($0) ? " (taken)" : "")" }
                .joined(separator: ", "))
        }
        let cal = Calendar.current
        let stack = FuelStore.shared.stack
        if !stack.isEmpty {
            parts.append("supplement schedules: " + stack.map { s in
                s.whenPicked ? "\(s.name) · when picked"
                    : ([s.name, s.schedule.summary(calendar: cal)] + [s.schedule.courseLine(now: Date(), calendar: cal)].compactMap { $0 }).joined(separator: " · ")
            }.joined(separator: "; "))
        }
        return parts.joined(separator: "; ")
    }

    private var header: some View {
        HStack(spacing: 10) {
            TabTitleMenu(tab: .fuel)
            Spacer()
            CoachHeaderTile()
            MePill()
        }
        .padding(.top, 4)
    }
}

/// Days slide under a centre lens like Train's week strip (#510, design B): 1 week back to 2 weeks ahead,
/// the day that settles under the lens is shown. Past days show what was counted, coming days the plan;
/// each day is tinted by its load (big hot, training violet, rest dark).
struct FuelDayStrip: View {
    @Binding var day: Date
    @Environment(AppModel.self) private var model

    /// 1 week back to 2 weeks ahead, in days from today.
    static let range = -7...14

    /// Load of every day in the strip, by days from today.
    @MainActor static func loads(_ model: AppModel, today: Date, calendar cal: Calendar) -> [Int: FuelLoad] {
        let weightKg = model.fuelWeightKg ?? Fuel.typicalKg
        var out: [Int: FuelLoad] = [:]
        for o in range {
            if let d = cal.date(byAdding: .day, value: o, to: today) { out[o] = Fuel.load(model.fuelActivities(on: d), weightKg: weightKg) }
        }
        return out
    }

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let picked = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: day)).day ?? 0
        // Each day's load once per render: the strip redraws its cells every time a cell slides under the lens.
        let loads = Self.loads(model, today: today, calendar: cal)
        LensDayStrip(range: Self.range, selected: picked, onPick: { o in
            if let d = cal.date(byAdding: .day, value: o, to: today) { withAnimation(.snappy) { day = d } }
        }) { o in
            if let d = cal.date(byAdding: .day, value: o, to: today) {
                let on = o == picked
                let load = loads[o] ?? Fuel.load(model.fuelActivities(on: d), weightKg: model.fuelWeightKg ?? Fuel.typicalKg)
                Button { withAnimation(.snappy) { day = d } } label: {
                    VStack(spacing: 2) {
                        Text(d.formatted(.dateTime.weekday(.narrow))).font(Theme.label(9)).opacity(0.75)
                        Text(d.formatted(.dateTime.day())).font(Theme.display(15)).monospacedDigit()
                        Text(FuelPalette.loadEmoji(load)).font(.system(size: 10))
                    }
                    .foregroundStyle(on ? Theme.ink : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? AnyShapeStyle(Theme.lime) : load == .rest ? AnyShapeStyle(Theme.card) : AnyShapeStyle(FuelPalette.load(load))))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.lime, lineWidth: o == 0 && !on ? 2 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(d.formatted(.dateTime.weekday(.wide).day().month())), \(load.label)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

// MARK: - Shared pieces

/// Gradient tile: icon tile left, label and value, big number right.
struct FuelTile<Trailing: View>: View {
    let emoji: String
    let label: String
    let title: String
    var detail: String?
    let gradient: LinearGradient
    var ink: Color = .white
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Text(emoji).font(.system(size: 22))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased()).font(Theme.label(10)).tracking(1.2).opacity(0.85)
                Text(title).font(Theme.display(17)).lineLimit(2).minimumScaleFactor(0.8)
                if let detail { Text(detail).font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.85).lineLimit(2) }
            }
            Spacer(minLength: 4)
            trailing()
        }
        .foregroundStyle(ink)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(gradient))
    }
}

extension FuelTile where Trailing == EmptyView {
    init(emoji: String, label: String, title: String, detail: String? = nil, gradient: LinearGradient, ink: Color = .white) {
        self.init(emoji: emoji, label: label, title: title, detail: detail, gradient: gradient, ink: ink) { EmptyView() }
    }
}

/// Small stat square in a grid.
struct FuelStat: View {
    let value: String
    let label: String
    var progress: Double?
    var bar: Color = Theme.lime

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(Theme.display(20)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased()).font(Theme.label(9)).tracking(1).opacity(0.85).lineLimit(1).minimumScaleFactor(0.8)
            if let progress {
                Capsule().fill(.black.opacity(0.28)).frame(height: 6)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in Capsule().fill(bar).frame(width: g.size.width * max(0, min(1, progress))) }
                    }
                    .clipShape(Capsule())
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.22)))
    }
}

/// Plate split: protein / carbs / veg widths from portions.
struct PlateBar: View {
    let portions: Portions

    var body: some View {
        let parts: [(String, Int, Color)] = [("PROTEIN", portions.palms, Color(hex: 0xFF6B9A)), ("CARBS", portions.cups, Color(hex: 0xFFD23D)),
                                             ("VEG", max(1, portions.fists), Color(hex: 0x3DFFB0))]
        let total = CGFloat(max(1, parts.reduce(0) { $0 + $1.1 }))
        GeometryReader { g in
            HStack(spacing: 0) {
                ForEach(parts, id: \.0) { p in
                    Text(p.0).font(Theme.label(9)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.5)
                        .frame(width: g.size.width * CGFloat(p.1) / total, height: 22)
                        .background(p.2)
                }
            }
        }
        .frame(height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityLabel("Plate: \(portions.palms) palms protein, \(portions.cups) cupped hands carbs, \(portions.fists) fists veg")
    }
}

/// Glasses to tap: tap the next empty one to fill up to it, tap the last full one to empty it.
struct WaterGlasses: View {
    let filled: Int
    let target: Int
    let set: (Int) -> Void

    var body: some View {
        let count = max(target, filled)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: min(10, max(5, count))), spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                let full = i < filled
                Button { set(full && i == filled - 1 ? i : i + 1) } label: {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(full ? Color(hex: 0x9BEBFF) : .white.opacity(0.2))
                        .frame(height: 26)
                        .overlay { if full { Image(systemName: "drop.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: 0x1E6BFF)) } }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Glass \(i + 1)\(full ? ", drunk" : "")")
            }
        }
        .sensoryFeedback(.increase, trigger: filled)
    }
}

extension FuelPrefs {
    func grams(_ g: Int) -> String { noNumbers ? "" : "\(g) g" }
    func litres(_ ml: Int) -> String { String(format: "%.1f L", Double(ml) / 1000) }
}

/// Up to 3 recipe ideas for a meal, as chips that open the recipe.
struct FuelIdeaChips: View {
    let slot: FuelSlot
    let plan: FuelPlan
    @State private var store = FuelStore.shared

    var body: some View {
        let ideas = RecipeBook.ideas(for: slot, load: plan.load, prefs: store.prefs, favourites: store.saved.favourites,
                                     own: store.saved.recipes, day: store.key(plan.day))
        FlowLayout(spacing: 6) {
            ForEach(ideas) { r in
                NavigationLink(value: r) {
                    Text("\(r.emoji) \(r.name)").font(Theme.label(11)).lineLimit(1)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(Capsule().fill(.black.opacity(0.28)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Tools

/// Fuel screens, pushed by value like the recipes inside them: a value link inside a screen pushed with a
/// destination link popped the recipe straight back (#508).
enum FuelRoute: Hashable {
    case pantry, mealPlan, groceries, recipes(MealKind?), week, learn, supplements
}

extension View {
    func fuelDestinations() -> some View {
        navigationDestination(for: FuelRoute.self) { route in
            switch route {
            case .pantry: PantryView()
            case .mealPlan: MealPlanView()
            case .groceries: GroceriesView()
            case .recipes(let slot): RecipeBrowserView(slot: slot)
            case .week: FuelWeekView()
            case .learn: FuelLearnView()
            case .supplements: SupplementsView()
            }
        }
    }
}

/// Actions on the next meal's card (#525, design C): cook from what's at home, other recipes, and a planned meal's
/// missing foods straight to Groceries.
struct FuelSlotActions: View {
    let slot: FuelSlot
    let day: Date
    var dark = false
    @State private var store = FuelStore.shared

    var body: some View {
        let planned = store.saved.plan.first { $0.day == store.key(day) && $0.slot == slot.id }
            .flatMap { RecipeBook.recipe($0.recipeId, own: store.recipeLookup) }
        let have = store.pantryIds
        let missing = have.isEmpty ? [] : (planned?.keys ?? []).filter { !have.contains($0) }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(.pantry, "🧊 From what I have")
                chip(.recipes(slot.recipeKind), "📖 Other recipes")
                // The count is this meal's; Groceries lists the whole basket, so the chip says which.
                if !missing.isEmpty {
                    chip(.groceries, "🛒 \(missing.count) to buy for this meal")
                        .accessibilityHint("Opens the full grocery list")
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ route: FuelRoute, _ text: String) -> some View {
        NavigationLink(value: route) {
            Text(text).font(Theme.label(11)).lineLimit(1)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(dark ? 0.14 : 0.25)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - One meal

/// A meal of the day: what to aim for, ideas (eat one with a tap), or mark something else eaten.
struct FuelSlotSheet: View {
    let slot: FuelSlot
    let plan: FuelPlan
    let day: Date
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared

    var body: some View {
        let log = store.log(day)
        let ticked = log.ticks[slot.id]
        let ideas = RecipeBook.ideas(for: slot, load: plan.load, prefs: store.prefs, favourites: store.saved.favourites,
                                     own: store.saved.recipes, day: store.key(day), count: 5)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(slot.time) · \(plan.load.label.uppercased())").font(Theme.label(10)).tracking(1.2).opacity(0.85)
                        Text(slot.hint).font(Theme.display(17)).fixedSize(horizontal: false, vertical: true)
                        PlateBar(portions: slot.portions)
                        HStack(spacing: 6) {
                            ForEach(Portions.Kind.allCases) { k in
                                if slot.portions[k] > 0 {
                                    Text("\(k.emoji) \(slot.portions[k])").font(Theme.label(12))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Capsule().fill(.black.opacity(0.25)))
                                }
                            }
                            Spacer()
                            if !store.prefs.noNumbers {
                                Text("\(slot.protein) g P · \(slot.carbs) g C").font(Theme.label(11)).opacity(0.9)
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.meal(slot.recipeKind)))

                    if ticked != nil {
                        Button {
                            // The foods logged next to its recipe go too (#819).
                            store.update(day, plan: plan) {
                                $0.untick(slot.id)
                                $0.untick(FuelDayLog.foodKey(slot.id))
                            }
                            dismiss()
                        } label: { Label("Not eaten after all", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(LimeButtonStyle(fill: Theme.cardStrong, text: .white))
                    } else {
                        Button {
                            store.update(day, plan: plan) { $0.tick(slot) }
                            dismiss()
                        } label: { Label("I ate something like this", systemImage: "checkmark") }
                            .buttonStyle(LimeButtonStyle())
                    }

                    Text("Ideas").eyebrow()
                    ForEach(ideas) { r in
                        HStack(spacing: 8) {
                            NavigationLink(value: r) { RecipeRow(recipe: r) }
                                .buttonStyle(.plain)
                            Button {
                                store.update(day, plan: plan) { $0.tick(slot, recipe: r) }
                                dismiss()
                            } label: {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.lime)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("I ate \(r.name)")
                        }
                    }
                    NavigationLink(value: FuelRoute.recipes(slot.recipeKind)) {
                        Label("All \(slot.recipeKind.label.lowercased()) recipes", systemImage: "book.fill")
                            .font(Theme.label(15)).foregroundStyle(Theme.lime)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(slot.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0, eat: (slot, plan, day)) }
            .fuelDestinations()
        }
        .presentationDetents([.large])
    }
}
