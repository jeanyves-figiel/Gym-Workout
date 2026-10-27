import Charts
import SwiftUI
import WorkoutEngine

/// Finish screen charts (#801 B): volume of the last workouts of the same focus, est. 1RM line per lift.
struct ReportCharts: View {
    let report: WorkoutReport
    @State private var pick: String?

    var body: some View {
        VStack(spacing: 12) {
            if report.volume.count >= 2 { volumeCard }
            if let lift = picked { oneRepMaxCard(lift) }
        }
    }

    private var picked: WorkoutReport.Lift? {
        let charted = report.charted
        return charted.first { $0.uid == pick } ?? charted.first
    }

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Volume · last \(report.volume.count) like this").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.9)
            HStack(alignment: .firstTextBaseline) {
                Text(ReportFormat.volume(report.volumeKg)).font(Theme.display(34)).monospacedDigit()
                Spacer(minLength: 6)
                if let v = report.volumeVsAverage {
                    Text("\(v >= 0 ? "▲" : "▼") \(Int(abs(v * 100).rounded()))% vs avg").font(Theme.label(13))
                }
            }
            Chart(report.volume) { p in
                BarMark(x: .value("Day", p.date, unit: .day), y: .value("kg", p.value), width: .ratio(0.7))
                    .foregroundStyle(p.today ? Theme.lime : .white.opacity(0.4))
                    .cornerRadius(4)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 90)
        }
        .gradientCard(WorkoutEngine.Category.mobility.gradient, padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Volume \(ReportFormat.volume(report.volumeKg))")
    }

    private func oneRepMaxCard(_ lift: WorkoutReport.Lift) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Est. 1-rep max").font(Theme.label(11)).tracking(1.2).textCase(.uppercase).opacity(0.9)
            if report.charted.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(report.charted) { l in
                            Button { withAnimation(.snappy) { pick = l.uid } } label: {
                                Text(l.name).font(Theme.label(12)).lineLimit(1)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .foregroundStyle(l.uid == lift.uid ? Theme.ink : .white)
                                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(l.uid == lift.uid ? Theme.lime : Color.black.opacity(0.25)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(LoadAdvisor.formatKg((lift.oneRepMax.last?.value ?? 0).rounded())) kg").font(Theme.display(30)).monospacedDigit()
                Spacer(minLength: 6)
                if lift.newBest { Text("NEW BEST").font(Theme.label(12)).foregroundStyle(Theme.lime) }
            }
            ReportLine(points: lift.oneRepMax, height: 80)
        }
        .gradientCard(WorkoutEngine.Category.strength.gradient, padding: 14)
    }
}

/// Finish screen lift report (#801 A): every lift vs last time; tap a row to open its chart, today's sets and last time.
struct LiftReportList: View {
    let report: WorkoutReport
    @State private var open: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Every exercise vs last time").eyebrow()
            ForEach(report.lifts) { lift in
                VStack(spacing: 6) {
                    Button { withAnimation(.snappy) { open = open == lift.uid ? nil : lift.uid } } label: { row(lift) }
                        .buttonStyle(.plain)
                    if open == lift.uid { LiftReportDetail(lift: lift).transition(.opacity.combined(with: .move(edge: .top))) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ lift: WorkoutReport.Lift) -> some View {
        HStack(spacing: 10) {
            Image(systemName: lift.category.symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(lift.category.ink)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(lift.category.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(lift.name).font(.subheadline.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.8)
                Text(lift.line).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            if lift.trend.count >= 2 {
                ReportLine(points: lift.trend, height: 24, color: ReportFormat.color(lift.change), axes: false).frame(width: 56)
            }
            Text(lift.change.label)
                .font(Theme.label(13)).monospacedDigit()
                .foregroundStyle(ReportFormat.color(lift.change))
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(open == lift.uid ? Theme.lime : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the chart and every set")
    }
}

/// One lift opened in place: chart (top set / 1RM / volume), today's sets, last time.
private struct LiftReportDetail: View {
    let lift: WorkoutReport.Lift
    @State private var metric = Metric.topSet

    enum Metric: String, CaseIterable, Identifiable {
        case topSet = "Top set", oneRM = "1RM", volume = "Volume"
        var id: String { rawValue }
    }

    private var metrics: [Metric] {
        Metric.allCases.filter { !points($0).isEmpty }
    }

    private func points(_ m: Metric) -> [WorkoutReport.Point] {
        switch m {
        case .topSet: lift.topKg
        case .oneRM: lift.oneRepMax
        case .volume: lift.volume
        }
    }

    var body: some View {
        let shown = metrics.contains(metric) ? metric : (metrics.first ?? .volume)
        VStack(alignment: .leading, spacing: 8) {
            if metrics.count > 1 {
                HStack(spacing: 6) {
                    ForEach(metrics) { m in
                        Button { metric = m } label: {
                            Text(m.rawValue).font(Theme.label(12))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .foregroundStyle(m == shown ? Theme.ink : .white)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(m == shown ? Theme.lime : Color.black.opacity(0.25)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if points(shown).count >= 2 {
                ReportLine(points: points(shown), height: 110)
            } else {
                Text("First time logged: the chart starts here.").font(.footnote.weight(.semibold)).opacity(0.85)
            }
            if !lift.sets.isEmpty {
                Text(lift.sets.enumerated().map { i, s in "Set \(i + 1) \(LoadAdvisor.formatKg(s.kg))×\(s.reps.map { "\($0)" } ?? "–")" }
                    .joined(separator: " · "))
                    .font(.footnote.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
            }
            if let last = lift.last {
                Text("Last time\(lift.lastDate.map { " · " + $0.formatted(.dateTime.day().month()) } ?? ""): "
                     + "\(last.weightKg.map { LoadAdvisor.formatKg($0) + " kg × " } ?? "")\(last.reps.map { "\(Int($0.rounded())) × " } ?? "")\(last.setsDone) sets")
                    .font(.footnote.weight(.semibold)).opacity(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gradientCard(lift.category.gradient, padding: 14, ink: lift.category.ink)
    }
}

/// Line with today's point in lime; `axes` adds month labels under it.
struct ReportLine: View {
    let points: [WorkoutReport.Point]
    var height: CGFloat
    var color: Color = .white
    var axes = true

    var body: some View {
        Chart(points) { p in
            LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: axes ? 3 : 2, lineCap: .round))
            if p.today {
                PointMark(x: .value("Date", p.date), y: .value("Value", p.value))
                    .foregroundStyle(axes ? Theme.lime : color)
                    .symbolSize(axes ? 90 : 30)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: .dateTime.day().month(), centered: false).foregroundStyle(.white.opacity(0.75))
            }
        }
        .chartXAxis(axes ? .automatic : .hidden)
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

enum ReportFormat {
    /// "6.2 t" from a tonne, "850 kg" below.
    static func volume(_ kg: Double) -> String {
        kg >= 1000 ? String(format: "%.1f t", kg / 1000) : "\(Int(kg.rounded())) kg"
    }

    static func color(_ c: WorkoutReport.Change) -> Color {
        switch c.better {
        case true?: Theme.lime
        case false?: Color(red: 1, green: 0.48, blue: 0.48)
        case nil: c == .new ? Theme.lime : Color.white.opacity(0.6)
        }
    }
}

#if DEBUG
extension Demo {
    /// Demo screen `player-done` (#801): charts + lift report without stored history.
    static var report: WorkoutReport {
        let day = 86_400.0
        let now = Date()
        func pts(_ values: [Double]) -> [WorkoutReport.Point] {
            values.enumerated().map { i, v in
                WorkoutReport.Point(date: now.addingTimeInterval(-Double(values.count - 1 - i) * 7 * day), value: v, today: i == values.count - 1)
            }
        }
        func lift(_ id: String, _ uid: String, _ cat: WorkoutEngine.Category, sets: Int, of planned: Int, reps: Int, kg: Double?,
                  change: WorkoutReport.Change, top: [Double], best: Bool = false) -> WorkoutReport.Lift {
            WorkoutReport.Lift(
                uid: uid, exerciseId: id, name: Exercise.find(id)?.name ?? id, category: cat, setsDone: sets, setsPlanned: planned,
                reps: reps, kg: kg,
                sets: (0..<sets).map { SetLog(date: now, exerciseId: id, setIndex: $0, kg: kg ?? 0, reps: reps) },
                last: nil, lastDate: nil, change: change,
                topKg: kg == nil ? [] : pts(top), oneRepMax: kg == nil ? [] : pts(top.map { $0 * (1 + Double(reps) / 30) }),
                volume: pts(top.map { ($0 > 0 ? $0 : 1) * Double(reps * sets) }), newBest: best)
        }
        return WorkoutReport(
            volumeKg: 6_200, volume: pts([4_800, 5_300, 5_000, 5_600, 5_400, 5_900, 6_000, 6_200]), volumeVsAverage: 0.12,
            lifts: [
                lift("bench-press", "a", .strength, sets: 4, of: 4, reps: 8, kg: 80, change: .heavier(2.5), top: [70, 72.5, 72.5, 75, 77.5, 80], best: true),
                lift("seated-db-press", "b", .strength, sets: 3, of: 3, reps: 8, kg: 45, change: .moreReps(1), top: [40, 40, 42.5, 42.5, 45, 45]),
                lift("incline-db-press", "c", .strength, sets: 3, of: 3, reps: 10, kg: 24, change: .same, top: [22, 24, 24, 24, 24, 24]),
                lift("dips", "d", .strength, sets: 2, of: 3, reps: 10, kg: nil, change: .fewerSets(1), top: [30, 30, 33, 33, 30, 20]),
            ])
    }
}
#endif
