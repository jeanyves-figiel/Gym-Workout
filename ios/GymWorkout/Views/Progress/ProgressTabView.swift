import Charts
import SwiftUI
import WorkoutEngine

/// "Progress" tab: totals, consistency calendar, trends, muscle balance, achievements, PRs, history.
struct ProgressTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var badge: Badge?
    @State private var lift: String?

    private var stats: ProgressStats {
        Progression.stats(records: model.state.history, weights: model.weightEntries, targetPerWeek: model.profile?.sessionsPerWeek ?? 3)
    }

    private var badges: [Badge] {
        Achievements.evaluate(records: model.state.history, weights: model.weightEntries, targetPerWeek: model.profile?.sessionsPerWeek ?? 3)
    }

    var body: some View {
        let s = stats
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                totals(s)
                ConsistencyCalendar(days: s.days)
                weeklyChart(s)
                strengthTrend
                if !health.snapshot.weightTrend.isEmpty || !health.snapshot.vo2Trend.isEmpty { bodyTrends }
                if !s.muscleBalance.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Muscle balance · last 28 days").eyebrow()
                        BodyMapPair(heat: s.muscleBalance).frame(height: 240)
                        HeatLegend()
                    }
                    .card()
                }
                achievements
                if !s.personalRecords.isEmpty { records(s) }
                historyList
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Progress")
        .toolbarTitleDisplayMode(.inlineLarge)
        .navigationDestination(for: UUID.self) { id in HistoryDetailView(recordId: id) }
        .sheet(item: $badge) { b in BadgeSheet(badge: b).presentationDetents([.medium]) }
    }

    // MARK: Sections

    private func totals(_ s: ProgressStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                StatTile(value: "\(s.totalWorkouts)", label: "Sessions")
                StatTile(value: "\(s.currentStreakWeeks)", label: "Week streak")
            }
            HStack(spacing: 10) {
                StatTile(value: String(format: "%.0f h", Double(s.totalMinutes) / 60), label: "Trained")
                StatTile(value: String(format: "%.1f t", s.totalVolumeKg / 1000), label: "Lifted")
            }
            Text("Best streak \(s.bestStreakWeeks) wk · \(s.thisWeek)/\(model.profile?.sessionsPerWeek ?? 3) this week")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }

    private func weeklyChart(_ s: ProgressStats) -> some View {
        let target = model.profile?.sessionsPerWeek ?? 3
        return VStack(alignment: .leading, spacing: 12) {
            Text("Sessions per week").eyebrow()
            Chart {
                ForEach(s.weeks) { w in
                    BarMark(x: .value("Week", w.weekStart, unit: .weekOfYear), y: .value("Sessions", w.workouts))
                        .foregroundStyle(w.workouts >= target ? Theme.lime : Color.white.opacity(0.35))
                        .cornerRadius(4)
                }
                RuleMark(y: .value("Target", target))
                    .foregroundStyle(Theme.lime.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 160)
        }
        .card()
    }

    private var liftOptions: [Exercise] {
        let ids = Set(model.state.history.flatMap { $0.exercises.filter { $0.estimatedOneRepMax != nil }.map(\.exerciseId) })
        return ids.compactMap(Exercise.find).filter(\.main).sorted { $0.name < $1.name }
    }

    @ViewBuilder
    private var strengthTrend: some View {
        let options = liftOptions
        if let selected = lift ?? options.first?.id {
            let points = Progression.oneRepMaxTrend(selected, records: model.state.history)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Strength · est. 1RM").eyebrow()
                    Spacer()
                    Menu {
                        ForEach(options) { e in Button(e.name) { lift = e.id } }
                    } label: {
                        Label(Exercise.find(selected)?.name ?? selected, systemImage: "chevron.down").font(Theme.label(12))
                    }
                }
                Chart {
                    ForEach(points, id: \.0) { p in
                        LineMark(x: .value("Week", p.0), y: .value("kg", p.1))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(WorkoutEngine.Category.strength.gradient)
                        PointMark(x: .value("Week", p.0), y: .value("kg", p.1)).foregroundStyle(Theme.lime)
                    }
                }
                .frame(height: 150)
                if let first = points.first?.1, let last = points.last?.1, points.count > 1 {
                    Text(String(format: "%+.1f kg since %@", last - first, points[0].0.formatted(.dateTime.day().month())))
                        .font(Theme.label(13))
                        .foregroundStyle(last >= first ? Theme.lime : .orange)
                }
            }
            .card()
        }
    }

    private var bodyTrends: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("From Apple Health").eyebrow()
            if !health.snapshot.weightTrend.isEmpty {
                trendChart(title: "Body weight (kg)", points: health.snapshot.weightTrend, color: WorkoutEngine.Category.cardio.color)
            }
            if !health.snapshot.vo2Trend.isEmpty {
                trendChart(title: "VO₂max (ml/kg/min)", points: health.snapshot.vo2Trend, color: WorkoutEngine.Category.power.color)
            }
        }
        .card()
    }

    private func trendChart(title: String, points: [HealthSnapshot.TrendPoint], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(Theme.label(13))
                Spacer()
                if let v = points.last?.value { Text(String(format: "%.1f", v)).font(Theme.display(18)) }
            }
            Chart(points) { p in
                LineMark(x: .value("Date", p.date), y: .value(title, p.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 110)
        }
    }

    private var achievements: some View {
        let all = badges
        let unlocked = all.filter(\.unlocked).count
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Achievements").eyebrow()
                Spacer()
                Text("\(unlocked)/\(all.count)").font(Theme.label(13)).foregroundStyle(Theme.lime)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                ForEach(all.sorted { ($0.unlocked ? 0 : 1, -$0.progress) < ($1.unlocked ? 0 : 1, -$1.progress) }) { b in
                    Button { badge = b } label: { BadgeView(badge: b) }
                        .buttonStyle(.plain)
                }
            }
        }
        .card()
    }

    private func records(_ s: ProgressStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Personal records").eyebrow()
            ForEach(s.personalRecords.prefix(8)) { pr in
                HStack {
                    Image(systemName: "trophy.fill").foregroundStyle(Theme.lime)
                    Text(Exercise.find(pr.exerciseId)?.name ?? pr.exerciseId).font(.body.weight(.semibold))
                    Spacer()
                    Text("\(Format.kg(pr.kg)) kg").font(Theme.display(18))
                    Text(pr.date.formatted(.dateTime.day().month())).font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
        .card()
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History").eyebrow()
            if model.history.isEmpty {
                Text("Finish a session and it shows up here with everything you did.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .card()
            }
            ForEach(model.history) { r in
                NavigationLink(value: r.id) { HistoryRow(record: r) }
                    .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Pieces

/// GitHub-style grid: 12 weeks × 7 days.
struct ConsistencyCalendar: View {
    let days: [Date: Int]

    var body: some View {
        let cal = Progression.calendar()
        let thisWeek = Progression.weekStart(Date(), cal)
        let today = cal.startOfDay(for: Date())
        VStack(alignment: .leading, spacing: 12) {
            Text("Consistency · 12 weeks").eyebrow()
            HStack(spacing: 4) {
                ForEach((0..<12).reversed(), id: \.self) { weeksAgo in
                    let start = cal.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeek)!
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = cal.date(byAdding: .day, value: d, to: start)!
                            let n = days[day] ?? 0
                            RoundedRectangle(cornerRadius: 4)
                                .fill(n > 0 ? AnyShapeStyle(Theme.lime.opacity(min(1, 0.55 + 0.25 * Double(n)))) : AnyShapeStyle(Color.white.opacity(day > today ? 0.02 : 0.07)))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            HStack {
                Text("12 weeks ago").font(.caption2).foregroundStyle(Theme.muted)
                Spacer()
                Text("This week").font(.caption2).foregroundStyle(Theme.muted)
            }
        }
        .card()
    }
}

extension BadgeTier {
    var colors: [Color] {
        switch self {
        case .bronze: [Color(red: 0.85, green: 0.52, blue: 0.28), Color(red: 1, green: 0.72, blue: 0.45)]
        case .silver: [Color(red: 0.70, green: 0.75, blue: 0.82), Color(red: 0.95, green: 0.97, blue: 1)]
        case .gold: [Color(red: 1, green: 0.78, blue: 0.1), Color(red: 1, green: 0.93, blue: 0.5)]
        }
    }
}

struct BadgeView: View {
    let badge: Badge

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if badge.unlocked {
                    Circle().fill(LinearGradient(colors: badge.tier.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: badge.tier.colors[0].opacity(0.5), radius: 8)
                } else {
                    Circle().fill(Color.white.opacity(0.06))
                    ProgressRing(progress: badge.progress, lineWidth: 4, colors: badge.tier.colors)
                }
                Image(systemName: badge.symbol)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(badge.unlocked ? Theme.ink : Color.white.opacity(0.4))
            }
            .frame(width: 64, height: 64)
            Text(badge.title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(badge.unlocked ? .white : Theme.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(badge.title), \(badge.unlocked ? "unlocked" : "\(Int(badge.progress * 100)) percent")")
    }
}

struct BadgeSheet: View {
    let badge: Badge

    var body: some View {
        VStack(spacing: 16) {
            BadgeView(badge: badge).scaleEffect(1.6).padding(.top, 40).padding(.bottom, 20)
            Text(badge.title).font(Theme.display(28))
            Text(badge.detail).font(.body.weight(.medium)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            if let d = badge.unlockedAt {
                Label("Unlocked \(d.formatted(date: .abbreviated, time: .omitted))", systemImage: "checkmark.seal.fill")
                    .font(Theme.label(14))
                    .foregroundStyle(Theme.lime)
            } else {
                Text("\(Format.count(badge.current)) / \(Format.count(badge.target))").font(Theme.display(22)).foregroundStyle(Theme.lime)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

struct HistoryRow: View {
    let record: WorkoutRecord

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(record.startedAt.formatted(.dateTime.day())).font(Theme.display(26))
                Text(record.startedAt.formatted(.dateTime.month(.abbreviated)).uppercased()).font(Theme.label(10)).foregroundStyle(Theme.muted)
            }
            .frame(width: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title).font(.system(.headline, design: .rounded).weight(.heavy))
                Text("\(record.durationSec / 60) min · \(record.totalSets) sets" + (record.volumeKg > 0 ? " · \(Format.kg((record.volumeKg / 100).rounded() / 10)) t" : ""))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                if let hr = record.avgHeartRate {
                    Label("\(Int(hr)) bpm avg", systemImage: "heart.fill").font(.caption2.weight(.bold)).foregroundStyle(WorkoutEngine.Category.power.color)
                }
            }
            Spacer()
            BodyMapView(side: .front, heat: record.muscleHeat, showLabel: false).frame(width: 34, height: 68)
        }
        .card(padding: 14)
    }
}

/// Everything done in one past session.
struct HistoryDetailView: View {
    let recordId: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        if let r = model.state.history.first(where: { $0.id == recordId }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(r.startedAt.formatted(date: .complete, time: .shortened)).eyebrow()
                        Text(r.title).font(Theme.display(34))
                        if r.deload { Text("Deload week").font(Theme.label(12)).foregroundStyle(.orange) }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        StatTile(value: "\(r.durationSec / 60)′", label: "Duration")
                        StatTile(value: "\(r.totalSets)", label: "Sets")
                        StatTile(value: r.volumeKg > 0 ? "\(Int(r.volumeKg)) kg" : "—", label: "Volume")
                        StatTile(value: r.kcal.map { "\(Int($0))" } ?? "—", label: "kcal (est.)")
                        if let a = r.avgHeartRate { StatTile(value: "\(Int(a))", label: "Avg bpm") }
                        if let m = r.maxHeartRate { StatTile(value: "\(Int(m))", label: "Max bpm") }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Muscles worked").eyebrow()
                        BodyMapPair(heat: r.muscleHeat).frame(height: 240)
                    }
                    .card()
                    ForEach(WorkoutEngine.Category.allCases) { cat in
                        let items = r.exercises.filter { $0.category == cat }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                CategoryPill(category: cat)
                                ForEach(items) { e in
                                    HStack {
                                        Image(systemName: e.setsDone >= e.setsPlanned ? "checkmark.circle.fill" : (e.setsDone > 0 ? "circle.lefthalf.filled" : "circle"))
                                            .foregroundStyle(e.setsDone > 0 ? Theme.lime : Theme.muted)
                                        Text(Exercise.find(e.exerciseId)?.name ?? e.exerciseId).font(.body.weight(.semibold))
                                        Spacer()
                                        Text("\(e.setsDone)/\(e.setsPlanned)").font(Theme.label(13)).foregroundStyle(Theme.muted)
                                        if let kg = e.weightKg { Text("\(Format.kg(kg)) kg").font(Theme.label(13)) }
                                    }
                                }
                            }
                            .card()
                        }
                    }
                    Button("Delete from history", role: .destructive) { confirmDelete = true }
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    model.deleteRecord(r.id)
                    dismiss()
                }
            }
        } else {
            ContentUnavailableView("Session not found", systemImage: "clock.arrow.circlepath")
        }
    }
}
