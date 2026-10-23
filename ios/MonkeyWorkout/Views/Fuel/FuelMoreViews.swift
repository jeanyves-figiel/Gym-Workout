import SwiftUI
import WorkoutEngine

// Fuel week, Learn, setup, the race card and the drawn plate pictures (#496).

/// Race or event within two days: what to eat now.
struct FuelEventCard: View {
    let event: FuelEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("🏁").font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.2)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.days == 0 ? "RACE DAY" : "CARB UP").font(Theme.label(10)).tracking(1.2).opacity(0.85)
                    Text(event.title).font(Theme.display(19)).lineLimit(2)
                }
                Spacer()
                Text(event.days == 0 ? "GO" : "−\(event.days)").font(Theme.display(30))
            }
            ForEach(event.pointers, id: \.self) { p in
                Text("• " + p).font(.system(size: 13, weight: .bold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(event.sport.gradient))
    }
}

/// A recipe drawn as a plate: protein, carbs and veg as wedges sized by the recipe, its foods on top.
struct PlatePicture: View {
    let recipe: Recipe
    var size: CGFloat = 120

    var body: some View {
        let p = recipe.portions
        let parts: [(Double, Color)] = [(Double(max(1, p.palms)), Color(hex: 0xFF6B9A)), (Double(max(p.cups, 0)), Color(hex: 0xFFD23D)),
                                        (Double(max(1, p.fists)), Color(hex: 0x3DFFB0))].filter { $0.0 > 0 }
        let total = parts.reduce(0) { $0 + $1.0 }
        let emojis = (recipe.keys ?? []).compactMap { FoodBook.food($0)?.emoji }.prefix(5)
        ZStack {
            Circle().fill(.white.opacity(0.95))
            Circle().fill(Color(hex: 0xF1F1F4)).padding(size * 0.07)
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let r = sz.width / 2 - size * 0.1
                var a = -90.0
                for (v, color) in parts {
                    let sweep = 360 * v / max(total, 1)
                    var path = Path()
                    path.move(to: c)
                    path.addArc(center: c, radius: r, startAngle: .degrees(a + 1.5), endAngle: .degrees(a + sweep - 1.5), clockwise: false)
                    path.closeSubpath()
                    ctx.fill(path, with: .color(color.opacity(0.85)))
                    a += sweep
                }
            }
            ForEach(Array(emojis.enumerated()), id: \.offset) { i, e in
                let angle = (Double(i) / Double(max(1, emojis.count))) * 2 * .pi - .pi / 2
                Text(e).font(.system(size: size * 0.17))
                    .offset(x: cos(angle) * size * 0.25, y: sin(angle) * size * 0.25)
            }
            Text(recipe.emoji).font(.system(size: size * 0.26))
                .padding(size * 0.03)
                .background(Circle().fill(.white))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .accessibilityHidden(true)
    }
}

struct FuelWeekView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let days = model.fuelWeek()
        let protein = FuelWeek.streak(days, today: Date()) { $0.log.proteinHit($0.plan) }
        let water = FuelWeek.streak(days, today: Date()) { $0.log.waterHit($0.plan) }
        let counted = days.filter { !$0.log.isEmpty }
        let avgPalms = counted.isEmpty ? 0 : counted.reduce(0) { $0 + $1.log.eaten.palms } / counted.count
        let avgGlasses = counted.isEmpty ? 0 : counted.reduce(0) { $0 + $1.log.glasses } / counted.count
        let recovery = days.filter { d in d.plan.slots.contains { s in (s.afterTraining || s.kind == .recovery) && d.log.ticks[s.id] != nil } }.count
        let trainingDays = days.filter { $0.plan.load > .rest }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    streakChip("🔥 \(protein)-day protein streak", on: protein > 0)
                    streakChip("💧 \(water)-day water streak", on: water > 0)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("LOAD VS FUEL").font(Theme.label(10)).tracking(1.2).opacity(0.85)
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(days) { d in
                            VStack(spacing: 4) {
                                HStack(alignment: .bottom, spacing: 2) {
                                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.9))
                                        .frame(height: CGFloat(d.plan.load.rawValue) / 3 * 90)
                                    RoundedRectangle(cornerRadius: 3).fill(Theme.lime)
                                        .frame(height: max(2, CGFloat(d.fuelled) * 90))
                                }
                                .frame(height: 90, alignment: .bottom)
                                Text(d.day.formatted(.dateTime.weekday(.narrow))).font(Theme.label(10))
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(d.day.formatted(.dateTime.weekday(.wide))): \(d.plan.load.label), \(Int(d.fuelled * 100)) % fuelled")
                        }
                    }
                    HStack(spacing: 10) {
                        Label("Load", systemImage: "square.fill").foregroundStyle(.white)
                        Label("Fuelled", systemImage: "square.fill").foregroundStyle(Theme.lime)
                    }
                    .font(Theme.label(11))
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.hot))

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    tile("\(avgPalms) ✋", "Protein palms a day", FuelPalette.protein)
                    tile("\(avgGlasses) 💧", "Glasses a day", FuelPalette.water)
                    tile("\(recovery)/\(trainingDays)", "Recovery meals", FuelPalette.lime, ink: Theme.ink)
                    tile(weightChange ?? "—", "Weight, 7 days", FuelPalette.fats)
                }
                FuelTile(emoji: "🐵", label: "Coach Monkey", title: FuelWeek.insight(days), gradient: FuelPalette.coach)
                Text("+\(FuelWeek.proteinXP) XP for each day at your protein target, +\(FuelWeek.waterXP) for water. They count toward your level.")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Fuel week")
    }

    private var weightChange: String? {
        guard !FuelStore.shared.prefs.noNumbers else { return nil }
        let trend = model.health?.snapshot.weightTrend ?? []
        let since = Date().addingTimeInterval(-7 * 86_400)
        guard let last = trend.last, let first = trend.first(where: { $0.date >= since }), first.date < last.date else { return nil }
        let d = last.value - first.value
        return String(format: "%+.1f kg", d)
    }

    private func streakChip(_ t: String, on: Bool) -> some View {
        Text(t).font(Theme.label(12)).foregroundStyle(on ? Theme.ink : .white)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.card)))
    }

    private func tile(_ value: String, _ label: String, _ g: LinearGradient, ink: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(Theme.display(24)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased()).font(Theme.label(9)).opacity(0.85)
        }
        .foregroundStyle(ink)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(g))
    }
}

struct FuelLearnView: View {
    @State private var open: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Array(FuelLearn.cards.enumerated()), id: \.element.id) { i, c in
                    let on = open == c.id
                    Button { withAnimation(.snappy) { open = on ? nil : c.id } } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Text(c.emoji).font(.system(size: 22))
                                    .frame(width: 44, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.2)))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.title).font(Theme.display(17))
                                    Text(c.summary).font(.system(size: 12, weight: .bold, design: .rounded)).opacity(0.85)
                                }
                                Spacer()
                                Image(systemName: on ? "chevron.up" : "chevron.down").font(.system(size: 13, weight: .heavy))
                            }
                            if on {
                                ForEach(c.points, id: \.self) { p in
                                    Text("• " + p).font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(gradient(i)))
                    }
                    .buttonStyle(.plain)
                }
                Text(FuelLearn.disclaimer).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted).padding(.top, 6)
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Learn")
    }

    private func gradient(_ i: Int) -> LinearGradient {
        [FuelPalette.protein, FuelPalette.hot, FuelPalette.water, FuelPalette.coach, FuelPalette.violet, FuelPalette.fats,
         FuelPalette.gradient(0x3D4BFF, 0x8A4DFF), FuelPalette.mint][i % 8]
    }
}

/// Goal, diet, avoid list, meals, day times, glass size, reminders and No numbers. As a sheet from the Set up Fuel
/// card or Settings → You → Onboarding (#686): ✕ leaves it for later, Save my fuel saves it.
struct FuelSetupView: View {
    var sheet = false
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared
    @State private var prefs = FuelStore.shared.prefs

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if sheet {
                    Text("Pointers that follow your training. Everything here is optional: ✕ leaves it for later, and it can change any time in Settings → Fuel.")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                section("🎯", "Goal", FuelPalette.coach) {
                    VStack(spacing: 6) {
                        choice("From my training (\(FuelGoal.from(model.profile?.goal ?? .balanced).label.lowercased()))", on: prefs.goal == nil) { prefs.goal = nil }
                        ForEach(FuelGoal.allCases) { g in
                            choice(g.label, detail: g.detail, on: prefs.goal == g) { prefs.goal = g }
                        }
                    }
                }
                section("🥗", "Diet", FuelPalette.mint) {
                    FlowLayout(spacing: 6) {
                        ForEach(FuelDiet.allCases) { d in chip("\(d.emoji) \(d.label)", on: prefs.diet == d) { prefs.diet = d } }
                    }
                }
                section("⚠️", "Avoid", FuelPalette.carbs, ink: Theme.ink) {
                    FlowLayout(spacing: 6) {
                        ForEach(Allergen.allCases) { a in
                            chip(a.label, on: prefs.avoid.contains(a), light: true) {
                                if prefs.avoid.contains(a) { prefs.avoid.remove(a) } else { prefs.avoid.insert(a) }
                            }
                        }
                    }
                }
                section("🍽️", "Meals a day", FuelPalette.violet) {
                    HStack(spacing: 6) {
                        ForEach(3...6, id: \.self) { n in chip("\(n)", on: prefs.meals == n, wide: true) { prefs.meals = n } }
                    }
                }
                section("⏰", "Your day", FuelPalette.water) {
                    VStack(spacing: 8) {
                        timeRow("Wake up", minutes: $prefs.wake)
                        timeRow("Bedtime", minutes: $prefs.sleep)
                        Stepper(value: $prefs.glassMl, in: 150...500, step: 50) {
                            Text("Glass \(prefs.glassMl) ml").font(Theme.display(15))
                        }
                    }
                }
                section("🔔", "Refuel reminder", FuelPalette.hot) {
                    Toggle(isOn: $prefs.nudges) {
                        Text("After training, when the recovery meal isn't ticked within an hour. Max 1 a day.")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .tint(Theme.lime)
                }
                section("🙈", "No numbers", FuelPalette.gradient(0x3D4BFF, 0x8A4DFF)) {
                    Toggle(isOn: $prefs.noNumbers) {
                        Text("Hide grams, kcal and weight in Fuel. Portions and plates stay.")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .tint(Theme.lime)
                }
                section("🛒", "Prices & currency", FuelPalette.gradient(0x7A3DFF, 0xFF3DA8)) {
                    let market = FuelMarket.current(store.saved.market)
                    Menu {
                        Button("From my iPhone's region") { store.setMarket(nil) }
                        ForEach(FuelMarket.all) { m in
                            Button("\(m.label) · \(m.currency)") { store.setMarket(m.id) }
                        }
                    } label: {
                        HStack {
                            Text("\(market.label) · \(market.currency)").font(.system(size: 15, weight: .heavy, design: .rounded))
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(.white)
                    }
                    Text(store.saved.market == nil ? "From your iPhone's region. Meal plan prices are local estimates." : "Meal plan prices are local estimates.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).opacity(0.85)
                }
                Text(FuelLearn.disclaimer).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                if sheet {
                    Button {
                        store.setPrefs(prefs)
                        dismiss()
                    } label: {
                        Text("SAVE MY FUEL").font(Theme.display(17)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("fuel.setup.save")
                }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Your fuel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if sheet {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
        }
        // Settings page: saved as you go (auto save).
        .onChange(of: prefs) { if !sheet { store.setPrefs(prefs) } }
    }

    private func section<C: View>(_ emoji: String, _ title: String, _ g: LinearGradient, ink: Color = .white, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(emoji).font(.system(size: 18))
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.2)))
                Text(title).font(Theme.display(18))
            }
            content()
        }
        .foregroundStyle(ink)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(g))
    }

    private func choice(_ title: String, detail: String? = nil, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.display(15))
                    if let detail { Text(detail).font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.85) }
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 20, weight: .bold))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(on ? 0.3 : 0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func chip(_ title: String, on: Bool, light: Bool = false, wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.label(13))
                .foregroundStyle(on ? (light ? .white : Theme.ink) : (light ? Theme.ink : .white))
                .frame(maxWidth: wide ? .infinity : nil)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(on ? AnyShapeStyle(light ? Theme.ink : Theme.lime) : AnyShapeStyle(.black.opacity(light ? 0.12 : 0.25))))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func timeRow(_ title: String, minutes: Binding<Int>) -> some View {
        let date = Binding<Date>(
            get: { Calendar.current.date(bySettingHour: minutes.wrappedValue / 60 % 24, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date() },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                var m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                // Bedtime after midnight counts as late evening of the same day.
                if title == "Bedtime" && m < 4 * 60 { m += 24 * 60 }
                minutes.wrappedValue = m
            })
        return DatePicker(title, selection: date, displayedComponents: .hourAndMinute)
            .font(Theme.display(15))
            .tint(Theme.lime)
    }
}

/// After a workout or a sport (#496): the recovery meal's pointer and two ideas; "I ate this" counts it in Fuel.
struct RecoveryFuelCard: View {
    @Environment(AppModel.self) private var model
    @State private var store = FuelStore.shared
    @State private var done = false

    var body: some View {
        let now = Date()
        let plan = model.fuelPlan(on: now)
        if let slot = plan.slots.first(where: { $0.kind == .recovery }) ?? plan.slots.first(where: \.afterTraining) {
            let ideas = RecipeBook.ideas(for: slot, load: plan.load, prefs: store.prefs, favourites: store.saved.favourites,
                                         own: store.saved.recipes, day: store.key(now), count: 2)
            let ticked = done || store.log(now).ticks[slot.id] != nil
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("🍽️").font(.system(size: 26))
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.2)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("REFUEL · \(slot.time)").font(Theme.label(10)).tracking(1.2).opacity(0.85)
                        Text(slot.hint).font(Theme.display(17)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(ideas) { r in
                    HStack(spacing: 8) {
                        Text("\(r.emoji) \(r.name)").font(.subheadline.weight(.bold)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(r.protein) g protein · \(r.minutes) min").font(Theme.label(11)).opacity(0.85).lineLimit(1)
                    }
                }
                Button {
                    store.update(now, plan: plan) { $0.tick(slot) }
                    NotificationManager.shared.cancelRefuel(dayKey: store.key(now))
                    withAnimation(.snappy) { done = true }
                } label: {
                    Label(ticked ? "COUNTED IN FUEL" : "I ATE MY RECOVERY MEAL", systemImage: ticked ? "checkmark.circle.fill" : "fork.knife")
                }
                .buttonStyle(LimeButtonStyle())
                .disabled(ticked)
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(FuelPalette.hot))
            .task {
                let k = store.key(now)
                guard store.prefs.nudges, !ticked, store.saved.nudged != k, !model.demo else { return }
                store.markNudged(now)
                await NotificationManager.shared.scheduleRefuel(dayKey: k)
            }
        }
    }
}

/// First open of Fuel (#686, design A from `fuel-setup-skip/proposals.png`): Fuel shows the day at once with default
/// pointers; this card offers the settings. Later or ✕ hides it, Settings → You → Onboarding keeps the set-up.
struct FuelSetupCard: View {
    let setUp: () -> Void
    let later: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FIRST TIME HERE").font(Theme.label(10)).tracking(1.2).opacity(0.75)
                    Text("Set up Fuel").font(Theme.display(24))
                    Text("Goal, diet, avoid list and meals a day. Defaults until then.")
                        .font(.footnote.weight(.semibold)).opacity(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button(action: later) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .heavy))
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.ink.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide")
            }
            HStack(spacing: 8) {
                Button(action: setUp) {
                    Text("SET UP · 1 MIN").font(Theme.label(14)).foregroundStyle(Theme.lime)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.ink))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fuel.setupCard.setUp")
                Button(action: later) {
                    Text("LATER").font(Theme.label(14))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.ink.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fuel.setupCard.later")
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(FuelPalette.lime))
    }
}

/// Gradient Undo bar after Later on the Set up Fuel card (#686).
struct FuelSetupLaterBar: View {
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Fuel set-up later").font(Theme.display(15))
                Text("Settings → You → Onboarding").font(.caption.weight(.semibold)).opacity(0.85)
            }
            Spacer(minLength: 4)
            Button {
                Haptics.undo()
                undo()
            } label: {
                Text("UNDO").font(Theme.label(13))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.2)))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(FuelPalette.coach))
    }
}
