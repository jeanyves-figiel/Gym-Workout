import AppIntents
import CoreLocation
import SwiftUI
import WidgetKit

// MARK: - Smart Stack relevance (#612, designs A + B + C from `apple-tech-radar/batch3.html`)
//
// The Watch shows the right MonkeyFit card at the right moment, no scrolling:
// A gym time: Next up 30′ before the usual training time on a training day, and at the home gym.
// B rest-day morning: easy day + water pace. C after a workout: recap + protein for the next hour.
// Each moment is its own Smart Stack card (recommendations); relevance comes from entry scores and relevant intents
// (date windows, gym region) refreshed with every timeline, i.e. every snapshot from the iPhone.

enum SmartMoment: String, AppEnum, CaseIterable {
    case gym, restDay, afterWorkout

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Moment" }
    static var caseDisplayRepresentations: [SmartMoment: DisplayRepresentation] {
        [.gym: "Gym time", .restDay: "Rest day", .afterWorkout: "After workout"]
    }

    /// Plain literals only (interpolated Text traps in WidgetKit).
    var recommendation: Text {
        switch self {
        case .gym: Text("Smart Stack: Gym time")
        case .restDay: Text("Smart Stack: Rest day")
        case .afterWorkout: Text("Smart Stack: After workout")
        }
    }
}

struct SmartMomentIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Smart Stack moment" }
    static var description: IntentDescription { "MonkeyWorkout card that rises when it matters." }

    @Parameter(title: "Moment", default: .gym)
    var moment: SmartMoment

    init() {}
    init(_ moment: SmartMoment) { self.moment = moment }
}

/// When each moment matters, from the snapshot.
enum SmartStackTimes {
    static let kind = "SmartStack"
    static let protein = 30

    /// Usual start time today: mean minute of day of the recent workouts; nil without any.
    static func usualStart(_ snap: WatchSnapshot, on day: Date, cal: Calendar = .current) -> Date? {
        let minutes = snap.progress.recent.map { cal.component(.hour, from: $0.date) * 60 + cal.component(.minute, from: $0.date) }
        guard !minutes.isEmpty else { return nil }
        let mean = minutes.reduce(0, +) / minutes.count
        return cal.date(byAdding: .minute, value: mean, to: cal.startOfDay(for: day))
    }

    /// A: from 30′ before the usual time to an hour after, on a day with a session today.
    static func gymWindow(_ snap: WatchSnapshot, at now: Date) -> DateInterval? {
        guard ComplicationInfo(snap, at: now)?.day == .today, let start = usualStart(snap, on: now) else { return nil }
        let w = DateInterval(start: start.addingTimeInterval(-30 * 60), end: start.addingTimeInterval(60 * 60))
        return w.end > now ? w : nil
    }

    /// B: 7:00–10:00 on today's or tomorrow's rest day, whichever comes first.
    static func restWindow(_ snap: WatchSnapshot, at now: Date, cal: Calendar = .current) -> DateInterval? {
        for offset in 0...1 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)),
                  let from = cal.date(bySettingHour: 7, minute: 0, second: 0, of: day),
                  let to = cal.date(bySettingHour: 10, minute: 0, second: 0, of: day), to > now else { continue }
            let d = ComplicationInfo(snap, at: from)?.day
            if d == .rest || d == .weekDone { return DateInterval(start: from, end: to) }
        }
        return nil
    }

    /// C: the hour after the last workout ended.
    static func afterWindow(_ snap: WatchSnapshot, at now: Date) -> DateInterval? {
        guard let last = snap.progress.recent.first else { return nil }
        let end = last.date.addingTimeInterval(TimeInterval(max(1, last.minutes) * 60))
        let w = DateInterval(start: end, end: end.addingTimeInterval(60 * 60))
        return w.end > now ? w : nil
    }

    static func window(_ m: SmartMoment, _ snap: WatchSnapshot, at now: Date) -> DateInterval? {
        switch m {
        case .gym: gymWindow(snap, at: now)
        case .restDay: restWindow(snap, at: now)
        case .afterWorkout: afterWindow(snap, at: now)
        }
    }

    /// Tells the Smart Stack when each moment matters: date windows, and the home gym's region for A.
    static func updateRelevantIntents(_ snap: WatchSnapshot?, now: Date = Date()) async {
        guard let snap else { return }
        var out: [RelevantIntent] = []
        for m in SmartMoment.allCases {
            if let w = window(m, snap, at: now) {
                out.append(RelevantIntent(SmartMomentIntent(m), widgetKind: kind, relevance: .date(from: w.start, to: w.end)))
            }
        }
        if let g = snap.gym {
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: g.latitude, longitude: g.longitude),
                                          radius: 150, identifier: "monkeyworkout.gym")
            out.append(RelevantIntent(SmartMomentIntent(.gym), widgetKind: kind, relevance: .location(region)))
        }
        try? await RelevantIntentManager.shared.updateRelevantIntents(out)
    }
}

struct SmartEntry: TimelineEntry {
    var date: Date
    var moment: SmartMoment
    var info: ComplicationInfo?
    var snap: WatchSnapshot?
    var relevance: TimelineEntryRelevance?
}

struct SmartProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SmartEntry { SmartEntry(date: Date(), moment: .gym, info: .sample) }

    func snapshot(for configuration: SmartMomentIntent, in context: Context) async -> SmartEntry {
        let snap = SharedSnapshot.load()
        let now = Date()
        return SmartEntry(date: now, moment: configuration.moment, info: ComplicationInfo(snap, at: now) ?? .sample, snap: snap)
    }

    func timeline(for configuration: SmartMomentIntent, in context: Context) async -> Timeline<SmartEntry> {
        let snap = SharedSnapshot.load()
        await SmartStackTimes.updateRelevantIntents(snap)
        let now = Date()
        let m = configuration.moment
        // Every hour for a day, plus the window's edges: the score is high inside the window only.
        var dates = MWTimeline.entries(preview: false).map(\.date)
        if let snap, let w = SmartStackTimes.window(m, snap, at: now) { dates += [w.start, w.end].filter { $0 > now } }
        let entries = Set(dates).sorted().map { d -> SmartEntry in
            let w = snap.flatMap { SmartStackTimes.window(m, $0, at: d) }
            let inside = w.map { $0.contains(d) } ?? false
            let left = inside ? (w?.end.timeIntervalSince(d) ?? 0) : 0
            return SmartEntry(date: d, moment: m, info: ComplicationInfo(snap, at: d), snap: snap,
                              relevance: TimelineEntryRelevance(score: inside ? 100 : 0, duration: left))
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    func recommendations() -> [AppIntentRecommendation<SmartMomentIntent>] {
        SmartMoment.allCases.map { AppIntentRecommendation(intent: SmartMomentIntent($0), description: $0.recommendation) }
    }
}

/// Smart Stack card: eyebrow, big line, one detail line on the moment's gradient.
struct SmartStackView: View {
    let entry: SmartEntry

    private var tint: (UInt32, UInt32) {
        switch entry.moment {
        case .gym: (entry.info?.tint ?? 0x2F6BFF, entry.info?.tint2 ?? 0x8A4DFF)
        case .restDay: (0x0F9D6A, 0x2F9BFF)
        case .afterWorkout: (0xFF8A00, 0xFF3D7B)
        }
    }

    private var lines: (eyebrow: String, title: String, detail: String) {
        let info = entry.info
        switch entry.moment {
        case .gym:
            let at = entry.snap?.gym.map { "📍 \($0.name.uppercased())" } ?? "GYM TIME"
            guard let info, info.day == .today else { return (at, info?.title ?? "No workout today", info?.eyebrow ?? "") }
            return ("\(at) · NOW", info.title, "\(info.minutes)′ · \(info.exercises) moves · ▶ Start")
        case .restDay:
            let water = info?.water.map { "💧 \($0.glasses) of \($0.target)" } ?? "💧 Drink up"
            return ("REST DAY", "Move easy, recover", "\(water) · next \(info?.dayLabel ?? "")")
        case .afterWorkout:
            guard let last = info?.last else { return ("DONE", "Nice work", "🍗 Protein soon") }
            return ("DONE · \(last.title.uppercased())", "\(last.minutes)′ · \(last.sets) sets",
                    "🍗 \(SmartStackTimes.protein) g protein soon")
        }
    }

    var body: some View {
        let l = lines
        VStack(alignment: .leading, spacing: 1) {
            Text(l.eyebrow).font(MW.label(10)).lineLimit(1).minimumScaleFactor(0.7).opacity(0.9)
            Text(l.title).font(MW.display(17)).lineLimit(1).minimumScaleFactor(0.6)
            Text(l.detail).font(MW.label(11)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { MW.gradient(tint.0, tint.1) }
    }
}

struct SmartStackWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SmartStackTimes.kind, intent: SmartMomentIntent.self, provider: SmartProvider()) {
            SmartStackView(entry: $0)
        }
        .configurationDisplayName("Smart Stack")
        .description("Gym time, rest day and after-workout cards that rise when they matter.")
        .supportedFamilies([.accessoryRectangular])
    }
}
