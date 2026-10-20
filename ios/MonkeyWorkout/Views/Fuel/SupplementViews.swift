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
                                .frame(width: 30, height: 30).background(Circle().fill(.white.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit supplements")
                    }
                    if doses.isEmpty {
                        Text("Nothing today: your stack is for training days.").font(.footnote.weight(.bold)).opacity(0.85)
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
                                    Text(s.timing.label + (s.restDays ? " · rest days too" : " · training days"))
                                        .font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.85)
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

/// Add or edit one supplement. Editing saves on its own; a new one keeps Save.
struct SupplementEditor: View {
    let supplement: Supplement
    let isNew: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared
    @State private var draft: Supplement?
    @State private var scanning = false
    @State private var confirmDelete = false

    var body: some View {
        let d = Binding(get: { draft ?? supplement }, set: { draft = $0 })
        Form {
            Section {
                TextField("Name, e.g. KaEx Boost+", text: d.name).font(.headline)
                Picker("Type", selection: d.kind) { ForEach(SupplementKind.allCases) { Text("\($0.emoji) \($0.label)").tag($0) } }
                TextField("Serving, e.g. 1 sachet in 300 ml water", text: d.dose)
            }
            Section("When") {
                Picker("Take it", selection: d.timing) { ForEach(SupplementTiming.allCases) { Text($0.label).tag($0) } }
                Toggle("Also on rest days", isOn: d.restDays)
            }
            Section {
                if LiveFoodScanner.available {
                    Button { scanning = true } label: { Label("Scan the label", systemImage: "text.viewfinder") }
                }
                Stepper("Caffeine \(d.wrappedValue.caffeineMg) mg", value: d.caffeineMg, in: 0...400, step: 5)
                Stepper("Creatine \(Self.g(d.wrappedValue.creatineG))", value: d.creatineG, in: 0...20, step: 0.5)
                Stepper("Protein \(Self.g(d.wrappedValue.proteinG))", value: d.proteinG, in: 0...80, step: 0.5)
                if d.wrappedValue.isMeal {
                    Stepper("Carbs \(Self.g(d.wrappedValue.carbsG))", value: d.carbsG, in: 0...150, step: 1)
                    Stepper("Fat \(Self.g(d.wrappedValue.fatG))", value: d.fatG, in: 0...80, step: 1)
                    Text("≈ \(d.wrappedValue.kcal) kcal").foregroundStyle(Theme.muted)
                }
            } header: {
                Text("Per serving")
            } footer: {
                Text(d.wrappedValue.isMeal ? "Ticking it fills the meal at that time with these macros." : "Protein counts toward your protein palms when you tick it. Creatine adds a glass to the day's water. Caffeine shows on the meter and is checked against your bedtime.")
            }
            if !isNew {
                Section {
                    Button("Remove from my stack", role: .destructive) { confirmDelete = true }
                        .confirmationDialog("Remove \(supplement.name)?", isPresented: $confirmDelete) {
                            Button("Remove", role: .destructive) {
                                store.deleteSupplement(supplement.id)
                                dismiss()
                            }
                        }
                }
            }
        }
        .themedForm()
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

    static func g(_ v: Double) -> String { v.rounded() == v ? "\(Int(v)) g" : String(format: "%.1f g", v) }
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
