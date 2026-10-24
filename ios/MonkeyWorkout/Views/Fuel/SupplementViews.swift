import SwiftUI
import WorkoutEngine

// Supplements in Fuel (#514, all three designs from `nutrition-pointers/supplements.png`): A on the timeline,
// B the My stack card with a caffeine meter, C what they add to the day's numbers.

/// B · Today's stack, ticked like meals, with the caffeine meter. An add tile when the stack is empty.
struct FuelStackCard: View {
    let plan: FuelPlan
    let log: FuelDayLog
    let day: Date
    @State private var store = FuelStore.shared

    var body: some View {
        if store.stack.isEmpty {
            NavigationLink(value: FuelRoute.supplements) {
                FuelTile(emoji: "💊", label: "Supplements", title: "Add your supplements",
                         detail: "Placed around training, caffeine checked against your sleep", gradient: FuelPalette.violet) {
                    Image(systemName: "plus").font(.system(size: 18, weight: .heavy))
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("fuel.supplements")
        } else {
            let doses = plan.supplements
            let taken = doses.filter { log.ticks[$0.id] != nil }.count
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("MY STACK · \(Calendar.current.isDateInToday(day) ? "TODAY" : day.formatted(.dateTime.weekday(.wide)).uppercased())")
                            .font(Theme.label(10)).tracking(1.2).opacity(0.85)
                        Spacer()
                        if !doses.isEmpty { Text("\(taken)/\(doses.count)").font(Theme.display(17)).monospacedDigit() }
                        NavigationLink(value: FuelRoute.supplements) {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 14, weight: .heavy))
                                .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit supplements")
                    }
                    if doses.isEmpty {
                        Text(store.stack.allSatisfy(\.whenPicked) ? "Nothing scheduled: pick yours in Just ate when you have one."
                             : "Nothing today: your stack is for training days.").font(.footnote.weight(.bold)).opacity(0.85)
                    }
                    ForEach(doses) { d in
                        SupplementDoseRow(dose: d, plan: plan, log: log, day: day)
                    }
                    let protein = Supplements.proteinTaken(doses, log: log)
                    if protein >= 1 && !store.prefs.noNumbers {
                        Text("🥛 \(Int(protein.rounded())) g protein from supplements counted in today's protein")
                            .font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.9)
                    }
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.violet))

                if store.stack.contains(where: { $0.caffeineMg > 0 }) {
                    CaffeineMeter(doses: doses, log: log, prefs: store.prefs)
                }
            }
        }
    }
}

/// One supplement on the day, with its tick.
struct SupplementDoseRow: View {
    let dose: SupplementDose
    let plan: FuelPlan
    let log: FuelDayLog
    let day: Date
    @State private var store = FuelStore.shared

    var body: some View {
        let done = log.ticks[dose.id] != nil
        HStack(spacing: 10) {
            Text(dose.supplement.emoji).font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 2) {
                Text(dose.supplement.name).font(Theme.display(15)).lineLimit(1).minimumScaleFactor(0.8)
                Text("\(dose.time) · \(dose.reason)\(dose.supplement.dose.isEmpty ? "" : " · \(dose.supplement.dose)")")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.85).lineLimit(2)
                if !dose.supplement.contents.isEmpty && !store.prefs.noNumbers {
                    Text(dose.supplement.contents.joined(separator: "  ")).font(Theme.label(10)).opacity(0.9).lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if dose.late {
                    Label("After your caffeine cut-off", systemImage: "moon.zzz.fill")
                        .font(Theme.label(10)).foregroundStyle(Color(hex: 0xFFD23D))
                }
            }
            Spacer(minLength: 4)
            Button {
                store.update(day, plan: plan) { l in if done { l.untick(dose) } else { l.tick(dose) } }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 26, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Taken, tap to undo" : "Mark taken")
        }
        .opacity(done ? 0.75 : 1)
    }
}

/// Caffeine today against the 400 mg guide, and the last time for the member's bedtime.
struct CaffeineMeter: View {
    let doses: [SupplementDose]
    let log: FuelDayLog
    let prefs: FuelPrefs

    var body: some View {
        let taken = Supplements.caffeineTaken(doses, log: log)
        let planned = Supplements.caffeine(doses)
        let guide = Supplements.caffeineGuideMg
        let items = doses.filter { $0.supplement.caffeineMg > 0 }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("CAFFEINE TODAY").font(Theme.label(10)).tracking(1.2).opacity(0.85)
                Spacer()
                Text("\(taken)").font(Theme.display(24)).monospacedDigit()
                Text("/ \(guide) mg").font(Theme.label(11)).opacity(0.85)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.25))
                    Capsule().fill(.white.opacity(0.35)).frame(width: g.size.width * min(1, Double(planned) / Double(guide)))
                    Capsule().fill(Theme.lime).frame(width: g.size.width * min(1, Double(taken) / Double(guide)))
                }
            }
            .frame(height: 8)
            Text((items.map { "\($0.supplement.emoji) \($0.supplement.name) \($0.supplement.caffeineMg)" } + ["planned \(planned) mg"])
                .joined(separator: " · "))
                .font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.9)
            Text("Last caffeine by \(Supplements.clock(Supplements.caffeineCutoff(prefs))) for \(Supplements.clock(prefs.sleep)) sleep")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.hot))
        .accessibilityElement(children: .combine)
    }
}

/// The member's stack: tap one to edit, add from a kind.
struct SupplementsView: View {
    @State private var store = FuelStore.shared
    @State private var editing: Supplement?
    @State private var adding: Supplement?
    @State private var browsing = false
    @State private var picked: Supplement?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !store.stack.isEmpty {
                    Text("My stack · \(store.stack.count)").eyebrow()
                    ForEach(store.stack) { s in
                        Button { editing = s } label: {
                            HStack(spacing: 10) {
                                Text(s.emoji).font(.system(size: 22))
                                    .frame(width: 44, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.2)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.name).font(Theme.display(16)).lineLimit(1)
                                    Text(s.whenPicked ? "When you pick it · Just ate, meal plan" : s.schedule.summary(calendar: .current))
                                        .font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.85).lineLimit(2)
                                    if !s.whenPicked, let course = s.schedule.courseLine(now: Date(), calendar: .current) {
                                        Text(course).font(Theme.label(10)).opacity(0.9).lineLimit(1).minimumScaleFactor(0.7)
                                    }
                                    if !s.contents.isEmpty {
                                        Text(s.contents.joined(separator: "  ")).font(Theme.label(10)).opacity(0.9).lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy))
                            }
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Self.gradient(s.kind)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Add a supplement").eyebrow()
                Button { browsing = true } label: {
                    HStack(spacing: 10) {
                        Text("🥤").font(.system(size: 22))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("From a brand").font(Theme.display(16))
                            Text("Huel, yfood, Saturo, Jimmy Joy, KaEx… with their variants").font(Theme.label(11)).opacity(0.9).lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(FuelPalette.hot))
                }
                .buttonStyle(.plain)
                FlowLayout(spacing: 6) {
                    ForEach(SupplementKind.allCases) { k in
                        Button { adding = k.preset } label: {
                            Text("\(k.emoji) \(k == .other ? "My own" : k.label)").font(Theme.label(12)).foregroundStyle(.white)
                                .padding(.horizontal, 11).padding(.vertical, 8)
                                .background(Capsule().fill(Theme.card))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Amounts come from your label: scan it when you add one. Fuel places each supplement around your training, counts protein from shakes, adds a glass on creatine days and checks caffeine against your bedtime. Pointers only, not medical advice.")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Supplements")
        .sheet(item: $editing) { s in NavigationStack { SupplementEditor(supplement: s, isNew: false) } }
        .sheet(item: $adding) { s in NavigationStack { SupplementEditor(supplement: s, isNew: true) } }
        // The editor opens once the brand sheet is gone.
        .sheet(isPresented: $browsing, onDismiss: {
            adding = picked
            picked = nil
        }) {
            ProductCatalogSheet(action: "Next", picked: { v, n in
                // Meals default to "when you pick it"; the editor sets a schedule if the member wants one.
                picked = ProductCatalog.mine(v, servings: n, onDemand: v.isMeal)
            }, own: { picked = SupplementKind.other.preset })
        }
    }

    static func gradient(_ k: SupplementKind) -> LinearGradient {
        switch k {
        case .mealReplacement, .hotMeal: FuelPalette.lime
        case .preWorkout, .caffeine: FuelPalette.hot
        case .creatine, .protein: FuelPalette.violet
        case .electrolytes: FuelPalette.water
        case .vitaminD, .omega3: FuelPalette.mint
        case .magnesium, .other: FuelPalette.coach
        }
    }
}

/// Add or edit one supplement (#572, designs A + C): a gradient card for the product, quick plan tiles, then the rhythm
/// (how often, times a day, course, cycle, loading, reminders) and the label amounts that fit its type.
/// Editing saves on its own; a new one keeps Save.
struct SupplementEditor: View {
    let supplement: Supplement
    let isNew: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared
    @State private var draft: Supplement?
    @State private var scanning = false

    private var cal: Calendar { .current }

    var body: some View {
        let d = Binding(get: { draft ?? supplement }, set: { draft = $0 })
        // Any change to the schedule saves it as the member's own, from today when it had no start.
        let r = Binding<SupplementRhythm>(get: { d.wrappedValue.schedule }, set: { v in
            var v = v
            if v.start == .distantPast { v.start = cal.startOfDay(for: Date()) }
            d.wrappedValue.rhythm = v
        })
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                hero(d, r.wrappedValue)
                SupplementTypeStrip(kind: d.wrappedValue.kind) { k in d.wrappedValue = d.wrappedValue.switching(to: k) }
                Toggle(isOn: Binding(get: { d.wrappedValue.whenPicked }, set: { d.wrappedValue.onDemand = $0 ? true : nil })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Only when I pick it").font(Theme.display(15))
                        Text(d.wrappedValue.isMeal ? "No schedule: pick it in Just ate or for a meal plan meal."
                             : "No schedule: tap it in Just ate when you have it.")
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.lime)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                if !d.wrappedValue.whenPicked {
                    Text("Pick a plan").eyebrow().padding(.top, 6)
                    SupplementQuickGrid(rhythm: r, kind: d.wrappedValue.kind)
                    SupplementSummaryCard(rhythm: r.wrappedValue, servingLabel: d.wrappedValue.dose)
                    SupplementRhythmBuilder(rhythm: r, kind: d.wrappedValue.kind)
                }
                amounts(d)
                if !isNew {
                    Button(role: .destructive) { remove() } label: {
                        Text("Remove from my stack").font(Theme.label(14)).frame(maxWidth: .infinity).padding(14)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0xFF3D6E).opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(hex: 0xFF6B9A))
                }
                Text("Pointers only, not medical advice: amounts and timings come from your label or your coach.")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(isNew ? "New supplement" : "Edit supplement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            CloseToolbarItem(placement: .topBarTrailing) { dismiss() }
            if isNew {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Save") {
                        var s = d.wrappedValue
                        s.name = s.name.trimmingCharacters(in: .whitespaces)
                        store.saveSupplement(s)
                        dismiss()
                    }
                    .bold()
                    .disabled(d.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .modifier(EditorAutoSave(enabled: !isNew, draft: draft))
        .onAppear { if draft == nil { draft = supplement } }
        .sheet(isPresented: $scanning) {
            SupplementLabelScan { found in
                var s = d.wrappedValue
                if found.caffeineMg > 0 { s.caffeineMg = found.caffeineMg }
                if found.creatineG > 0 { s.creatineG = found.creatineG }
                if found.proteinG > 0 { s.proteinG = found.proteinG }
                if found.carbsG > 0 { s.carbsG = found.carbsG }
                if found.fatG > 0 { s.fatG = found.fatG }
                draft = s
            }
        }
    }

    /// Removed at once (#717); the Undo bar puts it back with its meal plan meals.
    private func remove() {
        // No auto save of the open edits after it's gone.
        draft = nil
        let removed = store.deleteSupplement(supplement.id)
        dismiss()
        guard let removed else { return }
        UndoCloseCenter.shared.deleted("\(removed.supplement.name) removed", detail: "From my stack") {
            FuelStore.shared.restoreSupplement(removed.supplement, meals: removed.meals)
        }
    }

    /// Product card: emoji tile, name and serving, takes a day big on the right.
    private func hero(_ d: Binding<Supplement>, _ r: SupplementRhythm) -> some View {
        HStack(spacing: 12) {
            Text(d.wrappedValue.emoji).font(.system(size: 26))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 4) {
                TextField("Name, e.g. KaEx Boost+", text: d.name).font(Theme.display(19))
                TextField("Serving, e.g. 1 scoop", text: d.dose).font(.system(size: 13, weight: .bold, design: .rounded)).opacity(0.9)
            }
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(r.perDay)×").font(Theme.display(34))
                Text(r.days == .everyDay ? "a day" : r.daysLabel(calendar: cal)).font(Theme.label(10)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(minWidth: 56, alignment: .trailing)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SupplementsView.gradient(d.wrappedValue.kind)))
    }

    /// Per serving: only the amounts that fit the type (and any already set).
    private func amounts(_ d: Binding<Supplement>) -> some View {
        let s = d.wrappedValue
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Per serving").eyebrow()
                Spacer()
                if LiveFoodScanner.available {
                    Button { scanning = true } label: {
                        Label("Scan the label", systemImage: "text.viewfinder").font(Theme.label(12)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                }
            }
            if s.asksCaffeine {
                AmountTile(emoji: "⚡", title: "Caffeine", value: "\(s.caffeineMg) mg", fill: FuelPalette.hot,
                           minus: { d.wrappedValue.caffeineMg = max(0, s.caffeineMg - 5) }, plus: { d.wrappedValue.caffeineMg = min(400, s.caffeineMg + 5) })
            }
            if s.asksCreatine {
                AmountTile(emoji: "💪", title: "Creatine", value: Self.g(s.creatineG), fill: FuelPalette.violet,
                           minus: { d.wrappedValue.creatineG = max(0, s.creatineG - 0.5) }, plus: { d.wrappedValue.creatineG = min(20, s.creatineG + 0.5) })
            }
            if s.asksProtein {
                AmountTile(emoji: "🥛", title: "Protein", value: Self.g(s.proteinG), fill: FuelPalette.protein,
                           minus: { d.wrappedValue.proteinG = max(0, s.proteinG - 1) }, plus: { d.wrappedValue.proteinG = min(80, s.proteinG + 1) })
            }
            if s.isMeal {
                AmountTile(emoji: "🍚", title: "Carbs", value: Self.g(s.carbsG), fill: FuelPalette.carbs,
                           minus: { d.wrappedValue.carbsG = max(0, s.carbsG - 1) }, plus: { d.wrappedValue.carbsG = min(150, s.carbsG + 1) })
                AmountTile(emoji: "🥑", title: "Fat", value: Self.g(s.fatG), fill: FuelPalette.mint,
                           minus: { d.wrappedValue.fatG = max(0, s.fatG - 1) }, plus: { d.wrappedValue.fatG = min(80, s.fatG + 1) })
            }
            Text(s.isMeal ? "≈ \(s.kcal) kcal. Ticking it fills the meal at that time with these macros."
                 : "Protein counts toward your protein palms when you tick it. Creatine adds a glass to the day's water. Caffeine shows on the meter and is checked against your bedtime.")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
        }
        .padding(.top, 6)
    }

    static func g(_ v: Double) -> String { v.rounded() == v ? "\(Int(v)) g" : String(format: "%.1f g", v) }
}

/// Type as emoji chips; switching refills what the member hadn't changed.
private struct SupplementTypeStrip: View {
    let kind: SupplementKind
    let pick: (SupplementKind) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SupplementKind.allCases) { k in
                    Button { pick(k) } label: {
                        Text("\(k.emoji) \(k.label)").font(Theme.label(12)).foregroundStyle(k == kind ? Theme.ink : .white)
                            .padding(.horizontal, 11).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(k == kind ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.cardStrong)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(k == kind ? .isSelected : [])
                }
            }
        }
    }
}

/// Quick plans (design C): gradient tiles, the matching one outlined; "My own" scrolls to the builder below.
private struct SupplementQuickGrid: View {
    @Binding var rhythm: SupplementRhythm
    let kind: SupplementKind

    private static let fills: [SupplementRhythm.Quick: LinearGradient] = [
        .daily: FuelPalette.hot, .twice: FuelPalette.water, .training: FuelPalette.coach, .load: FuelPalette.violet, .cycle: FuelPalette.carbs,
    ]

    var body: some View {
        let current = rhythm.quick(kind)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(SupplementRhythm.Quick.allCases) { q in
                Button {
                    var r = SupplementRhythm.quick(q, kind: kind, start: rhythm.start == .distantPast ? Calendar.current.startOfDay(for: Date()) : rhythm.start)
                    r.length = rhythm.length
                    r.remind = rhythm.remind
                    if let s = rhythm.intakes.first?.servings { r.intakes = r.intakes.map { var i = $0; i.servings = s; return i } }
                    rhythm = r
                } label: {
                    tile(q.title, q.detail, fill: Self.fills[q] ?? FuelPalette.lime, on: current == q)
                }
                .buttonStyle(.plain)
            }
            tile("My own", current == nil ? "Set below" : "Times, days, length", fill: nil, on: current == nil)
        }
    }

    private func tile(_ title: String, _ detail: String, fill: LinearGradient?, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Theme.display(15)).lineLimit(1).minimumScaleFactor(0.8)
            Text(detail).font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.85).lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Theme.cardStrong)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white, lineWidth: on ? 3 : 0))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The plan in a sentence (design C).
private struct SupplementSummaryCard: View {
    let rhythm: SupplementRhythm
    let servingLabel: String

    var body: some View {
        let cal = Calendar.current
        VStack(alignment: .leading, spacing: 4) {
            Text("Your plan").eyebrow()
            Text(rhythm.summary(calendar: cal)).font(Theme.display(17)).foregroundStyle(Theme.lime)
            Text(rhythm.intakes.map { take in
                let n = take.servings.rounded() == take.servings ? "\(Int(take.servings))" : String(format: "%.1f", take.servings)
                return "\(take.minute.map { Supplements.clock($0) } ?? take.timing.label) · \(n) × \(servingLabel.isEmpty ? "serving" : servingLabel)"
            }.joined(separator: "\n"))
            .font(.system(size: 13, weight: .bold, design: .rounded))
            if let c = rhythm.courseLine(now: Date(), calendar: cal) {
                Text(c).font(Theme.label(11)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
    }
}

/// Rhythm builder (design A): how often, times a day, course, cycle, loading, reminders.
private struct SupplementRhythmBuilder: View {
    @Binding var rhythm: SupplementRhythm
    let kind: SupplementKind

    private var cal: Calendar { .current }
    private enum Often: String, CaseIterable { case every = "Every day", training = "Training days", pick = "Pick days", everyN = "Every N days" }
    private enum Course: String, CaseIterable { case ongoing = "Ongoing", weeks = "N weeks", until = "Until a date" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How often").eyebrow().padding(.top, 6)
            chips(Often.allCases.map(\.rawValue), on: often.rawValue) { v in setOften(Often(rawValue: v) ?? .every) }
            switch rhythm.days {
            case .weekdays(let w): weekdays(w)
            case .everyN(let k):
                PlusMinusRow(title: "Every \(k) days", minus: { rhythm.days = .everyN(max(2, k - 1)) }, plus: { rhythm.days = .everyN(min(14, k + 1)) })
            default: EmptyView()
            }

            Text("Times a day").eyebrow().padding(.top, 6)
            ForEach(rhythm.intakes.indices, id: \.self) { i in intakeRow(i) }
            if rhythm.intakes.count < 6 {
                Button {
                    let used = Set(rhythm.intakes.map(\.timing))
                    let next = [SupplementTiming.evening, .lunch, .bedtime, .afterTraining, .breakfast].first { !used.contains($0) } ?? .evening
                    rhythm.intakes.append(.init(timing: next, servings: rhythm.intakes.first?.servings ?? 1))
                } label: {
                    Text("+ Add a time").font(Theme.label(13)).foregroundStyle(Theme.lime).frame(maxWidth: .infinity).padding(11)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 2, dash: [6])))
                }
                .buttonStyle(.plain)
            }

            Text("Course").eyebrow().padding(.top, 6)
            VStack(alignment: .leading, spacing: 8) {
                chips(Course.allCases.map(\.rawValue), on: course.rawValue) { v in setCourse(Course(rawValue: v) ?? .ongoing) }
                switch rhythm.length {
                case .weeks(let w):
                    PlusMinusRow(title: "\(w) weeks", minus: { rhythm.length = .weeks(max(1, w - 1)) }, plus: { rhythm.length = .weeks(min(104, w + 1)) })
                case .until(let last):
                    DatePicker("Last day", selection: Binding(get: { last }, set: { rhythm.length = .until($0) }), in: rhythm.start..., displayedComponents: .date)
                        .font(Theme.label(13))
                case .ongoing: EmptyView()
                }
                DatePicker("Starts", selection: Binding(get: { rhythm.start == .distantPast ? Date() : rhythm.start },
                                                        set: { rhythm.start = cal.startOfDay(for: $0) }), displayedComponents: .date)
                    .font(Theme.label(13))
                CourseTrack(rhythm: rhythm)
                Toggle(isOn: Binding(get: { rhythm.cycle != nil }, set: { rhythm.cycle = $0 ? .init(onWeeks: 8, offWeeks: 4) : nil })) {
                    Text("Cycle on and off").font(Theme.label(13))
                }
                .tint(Theme.lime)
                if let c = rhythm.cycle {
                    PlusMinusRow(title: "\(c.onWeeks) weeks on", minus: { rhythm.cycle?.onWeeks = max(1, c.onWeeks - 1) },
                                 plus: { rhythm.cycle?.onWeeks = min(26, c.onWeeks + 1) })
                    PlusMinusRow(title: "\(c.offWeeks) weeks off", minus: { rhythm.cycle?.offWeeks = max(1, c.offWeeks - 1) },
                                 plus: { rhythm.cycle?.offWeeks = min(26, c.offWeeks + 1) })
                }
                Toggle(isOn: Binding(get: { rhythm.loadDays > 0 }, set: { rhythm.loadDays = $0 ? 7 : 0 })) {
                    Text("Loading phase first").font(Theme.label(13))
                }
                .tint(Theme.lime)
                if rhythm.loadDays > 0 {
                    PlusMinusRow(title: "\(rhythm.loadTimes)× a day", minus: { rhythm.loadTimes = max(2, rhythm.loadTimes - 1) },
                                 plus: { rhythm.loadTimes = min(4, rhythm.loadTimes + 1) })
                    PlusMinusRow(title: "for \(rhythm.loadDays) days", minus: { rhythm.loadDays = max(1, rhythm.loadDays - 1) },
                                 plus: { rhythm.loadDays = min(14, rhythm.loadDays + 1) })
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))

            Toggle(isOn: $rhythm.remind) {
                Label("Remind me at each time", systemImage: "bell.fill").font(Theme.label(13))
            }
            .tint(Theme.lime)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        }
    }

    private var often: Often {
        switch rhythm.days {
        case .everyDay: .every
        case .trainingDays: .training
        case .weekdays: .pick
        case .everyN: .everyN
        }
    }

    private func setOften(_ o: Often) {
        switch o {
        case .every: rhythm.days = .everyDay
        case .training: rhythm.days = .trainingDays
        case .pick: if case .weekdays = rhythm.days {} else { rhythm.days = .weekdays([2, 3, 4, 5, 6]) }
        case .everyN: if case .everyN = rhythm.days {} else { rhythm.days = .everyN(2) }
        }
    }

    private var course: Course {
        switch rhythm.length {
        case .ongoing: .ongoing
        case .weeks: .weeks
        case .until: .until
        }
    }

    private func setCourse(_ c: Course) {
        switch c {
        case .ongoing: rhythm.length = .ongoing
        case .weeks: if case .weeks = rhythm.length {} else { rhythm.length = .weeks(12) }
        case .until:
            if case .until = rhythm.length {} else {
                let from = rhythm.start == .distantPast ? Date() : rhythm.start
                rhythm.length = .until(cal.date(byAdding: .day, value: 30, to: from) ?? from)
            }
        }
    }

    private func chips(_ items: [String], on: String, pick: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { v in
                SelectChip(title: v, on: v == on, onFill: AnyShapeStyle(Theme.lime), offFill: AnyShapeStyle(Theme.cardStrong),
                           offInk: .white, size: 12, height: 32, fills: false) { pick(v) }
            }
        }
    }

    private func weekdays(_ w: [Int]) -> some View {
        let order = (0..<7).map { (cal.firstWeekday - 1 + $0) % 7 + 1 }
        return HStack(spacing: 5) {
            ForEach(order, id: \.self) { day in
                let on = w.contains(day)
                Button {
                    var set = Set(w)
                    if on { if set.count > 1 { set.remove(day) } } else { set.insert(day) }
                    rhythm.days = .weekdays(set.sorted())
                } label: {
                    Text(cal.veryShortWeekdaySymbols[day - 1]).font(Theme.label(13)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? AnyShapeStyle(FuelPalette.violet) : AnyShapeStyle(Theme.cardStrong)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(cal.weekdaySymbols[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private static let rowFills = [FuelPalette.hot, FuelPalette.water, FuelPalette.coach, FuelPalette.violet, FuelPalette.mint, FuelPalette.carbs]

    /// One take: moment or set time, servings, remove.
    private func intakeRow(_ i: Int) -> some View {
        let take = rhythm.intakes[i]
        let n = take.servings.rounded() == take.servings ? "\(Int(take.servings))" : String(format: "%.1f", take.servings)
        return HStack(spacing: 8) {
            Menu {
                ForEach(SupplementTiming.allCases) { t in
                    Button(t.label) { rhythm.intakes[i].timing = t; rhythm.intakes[i].minute = nil }
                }
                Button("At a set time") { rhythm.intakes[i].minute = rhythm.intakes[i].minute ?? 8 * 60 }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(take.minute == nil ? take.timing.label : "At a set time").font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.8)
                    Text("\(n) serving\(take.servings == 1 ? "" : "s") · change").font(.system(size: 10, weight: .bold, design: .rounded)).opacity(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let m = take.minute {
                DatePicker("", selection: Binding(get: {
                    Calendar.current.date(byAdding: .minute, value: m, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                }, set: { d in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                    rhythm.intakes[i].minute = (c.hour ?? 8) * 60 + (c.minute ?? 0)
                }), displayedComponents: .hourAndMinute)
                .labelsHidden()
            }
            SmallStep(symbol: "minus") { rhythm.intakes[i].servings = max(0.5, take.servings - 0.5) }
            SmallStep(symbol: "plus") { rhythm.intakes[i].servings = min(10, take.servings + 0.5) }
            if rhythm.intakes.count > 1 {
                SmallStep(symbol: "xmark") { rhythm.intakes.remove(at: i) }.accessibilityLabel("Remove this time")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Self.rowFills[i % Self.rowFills.count]))
    }
}

/// Weeks of the course as squares: lime on, plum off, dim past the end.
private struct CourseTrack: View {
    let rhythm: SupplementRhythm

    var body: some View {
        let cal = Calendar.current
        let total: Int = {
            switch rhythm.length {
            case .weeks(let w): return w
            case .until(let d): return max(1, ((cal.dateComponents([.day], from: rhythm.start, to: d).day ?? 0) / 7) + 1)
            case .ongoing: return rhythm.cycle.map { $0.onWeeks + $0.offWeeks } ?? 0
            }
        }()
        let shown = min(total, 26)
        let now = rhythm.start == .distantPast ? 0 : max(0, (cal.dateComponents([.day], from: rhythm.start, to: Date()).day ?? 0) / 7)
        if shown > 0 {
            HStack(spacing: 3) {
                ForEach(0..<shown, id: \.self) { w in
                    let off = rhythm.cycle.map { w % ($0.onWeeks + $0.offWeeks) >= $0.onWeeks } ?? false
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(off ? Color(hex: 0x5A3D7A) : Theme.lime)
                        .opacity(w < now ? 0.45 : 1)
                        .frame(height: 12)
                        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(.white, lineWidth: w == now ? 2 : 0))
                }
            }
            .accessibilityHidden(true)
        }
    }
}

private struct PlusMinusRow: View {
    let title: String
    let minus: () -> Void
    let plus: () -> Void

    var body: some View {
        HStack {
            Text(title).font(Theme.display(17))
            Spacer()
            SmallStep(symbol: "minus", action: minus)
            SmallStep(symbol: "plus", action: plus)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardStrong))
    }
}

private struct SmallStep: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "More" : symbol == "minus" ? "Less" : "Remove")
    }
}

/// One label amount: emoji tile left, value big, − + right.
private struct AmountTile: View {
    let emoji: String
    let title: String
    let value: String
    let fill: LinearGradient
    let minus: () -> Void
    let plus: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(emoji).font(.system(size: 18)).frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.22)))
            Text(title).font(Theme.label(13))
            Spacer()
            Text(value).font(Theme.display(20))
            SmallStep(symbol: "minus", action: minus).accessibilityLabel("Less \(title.lowercased())")
            SmallStep(symbol: "plus", action: plus).accessibilityLabel("More \(title.lowercased())")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
    }
}

/// Existing supplements save on their own (#437); new ones keep the Save button.
private struct EditorAutoSave: ViewModifier {
    let enabled: Bool
    let draft: Supplement?

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.autoSave(draft, title: "Supplement saved", detail: { $0.name }, save: { s in
                guard !s.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                FuelStore.shared.saveSupplement(s)
            })
        } else {
            content
        }
    }
}

/// Live text on the label: caffeine, creatine and protein per serving.
struct SupplementLabelScan: View {
    let onFound: (Supplements.LabelAmounts) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var found: Supplements.LabelAmounts?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                LiveFoodScanner(onText: { t in
                    text += "\n" + t
                    if let f = Supplements.parse(label: text) { found = f }
                }, onBarcode: { _ in })
                .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 8) {
                    Text(found == nil ? "Point at the nutrition table" : "Found on the label").font(Theme.display(17))
                    if let f = found {
                        Text([f.caffeineMg > 0 ? "⚡ \(f.caffeineMg) mg caffeine" : nil,
                              f.creatineG > 0 ? "💪 \(SupplementEditor.g(f.creatineG)) creatine" : nil,
                              f.proteinG > 0 ? "🥛 \(SupplementEditor.g(f.proteinG)) protein" : nil,
                              f.carbsG > 0 ? "🍚 \(SupplementEditor.g(f.carbsG)) carbs" : nil,
                              f.fatG > 0 ? "🧈 \(SupplementEditor.g(f.fatG)) fat" : nil].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.label(13))
                        Button {
                            onFound(f)
                            dismiss()
                        } label: { Text("USE THESE AMOUNTS") }
                            .buttonStyle(LimeButtonStyle())
                    }
                    Text("Read on your iPhone. Check the amounts per serving before saving.")
                        .font(.caption2.weight(.semibold)).opacity(0.75)
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.black.opacity(0.7)))
                .padding(12)
            }
            .navigationTitle("Scan the label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
    }
}
