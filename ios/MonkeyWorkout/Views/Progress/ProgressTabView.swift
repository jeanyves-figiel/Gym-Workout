import Charts
import SwiftUI
import WorkoutEngine

/// "Insights" tab (was Progress until #894; #444, design A + C): a board of widgets the member arranges like Train (#260): level, streak,
/// a tile per part of Progress, recent sessions, consistency, sessions per week, and optional sport widgets.
/// A tile opens its part as a page: training (live tiles #218, consistency, trends, climbing, sports), programmes,
/// body, records, badges, muscles; recent sessions open History (#442). New users get a "day one" layout.
struct ProgressTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var badge: Badge?
    @State private var lift: String?
    /// Part opened from a board tile (#444); History is its own page (#442).
    @State private var opened: ProgressSection?
    /// Sport widget tapped: History filtered to it.
    @State private var openedSport: Sport?
    @State private var arranging = false
    @State private var addingWidget = false
    @State private var customising = false
    /// Insights focus (#939): the first-open picker (A) and the Switch sheet (C).
    @State private var pickingFocus = false
    @State private var switchingFocus = false
    /// CI screenshots: open with this tile flipped.
    var demoFlipped: StatMetric?
    /// CI screenshots: open this part's page.
    var demoSection: ProgressSection?
    var demoEditing = false
    /// CI screenshots: ask the history bar its first starter (#868).
    var demoAsk = false
    /// Set on a part's page: shows only that part.
    var detail: ProgressSection?

    init(demoFlipped: StatMetric? = nil, demoSection: ProgressSection? = nil, demoEditing: Bool = false, demoAsk: Bool = false,
         detail: ProgressSection? = nil) {
        self.demoFlipped = demoFlipped
        self.demoAsk = demoAsk
        self.demoSection = demoSection
        self.demoEditing = demoEditing
        self.detail = detail
    }

    private var target: Int { model.profile?.sessionsPerWeek ?? 3 }

    /// Charts and trends use all of it: progress is free (Pro is Ask Coach, Generate & do today and scans).
    private var charted: [WorkoutRecord] { model.state.history }

    private var stats: ProgressStats {
        Progression.stats(records: charted, weights: model.weightEntries, targetPerWeek: target)
    }

    private var badges: [Badge] { model.badges }

    private var climbs: [ClimbEntry] {
        Climbs.merged(local: model.climbLogs, health: health.snapshot.recentClimbs,
                      monkeyGrade: MonkeyGradeLink.shared.climbs(for: model.user?.id))
    }

    var body: some View {
        let s = stats
        let fresh = s.totalWorkouts == 0
        let top = highlights(s)
        Group {
            if let detail {
                page(detail, s: s, fresh: fresh, top: top)
            } else {
                board(s: s, fresh: fresh, top: top)
            }
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .statusBarScrim()
        .sheet(item: $badge) { b in BadgeSheet(badge: b).presentationDetents([.medium]) }
    }

    // MARK: Board (#444)

    private func board(s: ProgressStats, fresh: Bool, top: ProgressHighlights) -> some View {
        let layout = model.progressBoard
        let items = model.historyItems(health: health)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if !arranging { focusTop(top: top, items: items) }
                if arranging {
                    ProgressEditBar(onAdd: { addingWidget = true }, onList: { customising = true })
                } else if !fresh {
                    // Ask your history (#868 A): on-device answers with a number and a mini chart.
                    ProgressAskBar(demoAsk: demoAsk)
                }
                ForEach(layout.rows) { row in
                    switch row {
                    case .full(let w):
                        widget(w, s: s, fresh: fresh, top: top, items: items)
                    case .pair(let a, let b):
                        HStack(alignment: .top, spacing: 12) {
                            widget(a, s: s, fresh: fresh, top: top, items: items)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            Group {
                                if let b { widget(b, s: s, fresh: fresh, top: top, items: items) } else { Color.clear }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if layout.widgets.isEmpty {
                    Button { arranging = true; addingWidget = true } label: {
                        Label("Add widgets to Insights", systemImage: "plus.square.dashed")
                            .font(Theme.label(15)).foregroundStyle(Theme.lime)
                            .frame(maxWidth: .infinity).padding(.vertical, 28)
                            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(Theme.lime.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .animation(.snappy, value: layout.widgets)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Insights")
        .navigationDestination(for: UUID.self) { id in HistoryDetailView(recordId: id) }
        .navigationDestination(for: ProgrammeRoute.self) { r in model.findProgramme(r.id).map { ProgrammeDetailView(programme: $0) } }
        .navigationDestination(item: $opened) { s in
            if s == .history { HistoryView() } else if s == .mind { MindView() } else { ProgressTabView(demoFlipped: demoFlipped, detail: s) }
        }
        .navigationDestination(item: $openedSport) { HistoryView(initial: .sport($0)) }
        .sheet(isPresented: $addingWidget) { ProgressWidgetGallery() }
        .sheet(isPresented: $customising) { ProgressCustomiseSheet() }
        .sheet(isPresented: $switchingFocus) { InsightsFocusSheet() }
        .fullScreenCover(isPresented: $pickingFocus) { InsightsFocusPicker() }
        // On each visit, so the picker never opens over another tab or the app tour.
        .onAppear { if model.needsInsightsFocus { pickingFocus = true } }
        .task {
            if demoEditing { arranging = true }
            guard let demoSection else { return }
            try? await Task.sleep(for: .milliseconds(400))
            opened = demoSection
        }
        // Opened from a Train widget (#260): that part's page.
        .task(id: model.progressJump) {
            guard let section = model.progressJump else { return }
            try? await Task.sleep(for: .milliseconds(350))
            opened = section
            model.progressJump = nil
        }
    }

    /// Insights focus (#939 C): the hero card, or a chip to pick one for A bit of everything.
    @ViewBuilder
    private func focusTop(top: ProgressHighlights, items: [HistoryItem]) -> some View {
        if let focus = model.insightsFocus {
            if focus == .everything {
                InsightsFocusChip { switchingFocus = true }
            } else {
                let sport = model.progressSports.first ?? .climbing
                InsightsFocusHero(focus: focus, h: top, sport: sport, sportItems: items.filter { $0.filter == .sport(sport) },
                                  onOpen: { if let s = focus.section { opened = s } else { openedSport = sport } },
                                  onSwitch: { switchingFocus = true })
            }
        }
    }

    /// Title with Edit (#444); while editing, "Edit Progress" and Done.
    private var header: some View {
        HStack(spacing: 10) {
            Text(arranging ? "Edit Insights" : "Insights").font(Theme.display(34)).lineLimit(1).minimumScaleFactor(0.7)
            Spacer()
            if arranging {
                Button { withAnimation(.snappy) { arranging = false } } label: {
                    Text("Done").font(Theme.label(15)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(Theme.lime))
                }
                .buttonStyle(.plain)
            } else {
                CoachHeaderTile()
                Button { withAnimation(.snappy) { arranging = true } } label: { HeaderTile(symbol: "square.grid.2x2.fill") }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit Insights")
                .accessibilityHint("Add, remove, resize and reorder the widgets on this screen")
                MePill()
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func widget(_ w: ProgressWidget, s: ProgressStats, fresh: Bool, top: ProgressHighlights, items: [HistoryItem]) -> some View {
        if arranging {
            ProgressWidgetEditChrome(widget: w) { widgetContent(w, s: s, fresh: fresh, top: top, items: items) }
        } else {
            widgetContent(w, s: s, fresh: fresh, top: top, items: items)
        }
    }

    @ViewBuilder
    private func widgetContent(_ w: ProgressWidget, s: ProgressStats, fresh: Bool, top: ProgressHighlights, items: [HistoryItem]) -> some View {
        switch w.kind {
        case .level:
            // Level card, trophy shelf or quest log: the member's game look (#227); a placeholder before the first workout.
            // XP from set-up already lifts the level (the header says "LV 2"): then the real card, not "shows after" (#823).
            if fresh && model.game.level <= 1 {
                ProgressWidgetPlaceholder(widget: w, note: "Your level shows after your first workout")
            } else {
                GameProgressCard(badges: badges)
            }
        case .chest:
            // Week chest (#476): this week's chest and XP, the last 8 weeks; a placeholder before the first workout.
            if fresh {
                ProgressWidgetPlaceholder(widget: w, note: "Your week chest opens when you meet your weekly goal")
            } else {
                WeekChestCard { opened = .training }
            }
        case .growth:
            // Growth path (#495): goal, its date and what Monkey noticed; opens the page.
            GrowthWidget()
        case .mood:
            // Mood vs training (#614 B): the finish faces against each workout's effort.
            MoodWidget(widget: w)
        case .today:
            // Body + Mind today (#852 C): ready score → auto-tune sheet, Mind score → Mind page, Coach's call.
            TodayBodyMindWidget { opened = .mind }
        case .mind:
            // Mind (#852 A): the part tile when small, the score card with 7-day bars when wide.
            Button { opened = .mind } label: {
                if w.size == .small { ProgressSectionTile(h: top, section: .mind) } else { MindScoreCard(score: top.mind) }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Mind")
        case .streak:
            StreakRow(current: s.currentStreakWeeks, best: s.bestStreakWeeks, thisWeek: s.thisWeek, target: target, fresh: fresh,
                      shields: s.streakShields)
        case .training, .body, .records, .badges, .muscles, .programmes:
            let section = w.kind.section
            Button {
                // Nothing to show yet (#345): the Programmes card goes straight to picking one.
                if section == .programmes && model.activeProgramme == nil && model.programmeHistory.isEmpty {
                    model.openExploreProgrammes()
                } else {
                    opened = section
                }
            } label: { ProgressSectionTile(h: top, section: section) }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(section.title)")
        case .history:
            if w.size == .small || items.isEmpty {
                Button { opened = .history } label: { ProgressSectionTile(h: top, section: .history) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens History")
            } else {
                // Recent sessions (#442 C): every kind of session, See all opens History.
                RecentSessionsStrip(items: items, seeAll: { opened = .history }, openClimbs: { openedSport = .climbing })
            }
        case .consistency:
            ConsistencyCalendar(days: s.days, records: dayRecords, empty: fresh)
        case .weekly:
            weeklyChart(s)
        case .sport:
            let sport = w.sport ?? .other
            Button { openedSport = sport } label: {
                SportProgressWidget(sport: sport, size: w.size, items: items.filter { $0.filter == .sport(sport) })
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens your \(sport.label) sessions")
        }
    }

    // MARK: A part's page

    private func page(_ section: ProgressSection, s: ProgressStats, fresh: Bool, top: ProgressHighlights) -> some View {
        let climbList = climbs
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch section {
                case .training:
                    if fresh {
                        FirstMilestonesCard(session: false, pr: !model.personalRecords.isEmpty, climb: !climbList.isEmpty)
                    } else {
                        tiles(climbs: climbList)
                    }
                    ConsistencyCalendar(days: s.days, records: dayRecords, empty: fresh)
                    weeklyChart(s)
                    strengthTrend
                    if !climbList.isEmpty { ClimbingCard(climbs: climbList) }
                    // Other sports (#416): logged here or from Apple Health.
                    let sports = Sports.merged(local: model.sportLogs, health: health.snapshot.recentSports)
                    // Hyrox hub (#426): division, goal, sims, races.
                    if model.doesHyrox { HyroxHubCard() }
                    // Week in heart-rate zones (#609 C): every workout's time in zone, Zone 2 goal.
                    if let zones = health.snapshot.zoneWeek, !zones.isEmpty {
                        ZoneWeekCard(time: zones, fromApple: health.snapshot.zonesFromApple == true)
                    }
                    if !sports.isEmpty { SportsCard(entries: sports) }
                case .programmes:
                    // Training programmes (#255): the running one, lifts start vs now, finished ones.
                    ProgrammeProgressSection()
                case .body:
                    if !model.measurementSeries(.weight).isEmpty || !health.snapshot.vo2Trend.isEmpty { bodyTrends }
                    ProgressMeasurementsSection()
                case .records:
                    records(s)
                case .badges:
                    achievements
                case .muscles:
                    muscleBalance(s, fresh: fresh)
                case .history, .mind:
                    EmptyView()
                }
            }
            .padding(16)
        }
        .navigationTitle(section.title)
        .toolbarTitleDisplayMode(.inlineLarge)
    }

    private func highlights(_ s: ProgressStats) -> ProgressHighlights {
        func measure(_ m: BodyMetric, _ pts: [BodyMeasurements.Point]) -> ProgressHighlights.Measure? {
            pts.last.map { ProgressHighlights.Measure(metric: m, value: $0.value, change: BodyMeasurements.change(pts)) }
        }
        func relative(_ m: ProgressHighlights.Measure) -> Double {
            guard let c = m.change, m.value - c > 0 else { return 0 }
            return abs(c / (m.value - c))
        }
        let measures = BodyMetric.all.compactMap { measure($0, model.measurementSeries($0)) }
            .sorted { relative($0) > relative($1) }
        var recs: [ProgressHighlights.Record] = []
        for pr in model.personalRecords {
            let name = Exercise.find(pr.exerciseId)?.name ?? pr.exerciseId
            guard !recs.contains(where: { $0.name == name }) else { continue }
            recs.append(.init(name: name, value: pr.kind == .maxReps ? "\(pr.reps)" : Format.kg(pr.kg),
                              unit: pr.kind == .maxReps ? "reps" : "kg", date: pr.date))
        }
        for pr in s.personalRecords {
            let name = Exercise.find(pr.exerciseId)?.name ?? pr.exerciseId
            guard !recs.contains(where: { $0.name == name }) else { continue }
            recs.append(.init(name: name, value: Format.kg(pr.kg), unit: "kg", date: pr.date))
        }
        let all = badges
        let vo2 = health.snapshot.vo2Trend.map { BodyMeasurements.Point(date: $0.date, value: $0.value) }
        return ProgressHighlights(
            measures: measures,
            records: recs,
            unlocked: all.filter(\.unlocked).count,
            badgeCount: all.count,
            nextBadge: all.filter { !$0.unlocked }.max { $0.progress < $1.progress },
            // VO₂max is not a BodyMetric; only its value and change are read.
            vo2: vo2.last.map { .init(metric: .weight, value: $0.value, change: BodyMeasurements.change(vo2)) },
            weight: measures.first { $0.metric == .weight },
            workouts: model.history.count,
            thisWeek: s.thisWeek,
            target: target,
            lastWorkout: model.history.map(\.startedAt).max(),
            topMuscle: s.muscleBalance.max { $0.value < $1.value }.map { $0.key.name },
            programme: model.activeProgramme.flatMap { a in
                a.programme.map { (name: $0.name, state: a.paused ? "Paused" : "Week \(model.programmeWeek ?? 1) of \($0.weeks)") }
            },
            programmesFinished: model.programmeHistory.filter(\.finished).count,
            mind: model.mindScore)
    }

    @ViewBuilder
    private func muscleBalance(_ s: ProgressStats, fresh: Bool) -> some View {
        if !s.muscleBalance.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                BodyMapPair(heat: s.muscleBalance).frame(height: 240)
                HeatLegend()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        } else {
            Text("Your muscle heat map fills in as you train.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }
    }

    // MARK: Sections

    private func tiles(climbs: [ClimbEntry]) -> some View {
        let recent = climbs.filter { $0.start > Date().addingTimeInterval(-84 * 86_400) }
        let grade = Climbs.hardest(recent.compactMap(\.topGrade))
        return LiveTiles(records: charted, climbs: recent.isEmpty ? nil : (recent.count, grade), flipped: demoFlipped)
    }

    /// Latest workout per day, so a lit square in the consistency calendar opens it (#218).
    private var dayRecords: [Date: UUID] {
        let cal = Progression.calendar()
        var out: [Date: WorkoutRecord] = [:]
        for r in charted {
            let d = cal.startOfDay(for: r.startedAt)
            if r.startedAt > (out[d]?.startedAt ?? .distantPast) { out[d] = r }
        }
        return out.mapValues(\.id)
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
                // Ask Coach about the bars (#412 C).
                CoachSpark(question: "How's my consistency?", focus: CoachFocus(
                    screen: "progress", title: "Sessions per week",
                    detail: "goal \(target) a week; last weeks oldest first: " + s.weeks.suffix(8).map { String($0.workouts) }.joined(separator: ", ")
                        + "; streak \(s.currentStreakWeeks) weeks"))
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
            let points = Progression.oneRepMaxTrend(selected, records: charted)
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
            Label(health.connected ? "Body · Apple Health" : "Body", systemImage: "heart.fill").eyebrow()
            // Apple Health samples merged with weights logged in Measurements (#185).
            let weight = model.measurementSeries(.weight).map { HealthSnapshot.TrendPoint(date: $0.date, value: $0.value) }
            if !weight.isEmpty {
                TrendChart(title: "Body weight", unit: "kg", symbol: "scalemass.fill", points: weight,
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
                            // Two lines that shrink a little: "Goblet Cossack…" hid the lift (#823).
                            Text(Exercise.find(pr.exerciseId)?.name ?? pr.exerciseId).font(.body.weight(.semibold))
                                .lineLimit(2).minimumScaleFactor(0.85)
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
}

// MARK: - Pieces

enum ProgressStyle {
    static let hero = LinearGradient(colors: [Theme.lime, Color(red: 0.12, green: 0.85, blue: 0.54)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let gold = LinearGradient(colors: [Color(red: 1, green: 0.72, blue: 0), Color(red: 1, green: 0.37, blue: 0.23)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let badge = LinearGradient(colors: [Color(red: 1, green: 0.55, blue: 0.1), Color(red: 1, green: 0.18, blue: 0.47)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Square gradient tile: icon tile top-left, big number, label.
struct GradientStat: View {
    let symbol: String
    let value: String
    let label: String
    let gradient: LinearGradient
    /// Type colour: `Theme.ink` on light gradients (#540).
    var ink: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 13).fill(ink == .white ? Color.white.opacity(0.2) : ink.opacity(0.12)))
            Text(value).font(Theme.display(30)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Theme.label(11)).tracking(1).textCase(.uppercase).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(ink)
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
struct TrendChart: View {
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
    /// Workout to open when a lit day is tapped.
    var records: [Date: UUID] = [:]
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
                            let square = RoundedRectangle(cornerRadius: 4)
                                .fill(n > 0 ? AnyShapeStyle(Theme.lime.opacity(min(1, 0.55 + 0.25 * Double(n)))) : AnyShapeStyle(Color.white.opacity(day > today ? 0.02 : 0.07)))
                                .overlay {
                                    if day == today && n == 0 {
                                        RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.lime, lineWidth: 2)
                                    }
                                }
                                .aspectRatio(1, contentMode: .fit)
                            if let id = records[day] {
                                NavigationLink(value: id) { square }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month()))
                            } else {
                                square
                            }
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
                    if !records.isEmpty { Text("Tap a day to open it").font(.caption2.weight(.semibold)).foregroundStyle(Theme.lime) }
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
                // Rounded-square badge tile (#541), its progress drawn around it by `ProgressRing`.
                if badge.unlocked {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .fill(LinearGradient(colors: badge.tier.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: badge.tier.colors[0].opacity(0.5), radius: 8)
                } else {
                    RoundedRectangle(cornerRadius: 19, style: .continuous).fill(Color.white.opacity(0.06))
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
                StoryShareButton(poster: .badge(badge), title: "Share this badge").padding(.horizontal, 24)
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

/// Everything done in one past session.
struct HistoryDetailView: View {
    let recordId: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let r = model.state.history.first(where: { $0.id == recordId }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(r.startedAt.formatted(date: .complete, time: .shortened)).eyebrow()
                        Text(r.title).font(Theme.display(34))
                        if r.deload { Text("Deload week").font(Theme.label(12)).foregroundStyle(.orange) }
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        GradientStat(symbol: "stopwatch.fill", value: "\(r.durationSec / 60)′", label: "Duration",
                                     gradient: WorkoutEngine.Category.cardio.gradient)
                        GradientStat(symbol: "square.stack.3d.up.fill", value: "\(r.totalSets)", label: "Sets",
                                     gradient: WorkoutEngine.Category.mobility.gradient)
                        GradientStat(symbol: "scalemass.fill", value: r.volumeKg > 0 ? Format.volume(r.volumeKg) : "—", label: "Volume",
                                     gradient: WorkoutEngine.Category.strength.gradient)
                        GradientStat(symbol: "flame.fill", value: r.kcal.map { "\(Int($0))" } ?? "—", label: "kcal (est.)",
                                     gradient: WorkoutEngine.Category.warmup.gradient, ink: WorkoutEngine.Category.warmup.ink)
                        if let a = r.avgHeartRate {
                            GradientStat(symbol: "heart.fill", value: "\(Int(a))", label: "Avg bpm", gradient: WorkoutEngine.Category.power.gradient)
                        }
                        if let m = r.maxHeartRate {
                            GradientStat(symbol: "bolt.heart.fill", value: "\(Int(m))", label: "Max bpm", gradient: AccountTint.danger)
                        }
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
                            GradientSection(symbol: cat.symbol, title: cat.label, gradient: cat.gradient, ink: cat.ink) {
                                ForEach(items) { e in
                                    HStack {
                                        Image(systemName: e.setsDone >= e.setsPlanned ? "checkmark.circle.fill" : (e.setsDone > 0 ? "circle.lefthalf.filled" : "circle"))
                                            .opacity(e.setsDone > 0 ? 1 : 0.6)
                                        Text(Exercise.find(e.exerciseId)?.name ?? e.exerciseId).font(.body.weight(.semibold))
                                        Spacer()
                                        Text("\(e.setsDone)/\(e.setsPlanned)").font(Theme.label(13)).opacity(0.8)
                                        if let kg = e.weightKg { Text("\(Format.kg(kg)) kg").font(Theme.label(13)) }
                                    }
                                }
                            }
                        }
                    }
                    // Gone at once (#539): the Undo bar puts it back, no confirmation.
                    AccountPillButton(title: "Undo workout", role: .destructive) { undo(r) }
                        .accessibilityHint("Removes it from history with its sets, PRs and progress. Undo for a few seconds.")
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Session not found", systemImage: "clock.arrow.circlepath")
        }
    }

    /// Removes the workout as if it never happened (#133) and closes; the Undo bar brings it all back (#539). The
    /// server delete waits for the bar to go.
    private func undo(_ r: WorkoutRecord) {
        guard let removed = model.undoWorkout(r.id, serverAfter: UndoCloseCenter.seconds + 0.5) else { return }
        dismiss()
        UndoCloseCenter.shared.deleted("Workout removed", detail: undoDetail(r.title, r.startedAt.formatted(date: .abbreviated, time: .omitted)),
                                       symbol: "clock.arrow.circlepath") { [model] in
            model.restoreWorkout(removed)
        }
    }
}

