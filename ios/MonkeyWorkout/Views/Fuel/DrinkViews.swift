import SwiftUI
import WorkoutEngine

// Drinks and good times weeks (#1039, mix A + B + C from `drinks-log/{a,b,c}.png`). Kind words, no judgement:
// the app only helps the member bounce back. Everything stays on the phone.

enum DrinkPalette {
    static let party = [Color(hex: 0xFF7A00), Color(hex: 0xFF2E63)]
    static let night = [Color(hex: 0x7B2FF7), Color(hex: 0xF107A3)]
    static let water = [Color(hex: 0x0061FF), Color(hex: 0x60EFFF)]
    static let fresh = [Color(hex: 0x00C96B), Color(hex: 0x00A3FF)]
    static let gold = [Color(hex: 0xF7B500), Color(hex: 0xFF7A00)]

    static func fill(_ c: [Color]) -> LinearGradient { LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing) }

    static func colors(_ k: DrinkKind) -> [Color] {
        switch k {
        case .beer: gold
        case .wine: party
        case .cocktail: water
        case .shot: night
        }
    }
}

private func tile(_ symbol: String) -> some View {
    Image(systemName: symbol)
        .font(.system(size: 18, weight: .bold))
        .frame(width: 44, height: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
}

func goodTimesRange(_ p: GoodTimesPeriod) -> String {
    let cal = Progression.calendar()
    func d(_ k: String) -> String { PlanCalendar.date(k, cal).map { $0.formatted(.dateTime.weekday(.abbreviated).day()) } ?? k }
    return p.start == p.end ? d(p.start) : "\(d(p.start)) – \(d(p.end))"
}

// MARK: B · Drinks tally (Fuel, today)

/// Tonight's tally with +1 tiles; water +1 counts in the Fuel tank. Undo on every tap.
struct DrinksCard: View {
    @Environment(AppModel.self) private var model
    private var store: DrinkStore { DrinkStore.shared }

    var body: some View {
        let now = Date()
        let tonight = Drinks.tonight(store.saved.entries, now: now, calendar: model.planCalendar)
        let n = Drinks.total(tonight)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                tile("wineglass.fill")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Drinks tonight").font(.system(size: 17, weight: .heavy, design: .rounded))
                    Text(n == 0 ? "Going out? Tap as you go, tomorrow adapts" : "≈ \(Self.fmt(n)) standard · water between helps")
                        .font(Theme.label(11)).opacity(0.85).lineLimit(2)
                }
                Spacer(minLength: 0)
                Text(Self.fmt(n)).font(.system(size: 34, weight: .black, design: .rounded)).monospacedDigit()
            }
            HStack(spacing: 8) {
                ForEach([DrinkKind.beer, .wine, .cocktail]) { k in
                    plus(k.emoji, "\(k.label) +1", DrinkPalette.colors(k)) { add(k) }
                }
                plus("💧", "Water +1", DrinkPalette.fresh) {
                    Haptics.undo()
                    FuelStore.shared.addGlasses(1)
                }
            }
            Menu {
                ForEach(DrinkKind.allCases) { k in Button("\(k.emoji) \(k.label) +1") { add(k) } }
            } label: {
                Label("Other drink", systemImage: "plus").font(Theme.label(12)).opacity(0.9)
            }
            if !store.saved.guideSeen {
                HStack(alignment: .top, spacing: 8) {
                    Text(Drinks.guide).font(.footnote.weight(.semibold)).opacity(0.85)
                    Spacer(minLength: 0)
                    Button { withAnimation(.snappy) { store.hideGuide() } } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .heavy)).frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Hide the guide")
                }
            }
            if let s = model.drinksSupport {
                Text(s).font(.footnote.weight(.semibold)).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DrinkPalette.fill(DrinkPalette.night)))
        .accessibilityElement(children: .contain)
    }

    private func plus(_ emoji: String, _ label: String, _ colors: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(emoji).font(.system(size: 26))
                Text(label).font(Theme.label(11)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DrinkPalette.fill(colors)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func add(_ k: DrinkKind) {
        Haptics.undo()
        let e = withAnimation(.snappy) { store.add(k) }
        UndoCloseCenter.shared.show(UndoOffer(title: "\(k.label) +1", detail: "Drinks tonight", symbol: "wineglass.fill",
                                              colors: DrinkPalette.night, reopen: { AnyView(EmptyView()) },
                                              revert: { DrinkStore.shared.remove(e.id) }), haptic: false)
    }

    static func fmt(_ n: Double) -> String { n.rounded() == n ? "\(Int(n))" : String(format: "%.1f", n) }
}

// MARK: A · Good times week

/// The week's plan while a good times period runs (Train and Fuel). Each tile opens where it acts.
struct GoodTimesCard: View {
    let period: GoodTimesPeriod
    @Environment(AppModel.self) private var model
    @State private var editing = false

    var body: some View {
        let today = PlanCalendar.key(Date(), model.planCalendar)
        let on = period.covers(today)
        VStack(alignment: .leading, spacing: 10) {
            Button { editing = true } label: {
                HStack(spacing: 12) {
                    tile("party.popper.fill")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(on ? "Good times week" : "Good times ahead").font(.system(size: 17, weight: .heavy, design: .rounded))
                        Text([goodTimesRange(period), period.note].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.label(11)).opacity(0.85).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.bold()).opacity(0.8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edits the dates")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                square("Workouts", "Light", "1 RPE easier, no PR tries", DrinkPalette.night) { model.tab = .train }
                square("Water", "+\(Drinks.goodTimesWater)", "glasses a day", DrinkPalette.water) { model.tab = .fuel }
                square("Fuel", "🍳", "protein + salty breakfasts", DrinkPalette.fresh) { model.tab = .fuel }
                square("Mind", "22:30", "wind down, breathe", DrinkPalette.gold) { model.tab = .progress }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DrinkPalette.fill(DrinkPalette.party)))
        .sheet(isPresented: $editing) { GoodTimesEditor(initial: period, isNew: false) }
    }

    private func square(_ title: String, _ value: String, _ sub: String, _ colors: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.label(11)).opacity(0.9)
                Text(value).font(.system(size: 24, weight: .black, design: .rounded))
                Text(sub).font(Theme.label(10)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DrinkPalette.fill(colors)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(value), \(sub)")
    }
}

/// New good times week (Save) or an existing one (auto-saved, Remove with Undo).
struct GoodTimesEditor: View {
    let initial: GoodTimesPeriod
    let isNew: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var from = Date()
    @State private var to = Date()
    @State private var note = ""
    @State private var loaded = false

    private var period: GoodTimesPeriod {
        let cal = Progression.calendar()
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return GoodTimesPeriod(id: initial.id, start: PlanCalendar.key(from, cal), end: PlanCalendar.key(max(from, to), cal),
                               note: n.isEmpty ? nil : String(n.prefix(40)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 0) {
                        DatePicker("From", selection: $from, displayedComponents: .date).padding(.vertical, 6)
                        Divider().overlay(Theme.stroke)
                        DatePicker("To", selection: $to, in: from..., displayedComponents: .date).padding(.vertical, 6)
                        Divider().overlay(Theme.stroke)
                        TextField("What's on (optional)", text: $note).padding(.vertical, 12)
                    }
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .card(padding: 14)
                    Text("While it runs").eyebrow()
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Drinks.goodTimesRules, id: \.self) { r in
                            Label(r, systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold))
                        }
                    }
                    .card(padding: 14)
                    Text("No workout within 12 hours of drinking. Stays on this phone, never shared.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                    if isNew {
                        Button("Save") {
                            DrinkStore.shared.savePeriod(period)
                            Haptics.success()
                            dismiss()
                        }
                        .buttonStyle(LimeButtonStyle())
                    } else {
                        Text("Changes save on their own.").font(.footnote).foregroundStyle(Theme.muted)
                        Button(role: .destructive) {
                            let stored = DrinkStore.shared.saved.periods.first { $0.id == initial.id } ?? period
                            DrinkStore.shared.deletePeriod(initial.id)
                            dismiss()
                            UndoCloseCenter.shared.deleted("Good times week removed", detail: goodTimesRange(stored), symbol: "party.popper.fill") {
                                DrinkStore.shared.savePeriod(stored)
                            }
                        } label: {
                            Text("Remove").font(Theme.label(15)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                    }
                }
                .padding(16)
            }
            .readableWidth()
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(isNew ? "Good times week" : "Edit good times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let cal = Progression.calendar()
            from = PlanCalendar.date(initial.start, cal) ?? Date()
            to = PlanCalendar.date(initial.end, cal) ?? from
            note = initial.note ?? ""
        }
        .onChange(of: period) { _, p in
            // Auto save on edit screens; a new one keeps Save.
            if !isNew && loaded { DrinkStore.shared.savePeriod(p) }
        }
    }
}

extension GoodTimesPeriod {
    /// A new week from today: today to 6 days on.
    static func fromToday() -> GoodTimesPeriod {
        let cal = Progression.calendar()
        let end = cal.date(byAdding: .day, value: 6, to: Date()) ?? Date()
        return GoodTimesPeriod(start: PlanCalendar.key(Date(), cal), end: PlanCalendar.key(end, cal))
    }
}

// MARK: C · Morning after (Train)

/// After a night out: what helps today, ticked as the member goes; Easy day moves a heavy session to a free day.
struct MorningAfterCard: View {
    let steps: [Drinks.Step]
    @Environment(AppModel.self) private var model
    /// Ticked steps, "yyyy-MM-dd:kind,…", for today only.
    @AppStorage("drinksMorningTicks") private var ticks = ""

    private var todayKey: String { PlanCalendar.key(Date(), model.planCalendar) }
    private var done: Set<String> {
        let parts = ticks.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == todayKey else { return [] }
        return Set(parts[1].split(separator: ",").map(String.init))
    }

    var body: some View {
        let n = model.drinksLastNight()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                tile("sunrise.fill")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Morning after · \(DrinksCard.fmt(n)) drinks").font(Theme.label(10)).tracking(1.2).textCase(.uppercase).opacity(0.85)
                    Text("Bounce back today").font(.system(size: 16, weight: .heavy, design: .rounded))
                }
                Spacer(minLength: 0)
                Text("\(model.tuneVerdict.score)").font(.system(size: 30, weight: .black, design: .rounded)).monospacedDigit()
                    .accessibilityLabel("Readiness \(model.tuneVerdict.score)")
            }
            VStack(spacing: 0) {
                ForEach(steps) { s in row(s) }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.12)))
            if let swap = model.drinksSwap {
                Button {
                    Haptics.start()
                    withAnimation(.snappy) { model.takeRecoverSwap(swap) }
                } label: {
                    Text("Easy day: \(swap.session.focus.label) → \(WeekSchedule.name(swap.to))")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Capsule().fill(.white))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Moves today's workout and makes today a recover day")
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DrinkPalette.fill(DrinkPalette.party)))
    }

    private func row(_ s: Drinks.Step) -> some View {
        let on = done.contains(s.id)
        return Button { toggle(s) } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20, weight: .bold))
                Text(s.title).font(.subheadline.weight(.bold)).strikethrough(on).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Text(s.value).font(.system(size: 15, weight: .heavy, design: .rounded))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(on ? "Done" : "Not done")
    }

    private func toggle(_ s: Drinks.Step) {
        Haptics.undo()
        var d = done
        if d.contains(s.id) { d.remove(s.id) } else { d.insert(s.id) }
        ticks = "\(todayKey):" + d.sorted().joined(separator: ",")
    }
}
