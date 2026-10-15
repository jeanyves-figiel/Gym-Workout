import AppIntents
import SwiftUI
import WidgetKit

// Home Screen and Lock Screen widgets (#297). The app writes `HomeWidgetSnapshot` to the App Group and picks the
// default look and topic per size (Account → Home Screen widgets); Edit Widget can override both per widget.

enum TopicChoice: String, AppEnum, CaseIterable {
    case account, nextUp, week, streak, readiness, level, records, lastWorkout, volume, climbing, dashboard

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Show" }
    static var caseDisplayRepresentations: [TopicChoice: DisplayRepresentation] {
        [.account: "As set in Account", .nextUp: "Next up", .week: "This week", .streak: "Streak", .readiness: "Readiness",
         .level: "Level + XP", .records: "Top lifts", .lastWorkout: "Last workout", .volume: "Volume", .climbing: "Climbing",
         .dashboard: "Week dashboard (large)"]
    }

    var topic: HomeWidgetTopic? { HomeWidgetTopic(rawValue: rawValue) }
}

enum LookChoice: String, AppEnum, CaseIterable {
    case account, gradient, coach, data

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Look" }
    static var caseDisplayRepresentations: [LookChoice: DisplayRepresentation] {
        [.account: "As set in Account", .gradient: "Gradient cards", .coach: "Monkey coach", .data: "Data tiles"]
    }

    var look: HomeWidgetLook? { HomeWidgetLook(rawValue: rawValue) }
}

struct HomeWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "MonkeyWorkout" }
    static var description: IntentDescription { "Pick what this widget shows, or follow Account → Home Screen widgets." }

    @Parameter(title: "Show", default: .account)
    var topic: TopicChoice

    @Parameter(title: "Look", default: .account)
    var look: LookChoice

    init() {}
}

struct HomeEntry: TimelineEntry {
    var date: Date
    var snap: HomeWidgetSnapshot
    var topic: TopicChoice
    var look: LookChoice
}

struct HomeProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HomeEntry {
        HomeEntry(date: Date(), snap: .sample, topic: .account, look: .account)
    }

    func snapshot(for configuration: HomeWidgetIntent, in context: Context) async -> HomeEntry {
        // The widget gallery shows sample numbers until the app has written real ones.
        let snap = HomeWidgetStore.load().flatMap { $0.signedIn ? $0 : nil } ?? (context.isPreview ? .sample : HomeWidgetSnapshot())
        return HomeEntry(date: Date(), snap: snap, topic: configuration.topic, look: configuration.look)
    }

    /// Now, then each midnight for two days (Today moves); the app reloads the timeline whenever its data changes.
    func timeline(for configuration: HomeWidgetIntent, in context: Context) async -> Timeline<HomeEntry> {
        let snap = HomeWidgetStore.load() ?? HomeWidgetSnapshot()
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let dates = [Date()] + (1...2).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        return Timeline(entries: dates.map { HomeEntry(date: $0, snap: snap, topic: configuration.topic, look: configuration.look) }, policy: .atEnd)
    }
}

struct HomeWidgetEntryView: View {
    let entry: HomeEntry
    @Environment(\.widgetFamily) private var family

    private var settings: HomeWidgetSettings { entry.snap.settings }
    private var look: HomeWidgetLook { entry.look.look ?? settings.look }

    private var size: HomeWidgetSize {
        switch family {
        case .systemSmall: .small
        case .systemMedium: .medium
        case .systemLarge, .systemExtraLarge: .large
        default: .lock
        }
    }

    private var topic: HomeWidgetTopic {
        let t = entry.topic.topic ?? settings.topic(size)
        // The dashboard needs the large size; smaller widgets show this week instead.
        return t == .dashboard && size != .large ? .week : t
    }

    var body: some View {
        Group {
            if !entry.snap.signedIn {
                signedOut
            } else {
                switch family {
                case .accessoryCircular: HomeLockFace(topic: topic, family: .circular, snap: entry.snap, now: entry.date)
                case .accessoryRectangular: HomeLockFace(topic: topic, family: .rectangular, snap: entry.snap, now: entry.date)
                case .accessoryInline: HomeLockFace(topic: topic, family: .inline, snap: entry.snap, now: entry.date)
                default: HomeWidgetFace(topic: topic, look: look, size: size, snap: entry.snap, now: entry.date)
                }
            }
        }
        .containerBackground(for: .widget) {
            if size == .lock { Color.clear } else { HomeWidgetBackground(topic: topic, look: look) }
        }
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "dumbbell.fill").font(.system(size: 18, weight: .bold))
            if size != .lock {
                Spacer(minLength: 0)
                Text("MonkeyWorkout").font(.system(size: 15, weight: .black, design: .rounded))
            }
            Text("Open the app to set up your week").font(.system(size: 11, weight: .heavy, design: .rounded)).opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(HomeWidgetLink.tab("train"))
    }
}

struct HomeScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: HomeWidgetStore.kind, intent: HomeWidgetIntent.self, provider: HomeProvider()) {
            HomeWidgetEntryView(entry: $0)
        }
        .configurationDisplayName("MonkeyWorkout")
        .description("Next up, your week, streak, level and more. Set the look in Account → Home Screen widgets.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
