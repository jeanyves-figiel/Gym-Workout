import Charts
import SwiftUI
import WorkoutEngine

/// "Progress" tab in the Explore card style (#82): streak hero, gradient stat tiles, consistency, trends,
/// records, climbing, muscle balance, achievements, history. New users get a "day one" layout instead of zeros.
struct ProgressTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var badge: Badge?
    @State private var lift: String?

    private var target: Int { model.profile?.sessionsPerWeek ?? 3 }

    private var stats: ProgressStats {
        Progression.stats(records: model.state.history, weights: model.weightEntries, targetPerWeek: target)
    }

    private var badges: [Badge] {
        Achievements.evaluate(records: model.state.history, weights: model.weightEntries, targetPerWeek: target)
    }

    private var climbs: [ClimbEntry] {
        Climbs.merged(local: model.climbLogs, health: health.snapshot.recentClimbs,
                      monkeyGrade: MonkeyGradeLink.shared.climbs(for: model.user?.id))
    }

    var body: some View {
        let s = stats
        let fresh = s.totalWorkouts == 0
        let climbList = climbs
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                StreakHero(stats: s, target: target)
                if fresh {
                    FirstMilestonesCard(session: false, pr: !model.personalRecords.isEmpty, climb: !climbList.isEmpty)
                } else {
                    totals(s, climbs: climbList)
                }
                ConsistencyCalendar(days: s.days, empty: fresh)
                weeklyChart(s)
                strengthTrend
                if !health.snapshot.weightTrend.isEmpty || !health.snapshot.vo2Trend.isEmpty { bodyTrends }
                records(s)
                if !climbList.isEmpty { ClimbingCard(climbs: climbList) }
                if !s.muscleBalance.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Muscle balance · last 28 days").eyebrow()
                        BodyMapPair(heat: s.muscleBalance).frame(height: 240)
                        HeatLegend()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                achievements
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

    private func totals(_ s: ProgressStats, climbs: [ClimbEntry]) -> some View {
        let recent = climbs.filter { $0.start > Date().addingTimeInterval(-84 * 86_400) }
        let grade = Climbs.hardest(recent.compactMap(\.topGrade))
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            GradientStat(symbol: "dumbbell.fill", value: "\(s.totalWorkouts)", label: "Sessions",
                         gradient: WorkoutEngine.Category.strength.gradient)
            GradientStat(symbol: "stopwatch.fill", value: Self.hours(s.totalMinutes), label: "Trained",
                         gradient: WorkoutEngine.Category.cardio.gradient)
            GradientStat(symbol: "scalemass.fill", value: String(format: "%.1f t", s.totalVolumeKg / 1000), label: "Lifted",
                         gradient: WorkoutEngine.Category.power.gradient)
            if recent.isEmpty {
                GradientStat(symbol: "square.stack.3d.up.fill", value: "\(s.totalSets)", label: "Sets",
                             gradient: WorkoutEngine.Category.mobility.gradient)
            } else {
                GradientStat(symbol: "figure.climbing", value: "\(recent.count)",
                             label: "Climbs · 12 wk" + (grade.map { " · \($0)" } ?? ""),
                             gradient: ClimbKind.boulder.gradient)
            }
        }
    }

    static func hours(_ minutes: Int) -> String {
        minutes < 600 && minutes % 60 != 0 ? String(format: "%.1f h", Double(minutes) / 60) : "\(minutes / 60) h"
    }

    @ViewBuilder
    private func weeklyChart(_ s: ProgressStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sessions per week").eyebrow()
                Spacer()
                Text("Goal \(target)").font(Theme.label(12)).foregroundStyle(Theme.lime)
            }
            if s.totalWorkouts == 0 {
                GhostBars().frame(height: 110)
                Text("Your weekly bars build here. Hit \(target) in a week and the bar turns lime.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.muted)
            } else {
                Chart {
                    ForEach(s.weeks) { w in
                        BarMark(x: .value("Week", w.weekStart, unit: .weekOfYear), y: .value("Sessions", w.workouts))
                            .foregroundStyle(w.workouts >= target
                                ? AnyShapeStyle(LinearGradient(colors: [Theme.lime, Color(red: 0.12, green: 0.85, blue: 0.54)], startPoint: .top, endPoint: .bottom))
                                : AnyShapeStyle(WorkoutEngine.Category.strength.gradient))
                            .cornerRadius(6)
                    }
                    RuleMark(y: .value("Target", target))
                        .foregroundStyle(Theme.lime.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 150)
            }
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
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Strength · est. 1RM").eyebrow()
                        Menu {
                            ForEach(options) { e in Button(e.name) { lift = e.id } }
                        } label: {
                            Label(Exercise.find(selected)?.name ?? selected, systemImage: "chevron.down")
                                .font(Theme.label(14))
                        }
                    }
                    Spacer()
                    if let last = points.last?.1 {
                        Text("\(Format.kg(last.rounded())) kg").font(Theme.display(26)).monospacedDigit()
                    }
                }
                let minKg = (points.map(\.1).min() ?? 0) - 2
                Chart {
                    ForEach(points, id: \.0) { p in
                        AreaMark(x: .value("Week", p.0), yStart: .value("Base", minKg), yEnd: .value("kg", p.1))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(LinearGradient(colors: [WorkoutEngine.Category.strength.color.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Week", p.0), y: .value("kg", p.1))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 3))
                            .foregroundStyle(WorkoutEngine.Category.strength.gradient)
                        PointMark(x: .value("Week", p.0), y: .value("kg", p.1)).foregroundStyle(Theme.lime)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
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
        VStack(alignment: .leading, spacing: 16) {
            Label("From Apple Health", systemImage: "heart.fill").eyebrow()
            if !health.snapshot.weightTrend.isEmpty {
                TrendChart(title: "Body weight", unit: "kg", symbol: "scalemass.fill", points: health.snapshot.weightTrend,
                           gradient: WorkoutEngine.Category.cardio.colors)
            }
            if !health.snapshot.vo2Trend.isEmpty {
                TrendChart(title: "VO₂max", unit: "ml/kg/min", symbol: "lungs.fill", points: health.snapshot.vo2Trend,
                           gradient: WorkoutEngine.Category.power.colors)
            }
        }
        .card()
    }

    @ViewBuilder
    private func records(_ s: ProgressStats) -> some View {
        let attempts = model.personalRecords
        VStack(alignment: .leading, spacing: 10) {
            Text("Personal records").eyebrow()
            if attempts.isEmpty && s.personalRecords.isEmpty {
                GradientRow(symbol: "trophy.fill", title: "No PRs yet",
                            subtitle: "Open any strength exercise in Explore and tap Attempt a PR.",
                            gradient: ProgressStyle.gold)
            }
            ForEach(attempts.prefix(3)) { pr in
                GradientRow(symbol: "trophy.fill", title: Exercise.find(pr.exerciseId)?.name ?? pr.exerciseId,
                            subtitle: Self.attemptLine(pr),
                            value: pr.kind == .maxReps ? "\(pr.reps)" : Format.kg(pr.kg),
                            unit: pr.kind == .maxReps ? "reps" : "kg",
                            gradient: ProgressStyle.gold)
            }
            if !s.personalRecords.isEmpty {
                VStack(spacing: 10) {
                    ForEach(s.personalRecords.prefix(6)) { pr in
                        HStack(spacing: 12) {
                            Image(systemName: "medal.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 32, height: 32)
                                .background(RoundedRectangle(cornerRadius: 10).fill(ProgressStyle.gold))
                            Text(Exercise.find(pr.exerciseId)?.name ?? pr.exerciseId).font(.body.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text("\(Format.kg(pr.kg)) kg").font(Theme.display(18)).monospacedDigit()
                            Text(pr.date.formatted(.dateTime.day().month())).font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .card()
            }
        }
    }

    static func attemptLine(_ pr: PRAttempt) -> String {
        var parts = ["New \(pr.label)", pr.date.formatted(.dateTime.day().month())]
        if let prev = pr.previousBest, pr.kind == .maxReps ? Double(pr.reps) > prev : pr.kg > prev {
            parts.append(pr.kind == .maxReps ? "+\(pr.reps - Int(prev)) reps" : "+\(Format.kg(pr.kg - prev)) kg")
        }
        return parts.joined(separator: " · ")
    }

    private var achievements: some View {
        let all = badges
        let unlocked = all.filter(\.unlocked).count
        let next = all.filter { !$0.unlocked }.max { $0.progress < $1.progress }
        return VStack(alignment: .leading, spacing: 12) {
            GradientRow(symbol: "medal.fill", title: "Achievements",
                        subtitle: next.map { "Next: \($0.title) · \(Format.count($0.current))/\(Format.count($0.target))" } ?? "All unlocked. Legend.",
                        value: "\(unlocked)/\(all.count)", gradient: ProgressStyle.badge)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                ForEach(all.sorted { ($0.unlocked ? 0 : 1, -$0.progress) < ($1.unlocked ? 0 : 1, -$1.progress) }) { b in
                    Button { badge = b } label: { BadgeView(badge: b) }
                        .buttonStyle(.plain)
                }
            }
            .card()
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History").eyebrow()
            if model.history.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.lime)
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.lime.opacity(0.12)))
                    Text("Finish a session and it shows up here with everything you did.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

enum ProgressStyle {
    static let hero = LinearGradient(colors: [Theme.lime, Color(red: 0.12, green: 0.85, blue: 0.54)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let gold = LinearGradient(colors: [Color(red: 1, green: 0.72, blue: 0), Color(red: 1, green: 0.37, blue: 0.23)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let badge = LinearGradient(colors: [Color(red: 1, green: 0.55, blue: 0.1), Color(red: 1, green: 0.18, blue: 0.47)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Lime hero: week streak and this week's sessions vs goal; "day one" copy for new users.
private struct StreakHero: View {
    let stats: ProgressStats
    let target: Int

    var body: some View {
        let fresh = stats.totalWorkouts == 0
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label(fresh ? "Day one" : "Week streak", systemImage: fresh ? "sparkles" : "flame.fill")
                    .font(Theme.label(12)).tracking(1.2).textCase(.uppercase)
                if fresh {
                    Text("Your streak starts with session one").font(Theme.display(26)).fixedSize(horizontal: false, vertical: true)
                    Text("Goal: \(target) sessions a week").font(.footnote.weight(.semibold)).opacity(0.75)
                } else {
                    Text("\(stats.currentStreakWeeks)").font(Theme.display(64)).monospacedDigit().contentTransition(.numericText())
                    Text(caption).font(.footnote.weight(.semibold)).opacity(0.75)
                }
            }
            Spacer(minLength: 0)
            ZStack {
                ProgressRing(progress: Double(stats.thisWeek) / Double(max(1, target)), lineWidth: 9,
                             colors: [Theme.ink, Theme.ink.opacity(0.8)])
                VStack(spacing: 0) {
                    Text("\(stats.thisWeek)/\(target)").font(Theme.display(20)).monospacedDigit()
                    Text("this wk").font(Theme.label(9)).opacity(0.7)
                }
            }
            .frame(width: 84, height: 84)
        }
        .foregroundStyle(Theme.ink)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(ProgressStyle.hero))
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        let left = max(0, target - stats.thisWeek)
        let goal = left == 0 ? "Week goal hit" : "\(left) more to keep it going"
        return "Best \(stats.bestStreakWeeks) wk · \(goal)"
    }
}

/// Square gradient tile: icon tile top-left, big number, label.
private struct GradientStat: View {
    let symbol: String
    let value: String
    let label: String
    let gradient: LinearGradient

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 13).fill(.white.opacity(0.2)))
            Text(value).font(Theme.display(30)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Theme.label(11)).tracking(1).textCase(.uppercase).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(gradient))
        .accessibilityElement(children: .combine)
    }
}

/// Explore-style row: icon tile left, title + subtitle, big number right.
struct GradientRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    var value: String?
    var unit: String?
    let gradient: LinearGradient

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .bold))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.7)
                Text(subtitle).font(.footnote.weight(.medium)).opacity(0.85).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            if let value {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(value).font(Theme.display(28)).monospacedDigit()
                    if let unit { Text(unit).font(Theme.label(11)).opacity(0.8) }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(gradient))
        .accessibilityElement(children: .combine)
    }
}

/// New users: three first wins, checked as they happen.
private struct FirstMilestonesCard: View {
    let session: Bool
    let pr: Bool
    let climb: Bool

    var body: some View {
        let items: [(String, String, Bool)] = [
            ("Finish your first session", "Train tab → start today's session", session),
            ("Attempt a PR", "Any strength exercise in Explore", pr),
            ("Log a climb", "Train tab → Log climb, or MonkeyGrade", climb),
        ]
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "target")
                    .font(.system(size: 24, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.2)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("First milestones").font(Theme.display(20))
                    Text("Small wins that start everything").font(.footnote.weight(.medium)).opacity(0.85)
                }
                Spacer(minLength: 0)
                Text("\(items.filter(\.2).count)/\(items.count)").font(Theme.display(28)).monospacedDigit()
            }
            ForEach(items, id: \.0) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.2 ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .bold))
                        .opacity(item.2 ? 1 : 0.6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.0).font(.subheadline.weight(.bold)).strikethrough(item.2)
                        Text(item.1).font(.caption.weight(.medium)).opacity(0.75)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WorkoutEngine.Category.strength.gradient))
    }
}

/// Placeholder bars for the empty weekly chart.
private struct GhostBars: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array([0.3, 0.5, 0.4, 0.65, 0.55, 0.8, 0.7, 1.0].enumerated()), id: \.offset) { bar in
                let h = bar.element
                GeometryReader { geo in
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
                            .frame(height: geo.size.height * h)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Health trend with the latest value and change over the period.
private struct TrendChart: View {
    let title: String
    let unit: String
    let symbol: String
    let points: [HealthSnapshot.TrendPoint]
    let gradient: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.bold))
                    if let first = points.first?.value, let last = points.last?.value, points.count > 1 {
                        Text(String(format: "%+.1f %@ since %@", last - first, unit, points[0].date.formatted(.dateTime.day().month())))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                if let v = points.last?.value {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(String(format: "%.1f", v)).font(Theme.display(24)).monospacedDigit()
                        Text(unit).font(Theme.label(10)).foregroundStyle(Theme.muted)
                    }
                }
            }
            Chart(points) { p in
                AreaMark(x: .value("Date", p.date), yStart: .value("Base", baseline), yEnd: .value(title, p.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [gradient[0].opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", p.date), y: .value(title, p.value))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    .foregroundStyle(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 110)
        }
    }

    private var baseline: Double { (points.map(\.value).min() ?? 0) - 0.5 }
}

/// Climbing over the last 12 weeks (logged here, Apple Health, MonkeyGrade).
private struct ClimbingCard: View {
    let climbs: [ClimbEntry]

    var body: some View {
        let recent = climbs.filter { $0.start > Date().addingTimeInterval(-84 * 86_400) }
        let minutes = recent.reduce(0) { $0 + $1.minutes }
        let grade = Climbs.hardest(recent.compactMap(\.topGrade))
        let thisWeek = Climbs.thisWeek(climbs)
        GradientRow(symbol: "figure.climbing", title: "Climbing",
                    subtitle: "\(recent.count) sessions · \(ProgressTabView.hours(minutes)) in 12 weeks"
                        + (thisWeek > 0 ? " · \(thisWeek) this week" : ""),
                    value: grade ?? "\(recent.count)", unit: grade == nil ? "climbs" : "top grade",
                    gradient: ClimbKind.boulder.gradient)
    }
}

/// GitHub-style grid: 12 weeks × 7 days. Today is outlined; new users get a nudge instead of a dead grid.
struct ConsistencyCalendar: View {
    let days: [Date: Int]
    var empty = false

    var body: some View {
        let cal = Progression.calendar()
        let thisWeek = Progression.weekStart(Date(), cal)
        let today = cal.startOfDay(for: Date())
        let active = days.filter { $0.key >= cal.date(byAdding: .weekOfYear, value: -11, to: thisWeek)! && $0.value > 0 }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Consistency · 12 weeks").eyebrow()
                Spacer()
                if !empty { Text("\(active) days").font(Theme.label(12)).foregroundStyle(Theme.lime) }
            }
            HStack(spacing: 4) {
                ForEach((0..<12).reversed(), id: \.self) { weeksAgo in
                    let start = cal.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeek)!
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = cal.date(byAdding: .day, value: d, to: start)!
                            let n = days[day] ?? 0
                            RoundedRectangle(cornerRadius: 4)
                                .fill(n > 0 ? AnyShapeStyle(Theme.lime.opacity(min(1, 0.55 + 0.25 * Double(n)))) : AnyShapeStyle(Color.white.opacity(day > today ? 0.02 : 0.07)))
                                .overlay {
                                    if day == today && n == 0 {
                                        RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.lime, lineWidth: 2)
                                    }
                                }
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            if empty {
                Text("Today's square is waiting. Every session lights one up.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.muted)
            } else {
                HStack {
                    Text("12 weeks ago").font(.caption2).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("This week").font(.caption2).foregroundStyle(Theme.muted)
                }
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
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                            .frame(maxWidth: .infinity, alignment: .leading)
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
