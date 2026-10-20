import AppIntents
import SwiftUI
import WidgetKit

// Water widget (#520, design B): today's glasses against Fuel's target and a +1 glass button that counts without
// opening the app (`AddWaterIntent`). Home Screen and Lock Screen.

struct WaterEntry: TimelineEntry {
    var date: Date
    var glasses: Int
    var target: Int
    var ml: Int
    /// Nothing from the app yet (signed out or Fuel never opened).
    var empty: Bool

    var progress: Double { target > 0 ? min(1, Double(glasses) / Double(target)) : 0 }
    var done: Bool { target > 0 && glasses >= target }

    static let sample = WaterEntry(date: Date(), glasses: 6, target: 12, ml: 250, empty: false)
}

struct WaterProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (WaterEntry) -> Void) {
        completion(entry(Date(), preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WaterEntry>) -> Void) {
        // Midnight starts a new day at 0; the app reloads on every counted glass.
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        completion(Timeline(entries: [entry(now, preview: false), entry(midnight, preview: false)], policy: .atEnd))
    }

    private func entry(_ date: Date, preview: Bool) -> WaterEntry {
        guard let snap = HomeWidgetStore.load(), snap.signedIn, let fuel = snap.fuel else {
            return preview ? .sample : WaterEntry(date: date, glasses: 0, target: 0, ml: 250, empty: true)
        }
        return WaterEntry(date: date, glasses: fuel.glassesToday(date) + WaterQueue.pending(on: date),
                          target: fuel.glassesTarget, ml: fuel.glassMl ?? 250, empty: false)
    }
}

struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WaterQueue.kind, provider: WaterProvider()) { WaterWidgetView(entry: $0) }
            .configurationDisplayName("Water")
            .description("Today's glasses. Tap +1 to count one without opening the app.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

private let waterTop = Color(red: 0.18, green: 0.77, blue: 1.0)
private let waterBottom = Color(red: 0.18, green: 0.42, blue: 1.0)
private let waterDone = Color(red: 0.24, green: 1.0, blue: 0.69)

struct WaterWidgetView: View {
    let entry: WaterEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
        .widgetURL(HomeWidgetLink.tab("fuel"))
    }

    private var plus: some View {
        Button(intent: AddWaterIntent()) {
            Label("+1 glass", systemImage: "plus")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(entry.empty)
    }

    private var count: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(entry.glasses)").font(.system(size: 40, weight: .black, design: .rounded))
            Text("/\(entry.target)").font(.system(size: 18, weight: .heavy, design: .rounded)).opacity(0.75)
        }
        .monospacedDigit()
        .contentTransition(.numericText())
    }

    private var tile: some View {
        Image(systemName: entry.done ? "checkmark" : "drop.fill")
            .font(.system(size: 16, weight: .heavy))
            .frame(width: 32, height: 32)
            .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var caption: String {
        if entry.empty { return "Open Fuel to start" }
        if entry.done { return "Target hit 💧" }
        return "\(entry.target - entry.glasses) to go · \(entry.ml) ml"
    }

    private var bar: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.25))
                RoundedRectangle(cornerRadius: 3).fill(entry.done ? waterDone : .white).frame(width: g.size.width * entry.progress)
            }
        }
        .frame(height: 6)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                tile
                Spacer()
                count
            }
            Text("WATER").font(.system(size: 11, weight: .heavy, design: .rounded)).opacity(0.85)
            bar
            Spacer(minLength: 0)
            plus
        }
        .foregroundStyle(.white)
        .containerBackground(LinearGradient(colors: [waterTop, waterBottom], startPoint: .topLeading, endPoint: .bottomTrailing), for: .widget)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    tile
                    Text("WATER TODAY").font(.system(size: 12, weight: .heavy, design: .rounded)).opacity(0.85)
                }
                count
                Text(caption).font(.system(size: 12, weight: .bold, design: .rounded)).opacity(0.85)
                bar
            }
            plus
            .frame(width: 110)
        }
        .foregroundStyle(.white)
        .containerBackground(LinearGradient(colors: [waterTop, waterBottom], startPoint: .topLeading, endPoint: .bottomTrailing), for: .widget)
    }

    private var circular: some View {
        Button(intent: AddWaterIntent()) {
            Gauge(value: entry.progress) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text("\(entry.glasses)").font(.system(size: 18, weight: .black, design: .rounded))
            }
            .gaugeStyle(.accessoryCircular)
        }
        .buttonStyle(.plain)
        .containerBackground(.clear, for: .widget)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("💧 WATER").font(.system(size: 11, weight: .heavy, design: .rounded))
                Text("\(entry.glasses)/\(entry.target) glasses").font(.system(size: 15, weight: .black, design: .rounded))
                Gauge(value: entry.progress) { EmptyView() }.gaugeStyle(.accessoryLinear)
            }
            Button(intent: AddWaterIntent()) {
                Image(systemName: "plus").font(.system(size: 16, weight: .heavy))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .containerBackground(.clear, for: .widget)
    }
}
