import SwiftUI
import WorkoutEngine

/// Top of the Progress tab (#238): measurements, records, achievements and body visible without scrolling.
/// Three layouts the member picks in Account → Progress layout; Hub grid is the default.
enum ProgressLayout: String, CaseIterable, Identifiable {
    case strip, hub, tabs

    static let storageKey = "progress.layout"
    static let `default` = ProgressLayout.hub

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strip: "Shortcut strip"
        case .hub: "Hub grid"
        case .tabs: "Section tabs"
        }
    }

    var detail: String {
        switch self {
        case .strip: "A row of bold tiles under the streak: swipe, tap one to jump to it."
        case .hub: "Four big tiles at the top: measurements, records, achievements, body."
        case .tabs: "A pill bar switches the page: Training, Body, Records, Badges, History."
        }
    }

    var symbol: String {
        switch self {
        case .strip: "rectangle.split.3x1.fill"
        case .hub: "square.grid.2x2.fill"
        case .tabs: "menubar.rectangle"
        }
    }

    var colors: [Color] {
        switch self {
        case .strip: WorkoutEngine.Category.cardio.colors
        case .hub: WorkoutEngine.Category.strength.colors
        case .tabs: WorkoutEngine.Category.mobility.colors
        }
    }
}

/// Page sections: scroll targets for the strip / hub, pages for the tabs.
enum ProgressSection: String, CaseIterable, Identifiable, Hashable {
    case training, body, records, badges, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .training: "Training"
        case .body: "Body"
        case .records: "Records"
        case .badges: "Badges"
        case .history: "History"
        }
    }
}

/// What the top tiles show, computed once per render by `ProgressTabView`.
struct ProgressHighlights {
    struct Measure {
        let metric: BodyMetric
        let value: Double
        let change: Double?
    }

    struct Record: Identifiable {
        let name: String
        let value: String
        let unit: String
        let date: Date
        var id: String { name }
    }

    /// Every metric with at least one value, biggest relative change first (girths and body fat before weight).
    var measures: [Measure]
    var records: [Record]
    var unlocked: Int
    var badgeCount: Int
    var nextBadge: Badge?
    var vo2: Measure?
    var weight: Measure?
    var workouts: Int

    /// The measurement the hub / strip features: biggest change among girths and body fat, else any.
    var featured: Measure? {
        measures.first { $0.metric != .weight && $0.metric != .leanMass } ?? measures.first
    }
}

extension BodyMetric {
    func format(_ v: Double) -> String {
        "\(Format.kg((v * 10).rounded() / 10)) \(unit)"
    }

    func formatChange(_ d: Double) -> String {
        let r = (abs(d) * 10).rounded() / 10
        return r == 0 ? "No change" : "\(d < 0 ? "▼" : "▲") \(Format.kg(r)) \(unit)"
    }
}

// MARK: - B · Hub grid (default)

struct ProgressHub: View {
    let h: ProgressHighlights
    let open: (ProgressSection) -> Void

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                NavigationLink { MeasurementsView() } label: { measurements }.buttonStyle(.plain)
                Button { open(.records) } label: { records }.buttonStyle(.plain)
            }
            GridRow {
                Button { open(.badges) } label: { badges }.buttonStyle(.plain)
                Button { open(.body) } label: { bodyTile }.buttonStyle(.plain)
            }
        }
    }

    private var measurements: some View {
        HubTile(symbol: "ruler.fill", colors: WorkoutEngine.Category.strength.colors, label: "Measurements") {
            if let m = h.featured {
                HubValue(m.metric.format(m.value))
                HubNote("\(m.metric.label) · \(m.change.map(m.metric.formatChange) ?? "Log again to track")")
            } else {
                HubValue("Log")
                HubNote("Chest, arms, waist… track them over time")
            }
        }
    }

    private var records: some View {
        HubTile(symbol: "trophy.fill", colors: [Color(red: 1, green: 0.72, blue: 0), Color(red: 1, green: 0.37, blue: 0.23)],
                label: "Records", ink: Theme.ink) {
            if h.records.isEmpty {
                HubValue("No PRs")
                HubNote("Log weights or tap Attempt a PR")
            } else {
                HubValue(h.records.count == 1 ? "1 PR" : "\(h.records.count) PRs")
                ForEach(h.records.prefix(2)) { r in HubNote("\(r.name) \(r.value) \(r.unit)") }
            }
        }
    }

    private var badges: some View {
        HubTile(symbol: "medal.fill", colors: [Color(red: 1, green: 0.55, blue: 0.1), Color(red: 1, green: 0.18, blue: 0.47)],
                label: "Achievements") {
            HubValue("\(h.unlocked)/\(h.badgeCount)")
            HubNote(h.nextBadge.map { "Next: \($0.title) · \(Format.count($0.current))/\(Format.count($0.target))" } ?? "All unlocked")
        } corner: {
            if let next = h.nextBadge {
                ProgressRing(progress: next.progress, lineWidth: 5, colors: [.white, .white.opacity(0.85)])
                    .frame(width: 30, height: 30)
            }
        }
    }

    private var bodyTile: some View {
        HubTile(symbol: "heart.fill", colors: WorkoutEngine.Category.cardio.colors, label: h.vo2 != nil ? "VO₂max · Body" : "Body") {
            if let v = h.vo2 {
                HubValue(Format.kg((v.value * 10).rounded() / 10))
            } else if let w = h.weight {
                HubValue(w.metric.format(w.value))
            } else {
                HubValue("Body")
            }
            if let w = h.weight, h.vo2 != nil {
                HubNote("Weight \(w.metric.format(w.value))" + (w.change.map { " \(w.metric.formatChange($0))" } ?? ""))
            } else if let w = h.weight {
                HubNote(w.change.map(w.metric.formatChange) ?? "Body weight")
            } else {
                HubNote("Connect Apple Health or log your weight")
            }
        }
    }
}

/// Gradient hub tile: icon tile, big value, uppercase label, one or two notes.
struct HubTile<Content: View, Corner: View>: View {
    let symbol: String
    let colors: [Color]
    let label: String
    var ink: Color = .white
    let content: Content
    let corner: Corner

    init(symbol: String, colors: [Color], label: String, ink: Color = .white,
         @ViewBuilder content: () -> Content, @ViewBuilder corner: () -> Corner = { EmptyView() }) {
        self.symbol = symbol
        self.colors = colors
        self.label = label
        self.ink = ink
        self.content = content()
        self.corner = corner()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.22)))
                .padding(.bottom, 4)
            content
            Spacer(minLength: 0)
            Text(label).font(Theme.label(11)).tracking(1).textCase(.uppercase).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(alignment: .topTrailing) { corner.padding(12) }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

private struct HubValue: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Theme.display(26)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
    }
}

private struct HubNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).opacity(0.9).lineLimit(2).multilineTextAlignment(.leading)
    }
}

// MARK: - A · Shortcut strip

struct ProgressStrip: View {
    let h: ProgressHighlights
    let open: (ProgressSection) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                NavigationLink { MeasurementsView() } label: {
                    if let m = h.featured {
                        StripTile(symbol: "ruler.fill", value: m.metric.format(m.value), label: m.metric.label,
                                  note: m.change.map(m.metric.formatChange) ?? "Log again", colors: WorkoutEngine.Category.strength.colors)
                    } else {
                        StripTile(symbol: "ruler.fill", value: "Log", label: "Measurements", note: "Track your body",
                                  colors: WorkoutEngine.Category.strength.colors)
                    }
                }
                .buttonStyle(.plain)
                Button { open(.records) } label: {
                    StripTile(symbol: "trophy.fill", value: h.records.first.map { "\($0.value) \($0.unit)" } ?? "No PRs",
                              label: "Top PR", note: h.records.first?.name ?? "Attempt a PR",
                              colors: [Color(red: 1, green: 0.72, blue: 0), Color(red: 1, green: 0.37, blue: 0.23)], ink: Theme.ink)
                }
                .buttonStyle(.plain)
                Button { open(.badges) } label: {
                    StripTile(symbol: "medal.fill", value: "\(h.unlocked)/\(h.badgeCount)", label: "Badges",
                              note: h.nextBadge.map { "Next: \($0.title)" } ?? "All unlocked",
                              colors: [Color(red: 1, green: 0.55, blue: 0.1), Color(red: 1, green: 0.18, blue: 0.47)])
                }
                .buttonStyle(.plain)
                if let w = h.weight {
                    Button { open(.body) } label: {
                        StripTile(symbol: "scalemass.fill", value: w.metric.format(w.value), label: "Body weight",
                                  note: w.change.map(w.metric.formatChange) ?? "Latest", colors: WorkoutEngine.Category.cardio.colors)
                    }
                    .buttonStyle(.plain)
                }
                if let v = h.vo2 {
                    Button { open(.body) } label: {
                        StripTile(symbol: "lungs.fill", value: Format.kg((v.value * 10).rounded() / 10), label: "VO₂max",
                                  note: v.change.map { String(format: "%@ %.1f", $0 < 0 ? "▼" : "▲", abs($0)) } ?? "ml/kg/min",
                                  colors: WorkoutEngine.Category.power.colors)
                    }
                    .buttonStyle(.plain)
                }
                Button { open(.history) } label: {
                    StripTile(symbol: "clock.arrow.circlepath", value: "\(h.workouts)", label: "History",
                              note: "All your sessions", colors: WorkoutEngine.Category.mobility.colors)
                }
                .buttonStyle(.plain)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }
}

private struct StripTile: View {
    let symbol: String
    let value: String
    let label: String
    let note: String
    let colors: [Color]
    var ink: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.22)))
                .padding(.bottom, 4)
            Text(value).font(Theme.display(24)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Theme.label(10)).tracking(1).textCase(.uppercase).opacity(0.85).lineLimit(1)
            Text(note).font(.caption2.weight(.semibold)).opacity(0.9).lineLimit(1)
        }
        .foregroundStyle(ink)
        .frame(width: 128, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - C · Section tabs

struct ProgressTabBar: View {
    @Binding var selection: ProgressSection
    @Namespace private var pill

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ProgressSection.allCases) { s in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selection = s }
                    } label: {
                        Text(s.title)
                            .font(Theme.label(13))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .foregroundStyle(selection == s ? Theme.ink : .white.opacity(0.75))
                            .background {
                                if selection == s {
                                    Capsule().fill(Theme.lime).matchedGeometryEffect(id: "tab", in: pill)
                                } else {
                                    Capsule().fill(Color.white.opacity(0.08))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == s ? .isSelected : [])
                }
            }
        }
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Body tab: Measure with me + one tile per logged measurement (tap → its chart and entries).
struct BodyTilesGrid: View {
    let h: ProgressHighlights

    var body: some View {
        VStack(spacing: 10) {
            NavigationLink { MeasurementsView() } label: {
                GradientRow(symbol: "ruler.fill", title: h.measures.isEmpty ? "Log measurements" : "Measurements",
                            subtitle: "Log new values, Measure with me guides you",
                            gradient: WorkoutEngine.Category.strength.gradient)
            }
            .buttonStyle(.plain)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ForEach(h.measures, id: \.metric.id) { m in
                    NavigationLink { MeasurementDetailView(metric: m.metric) } label: {
                        GradientStat(symbol: m.metric.symbol, value: m.metric.format(m.value),
                                     label: m.metric.label + (m.change.map { " · \(m.metric.formatChange($0))" } ?? ""),
                                     gradient: m.metric.category.gradient)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Account → Progress layout

struct ProgressLayoutView: View {
    @AppStorage(ProgressLayout.storageKey) private var layoutRaw = ProgressLayout.default.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top of your Progress page").font(Theme.label(13)).tracking(1).textCase(.uppercase)
                    .foregroundStyle(Theme.lime)
                ForEach(ProgressLayout.allCases) { l in
                    Button { layoutRaw = l.rawValue } label: { LayoutCard(layout: l, selected: layoutRaw == l.rawValue) }
                        .buttonStyle(.plain)
                }
                Text("Measurements, records, achievements and body stay one tap away in every layout.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .sensoryFeedback(.selection, trigger: layoutRaw)
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Progress layout")
    }
}

private struct LayoutCard: View {
    let layout: ProgressLayout
    let selected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: layout.symbol)
                .font(.system(size: 24, weight: .bold))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(layout.title).font(Theme.display(21))
                    if layout == .default {
                        Text("DEFAULT").font(Theme.label(10)).tracking(1)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.white.opacity(0.25)))
                    }
                }
                Text(layout.detail).font(.footnote.weight(.medium)).opacity(0.9).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 4)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(selected ? Theme.lime : .white.opacity(0.6))
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: layout.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.lime, lineWidth: selected ? 3 : 0))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
