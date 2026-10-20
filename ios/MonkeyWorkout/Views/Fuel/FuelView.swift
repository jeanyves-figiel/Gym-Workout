import SwiftUI
import WorkoutEngine

// Fuel (#496, designs A + B + C from `nutrition-pointers/section-home.png`): a tab between Progress and Community.
// Pointers come from the day's training; the member picks how to look at the day (Day / Timeline / Portions);
// recipes, What I have, meal plan with groceries, Fuel week and Learn are one tap away.

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

/// Round avatar with a gear (#496): opens Settings from the top right of every tab.
struct SettingsAvatar: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat = 36

    private var initials: String {
        let name = model.user?.name ?? ""
        let parts = name.split(separator: " ").prefix(2).compactMap(\.first)
        return parts.isEmpty ? "🐵" : String(parts).uppercased()
    }

    var body: some View {
        Button { model.settingsOpen = true } label: {
            Text(initials)
                .font(Theme.label(size * 0.36))
                .foregroundStyle(Theme.ink)
                .frame(width: size, height: size)
                .background(Circle().fill(FuelPalette.lime))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: size * 0.3, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(2)
                        .background(Circle().fill(Theme.bg))
                        .offset(x: 3, y: 3)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("settings.avatar")
    }
}

struct FuelView: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var store = FuelStore.shared
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var setup = false
    @State private var slot: FuelSlot?

    private var layout: Binding<FuelLayout> {
        Binding(get: { store.prefs.layout }, set: { l in
            var p = store.prefs
            p.layout = l
            store.setPrefs(p)
        })
    }

    var body: some View {
        // Observed so the day re-plans when training, steps or settings change.
        let _ = (health.snapshot.recentSports.count, model.state.history.count, store.saved.prefs)
        let plan = model.fuelPlan(on: day)
        let log = store.log(day)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                GradientSegments(selection: layout, items: FuelLayout.allCases.map {
                    SegmentItem(value: $0, title: $0.label, symbol: $0.symbol)
                }, gradient: FuelPalette.hot)
                FuelDayStrip(day: $day)
                FuelToolRow()
                if let e = plan.event { FuelEventCard(event: e) }
                switch store.prefs.layout {
                case .dashboard: FuelDashboard(plan: plan, log: log, day: day, open: { slot = $0 })
                case .timeline: FuelTimeline(plan: plan, log: log, day: day, open: { slot = $0 })
                case .portions: FuelPortionsView(plan: plan, log: log, day: day, open: { slot = $0 })
                }
                FuelStackCard(plan: plan, log: log, day: day)
                Text(FuelLearn.disclaimer)
                    .font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
                    .padding(.top, 4)
            }
            .padding(16)
            .animation(.snappy, value: store.prefs.layout)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .statusBarScrim()
        .navigationTitle("Fuel")
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $setup) { NavigationStack { FuelSetupView(sheet: true) } }
        .sheet(item: $slot) { s in FuelSlotSheet(slot: s, plan: plan, day: day) }
        .navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }
        .fuelDestinations()
        .onAppear { if !store.saved.setUp && !model.demo { setup = true } }
        .coachFocus(CoachFocus(screen: "fuel", title: "Fuel", detail: Self.coachDetail(plan, log: log, prefs: store.prefs),
                               starters: CoachFocus.tab(.fuel).starters))
    }

    /// Today's targets and what was counted, for Ask Coach (not shown).
    static func coachDetail(_ plan: FuelPlan, log: FuelDayLog, prefs: FuelPrefs) -> String {
        var parts = ["\(plan.headline)", "target ~\(plan.protein) g protein, \(plan.carbs) g carbs, \(plan.fat) g fat, \(plan.glasses) glasses",
                     "counted \(log.eaten.palms)/\(plan.portions.palms) protein palms, \(log.glasses) glasses",
                     "diet \(prefs.diet.rawValue)"]
        if !prefs.avoid.isEmpty { parts.append("avoids " + prefs.avoid.map(\.rawValue).sorted().joined(separator: ", ")) }
        if let e = plan.event { parts.append("event: \(e.title)") }
        return parts.joined(separator: "; ")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Fuel").font(Theme.display(34)).lineLimit(1)
            Spacer()
            Button { setup = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your fuel settings")
            SettingsAvatar()
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

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let picked = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: day)).day ?? 0
        LensDayStrip(range: -7...14, selected: picked, onPick: { o in
            if let d = cal.date(byAdding: .day, value: o, to: today) { withAnimation(.snappy) { day = d } }
        }) { o in
            if let d = cal.date(byAdding: .day, value: o, to: today) {
                let on = o == picked
                let load = Fuel.load(model.fuelActivities(on: d), weightKg: model.fuelWeightKg ?? Fuel.typicalKg)
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

// MARK: - A · Day dashboard

struct FuelDashboard: View {
    let plan: FuelPlan
    let log: FuelDayLog
    let day: Date
    let open: (FuelSlot) -> Void
    @State private var store = FuelStore.shared

    var body: some View {
        let prefs = store.prefs
        let now = Calendar.current.isDateInToday(day) ? Calendar.current.component(.hour, from: Date()) * 60 + Calendar.current.component(.minute, from: Date()) : 0
        let next = plan.next(after: now)
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text(FuelPalette.loadEmoji(plan.load)).font(.system(size: 22))
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.2)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(plan.load.label.uppercased()).font(Theme.label(10)).tracking(1.2).opacity(0.85)
                        Text(plan.headline).font(Theme.display(19)).lineLimit(2).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(plan.load.rawValue)/3").font(Theme.display(30))
                        Text("LOAD").font(Theme.label(9)).opacity(0.85)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    FuelStat(value: prefs.noNumbers ? "\(log.eaten.palms)/\(plan.portions.palms) ✋" : "\(plan.protein) g",
                             label: prefs.noNumbers ? "Protein palms" : "Protein · \(log.eaten.palms)/\(plan.portions.palms) palms",
                             progress: Double(log.eaten.palms) / Double(max(1, plan.portions.palms)))
                    FuelStat(value: plan.load.carbLabel, label: prefs.noNumbers ? "Carbs" : "Carbs · \(plan.carbs) g",
                             progress: Double(log.eaten.cups) / Double(max(1, plan.portions.cups)), bar: Color(hex: 0xFFD23D))
                    FuelStat(value: "\(log.glasses)/\(plan.glasses)", label: "Water · \(prefs.litres(plan.waterMl))",
                             progress: Double(log.glasses) / Double(max(1, plan.glasses)), bar: Color(hex: 0x9BEBFF))
                    if let next {
                        Button { open(next) } label: {
                            FuelStat(value: next.time, label: "Next · \(next.title)")
                        }
                        .buttonStyle(.plain)
                    }
                }
                if plan.estimated && !prefs.noNumbers {
                    Text("Add your weight in Body & Health for exact numbers.").font(.caption2.weight(.bold)).opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(FuelPalette.load(plan.load)))

            if let next {
                VStack(alignment: .leading, spacing: 8) {
                    Button { open(next) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("YOUR PLATE · \(next.title.uppercased())").font(Theme.label(10)).tracking(1.2).opacity(0.85)
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
                    if Calendar.current.isDateInToday(day) { FuelSlotActions(slot: next, day: day) }
                }
                .foregroundStyle(.white)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.violet))
            }

            FuelWaterCard(plan: plan, log: log, day: day, title: "WATER · TAP A GLASS")

            FuelCoachCard(plan: plan)
        }
    }
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

/// Coach Monkey's pointers for the day and tomorrow.
struct FuelCoachCard: View {
    let plan: FuelPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("🐵").font(.system(size: 24))
                    .frame(width: 40, height: 40).background(Circle().fill(Color(hex: 0x8A5A2B)))
                Text("COACH MONKEY · FUEL").font(Theme.label(10)).tracking(1.2).opacity(0.9)
            }
            ForEach(plan.tips, id: \.self) { t in
                Text(t).font(.system(size: 14, weight: .heavy, design: .rounded)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.coach))
    }
}

// MARK: - B · Day timeline

struct FuelTimeline: View {
    let plan: FuelPlan
    let log: FuelDayLog
    let day: Date
    let open: (FuelSlot) -> Void
    @Environment(AppModel.self) private var model
    @State private var store = FuelStore.shared

    private enum Row: Identifiable {
        case meal(FuelSlot)
        case training(FuelActivity)
        case supplement(SupplementDose)
        var id: String {
            switch self {
            case .meal(let s): "m-\(s.id)"
            case .training(let a): "t-\(a.id)"
            case .supplement(let d): "s-\(d.id)"
            }
        }
        var minute: Int {
            switch self {
            case .meal(let s): s.minute
            case .supplement(let d): d.minute
            case .training(let a): Calendar.current.component(.hour, from: a.start) * 60 + Calendar.current.component(.minute, from: a.start)
            }
        }
    }

    var body: some View {
        // Supplements sit between meals (#514); a meal shake shows in its meal's row instead.
        let rows = (plan.slots.map(Row.meal) + plan.activities.map(Row.training)
            + plan.supplements.filter { $0.replaces == nil }.map(Row.supplement)).sorted { $0.minute < $1.minute }
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minute = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let next = Calendar.current.isDateInToday(day)
            ? plan.slots.first { s in s.minute >= minute - 30 && log.ticks[s.id] == nil && !plan.supplements.contains { $0.replaces == s.id } }?.id : nil
        VStack(spacing: 8) {
            FuelCoachCard(plan: plan)
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    Text(String(format: "%02d:%02d", row.minute / 60 % 24, row.minute % 60))
                        .font(Theme.label(11)).foregroundStyle(Theme.muted).monospacedDigit()
                        .frame(width: 40, alignment: .trailing).padding(.top, 14)
                    switch row {
                    case .meal(let s): meal(s, next: s.id == next)
                    case .training(let a): training(a)
                    case .supplement(let d):
                        SupplementDoseRow(dose: d, plan: plan, log: log, day: day)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SupplementsView.gradient(d.supplement.kind)))
                    }
                }
            }
        }
    }

    private func meal(_ s: FuelSlot, next: Bool) -> some View {
        let shake = plan.supplements.first { $0.replaces == s.id }
        let done = shake.map { log.taken($0) } ?? (log.ticks[s.id] != nil)
        let kind = s.afterTraining ? MealKind.recovery : s.kind
        let dark = kind == .pre || kind == .breakfast || kind == .lunch
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { open(s) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(s.kind.emoji) \(s.title.uppercased())").font(Theme.label(10)).tracking(1).opacity(0.9)
                        Text(shake.map { "\($0.supplement.emoji) \($0.supplement.name)" } ?? ideaName(s) ?? s.hint).font(Theme.display(15)).lineLimit(2).minimumScaleFactor(0.8)
                            .multilineTextAlignment(.leading)
                        Text(store.prefs.noNumbers ? "✋ \(s.portions.palms) · 🤲 \(s.portions.cups) · ✊ \(s.portions.fists)"
                             : "\(s.protein) g protein · \(s.carbs) g carbs")
                            .font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.85)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Button {
                    store.update(day, plan: plan) { l in
                        if let shake { if done { l.untick(shake) } else { l.tick(shake) } } else if done { l.untick(s.id) } else { l.tick(s) }
                    }
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 26, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(done ? "Eaten, tap to undo" : "Mark eaten")
            }
            // The next meal carries its actions (#525, design C).
            if next { FuelSlotActions(slot: s, day: day, dark: dark) }
        }
        .foregroundStyle(dark ? Theme.ink : .white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(FuelPalette.meal(kind)))
        .overlay { if next { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.lime, lineWidth: 2) } }
        .opacity(done ? 0.75 : 1)
    }

    private func ideaName(_ s: FuelSlot) -> String? {
        if let id = log.ticks[s.id]?.recipeId, let r = RecipeBook.recipe(id, own: store.saved.recipes) { return "\(r.emoji) \(r.name)" }
        if let m = store.saved.plan.first(where: { $0.day == store.key(day) && $0.slot == s.id }),
           let r = RecipeBook.recipe(m.recipeId, own: store.saved.recipes) { return "\(r.emoji) \(r.name)" }
        return RecipeBook.ideas(for: s, load: plan.load, prefs: store.prefs, favourites: store.saved.favourites,
                                own: store.saved.recipes, day: store.key(day), count: 1).first.map { "\($0.emoji) \($0.name)" }
    }

    private func training(_ a: FuelActivity) -> some View {
        let gradient: LinearGradient = a.sport?.gradient ?? WorkoutEngine.Category.strength.gradient
        return HStack(spacing: 10) {
            Image(systemName: a.sport?.symbol ?? "dumbbell.fill")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 1) {
                Text(a.done ? "DONE" : "PLANNED").font(Theme.label(9)).tracking(1).opacity(0.85)
                Text("\(a.title) · \(a.minutes) min").font(Theme.display(15)).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            if !store.prefs.noNumbers {
                Text("~\(Int(a.energy(weightKg: model.fuelWeightKg ?? Fuel.typicalKg).rounded())) kcal").font(Theme.label(11)).opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(gradient))
    }
}

// MARK: - C · Hand portions

struct FuelPortionsView: View {
    let plan: FuelPlan
    let log: FuelDayLog
    let day: Date
    let open: (FuelSlot) -> Void
    @State private var store = FuelStore.shared

    var body: some View {
        let fuelled = log.fuelled(plan)
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("TODAY · \(plan.load.label.uppercased())").font(Theme.label(10)).tracking(1.2).opacity(0.85)
                        Text(plan.headline).font(Theme.display(19)).lineLimit(2).minimumScaleFactor(0.7)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(Int((fuelled * 100).rounded()))%").font(Theme.display(32)).monospacedDigit()
                        Text("FUELLED").font(Theme.label(9)).opacity(0.85)
                    }
                }
                Capsule().fill(.black.opacity(0.28)).frame(height: 7)
                    .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(Theme.lime).frame(width: g.size.width * fuelled) } }
                    .clipShape(Capsule())
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.load(plan.load)))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Portions.Kind.allCases) { k in hand(k) }
            }
            Text("Tap a tile for each portion you ate. Hold to take one back.")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)

            FuelWaterCard(plan: plan, log: log, day: day)

            if let line = coachLine {
                Button { if let s = nextSlot { open(s) } } label: {
                    HStack(spacing: 10) {
                        Text("🐵").font(.system(size: 20)).frame(width: 34, height: 34).background(Circle().fill(Color(hex: 0x8A5A2B)))
                        Text(line).font(.system(size: 14, weight: .heavy, design: .rounded)).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var nextSlot: FuelSlot? {
        let cal = Calendar.current
        let now = cal.isDateInToday(day) ? cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date()) : 0
        return plan.slots.first { $0.minute >= now - 30 && log.ticks[$0.id] == nil }
    }

    private var coachLine: String? {
        let left = plan.portions.palms - log.eaten.palms
        guard let s = nextSlot else { return left > 0 ? "\(left) palm\(left == 1 ? "" : "s") of protein left today." : "All set for today. Nice fuelling!" }
        return left > 0 ? "\(left) palm\(left == 1 ? "" : "s") of protein left: \(s.title.lowercased()) at \(s.time)." : "Protein done. \(s.title) at \(s.time): veg and carbs."
    }

    private func hand(_ k: Portions.Kind) -> some View {
        let have = log.eaten[k], target = plan.portions[k]
        let ink = FuelPalette.ink(k)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(k.emoji).font(.system(size: 24))
                Spacer()
                Text("\(have)/\(target)").font(Theme.display(22)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            }
            Text("\(k.label.uppercased()) · \(k.food.uppercased())").font(Theme.label(9)).tracking(0.8).lineLimit(1).minimumScaleFactor(0.7)
            // Big days can ask for 15+ portions: the squares wrap inside the tile instead of pushing it off screen.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 11, maximum: 11), spacing: 3)], alignment: .leading, spacing: 3) {
                ForEach(0..<max(target, have), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3).fill(i < have ? ink : ink.opacity(0.25)).frame(width: 11, height: 11)
                }
            }
        }
        .foregroundStyle(ink)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(FuelPalette.portion(k)))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { store.update(day, plan: plan) { $0.eaten[k] += 1 } }
        .onLongPressGesture { store.update(day, plan: plan) { $0.eaten[k] -= 1 } }
        .sensoryFeedback(.increase, trigger: have)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(k.label), \(k.food): \(have) of \(target)")
        .accessibilityHint(k.examples)
        .accessibilityAdjustableAction { d in
            store.update(day, plan: plan) { l in l.eaten[k] += d == .increment ? 1 : -1 }
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

/// Fuel's tools in one row of square tiles under the date bar (#525, design A): always one tap away, the day below
/// doesn't move.
struct FuelToolRow: View {
    @Environment(AppModel.self) private var model
    @State private var store = FuelStore.shared

    var body: some View {
        let today = store.key(Date())
        let planned = store.saved.plan.filter { $0.day >= today }.count
        let pantry = store.saved.pantry.count
        HStack(spacing: 6) {
            tile(.pantry, "🧊", "I have", pantry > 0 ? "\(pantry)" : nil, FuelPalette.mint, name: "What I have", id: "fuel.pantry")
            tile(.recipes(nil), "📖", "Recipes", nil, FuelPalette.coach, name: "Recipes")
            tile(.mealPlan, "🗓️", "Plan", planned > 0 ? "\(planned)" : nil, FuelPalette.violet, name: "Meal plan")
            tile(.groceries, "🛒", "Buy", planned > 0 ? "\(model.groceries().count)" : nil, FuelPalette.hot, name: "Groceries")
            tile(.week, "📈", "Week", nil, FuelPalette.water, name: "Fuel week")
            tile(.learn, "🎓", "Learn", nil, FuelPalette.gradient(0x3D4BFF, 0x8A4DFF), name: "Learn")
        }
    }

    private func tile(_ route: FuelRoute, _ emoji: String, _ label: String, _ badge: String?, _ g: LinearGradient,
                      name: String, id: String? = nil) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 3) {
                Text(emoji).font(.system(size: 19))
                Text(label).font(Theme.label(10)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(g))
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge).font(Theme.label(9)).monospacedDigit()
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.black.opacity(0.35)))
                        .foregroundStyle(.white)
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge.map { "\(name), \($0)" } ?? name)
        .accessibilityIdentifier(id ?? "fuel.\(label.lowercased())")
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
            .flatMap { RecipeBook.recipe($0.recipeId, own: store.saved.recipes) }
        let have = store.pantryIds
        let missing = have.isEmpty ? [] : (planned?.keys ?? []).filter { !have.contains($0) }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(.pantry, "🧊 From what I have")
                chip(.recipes(slot.recipeKind), "📖 Other recipes")
                if !missing.isEmpty { chip(.groceries, "🛒 \(missing.count) missing · Groceries") }
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
                            store.update(day, plan: plan) { $0.untick(slot.id) }
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
