import SwiftUI
import WorkoutEngine

// Customisable Train screen (#260): widgets added from the gallery, plus the small / wide versions of the
// cards Train always had. Every widget opens its screen when tapped (Progress sections switch to that tab).

extension TrainWidgetKind {
    var symbol: String {
        switch self {
        case .actions: "square.grid.3x1.below.line.grid.1x2"
        case .coach: "face.smiling.inverse"
        case .week: "circle.dashed.inset.filled"
        case .level: "star.fill"
        case .nextUp: "play.fill"
        case .climbing: "figure.climbing"
        case .calendar: "calendar"
        case .streak: "flame.fill"
        case .volume: "chart.bar.fill"
        case .records: "trophy.fill"
        case .body: "scalemass.fill"
        case .muscles: "figure.arms.open"
        case .lastWorkout: "clock.arrow.circlepath"
        case .thisWeek: "list.bullet.rectangle.fill"
        case .programme: "flag.checkered"
        }
    }

    var palette: WorkoutEngine.Category {
        switch self {
        case .actions, .nextUp, .calendar: .strength
        case .coach, .muscles: .mobility
        case .week, .lastWorkout: .cardio
        case .level, .records: .stretch
        case .climbing, .streak: .warmup
        case .volume, .body, .thisWeek: .power
        case .programme: .strength
        }
    }
}

/// Small widgets share one height so pairs line up.
enum TrainWidgetMetrics {
    static let smallHeight: CGFloat = 150
    static let corner: CGFloat = 24
}

/// Gradient tile every new widget is drawn on: eyebrow with icon, then the content.
struct WidgetTile<Content: View>: View {
    let kind: TrainWidgetKind
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title ?? kind.title, systemImage: kind.symbol)
                .font(Theme.label(10)).tracking(1.2).textCase(.uppercase)
                .lineLimit(1).minimumScaleFactor(0.7)
                .opacity(0.9)
            content
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: TrainWidgetMetrics.corner, style: .continuous).fill(kind.palette.gradient))
        .contentShape(RoundedRectangle(cornerRadius: TrainWidgetMetrics.corner, style: .continuous))
    }
}

/// Opens a Progress section from a Train widget.
struct OpensProgress: ViewModifier {
    let section: ProgressSection
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        Button {
            model.progressJump = section
            model.tab = .progress
        } label: { content }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(section.title) in Progress")
    }
}

extension View {
    func opensProgress(_ section: ProgressSection) -> some View { modifier(OpensProgress(section: section)) }
}

private func bigNumber(_ text: String, unit: String? = nil) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(text).font(Theme.display(34)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
        if let unit { Text(unit).font(Theme.label(14)).opacity(0.85) }
    }
}

private func caption(_ text: String) -> some View {
    Text(text).font(.caption.weight(.semibold)).opacity(0.9).lineLimit(2).minimumScaleFactor(0.8)
}

// MARK: - Small / wide versions of the classic cards

/// Coach monkey, small: the monkey, its mood and the first tip. Tap → Levels (where the monkey's gear comes from).
struct CoachSmallWidget: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health

    var body: some View {
        let target = model.gameTarget
        let stats = Progression.stats(records: model.state.history, weights: model.weightEntries, targetPerWeek: target)
        let mood = MonkeyFace.Mood.from(weekDone: model.nextSession == nil || stats.thisWeek >= target,
                                        readiness: Readiness.assess(health.snapshot)?.0.title, streakWeeks: stats.currentStreakWeeks)
        WidgetTile(kind: .coach, title: "Coach · \(mood.word)") {
            HStack {
                Spacer(minLength: 0)
                MonkeyFace(mood: mood, scale: 1.1, gear: model.rank.gear)
                Spacer(minLength: 0)
            }
            caption("🔥 \(stats.currentStreakWeeks) wk · \(stats.thisWeek)/\(target) this week")
        }
        .opensLevels()
    }
}

/// Week + readiness, small: done ring and today's verdict (or the phase).
struct WeekSmallWidget: View {
    let plan: WeekPlan
    let done: Int
    @Environment(HealthManager.self) private var health
    @State private var explaining = false

    var body: some View {
        let readiness = Readiness.assess(health.snapshot)?.0
        Button { explaining = true } label: {
            WidgetTile(kind: .week, title: "W\(plan.week)/\(Generator.mesocycleWeeks) · \(Generator.phaseName(plan.week))") {
                HStack {
                    Spacer(minLength: 0)
                    DoneRing(done: done, total: plan.sessions.count)
                    Spacer(minLength: 0)
                }
                Text(readiness?.title ?? "\(plan.sessions.count) sessions · \(plan.sessionMinutes) min")
                    .font(Theme.display(15)).lineLimit(2).minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Explains this week's training phase")
        .sheet(isPresented: $explaining) { WeekPhaseSheet(week: plan.week).presentationDetents([.large]) }
    }
}

/// Level, small: LV, rank and XP bar. Tap → Levels.
struct LevelSmallWidget: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let g = model.game
        WidgetTile(kind: .level, title: model.rank.title) {
            bigNumber("LV \(g.level)")
            XPBarView(progress: g.levelProgress, height: 8, track: .white.opacity(0.25))
            caption("\(g.xpToNext) XP to level \(g.level + 1)")
        }
        .opensLevels()
    }
}

/// Next up, small or wide: session, minutes and Start. The rest of the card opens the session page.
struct NextUpCompactWidget: View {
    let session: Session?
    let wide: Bool
    let onStart: (Session) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        if let session {
            WidgetTile(kind: .nextUp, title: "Next up · \(session.dayLabel)") {
                if wide {
                    HStack(spacing: 10) {
                        NavigationLink(value: session.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.displayTitle).font(Theme.display(24)).lineLimit(1).minimumScaleFactor(0.6)
                                caption("\(session.estMin) min · +\(model.xp(for: session)) XP")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        startButton(session)
                    }
                } else {
                    NavigationLink(value: session.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.displayTitle).font(Theme.display(20)).lineLimit(2).minimumScaleFactor(0.6)
                            caption("\(session.estMin) min")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    startButton(session).frame(maxWidth: .infinity)
                }
            }
        } else {
            WidgetTile(kind: .nextUp, title: "This week") {
                Label("Week complete", systemImage: "trophy.fill").font(Theme.display(18))
                caption("Rest, climb or move to the next week.")
            }
        }
    }

    private func startButton(_ s: Session) -> some View {
        Button { onStart(s) } label: {
            Label(model.activeWorkout(s.id) == nil ? "Start" : "Resume", systemImage: "play.fill")
                .font(Theme.label(14))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: wide ? nil : .infinity)
                .background(Capsule().fill(Theme.lime))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.activeWorkout(s.id) == nil ? "Start" : "Resume") \(s.displayTitle)")
    }
}

/// Climbing, small: climbs this week; tap to log one.
struct ClimbSmallWidget: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var logging: ClimbLog?

    var body: some View {
        let all = Climbs.merged(local: model.climbLogs, health: health.snapshot.recentClimbs,
                                monkeyGrade: MonkeyGradeLink.shared.climbs(for: model.user?.id))
        Button { logging = ClimbLog(start: Date().addingTimeInterval(-90 * 60)) } label: {
            WidgetTile(kind: .climbing) {
                bigNumber("\(Climbs.thisWeek(all))", unit: "this week")
                Spacer(minLength: 0)
                Label("Log climb", systemImage: "plus.circle.fill").font(Theme.label(13))
            }
        }
        .buttonStyle(.plain)
        .sheet(item: $logging) { LogClimbView(initial: $0) }
    }
}

// MARK: - New widgets

/// Calendar: week strip, next 4 weeks or agenda. Tap → the training calendar.
struct CalendarWidget: View {
    let look: TrainWidgetLook
    let size: TrainWidgetSize
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationLink { CalendarView() } label: {
            WidgetTile(kind: .calendar, title: title) {
                switch size == .small ? TrainWidgetLook.week : look {
                case .month: month
                case .agenda: agenda
                default: weekStrip
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the training calendar")
    }

    private var title: String {
        if size == .small { return "This week" }
        switch look {
        case .month: return "Next 4 weeks"
        case .agenda: return "Coming up"
        default: return "This week"
        }
    }

    private enum Mark { case none, planned, done, climb, off, today }

    private struct Day: Identifiable {
        let id: String
        let date: Date
        let marks: [Mark]
        let title: String?
    }

    /// Days of the next `count` weeks from this Monday, with what's on each.
    private func days(weeks count: Int) -> [Day] {
        let cal = model.planCalendar
        let doneDays = Set(model.state.history.map { cal.startOfDay(for: $0.startedAt) })
        let today = cal.startOfDay(for: Date())
        var out: [Day] = []
        for w in model.calendarWeeks(count: count) {
            for wd in 1...7 {
                guard let date = cal.date(byAdding: .day, value: wd - 1, to: w.start) else { continue }
                let day = cal.startOfDay(for: date)
                var marks: [Mark] = []
                let session = w.plan.sessions.first { $0.weekday == wd }
                if w.off[wd] != nil { marks.append(.off) }
                if doneDays.contains(day) { marks.append(.done) } else if session != nil, day >= today { marks.append(.planned) }
                if w.climbing.contains(wd) { marks.append(.climb) }
                if day == today { marks.append(.today) }
                out.append(Day(id: w.days[wd - 1], date: day, marks: marks, title: session?.displayTitle))
            }
        }
        return out
    }

    private func fill(_ marks: [Mark]) -> Color {
        if marks.contains(.done) { return .white }
        if marks.contains(.planned) { return Theme.lime }
        if marks.contains(.climb) { return Color(hex: 0xFF9A3C) }
        if marks.contains(.off) { return .black.opacity(0.35) }
        return .white.opacity(0.18)
    }

    private func ink(_ marks: [Mark]) -> Color {
        marks.contains(.done) || marks.contains(.planned) ? Theme.ink : .white
    }

    private var weekStrip: some View {
        let list = days(weeks: 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(list) { d in
                    Text(d.date.formatted(.dateTime.weekday(.narrow)))
                        .font(Theme.label(12))
                        .foregroundStyle(ink(d.marks))
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fill(d.marks)))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(.white, lineWidth: d.marks.contains(.today) ? 2 : 0))
                }
            }
            if size != .small {
                caption(list.compactMap { d in d.marks.contains(.planned) ? d.title : nil }.joined(separator: " · ").ifEmpty("Nothing left this week"))
            }
            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(list.map { "\($0.date.formatted(.dateTime.weekday(.wide))): \(describe($0))" }.joined(separator: ", "))
    }

    private var month: some View {
        let list = days(weeks: 4)
        return VStack(alignment: .leading, spacing: 4) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(list.prefix(7).enumerated()), id: \.offset) { _, d in
                    Text(d.date.formatted(.dateTime.weekday(.narrow))).font(Theme.label(10)).opacity(0.8)
                }
                ForEach(list) { d in
                    Text(d.date.formatted(.dateTime.day()))
                        .font(Theme.label(11)).monospacedDigit()
                        .foregroundStyle(ink(d.marks))
                        .frame(maxWidth: .infinity, minHeight: size == .large ? 34 : 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill(d.marks)))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(.white, lineWidth: d.marks.contains(.today) ? 2 : 0))
                }
            }
            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next 4 weeks: \(list.filter { $0.marks.contains(.planned) }.count) sessions planned")
    }

    private var agenda: some View {
        let cal = model.planCalendar
        let from = cal.startOfDay(for: Date())
        let to = cal.date(byAdding: .day, value: 14, to: from) ?? from
        let items = model.plannedSessions(from: from, to: to).prefix(size == .large ? 7 : 4)
        return VStack(alignment: .leading, spacing: 4) {
            if items.isEmpty { caption("Nothing planned in the next 2 weeks") }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.date.formatted(.dateTime.weekday(.abbreviated).day())).font(Theme.label(13)).frame(width: 64, alignment: .leading)
                    Text(item.session.displayTitle).font(.subheadline.weight(.bold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(item.session.estMin) min").font(.caption.weight(.semibold)).opacity(0.85)
                }
                .padding(.vertical, 3)
                Divider().overlay(.white.opacity(0.25))
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            dot(Theme.lime, "Planned")
            dot(.white, "Done")
            if model.profile?.climbingDays.isEmpty == false { dot(Color(hex: 0xFF9A3C), "Climb") }
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .opacity(0.9)
    }

    private func dot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 3) { Circle().fill(c).frame(width: 7, height: 7); Text(t) }
    }

    private func describe(_ d: Day) -> String {
        if d.marks.contains(.done) { return "done" }
        if d.marks.contains(.planned) { return d.title ?? "planned" }
        if d.marks.contains(.climb) { return "climbing" }
        if d.marks.contains(.off) { return "can't train" }
        return "rest"
    }
}

private extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}

/// Weeks in a row at the goal. Tap → Progress training.
struct StreakWidget: View {
    let size: TrainWidgetSize
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = Progression.stats(records: model.state.history, weights: model.weightEntries, targetPerWeek: model.gameTarget)
        WidgetTile(kind: .streak) {
            bigNumber("🔥 \(s.currentStreakWeeks)", unit: s.currentStreakWeeks == 1 ? "week" : "weeks")
            Spacer(minLength: 0)
            caption("Best \(s.bestStreakWeeks) · \(s.thisWeek)/\(model.gameTarget) this week")
            if size != .small {
                HStack(spacing: 4) {
                    ForEach(s.weeks.suffix(12)) { w in
                        Capsule().fill(w.workouts >= model.gameTarget ? Color.white : .white.opacity(0.3)).frame(height: 8)
                    }
                }
            }
        }
        .opensProgress(.training)
    }
}

/// Kg lifted, minutes or sets this week with the 8-week trend. Tap → Progress training.
struct VolumeWidget: View {
    let look: TrainWidgetLook
    let size: TrainWidgetSize
    @Environment(AppModel.self) private var model

    private var metric: StatMetric {
        switch look {
        case .minutes: .minutes
        case .sets: .sets
        default: .volume
        }
    }

    private func text(_ v: Double) -> (String, String) {
        switch metric {
        case .volume: let p = Format.volumeParts(v); return (p.value, p.unit)
        case .minutes: return (Format.count(v), "min")
        default: return (Format.count(v), "sets")
        }
    }

    var body: some View {
        let sum = Progression.periodSummary(records: model.state.history, period: .week)
        let value = text(sum.current.value(metric))
        let values = sum.buckets.map { $0.totals.value(metric) }
        let top = max(1, values.max() ?? 1)
        WidgetTile(kind: .volume, title: "\(look.title) · week") {
            bigNumber(value.0, unit: value.1)
            if let d = sum.delta(metric), d != 0 {
                caption("\(d > 0 ? "▲" : "▼") \(text(abs(d)).0) \(text(abs(d)).1) vs last week")
            } else {
                caption("Same as last week")
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(i == values.count - 1 ? 1 : 0.55))
                        .frame(height: max(3, CGFloat(v / top) * (size == .large ? 80 : 30)))
                }
            }
            .frame(height: size == .large ? 80 : 30, alignment: .bottom)
        }
        .opensProgress(.training)
    }
}

/// Best lifts: the top one (small) or top three. Tap → Progress records.
struct RecordsWidget: View {
    let size: TrainWidgetSize
    @Environment(AppModel.self) private var model

    var body: some View {
        let prs = Progression.stats(records: model.state.history, weights: model.weightEntries, targetPerWeek: model.gameTarget)
            .personalRecords.sorted { $0.date > $1.date }
        WidgetTile(kind: .records) {
            if let first = prs.first {
                if size == .small {
                    Text(Exercise.get(first.exerciseId).name).font(Theme.display(16)).lineLimit(2).minimumScaleFactor(0.7)
                    bigNumber(Format.kg(first.kg), unit: "kg")
                    caption(first.date.formatted(.dateTime.day().month(.abbreviated)))
                } else {
                    ForEach(prs.prefix(3)) { pr in
                        HStack {
                            Text(Exercise.get(pr.exerciseId).name).font(.subheadline.weight(.bold)).lineLimit(1)
                            Spacer(minLength: 6)
                            Text("\(Format.kg(pr.kg)) kg").font(Theme.label(15)).monospacedDigit()
                        }
                    }
                }
            } else {
                Text("No records yet").font(Theme.display(16))
                caption("Log weights in a workout and your best lifts show here.")
            }
        }
        .opensProgress(.records)
    }
}

/// Latest body weight with the change over the last 4 weeks. Tap → Progress body.
struct BodyWeightWidget: View {
    let size: TrainWidgetSize
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health

    var body: some View {
        let pts = model.measurementSeries(.weight)
        let latest = pts.last?.value ?? health.snapshot.weightKg ?? model.body.weightKg
        let monthAgo = Date().addingTimeInterval(-28 * 86_400)
        let base = pts.last { $0.date <= monthAgo }?.value ?? pts.first?.value
        WidgetTile(kind: .body) {
            if let latest {
                bigNumber(Format.kg((latest * 10).rounded() / 10), unit: "kg")
                if let base, pts.count > 1 {
                    let d = ((latest - base) * 10).rounded() / 10
                    caption(d == 0 ? "Steady · 4 wk" : "\(d > 0 ? "+" : "−")\(Format.kg(abs(d))) kg · 4 wk")
                }
                if size != .small, pts.count > 1 {
                    let recent = pts.suffix(12).map(\.value)
                    let lo = recent.min() ?? 0, hi = max((recent.max() ?? 1), lo + 0.1)
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(recent.enumerated()), id: \.offset) { _, v in
                            Capsule().fill(.white.opacity(0.8)).frame(height: 6 + CGFloat((v - lo) / (hi - lo)) * 24)
                        }
                    }
                    .frame(height: 30, alignment: .bottom)
                }
            } else {
                Text("Add your weight").font(Theme.display(16))
                caption("From Apple Health or a measurement.")
            }
        }
        .opensProgress(.body)
    }
}

/// Muscles worked in the last 28 days on the body map, front and back. Tap → Progress muscles.
struct MusclesWidget: View {
    let size: TrainWidgetSize
    @Environment(AppModel.self) private var model

    var body: some View {
        let balance = Progression.stats(records: model.state.history, weights: model.weightEntries, targetPerWeek: model.gameTarget).muscleBalance
        let top = balance.sorted { $0.value > $1.value }.prefix(3)
        let h: CGFloat = size == .large ? 220 : 120
        WidgetTile(kind: .muscles, title: "Muscles · 28 days") {
            HStack(spacing: 8) {
                BodyMapView(side: .front, heat: balance, showLabel: false).frame(height: h)
                BodyMapView(side: .back, heat: balance, showLabel: false).frame(height: h)
                VStack(alignment: .leading, spacing: 4) {
                    if top.isEmpty { caption("Train to light up your map") }
                    ForEach(Array(top), id: \.key) { m, _ in
                        Text(m.name).font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .opensProgress(.muscles)
    }
}

/// Last finished workout. Tap → Progress history.
struct LastWorkoutWidget: View {
    let size: TrainWidgetSize
    @Environment(AppModel.self) private var model

    var body: some View {
        WidgetTile(kind: .lastWorkout) {
            if let r = model.history.first {
                Text(r.title).font(Theme.display(size == .small ? 17 : 22)).lineLimit(2).minimumScaleFactor(0.7)
                caption(r.startedAt.formatted(.relative(presentation: .named)))
                Spacer(minLength: 0)
                caption("\(r.durationSec / 60) min · \(r.totalSets) sets\(r.volumeKg > 0 ? " · \(Format.volume(r.volumeKg))" : "")")
            } else {
                Text("No workouts yet").font(Theme.display(16))
                caption("Your first one shows here.")
            }
        }
        .opensProgress(.history)
    }
}
