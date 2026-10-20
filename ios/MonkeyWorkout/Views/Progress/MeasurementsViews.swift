import SwiftUI
import WorkoutEngine

/// Body measurements (#185): log girths, weight and body fat; see each one's progression; Apple Health in sync
/// for weight, body fat, lean mass and waist. Body fat and arm/thigh girth refine first-time load estimates.

extension BodyMetric {
    var category: WorkoutEngine.Category {
        switch self {
        case .weight: .cardio
        case .bodyFat: .warmup
        case .leanMass: .power
        case let .girth(p):
            switch p {
            case .neck, .hips: .mobility
            case .shoulders, .upperArm: .strength
            case .chest, .thigh: .power
            case .waist: .warmup
            case .forearm, .calf: .cardio
            }
        }
    }

    var symbol: String {
        switch self {
        case .weight: "scalemass.fill"
        case .bodyFat: "drop.fill"
        case .leanMass: "figure.strengthtraining.traditional"
        case let .girth(p):
            switch p {
            case .neck: "person.fill"
            case .shoulders, .chest: "figure.arms.open"
            case .waist, .hips: "figure.stand"
            case .upperArm, .forearm: "dumbbell.fill"
            case .thigh: "figure.walk"
            case .calf: "figure.run"
            }
        }
    }

    /// Weight, body fat, lean mass and waist come from / go to Apple Health too.
    var inHealth: Bool {
        switch self {
        case .weight, .bodyFat, .leanMass, .girth(.waist): true
        default: false
        }
    }
}

enum MeasureFormat {
    static func value(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(r)) : String(format: "%.1f", r)
    }

    static func change(_ d: Double, unit: String) -> String {
        let r = (d * 10).rounded() / 10
        return r == 0 ? "No change" : (r > 0 ? "+" : "−") + value(abs(r)) + " " + unit
    }

    static func date(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated)) }
}

/// Entry card used in Settings → Body & Health and Progress.
struct MeasurementsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationLink { MeasurementsView() } label: {
            let last = model.measurements.last
            AccountCard(symbol: "ruler.fill", title: "Measurements",
                        subtitle: last.map { "Last logged \(MeasureFormat.date($0.date)) · \($0.count) values" }
                            ?? "Chest, arms, waist, thighs… track them over time",
                        gradient: WorkoutEngine.Category.strength.gradient) {
                let n = model.measurements.count
                if n > 0 {
                    AccountValue(value: "\(n)", unit: n == 1 ? "entry" : "entries")
                } else {
                    AccountChevron()
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct MeasurementsView: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var logging: BodyMeasurement?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                AccountHeader(symbol: "ruler.fill", title: "Measurements",
                              subtitle: "Log every 2 to 4 weeks, same time of day. Every value is optional.",
                              gradient: WorkoutEngine.Category.strength.gradient)
                LimeActionButton(title: "Log measurements", symbol: "plus") {
                    logging = BodyMeasurement(date: Date())
                }
                .padding(.vertical, 6)
                if health.connected && health.needsMeasurementAccess {
                    Button { Task { await health.connect() } } label: {
                        AccountCard(symbol: "heart.fill", title: "Allow in Apple Health",
                                    subtitle: "Read and save body fat, lean mass and waist", gradient: nil, textColor: .pink) {
                            AccountChevron()
                        }
                    }
                    .buttonStyle(.plain)
                }

                section("Body")
                ForEach([BodyMetric.weight, .bodyFat, .leanMass]) { row($0) }
                section("Girths")
                ForEach(GirthSite.allCases) { row(.girth($0)) }
                AccountNote(text: "Weight, body fat, lean mass and waist sync with Apple Health (marked with a heart). Other girths stay in the app and your account. Declined Health access once? Turn it back on in Settings → Body & Health → Manage Health access. Body fat (lean mass) and arm and thigh girth fine-tune the first suggested weight for exercises you've never logged; once you log an exercise, your own sets decide.")
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Measurements")
        .toolbarTitleDisplayMode(.inline)
        .sheet(item: $logging) { MeasurementLogSheet(initial: $0) }
        .task { await health.refresh() }
    }

    private func section(_ title: String) -> some View {
        Text(title).eyebrow().padding(.leading, 4).padding(.top, 12)
    }

    private func row(_ metric: BodyMetric) -> some View {
        let points = model.measurementSeries(metric)
        let subtitle: String = if let last = points.last {
            BodyMeasurements.change(points).map { "\(MeasureFormat.change($0, unit: metric.unit)) since \(MeasureFormat.date(points[0].date))" }
                ?? "Logged \(MeasureFormat.date(last.date))"
        } else {
            "Not logged yet"
        }
        return NavigationLink { MeasurementDetailView(metric: metric) } label: {
            AccountCard(symbol: metric.symbol, title: metric.label, subtitle: subtitle, gradient: metric.category.gradient) {
                if let v = points.last?.value {
                    HStack(spacing: 6) {
                        if metric.inHealth && health.connected { Image(systemName: "heart.fill").font(.caption) }
                        AccountValue(value: MeasureFormat.value(v), unit: metric.unit)
                    }
                } else {
                    AccountChevron()
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(points.last.map { "\(metric.label), \(MeasureFormat.value($0.value)) \(metric.unit), \(subtitle)" } ?? "\(metric.label), not logged yet")
    }
}

/// One metric's progression: chart and the logged entries (swipe-free: tap an entry to edit or delete it).
struct MeasurementDetailView: View {
    @Environment(AppModel.self) private var model
    let metric: BodyMetric
    @State private var editing: BodyMeasurement?

    var body: some View {
        let points = model.measurementSeries(metric)
        let entries = model.measurements.filter { metric.value($0) != nil }.reversed()
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Explore-style hero: gradient, icon tile, latest value big on the right.
                AccountHeader(symbol: metric.symbol, title: metric.label, subtitle: heroSubtitle(points),
                              gradient: metric.category.gradient, ink: metric.category.isLight) {
                    if let v = points.last?.value { AccountValue(value: MeasureFormat.value(v), unit: metric.unit) }
                }
                if points.count > 1 {
                    TrendChart(title: metric.label, unit: metric.unit, symbol: metric.symbol,
                               points: points.map { .init(date: $0.date, value: $0.value) }, gradient: metric.category.colors)
                        .card()
                }
                if case let .girth(part) = metric {
                    AccountNote(text: "How to measure: \(part.howTo.lowercased()).")
                }
                if !entries.isEmpty {
                    Text("Logged").eyebrow().padding(.leading, 4).padding(.top, 8)
                    ForEach(Array(entries)) { m in
                        Button { editing = m } label: {
                            AccountCard(symbol: "calendar", title: m.date.formatted(date: .abbreviated, time: .omitted),
                                        subtitle: sides(m) ?? "Tap to edit", gradient: nil, textColor: metric.category.color) {
                                AccountValue(value: MeasureFormat.value(metric.value(m) ?? 0), unit: metric.unit)
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if points.count > entries.count {
                    AccountNote(text: "Includes values from Apple Health.")
                }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(metric.label)
        .toolbarTitleDisplayMode(.inline)
        .sheet(item: $editing) { MeasurementLogSheet(initial: $0, isNew: false) }
    }

    private func heroSubtitle(_ points: [BodyMeasurements.Point]) -> String {
        guard let last = points.last else { return "Not logged yet" }
        return BodyMeasurements.change(points).map { "\(MeasureFormat.change($0, unit: metric.unit)) since \(MeasureFormat.date(points[0].date))" }
            ?? "Logged \(MeasureFormat.date(last.date))"
    }

    /// "L 35.2 · R 35.7" when both sides were measured.
    private func sides(_ m: BodyMeasurement) -> String? {
        guard case let .girth(part) = metric, part.bilateral,
              let l = m.girth(part, side: .left), let r = m.girth(part, side: .right) else { return nil }
        return "L \(MeasureFormat.value(l)) · R \(MeasureFormat.value(r)) \(metric.unit)"
    }
}

/// Quick log: date, weight, body fat and girths; arms and legs per side if wanted. Empty fields are skipped.
struct MeasurementLogSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss

    let initial: BodyMeasurement
    var isNew = true
    /// Values brought back by Undo (#285).
    var restoring: Draft?

    /// What's typed, kept for Undo (#285).
    struct Draft: Equatable, Codable {
        var date: Date
        var text: [String: String]
        var perSide: Bool
    }

    @State private var date = Date()
    @State private var text: [String: String] = [:]
    @State private var perSide = false
    @State private var toHealth = true
    @State private var loaded = false
    @State private var help: HelpTopic?
    @State private var guiding = false
    @State private var start: Draft?
    @State private var closeGuard = CloseGuard()
    /// A new entry's typing kept from last time (#437).
    @State private var draftRestored = false
    @FocusState private var focus: String?

    private static let draftKey = "measurement"

    /// The ? on a card (#220).
    private struct HelpTopic: Identifiable {
        let metric: BodyMetric
        var side: LimbSide?
        var id: String { metric.id + (side?.rawValue ?? "") }
    }

    private static let weightKey = "weight"
    private static let fatKey = "bodyFat"

    /// Latest earlier entry, shown as a hint under each field.
    private var previous: BodyMeasurement? { model.measurements.last { $0.id != initial.id && $0.date <= date } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ContentTitle(title: isNew ? "Log measurements" : "Edit measurements",
                                 subtitle: isNew ? "New entry · Save to keep" : "Saved entry · changes save on their own")
                    if draftRestored {
                        DraftRestoredStrip {
                            DraftStore.clear(Self.draftKey)
                            date = Date(); text = [:]; perSide = false
                            start = draft
                            draftRestored = false
                        }
                    }
                    Button { focus = nil; guiding = true } label: {
                        AccountCard(symbol: "ruler.fill", title: "Measure with me", subtitle: "Step by step, a picture for each one",
                                    gradient: LinearGradient(colors: [Theme.lime, Color(red: 0.31, green: 0.88, blue: 0.63)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                                    ink: true) {
                            Image(systemName: "chevron.right").font(.system(size: 17, weight: .heavy))
                        }
                    }
                    .buttonStyle(.plain)

                    AccountCard(symbol: "calendar", title: "Date", gradient: WorkoutEngine.Category.mobility.gradient) {
                        DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.colorScheme, .dark)
                    }

                    section("Body")
                    field(Self.weightKey, metric: .weight, hint: previous?.weightKg)
                    field(Self.fatKey, metric: .bodyFat, hint: previous?.bodyFatPct, howTo: "From a smart scale, calipers or a scan")

                    section("Girths · cm")
                    Toggle(isOn: $perSide) {
                        Text("Arms & legs: left and right").font(.body.weight(.semibold))
                    }
                    .tint(Theme.lime)
                    .card(padding: 16)
                    ForEach(GirthSite.allCases) { part in
                        if part.bilateral && perSide {
                            ForEach(LimbSide.allCases, id: \.self) { side in
                                field(BodyMeasurement.key(part, side), metric: .girth(part), side: side,
                                      title: "\(part.label) · \(side == .left ? "left" : "right")",
                                      hint: previous?.girth(part, side: side) ?? previous?.girth(part), howTo: part.howTo)
                            }
                        } else {
                            field(BodyMeasurement.key(part), metric: .girth(part), hint: previous?.girth(part), howTo: part.howTo)
                        }
                    }

                    if health.connected {
                        Toggle(isOn: $toHealth) {
                            Text("Also save weight, body fat & waist to Health").font(.body.weight(.semibold))
                        }
                        .tint(Theme.lime)
                        .card(padding: 16)
                    }

                    if isNew {
                        LimeActionButton(title: "Save", disabled: entry.isEmpty) { save() }
                            .padding(.top, 14)
                    } else {
                        AccountNote(text: "Changes save on their own.").padding(.top, 8)
                    }
                    if !isNew {
                        AccountPillButton(title: "Delete this entry", role: .destructive) { delete() }
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .readableWidth()
            .themedForm()
            .titleInContent(isNew ? "Log measurements" : "Edit measurements")
            .toolbar {
                // Standard chrome (#539): Save beside the X for a new entry; an existing one saves on its own.
                if isNew {
                    SaveToolbarItem(disabled: entry.isEmpty) { save() }
                }
                CloseToolbarItem { dismiss() }
            }
            // Editing an entry saves on its own (#437); a deleted one is never written back.
            .autoSave(!isNew && start != nil && !entry.isEmpty ? entry : nil, title: "Measurements", symbol: "ruler.fill",
                      detail: Self.detail,
                      save: { [model] m in if model.measurements.contains(where: { $0.id == m.id }) { model.saveMeasurement(m) } })
            .sheet(item: $help) { MeasurementHowToSheet(metric: $0.metric, side: $0.side) }
            .fullScreenCover(isPresented: $guiding) { MeasureGuideView(steps: guideSteps, text: $text) }
        }
        .onAppear(perform: load)
        .undoableClose(closeGuard, offer: undoOffer)
        .onChange(of: draft) { _, d in
            guard isNew, start != nil else { return }
            if d.text.isEmpty { DraftStore.clear(Self.draftKey) } else { DraftStore.save(Self.draftKey, d) }
        }
    }

    /// Deleted at once (#539); Undo puts the entry back (as a new entry, so a queued server delete can't remove it).
    private func delete() {
        let stored = model.measurements.first { $0.id == initial.id } ?? entry
        closeGuard.done()
        model.deleteMeasurement(initial.id)
        dismiss()
        UndoCloseCenter.shared.deleted("Measurements deleted", detail: Self.detail(stored), symbol: "ruler.fill") { [model] in
            var m = stored
            m.id = UUID()
            model.saveMeasurement(m)
        }
    }

    private static func detail(_ m: BodyMeasurement) -> String {
        let girths = m.girthsCm?.count ?? 0
        return undoDetail(m.weightKg.map { "\(MeasureFormat.value($0)) kg" }, m.bodyFatPct.map { "\(MeasureFormat.value($0)) %" },
                          girths > 0 ? "\(girths) girth\(girths == 1 ? "" : "s")" : nil)
    }

    private var draft: Draft { Draft(date: date, text: text.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }, perSide: perSide) }

    /// Undo bar when something was typed or changed since the sheet opened (#285).
    private var undoOffer: UndoOffer? {
        guard isNew, let start, draft != start else { return nil }
        let kept = draft
        let m = entry
        let girths = m.girthsCm?.count ?? 0
        let detail = undoDetail(m.weightKg.map { _ in "Weight" }, m.bodyFatPct.map { _ in "body fat" },
                                girths > 0 ? "\(girths) girth\(girths == 1 ? "" : "s")" : nil)
        let original = self.initial, new = self.isNew
        return UndoOffer(title: new ? "Measurements closed" : "Edit closed", detail: detail, symbol: "ruler.fill",
                         colors: WorkoutEngine.Category.mobility.colors) {
            AnyView(MeasurementLogSheet(initial: original, isNew: new, restoring: kept))
        }
    }

    private func section(_ title: String) -> some View {
        Text(title).eyebrow().padding(.leading, 4).padding(.top, 12)
    }

    private func field(_ key: String, metric: BodyMetric, side: LimbSide? = nil, title: String? = nil, hint: Double?,
                       howTo: String? = nil) -> some View {
        // How-to first; the last value is the field's placeholder, so it only shows as text when there's no tip.
        let subtitle = howTo ?? hint.map { "Last \(MeasureFormat.value($0)) \(metric.unit)" }
        return AccountCard(symbol: metric.symbol, title: title ?? metric.label, subtitle: subtitle,
                           gradient: metric.category.gradient, ink: metric.category.isLight) {
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 0) {
                    TextField(title ?? metric.label, text: Binding(get: { text[key] ?? "" }, set: { text[key] = $0 }),
                              prompt: Text(hint.map(MeasureFormat.value) ?? "–").foregroundStyle(metric.category.ink.opacity(0.55)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(Theme.display(24).monospacedDigit())
                        .focused($focus, equals: key)
                        .frame(width: 90)
                    Text(metric.unit.uppercased()).font(Theme.label(9)).tracking(1).opacity(0.8)
                }
                Button { help = HelpTopic(metric: metric, side: side) } label: {
                    // Rounded square (#541) in a 44 pt hit area (#540).
                    Image(systemName: "questionmark")
                        .font(.system(size: 13, weight: .heavy))
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.2)))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(HierarchicalShapeStyle.primary.opacity(0.75), lineWidth: 1.5))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("How to measure \(title ?? metric.label)")
            }
        }
        .onTapGesture { focus = key }
    }

    /// Guided mode order: weight, body fat, then every girth as shown in the list.
    private var guideSteps: [MeasureGuideView.Step] {
        [MeasureGuideView.Step(key: Self.weightKey, metric: .weight, last: previous?.weightKg),
         MeasureGuideView.Step(key: Self.fatKey, metric: .bodyFat, last: previous?.bodyFatPct)]
            + GirthSite.allCases.flatMap { part -> [MeasureGuideView.Step] in
                if part.bilateral && perSide {
                    return LimbSide.allCases.map { side in
                        MeasureGuideView.Step(key: BodyMeasurement.key(part, side), metric: .girth(part), side: side,
                                              last: previous?.girth(part, side: side) ?? previous?.girth(part))
                    }
                }
                return [MeasureGuideView.Step(key: BodyMeasurement.key(part), metric: .girth(part), last: previous?.girth(part))]
            }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        var t: [String: String] = [:]
        if let w = initial.weightKg { t[Self.weightKey] = MeasureFormat.value(w) }
        if let f = initial.bodyFatPct { t[Self.fatKey] = MeasureFormat.value(f) }
        for (k, v) in initial.girthsCm ?? [:] { t[k] = MeasureFormat.value(v) }
        let sides = GirthSite.allCases.contains { p in p.bilateral && LimbSide.allCases.contains { initial.girth(p, side: $0) != nil } }
        start = Draft(date: initial.date, text: t, perSide: sides)
        var kept: Draft?
        if isNew, restoring == nil, let d = DraftStore.load(Self.draftKey, as: Draft.self), !d.text.isEmpty {
            kept = d
            draftRestored = true
        }
        let shown = restoring ?? kept ?? start!
        date = shown.date
        text = shown.text
        perSide = shown.perSide
    }

    private func number(_ key: String, in range: ClosedRange<Double>) -> Double? {
        guard let s = text[key], let v = Double(s.replacingOccurrences(of: ",", with: ".")), range.contains(v) else { return nil }
        return v
    }

    /// The entry as typed; only fields shown in the current left/right mode count.
    private var entry: BodyMeasurement {
        var m = BodyMeasurement(id: initial.id, date: date)
        m.weightKg = number(Self.weightKey, in: BodyMeasurement.weightRange)
        m.bodyFatPct = number(Self.fatKey, in: BodyMeasurement.bodyFatRange)
        for part in GirthSite.allCases {
            if part.bilateral && perSide {
                for side in LimbSide.allCases {
                    m.setGirth(part, side: side, number(BodyMeasurement.key(part, side), in: BodyMeasurement.girthRange))
                }
            } else {
                m.setGirth(part, number(BodyMeasurement.key(part), in: BodyMeasurement.girthRange))
            }
        }
        return m
    }

    private func save() {
        let m = entry
        model.saveMeasurement(m)
        if health.connected && toHealth && isNew { Task { await health.saveMeasurement(m) } }
        if isNew { DraftStore.clear(Self.draftKey) }
        closeGuard.done()
        dismiss()
    }
}

/// Progress tab section: the biggest changes as charts, or a prompt to start.
struct ProgressMeasurementsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Measurements").eyebrow()
            ForEach(charted) { c in
                TrendChart(title: c.metric.label, unit: c.metric.unit, symbol: c.metric.symbol,
                           points: c.points.map { .init(date: $0.date, value: $0.value) }, gradient: c.metric.category.colors)
            }
            MeasurementsCard()
        }
        .card()
    }

    private struct Charted: Identifiable {
        let metric: BodyMetric
        let points: [BodyMeasurements.Point]
        var id: String { metric.id }
    }

    /// Up to two girths / body fat with the biggest relative change (weight already has its own chart).
    private var charted: [Charted] {
        let all = BodyMetric.all.filter { $0 != .weight && $0 != .leanMass }.compactMap { metric -> Charted? in
            let pts = model.measurementSeries(metric)
            return pts.count > 1 ? Charted(metric: metric, points: pts) : nil
        }
        return Array(all.sorted { abs(relative($0.points)) > abs(relative($1.points)) }.prefix(2))
    }

    private func relative(_ pts: [BodyMeasurements.Point]) -> Double {
        guard let first = pts.first?.value, first > 0, let change = BodyMeasurements.change(pts) else { return 0 }
        return change / first
    }
}
