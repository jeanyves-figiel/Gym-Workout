import AppIntents
import SwiftUI
import WidgetKit

/// Watch face complications (#190). Every complication fits every slot (circle, corner, rectangle, inline line);
/// data comes from the snapshot the Watch app shares in the App Group; tapping opens the Watch app.
@main
struct MonkeyWorkoutComplications: WidgetBundle {
    var body: some Widget {
        PlanComplications().body
        StatComplications().body
    }
}

struct PlanComplications: WidgetBundle {
    var body: some Widget {
        NextWorkoutWidget()
        WeekGoalWidget()
        StreakWidget()
        WeekStripWidget()
    }
}

struct StatComplications: WidgetBundle {
    var body: some Widget {
        ReadinessWidget()
        TopLiftWidget()
        LastWorkoutWidget()
        MyStatWidget()
        WaterWidget()
        SmartStackWidget()
    }
}

enum ComplicationKind: String, CaseIterable {
    case next = "NextWorkout", week = "WeekGoal", streak = "Streak", weekStrip = "WeekStrip"
    case readiness = "Readiness", topLift = "TopLift", lastWorkout = "LastWorkout"
    case water = "Water"

    var name: String {
        switch self {
        case .next: "Next workout"
        case .week: "Weekly goal"
        case .streak: "Streak"
        case .weekStrip: "Week strip"
        case .readiness: "Readiness"
        case .topLift: "Top lift"
        case .lastWorkout: "Last workout"
        case .water: "Water"
        }
    }

    var summary: String {
        switch self {
        case .next: "Today's workout or the next one, its length and your week."
        case .week: "Sessions done this week against your target."
        case .streak: "Weeks in a row you hit your training goal."
        case .weekStrip: "Monday to Sunday: done, today and planned sessions."
        case .readiness: "Readiness from Apple Health: push, as planned or easier."
        case .topLift: "Your best lifts, one at a time."
        case .lastWorkout: "When you last trained, minutes and sets."
        case .water: "Glasses today against Fuel's target (#520). Tap to add one."
        }
    }
}

let allFamilies: [WidgetFamily] = [.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline]

struct MWEntry: TimelineEntry {
    var date: Date
    /// nil = not synced from the iPhone yet.
    var info: ComplicationInfo?
}

/// Now, then every hour for a day: today / rest days and the Monday week reset change on time and top lifts rotate.
/// The Watch app reloads the timelines whenever a new snapshot arrives from the iPhone.
enum MWTimeline {
    static func entries(preview: Bool) -> [MWEntry] {
        let snap = SharedSnapshot.load()
        let now = Date()
        let cal = Calendar.current
        let hour = cal.dateInterval(of: .hour, for: now)?.start ?? now
        let dates = [now] + (1...24).compactMap { cal.date(byAdding: .hour, value: $0, to: hour) }
        return dates.map { MWEntry(date: $0, info: ComplicationInfo(snap, at: $0) ?? (preview ? .sample : nil)) }
    }
}

struct MWProvider: TimelineProvider {
    func placeholder(in context: Context) -> MWEntry { MWEntry(date: Date(), info: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (MWEntry) -> Void) {
        completion(MWTimeline.entries(preview: context.isPreview)[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MWEntry>) -> Void) {
        completion(Timeline(entries: MWTimeline.entries(preview: false), policy: .atEnd))
    }
}

/// Same configuration for every fixed complication; `Widget` needs `init()`, hence one tiny type per kind.
@MainActor
func mwConfiguration(_ kind: ComplicationKind) -> some WidgetConfiguration {
    StaticConfiguration(kind: kind.rawValue, provider: MWProvider()) { ComplicationView(face: Face(kind, $0)) }
        .configurationDisplayName(kind.name)
        .description(kind.summary)
        .supportedFamilies(allFamilies)
}

struct NextWorkoutWidget: Widget { var body: some WidgetConfiguration { mwConfiguration(.next) } }
struct WeekGoalWidget: Widget { var body: some WidgetConfiguration { mwConfiguration(.week) } }
struct StreakWidget: Widget { var body: some WidgetConfiguration { mwConfiguration(.streak) } }
struct WeekStripWidget: Widget { var body: some WidgetConfiguration { mwConfiguration(.weekStrip) } }
struct ReadinessWidget: Widget { var body: some WidgetConfiguration { mwConfiguration(.readiness) } }
struct TopLiftWidget: Widget { var body: some WidgetConfiguration { mwConfiguration(.topLift) } }
struct LastWorkoutWidget: Widget { var body: some WidgetConfiguration { mwConfiguration(.lastWorkout) } }
struct WaterWidget: Widget { var body: some WidgetConfiguration { mwConfiguration(.water) } }

// MARK: My stat (pick what it shows)

enum StatChoice: String, AppEnum, CaseIterable {
    case week, streak, minutes, readiness

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Stat" }
    static var caseDisplayRepresentations: [StatChoice: DisplayRepresentation] {
        [.week: "Weekly goal", .streak: "Streak", .minutes: "Next workout minutes", .readiness: "Readiness"]
    }

    var label: String {
        switch self {
        case .week: "Weekly goal"
        case .streak: "Streak"
        case .minutes: "Next workout minutes"
        case .readiness: "Readiness"
        }
    }

    var recommendation: Text {
        switch self {
        case .week: Text("My stat: Weekly goal")
        case .streak: Text("My stat: Streak")
        case .minutes: Text("My stat: Next workout minutes")
        case .readiness: Text("My stat: Readiness")
        }
    }

    var kind: ComplicationKind {
        switch self {
        case .week: .week
        case .streak: .streak
        case .minutes: .next
        case .readiness: .readiness
        }
    }
}

struct StatIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "My stat" }
    static var description: IntentDescription { "Choose what MonkeyWorkout shows." }

    @Parameter(title: "Show", default: .week)
    var stat: StatChoice

    init() {}
    init(_ stat: StatChoice) { self.stat = stat }
}

struct StatEntry: TimelineEntry {
    var date: Date
    var info: ComplicationInfo?
    var stat: StatChoice
}

struct StatProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StatEntry { StatEntry(date: Date(), info: .sample, stat: .week) }

    func snapshot(for configuration: StatIntent, in context: Context) async -> StatEntry {
        let e = MWTimeline.entries(preview: context.isPreview)[0]
        return StatEntry(date: e.date, info: e.info, stat: configuration.stat)
    }

    func timeline(for configuration: StatIntent, in context: Context) async -> Timeline<StatEntry> {
        Timeline(entries: MWTimeline.entries(preview: false).map { StatEntry(date: $0.date, info: $0.info, stat: configuration.stat) },
                 policy: .atEnd)
    }

    /// watchOS has no edit screen for widget options: each choice is offered as its own complication.
    /// Descriptions must be plain literals: interpolated Text traps in WidgetKit and kills every complication.
    func recommendations() -> [AppIntentRecommendation<StatIntent>] {
        StatChoice.allCases.map { AppIntentRecommendation(intent: StatIntent($0), description: $0.recommendation) }
    }
}

struct MyStatWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MyStat", intent: StatIntent.self, provider: StatProvider()) {
            ComplicationView(face: Face($0.stat.kind, MWEntry(date: $0.date, info: $0.info)))
        }
        .configurationDisplayName("My stat")
        .description("Choose what MonkeyWorkout shows.")
        .supportedFamilies(allFamilies)
    }
}

// MARK: Content

/// One complication's content, laid out by `ComplicationView` for each slot.
struct Face {
    enum Extra { case none, pills(done: Int, target: Int), days([ComplicationInfo.DayState]) }

    var symbol: String
    var tint: (UInt32, UInt32)
    var eyebrow: String
    var title: String
    var detail: String
    /// Short value for the circle and corner ("2/3", "4w", "50m").
    var value: String
    var cornerLabel: String
    var inline: String
    /// 0…1: drawn as a ring in the circle and a curved gauge in the corner.
    var gauge: Double?
    var ring: [Color]?
    var extra: Extra = .none
    /// Extra row also shown on the watch face, not only in the Smart Stack.
    var extraOnFace = false

    init(_ kind: ComplicationKind, _ entry: MWEntry) {
        guard let i = entry.info else {
            symbol = "applewatch"; tint = (0x3A3F47, 0x1B1E23); eyebrow = "MONKEYWORKOUT"; title = "Open on iPhone"
            detail = "to sync your plan"; value = "Sync"; cornerLabel = "OPEN IPHONE"; inline = "MonkeyWorkout · open on iPhone"
            return
        }
        let weekRing = i.done >= i.target ? [MW.mint, MW.color(0x1E9BFF)] : [MW.lime, MW.mint, MW.color(0x1E9BFF)]
        switch kind {
        case .next:
            symbol = i.day == .weekDone ? "trophy.fill" : i.day == .rest ? "bed.double.fill" : "figure.strengthtraining.traditional"
            tint = (i.tint, i.tint2)
            eyebrow = i.eyebrow
            if i.day == .weekDone {
                title = "\(i.done)/\(i.target) done"; detail = "🔥 \(i.streak) week streak"; value = "\(i.done)/\(i.target)"
                cornerLabel = "WEEK DONE"; inline = "Week done \(i.done)/\(i.target) · 🔥\(i.streak)w"
            } else {
                title = i.title
                detail = "\(i.minutes) min · \(i.exercises) exercises"
                value = i.day == .rest ? i.dayLabel : "\(i.minutes)m"
                cornerLabel = "\(i.title) \(i.minutes)m".uppercased()
                inline = i.day == .rest ? "Rest · \(i.dayLabel) \(i.title)" : "\(i.title) · \(i.minutes) min · \(i.done)/\(i.target)"
            }
            extra = .pills(done: i.done, target: i.target)
        case .week:
            let complete = i.done >= i.target
            symbol = "dumbbell.fill"; tint = (0xFF7A3D, 0xFF3D5A)
            eyebrow = complete ? "WEEK COMPLETE" : "THIS WEEK"
            title = "\(i.done)/\(i.target) sessions"
            detail = i.streak > 0 ? "🔥 \(i.streak) week streak" : "Hit \(i.target) to start a streak"
            value = complete ? "✓" : "\(i.done)/\(i.target)"
            cornerLabel = "WEEK \(i.done)/\(i.target)"; inline = "\(i.done)/\(i.target) this week · 🔥\(i.streak)w"
            gauge = i.progress; ring = weekRing
            extra = .pills(done: i.done, target: i.target); extraOnFace = true
        case .streak:
            symbol = "flame.fill"; tint = (0xFFC23D, 0xFF3D5A)
            eyebrow = "STREAK"; title = "\(i.streak) week\(i.streak == 1 ? "" : "s")"; detail = "Best \(i.bestStreak) weeks"
            value = "\(i.streak)w"; cornerLabel = "\(i.streak) WEEK STREAK"; inline = "🔥 \(i.streak)-week streak · best \(i.bestStreak)"
            let best = max(i.bestStreak, i.streak, 1)
            gauge = Double(i.streak) / Double(best); ring = [MW.color(0xFFC23D), MW.color(0xFF7A3D), MW.color(0xFF3D5A)]
        case .weekStrip:
            symbol = "calendar"; tint = (0x2F6BFF, 0x8A4DFF)
            eyebrow = "THIS WEEK · 🔥 \(i.streak) WEEK\(i.streak == 1 ? "" : "S")"
            title = "\(i.done)/\(i.target) done"; detail = i.eyebrow.capitalized
            let today = i.days?.first { $0 == .today || $0 == .restToday }
            value = today == .today ? "GO" : today == .restToday ? "REST" : "\(i.done)/\(i.target)"
            cornerLabel = "WEEK \(i.done)/\(i.target)"
            if let days = i.days {
                var marks: [String] = []
                for (name, d) in zip(WeekdayName.all, days) {
                    switch d {
                    case .done: marks.append("✓\(name.prefix(2))")
                    case .today: marks.append("●\(name.prefix(2))")
                    case .planned, .missed: marks.append("○\(name.prefix(2))")
                    case .rest, .restToday: break
                    }
                }
                inline = marks.joined(separator: " ")
                extra = .days(days)
            } else {
                inline = "\(i.done)/\(i.target) this week"
                extra = .pills(done: i.done, target: i.target)
            }
            gauge = i.progress; ring = weekRing; extraOnFace = true
        case .readiness:
            let level = i.readinessLevel
            let colors: (UInt32, UInt32) = switch level ?? 0 {
            case 3: (0x3DFFB0, 0x00C9A7)
            case 2: (0xFFC23D, 0xFF7A3D)
            case 1: (0xFF3D5A, 0xFF2D55)
            default: (0x3A3F47, 0x1B1E23)
            }
            symbol = "heart.fill"
            tint = colors
            eyebrow = "READINESS"; title = i.readiness ?? "No data yet"
            detail = level == nil ? "Allow Apple Health on iPhone" : "From Apple Health"
            value = ["–", "EASY", "OK", "GO"][min(max(level ?? 0, 0), 3)]
            cornerLabel = (i.readiness ?? "Readiness").uppercased(); inline = "Readiness: \(i.readiness ?? "no data")"
            gauge = Double(level ?? 0) / 3; ring = [MW.color(colors.0), MW.color(colors.1)]
        case .topLift:
            symbol = "trophy.fill"; tint = (0xFF2D55, 0xFF6FB5)
            if i.records.isEmpty {
                eyebrow = "TOP LIFT"; title = "No lifts yet"; detail = "Log a set to start"; value = "–"
                cornerLabel = "TOP LIFT"; inline = "🏆 Top lift: none yet"
            } else {
                // Rotates hourly through the best lifts.
                let n = (Calendar.current.component(.hour, from: entry.date)) % i.records.count
                let r = i.records[n]
                eyebrow = i.records.count > 1 ? "TOP LIFT · \(n + 1)/\(i.records.count)" : "TOP LIFT"
                title = r.name; detail = "\(MW.kg(r.kg)) kg · best"; value = MW.kg(r.kg)
                cornerLabel = "\(r.name) \(MW.kg(r.kg)) KG".uppercased(); inline = "🏆 \(r.name) \(MW.kg(r.kg)) kg"
            }
        case .lastWorkout:
            symbol = "clock.arrow.circlepath"; tint = (0x00C9A7, 0x2EC5FF)
            if let l = i.last {
                let when = MW.relativeDay(l.date, from: entry.date)
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: l.date),
                                                           to: Calendar.current.startOfDay(for: entry.date)).day ?? 0
                eyebrow = "LAST WORKOUT · \(when.uppercased())"; title = l.title; detail = "\(l.minutes) min · \(l.sets) sets"
                value = days <= 0 ? "Today" : "\(days)d"
                cornerLabel = "\(when) \(l.minutes) MIN".uppercased(); inline = "Last: \(when) · \(l.minutes) min"
            } else {
                eyebrow = "LAST WORKOUT"; title = "No workout yet"; detail = "Start one today"; value = "–"
                cornerLabel = "NO WORKOUT YET"; inline = "No workout yet"
            }
        case .water:
            symbol = "drop.fill"; tint = (0x2EC5FF, 0x2F6BFF); eyebrow = "WATER"
            if let w = i.water, w.target > 0 {
                let g = w.today(entry.date)
                title = "\(g)/\(w.target) glasses"
                detail = g >= w.target ? "Target hit 💧" : "\(w.target - g) to go · tap to add"
                value = "\(g)"; cornerLabel = "WATER \(g)/\(w.target)"; inline = "💧 \(g)/\(w.target) glasses"
                gauge = min(1, Double(g) / Double(w.target))
            } else {
                title = "No target yet"; detail = "Set up Fuel on iPhone"; value = "–"
                cornerLabel = "WATER"; inline = "💧 Water"
            }
            ring = [MW.color(0x2EC5FF), MW.color(0x2F6BFF)]
        }
    }
}

struct ComplicationView: View {
    let face: Face
    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var stack
    @Environment(\.widgetRenderingMode) private var mode

    /// Full-colour faces get filled gradient cards and discs; tinted faces fall back to one-colour outlines.
    private var color: Bool { mode == .fullColor }
    private var fill: LinearGradient { MW.gradient(face.tint.0, face.tint.1) }
    private var ring: Gradient { Gradient(colors: face.ring ?? [MW.color(face.tint.0), MW.color(face.tint.1)]) }
    private var accent: Color { MW.color(face.tint.1) }

    var body: some View {
        content.containerBackground(for: .widget) { fill }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline: Label(face.inline, systemImage: face.symbol)
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        default: rectangular
        }
    }

    @ViewBuilder private var circular: some View {
        if let g = face.gauge {
            Gauge(value: min(max(g, 0), 1)) {
                Image(systemName: face.symbol)
            } currentValueLabel: {
                Text(face.value).font(MW.display(15)).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(ring)
            .widgetAccentable()
        } else {
            ZStack {
                if color { Circle().fill(fill) } else { AccessoryWidgetBackground() }
                VStack(spacing: 0) {
                    Image(systemName: face.symbol).font(.system(size: 17, weight: .bold)).widgetAccentable()
                    Text(face.value).font(MW.display(15)).minimumScaleFactor(0.5).lineLimit(1)
                }
                .padding(4)
                .foregroundStyle(.white)
            }
        }
    }

    /// Short value in the corner, or the symbol when the value is too long for it.
    @ViewBuilder private var cornerCore: some View {
        if face.value.count <= 4 {
            Text(face.value).font(MW.display(17)).minimumScaleFactor(0.5)
        } else {
            Image(systemName: face.symbol).font(.system(size: 18, weight: .bold))
        }
    }

    private var corner: some View {
        cornerCore
            .foregroundStyle(fill)
            .widgetAccentable()
            .widgetLabel {
                if let g = face.gauge {
                    Gauge(value: min(max(g, 0), 1)) { Text(face.cornerLabel) }
                        .tint(ring)
                } else {
                    Text(face.cornerLabel).foregroundStyle(accent)
                }
            }
    }

    /// Filled Explore-style card on full-colour faces; the Smart Stack draws the same gradient as container background.
    @ViewBuilder private var rectangular: some View {
        if color, !stack {
            rectangularContent(onColor: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
        } else if stack {
            rectangularContent(onColor: true)
        } else {
            HStack(spacing: 6) {
                Capsule().fill(fill).frame(width: 4).widgetAccentable()
                rectangularContent(onColor: false)
            }
        }
    }

    private func rectangularContent(onColor: Bool) -> some View {
        let showExtra = stack || face.extraOnFace
        var isDays = false
        if case .days = face.extra { isDays = true }
        let stripOnly = isDays && showExtra
        return HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(face.eyebrow).font(MW.label(11)).tracking(0.6).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(onColor ? Color.white.opacity(0.85) : MW.lime)
                    .widgetAccentable()
                // The week strip replaces title and detail; on the face an extra row replaces the detail.
                if !stripOnly {
                    Text(face.title).font(MW.display(19)).lineLimit(1).minimumScaleFactor(0.6)
                    if stack || !face.extraOnFace {
                        Text(face.detail).font(MW.label(13)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                if showExtra {
                    switch face.extra {
                    case .none: EmptyView()
                    case let .pills(done, target): WeekPills(done: done, target: target)
                    case let .days(days): WeekStrip(days: days)
                    }
                }
            }
            Spacer(minLength: 0)
            if onColor { IconTile(symbol: face.symbol) }
        }
        .foregroundStyle(.white)
    }
}

/// White 22 % tile with the symbol, as on the Explore cards.
struct IconTile: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .bold))
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.22)))
    }
}

/// One pill per planned session; done ones glow lime.
struct WeekPills: View {
    let done: Int
    let target: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<min(max(target, 1), 7), id: \.self) { n in
                Capsule()
                    .fill(n < done ? MW.lime : Color.white.opacity(0.3))
                    .frame(height: 5)
                    .shadow(color: n < done ? MW.lime.opacity(0.8) : .clear, radius: 3)
            }
        }
        .padding(.top, 3)
        .widgetAccentable()
    }
}

/// Monday … Sunday dots: lime ✓ done, white ring today, faint planned, dark rest.
struct WeekStrip: View {
    let days: [ComplicationInfo.DayState]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.prefix(7).enumerated()), id: \.offset) { n, d in
                ZStack {
                    Circle().fill(fill(d))
                    if d == .today || d == .restToday { Circle().strokeBorder(MW.lime, lineWidth: 2) }
                    Text(d == .done ? "✓" : WeekdayName.letters[n])
                        .font(MW.label(10))
                        .foregroundStyle(d == .done || d == .today ? Color.black : .white)
                }
                .frame(width: 19, height: 19)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
        .widgetAccentable()
    }

    private func fill(_ d: ComplicationInfo.DayState) -> Color {
        switch d {
        case .done: MW.lime
        case .today: .white
        case .planned: .white.opacity(0.45)
        case .missed: MW.color(0xFF3D5A).opacity(0.7)
        case .rest, .restToday: .white.opacity(0.12)
        }
    }
}
