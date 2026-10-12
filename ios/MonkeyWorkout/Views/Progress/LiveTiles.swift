import Charts
import SwiftUI
import WorkoutEngine

/// Progress live tiles (#218, design A): Week / Month / All switch, each tile with a trend line and the change
/// vs the previous period; tap a tile to flip it into a full-width bar chart of that metric.
struct LiveTiles: View {
    let records: [WorkoutRecord]
    /// Recent climbs tile (12 weeks), shown when there are any; not period-based.
    var climbs: (count: Int, grade: String?)?

    @AppStorage("progress.period") private var periodRaw = StatPeriod.week.rawValue
    @State private var flipped: StatMetric?
    @Namespace private var seg

    private var period: StatPeriod { StatPeriod(rawValue: periodRaw) ?? .week }

    init(records: [WorkoutRecord], climbs: (count: Int, grade: String?)? = nil, flipped: StatMetric? = nil) {
        self.records = records
        self.climbs = climbs
        _flipped = State(initialValue: flipped)
    }

    private enum Tile: Hashable { case metric(StatMetric), climbs }

    var body: some View {
        let s = Progression.periodSummary(records: records, period: period)
        VStack(spacing: 10) {
            periodSwitch
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { tile in
                        switch tile {
                        case .metric(let m):
                            MetricTile(metric: m, summary: s, flipped: flipped == m)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { flipped = flipped == m ? nil : m }
                                }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityHint(flipped == m ? "Shows the total" : "Shows the chart")
                        case .climbs:
                            if let climbs {
                                GradientStat(symbol: "figure.climbing", value: "\(climbs.count)",
                                             label: "Climbs · 12 wk" + (climbs.grade.map { " · \($0)" } ?? ""),
                                             gradient: ClimbKind.boulder.gradient)
                            }
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: flipped)
        .sensoryFeedback(.selection, trigger: periodRaw)
    }

    /// Two tiles per row; a flipped tile takes its own full-width row, as does an odd tile out.
    private var rows: [[Tile]] {
        var tiles: [Tile] = [.metric(.sessions), .metric(.minutes), .metric(.volume), .metric(.sets), .metric(.days)]
        if climbs != nil { tiles.append(.climbs) }
        var out: [[Tile]] = []
        var pending: Tile?
        for t in tiles {
            if case .metric(let m) = t, m == flipped {
                out.append([t])
                continue
            }
            if let p = pending {
                out.append([p, t])
                pending = nil
            } else {
                pending = t
            }
        }
        if let pending { out.append([pending]) }
        return out
    }

    private var periodSwitch: some View {
        HStack(spacing: 4) {
            ForEach(StatPeriod.allCases) { p in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { periodRaw = p.rawValue }
                } label: {
                    Text(p.title)
                        .font(Theme.label(13))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(period == p ? Theme.ink : Theme.muted)
                        .background {
                            if period == p {
                                Capsule().fill(Theme.lime).matchedGeometryEffect(id: "period", in: seg)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(period == p ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

extension StatPeriod {
    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .all: "All"
        }
    }

    /// "vs last wk" / "vs last month".
    var versus: String { self == .week ? "vs last wk" : "vs last month" }
    var per: String { self == .week ? "per week" : "per month" }
    var bucketName: String { self == .week ? "week" : "month" }
}

extension StatMetric {
    var label: String {
        switch self {
        case .sessions: "Sessions"
        case .minutes: "Trained"
        case .volume: "Lifted"
        case .sets: "Sets"
        case .days: "Days active"
        }
    }

    var symbol: String {
        switch self {
        case .sessions: "dumbbell.fill"
        case .minutes: "stopwatch.fill"
        case .volume: "scalemass.fill"
        case .sets: "square.stack.3d.up.fill"
        case .days: "calendar"
        }
    }

    var colors: [Color] {
        switch self {
        case .sessions: WorkoutEngine.Category.strength.colors
        case .minutes: WorkoutEngine.Category.cardio.colors
        case .volume: WorkoutEngine.Category.power.colors
        case .sets: WorkoutEngine.Category.mobility.colors
        case .days: [Theme.lime, Color(red: 0.12, green: 0.85, blue: 0.54)]
        }
    }

    /// Dark text on the lime tile, white elsewhere.
    var ink: Color { self == .days ? Theme.ink : .white }

    func format(_ v: Double) -> String {
        switch self {
        case .minutes: v < 60 ? "\(Int(v)) min" : ProgressTabView.hours(Int(v))
        case .volume: Format.volume(v)
        case .sessions, .sets, .days: Format.count(v)
        }
    }

    /// "+2", "−25 min", "+1.2 t".
    func formatDelta(_ d: Double) -> String {
        (d < 0 ? "−" : "+") + format(abs(d))
    }
}

/// One live tile: front = value, trend line and change; flipped = full-width bars per week / month.
private struct MetricTile: View {
    let metric: StatMetric
    let summary: PeriodSummary
    let flipped: Bool

    var body: some View {
        let value = summary.current.value(metric)
        Group {
            if flipped { back(value) } else { front(value) }
        }
        .foregroundStyle(metric.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: metric.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(alignment: .topTrailing) {
            Image(systemName: flipped ? "xmark" : "chart.bar.fill")
                .font(.system(size: 11, weight: .heavy))
                .opacity(0.7)
                .padding(12)
                .foregroundStyle(metric.ink)
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private func front(_ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: metric.symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.22)))
            Text(metric.format(value))
                .font(Theme.display(28)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: value))
            Text(metric.label).font(Theme.label(11)).tracking(1).textCase(.uppercase).opacity(0.85).lineLimit(1)
            Sparkline(values: summary.buckets.map { $0.totals.value(metric) }, color: metric.ink)
                .frame(height: 22)
            DeltaPill(text: deltaText, up: (summary.delta(metric) ?? 0) >= 0, ink: metric.ink)
        }
        .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
    }

    private func back(_ value: Double) -> some View {
        let best = summary.best(metric)
        let last = summary.buckets.count - 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.format(value)).font(Theme.display(34)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text("\(metric.label) · \(summary.period == .all ? "per month" : summary.period.per)")
                        .font(Theme.label(11)).tracking(1).textCase(.uppercase).opacity(0.85)
                }
                Spacer(minLength: 0)
            }
            Chart {
                ForEach(Array(summary.buckets.enumerated()), id: \.offset) { i, b in
                    BarMark(x: .value("Period", i), y: .value(metric.label, b.totals.value(metric)), width: .ratio(0.7))
                        .cornerRadius(5)
                        .foregroundStyle(metric.ink.opacity(i == last || i == best ? 1 : 0.45))
                        .annotation(position: .top, spacing: 2) {
                            if i == best {
                                Image(systemName: "crown.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(metric.ink)
                            }
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: last == 0 ? [0] : [0, last]) { v in
                    AxisValueLabel {
                        Text(axisLabel(v.as(Int.self) ?? 0))
                            .font(Theme.label(10))
                            .foregroundStyle(metric.ink.opacity(0.8))
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 110)
            DeltaPill(text: backCaption(best), up: true, ink: metric.ink, plain: true)
        }
        .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
    }

    private var deltaText: String {
        guard let d = summary.delta(metric) else {
            return summary.buckets.count > 1 ? "Since \(bucketLabel(summary.buckets[0].start))" : "All time"
        }
        if d == 0 { return "Same \(summary.period.versus.replacingOccurrences(of: "vs ", with: "as "))" }
        return "\(metric.formatDelta(d)) \(summary.period.versus)"
    }

    private func backCaption(_ best: Int?) -> String {
        let name = summary.period == .all ? "month" : summary.period.bucketName
        guard let best else { return "Nothing logged yet" }
        if best == summary.buckets.count - 1 { return "Best \(name) in this chart. Keep it up" }
        return "Best \(name): \(metric.format(summary.buckets[best].totals.value(metric))) · \(bucketLabel(summary.buckets[best].start))"
    }

    private func axisLabel(_ i: Int) -> String {
        i == summary.buckets.count - 1 ? "Now" : bucketLabel(summary.buckets[i].start)
    }

    private func bucketLabel(_ d: Date) -> String {
        summary.period == .week ? d.formatted(.dateTime.day().month(.abbreviated)) : d.formatted(.dateTime.month(.abbreviated))
    }
}

private struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("i", i), y: .value("v", v))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(color)
            }
            if let v = values.last {
                PointMark(x: .value("i", values.count - 1), y: .value("v", v)).symbolSize(28).foregroundStyle(color)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...max(1, values.max() ?? 1))
        .accessibilityHidden(true)
    }
}

private struct DeltaPill: View {
    let text: String
    let up: Bool
    let ink: Color
    var plain = false

    var body: some View {
        HStack(spacing: 4) {
            if !plain {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right").font(.system(size: 9, weight: .heavy))
            }
            Text(text).font(Theme.label(10)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(ink.opacity(0.18)))
    }
}
