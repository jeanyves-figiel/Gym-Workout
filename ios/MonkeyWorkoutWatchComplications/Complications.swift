import SwiftUI
import WidgetKit

/// Watch face complications (#190): next workout, weekly goal and streak, in every accessory family.
/// Data comes from the snapshot the Watch app shares in the App Group; tapping opens the Watch app.
@main
struct MonkeyWorkoutComplications: WidgetBundle {
    var body: some Widget {
        NextWorkoutWidget()
        WeekGoalWidget()
        StreakWidget()
    }
}

struct MWEntry: TimelineEntry {
    var date: Date
    /// nil = not synced from the iPhone yet.
    var info: ComplicationInfo?
}

struct MWProvider: TimelineProvider {
    func placeholder(in context: Context) -> MWEntry { MWEntry(date: Date(), info: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (MWEntry) -> Void) {
        let now = Date()
        completion(MWEntry(date: now, info: ComplicationInfo(SharedSnapshot.load(), at: now) ?? (context.isPreview ? .sample : nil)))
    }

    /// Now, then each of the next midnights so "today", rest days and the Monday week reset change on time.
    /// The Watch app reloads the timelines whenever a new snapshot arrives from the iPhone.
    func getTimeline(in context: Context, completion: @escaping (Timeline<MWEntry>) -> Void) {
        let snap = SharedSnapshot.load()
        let now = Date()
        let cal = Calendar.current
        var dates = [now]
        var d = cal.startOfDay(for: now)
        for _ in 0..<3 {
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d.addingTimeInterval(86_400)
            dates.append(d)
        }
        completion(Timeline(entries: dates.map { MWEntry(date: $0, info: ComplicationInfo(snap, at: $0)) }, policy: .atEnd))
    }
}

// MARK: Next workout

struct NextWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextWorkout", provider: MWProvider()) { NextWorkoutView(entry: $0) }
            .configurationDisplayName("Next workout")
            .description("Today's workout or the next one, its length and your week.")
            .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct NextWorkoutView: View {
    let entry: MWEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var stack

    var body: some View {
        content.containerBackground(for: .widget) {
            if let i = entry.info { MW.gradient(i.tint, i.tint2) } else { MW.gradient(0x2B2E33, 0x15171A) }
        }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        default: rectangular
        }
    }

    private var symbol: String {
        entry.info?.day == .weekDone ? "trophy.fill" : entry.info?.day == .rest ? "bed.double.fill" : "figure.strengthtraining.traditional"
    }

    private var inline: some View {
        Group {
            if let i = entry.info {
                switch i.day {
                case .weekDone: Label("Week done \(i.done)/\(i.target) · 🔥\(i.streak)w", systemImage: symbol)
                case .rest: Label("Rest · \(i.dayLabel) \(i.title)", systemImage: symbol)
                default: Label("\(i.title) · \(i.minutes) min · \(i.done)/\(i.target)", systemImage: symbol)
                }
            } else {
                Label("MonkeyWorkout", systemImage: symbol)
            }
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(MW.lime).widgetAccentable()
                Text(circularValue).font(MW.label(13)).minimumScaleFactor(0.6)
            }
        }
    }

    private var circularValue: String {
        guard let i = entry.info else { return "Sync" }
        switch i.day {
        case .weekDone: return "\(i.done)/\(i.target)"
        case .rest: return i.dayLabel
        default: return "\(i.minutes)m"
        }
    }

    private var corner: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(MW.lime)
            .widgetAccentable()
            .widgetLabel {
                if let i = entry.info {
                    Text(i.day == .weekDone ? "WEEK DONE" : "\(i.title) \(i.minutes)m".uppercased()).foregroundStyle(MW.lime)
                } else {
                    Text("MONKEYWORKOUT")
                }
            }
    }

    private var rectangular: some View {
        HStack(spacing: 6) {
            if !stack, let i = entry.info {
                Capsule().fill(MW.gradient(i.tint, i.tint2)).frame(width: 4).widgetAccentable()
            }
            VStack(alignment: .leading, spacing: 1) {
                if let i = entry.info {
                    Text(i.eyebrow).font(MW.label(11)).tracking(0.6)
                        .foregroundStyle(stack ? Color.white.opacity(0.85) : (i.day == .weekDone ? MW.mint : MW.lime))
                        .widgetAccentable()
                    Text(i.day == .weekDone ? "\(i.done)/\(i.target) done 🏆" : i.title)
                        .font(MW.display(19)).lineLimit(1).minimumScaleFactor(0.6)
                    if i.day == .weekDone {
                        Text("🔥 \(i.streak) week streak").font(MW.label(13)).foregroundStyle(.secondary)
                    } else if stack {
                        Text("\(i.minutes) min\(i.readiness.map { " · \($0)" } ?? "")").font(MW.label(13)).lineLimit(1)
                        ProgressView(value: i.progress).tint(MW.lime)
                    } else {
                        Text("\(i.minutes) min · \(i.exercises) exercises · \(i.done)/\(i.target)")
                            .font(MW.label(13)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                } else {
                    Text("MONKEYWORKOUT").font(MW.label(11)).foregroundStyle(MW.lime).widgetAccentable()
                    Text("Open on iPhone").font(MW.display(18))
                    Text("to sync your plan").font(MW.label(13)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: Weekly goal

struct WeekGoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekGoal", provider: MWProvider()) { WeekGoalView(entry: $0) }
            .configurationDisplayName("Weekly goal")
            .description("Sessions done this week against your target.")
            .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular])
    }
}

struct WeekGoalView: View {
    let entry: MWEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var stack

    private var done: Int { entry.info?.done ?? 0 }
    private var target: Int { max(1, entry.info?.target ?? 3) }
    private var complete: Bool { done >= target }
    private var ring: Gradient { complete ? Gradient(colors: [MW.mint, MW.color(0x1E9BFF)]) : Gradient(colors: [MW.lime, MW.color(0x7FD320)]) }

    var body: some View {
        content.containerBackground(for: .widget) { MW.gradient(0xFF7A3D, 0xFF3D5A) }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(min(done, target)), in: 0...Double(target)) {
                Image(systemName: "dumbbell.fill")
            } currentValueLabel: {
                Text(complete ? "✓" : "\(done)/\(target)").font(MW.display(16))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(ring)
            .widgetAccentable()
        case .accessoryCorner:
            Text("\(done)/\(target)")
                .font(MW.display(18))
                .foregroundStyle(complete ? MW.mint : MW.lime)
                .widgetAccentable()
                .widgetLabel {
                    Gauge(value: Double(min(done, target)), in: 0...Double(target)) {
                        Text("Week")
                    } currentValueLabel: {
                        Text("\(done)")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("\(target)")
                    }
                    .tint(ring)
                }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text(complete ? "WEEK COMPLETE" : "THIS WEEK").font(MW.label(11)).tracking(0.6)
                    .foregroundStyle(stack ? Color.white.opacity(0.85) : (complete ? MW.mint : MW.lime))
                    .widgetAccentable()
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(done)/\(target)").font(MW.display(24))
                    Text("sessions").font(MW.label(13)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let s = entry.info?.streak, s > 0 { Text("🔥\(s)w").font(MW.label(14)) }
                }
                Gauge(value: Double(min(done, target)), in: 0...Double(target)) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(stack ? Gradient(colors: [.white]) : ring)
                    .widgetAccentable()
            }
        }
    }
}

// MARK: Streak

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Streak", provider: MWProvider()) { StreakView(entry: $0) }
            .configurationDisplayName("Streak")
            .description("Weeks in a row you hit your training goal.")
            .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct StreakView: View {
    let entry: MWEntry
    @Environment(\.widgetFamily) private var family

    private var streak: Int { entry.info?.streak ?? 0 }

    var body: some View {
        content.containerBackground(for: .widget) { MW.gradient(0xFFC23D, 0xFF7A3D) }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            Label("\(streak)-week streak · best \(entry.info?.bestStreak ?? 0)", systemImage: "flame.fill")
        case .accessoryCorner:
            Image(systemName: "flame.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [MW.flame, MW.flame2], startPoint: .top, endPoint: .bottom))
                .widgetAccentable()
                .widgetLabel { Text("\(streak) WEEK STREAK").foregroundStyle(MW.flame) }
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -1) {
                    Image(systemName: "flame.fill").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [MW.flame, MW.flame2], startPoint: .top, endPoint: .bottom))
                        .widgetAccentable()
                    Text("\(streak)w").font(MW.display(17)).minimumScaleFactor(0.6)
                }
            }
        }
    }
}
