import SwiftUI
import WorkoutEngine

/// Progress parts (#243): each has a board tile (#444) and its own page.
enum ProgressSection: String, CaseIterable, Identifiable, Hashable {
    case training, programmes, body, records, badges, muscles, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .training: "Training"
        case .programmes: "Programmes"
        case .body: "Body"
        case .records: "Records"
        case .badges: "Badges"
        case .muscles: "Muscles"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .training: "dumbbell.fill"
        case .programmes: "flag.checkered"
        case .body: "ruler.fill"
        case .records: "trophy.fill"
        case .badges: "medal.fill"
        case .muscles: "figure.strengthtraining.traditional"
        case .history: "clock.arrow.circlepath"
        }
    }

    var colors: [Color] {
        switch self {
        case .training: [Color(red: 1, green: 0.18, blue: 0.33), Color(red: 1, green: 0.44, blue: 0.71)]
        case .programmes: WorkoutEngine.Category.power.colors
        case .body: WorkoutEngine.Category.strength.colors
        case .records: [Color(red: 1, green: 0.72, blue: 0), Color(red: 1, green: 0.37, blue: 0.23)]
        case .badges: [Theme.lime, Color(red: 0.12, green: 0.85, blue: 0.54)]
        case .muscles: WorkoutEngine.Category.cardio.colors
        case .history: [Color(red: 1, green: 0.55, blue: 0.1), Color(red: 1, green: 0.18, blue: 0.47)]
        }
    }

    /// Dark text on the light cards (gold, lime).
    var ink: Color { self == .records || self == .badges ? Theme.ink : .white }
}

/// What the top tiles show, computed once per render by `ProgressTabView`.
struct ProgressHighlights {
    struct Measure {
        let metric: BodyMetric
        let value: Double
        let change: Double?
    }

    struct Record: Identifiable {
        let name: String
        let value: String
        let unit: String
        let date: Date
        var id: String { name }
    }

    /// Every metric with at least one value, biggest relative change first (girths and body fat before weight).
    var measures: [Measure]
    var records: [Record]
    var unlocked: Int
    var badgeCount: Int
    var nextBadge: Badge?
    var vo2: Measure?
    var weight: Measure?
    var workouts: Int
    var thisWeek: Int
    var target: Int
    var lastWorkout: Date?
    /// Most worked muscle in the last 28 days; nil when nothing logged or the heat map is Pro-locked.
    var topMuscle: String?
    var musclesLocked: Bool
    /// Running programme (#255): name and "Week 3 of 8" / "Paused"; nil when none.
    var programme: (name: String, state: String)?
    var programmesFinished: Int

    /// The measurement the body card features: biggest change among girths and body fat, else any.
    var featured: Measure? {
        measures.first { $0.metric != .weight && $0.metric != .leanMass } ?? measures.first
    }
}

extension BodyMetric {
    func format(_ v: Double) -> String {
        "\(Format.kg((v * 10).rounded() / 10)) \(unit)"
    }

    func formatChange(_ d: Double) -> String {
        let r = (abs(d) * 10).rounded() / 10
        return r == 0 ? "No change" : "\(d < 0 ? "▼" : "▲") \(Format.kg(r)) \(unit)"
    }
}

// MARK: - Section tile

/// A Progress part as a bold tile with its key number (board widget, #444); tap opens its page.
struct ProgressSectionTile: View {
    let h: ProgressHighlights
    let section: ProgressSection

    var body: some View {
        HubTile(symbol: section.symbol, colors: section.colors, label: section.title, ink: section.ink) {
            content(section)
        } corner: {
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy)).foregroundStyle(section.ink).opacity(0.7)
        }
    }

    @ViewBuilder
    private func content(_ s: ProgressSection) -> some View {
        switch s {
        case .training:
            HubValue("\(h.thisWeek)/\(h.target)")
            HubNote("sessions this week")
        case .body:
            if let m = h.weight ?? h.featured {
                HubValue(m.metric.format(m.value))
                HubNote(m.change.map(m.metric.formatChange) ?? m.metric.label)
            } else {
                HubValue("Log")
                HubNote("Weight, girths, body fat")
            }
        case .records:
            if let r = h.records.first {
                HubValue(h.records.count == 1 ? "1 PR" : "\(h.records.count) PRs")
                HubNote("\(r.name) \(r.value) \(r.unit)")
            } else {
                HubValue("No PRs")
                HubNote("Log weights or attempt a PR")
            }
        case .badges:
            HubValue("\(h.unlocked)/\(h.badgeCount)")
            HubNote(h.nextBadge.map { "Next: \($0.title)" } ?? "All unlocked")
        case .muscles:
            if h.musclesLocked {
                HubValue("Pro")
                HubNote("Muscle heat map")
            } else if let m = h.topMuscle {
                HubValue(m)
                HubNote("most worked · 28 days")
            } else {
                HubValue("Heat map")
                HubNote("Fills as you train")
            }
        case .programmes:
            if let p = h.programme {
                HubValue(p.name)
                HubNote(p.state)
            } else {
                HubValue(h.programmesFinished > 0 ? "\(h.programmesFinished) done" : "Start one")
                HubNote("Multi-week plans toward a goal")
            }
        case .history:
            HubValue("\(h.workouts)")
            HubNote(h.lastWorkout.map { "Last: \($0.formatted(.relative(presentation: .named)))" } ?? "Sessions show here")
        }
    }
}

/// Bold header opening each section: colour icon tile + title.
struct ProgressSectionHeader: View {
    let section: ProgressSection
    var trailing: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(section.ink)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: section.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
            Text(section.title).font(Theme.display(24))
            Spacer(minLength: 0)
            if let trailing { Text(trailing).font(Theme.label(12)).foregroundStyle(Theme.muted) }
        }
        .padding(.top, 10)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Slim lime streak row (was the big hero): streak, best, this week vs goal.
struct StreakRow: View {
    let current: Int
    let best: Int
    let thisWeek: Int
    let target: Int
    let fresh: Bool
    /// Streak shields held (#501).
    var shields = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: fresh ? "sparkles" : "flame.fill")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.ink.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(fresh ? "Day one" : "\(current) wk streak").font(Theme.display(22)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(caption).font(.caption.weight(.semibold)).opacity(0.75).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            // This week as a segmented bar (#541), one segment per planned session.
            VStack(alignment: .trailing, spacing: 5) {
                Text("\(thisWeek)/\(target)").font(Theme.display(17)).monospacedDigit()
                ProgressBar(progress: Double(thisWeek) / Double(max(1, target)), height: 6, segments: min(max(1, target), 7),
                            fill: Theme.ink, track: Theme.ink.opacity(0.18))
                    .frame(width: 56)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(thisWeek) of \(target) sessions this week")
        }
        .foregroundStyle(Theme.ink)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(ProgressStyle.hero))
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        if fresh { return "Your streak starts with session one · goal \(target) a week" }
        let left = max(0, target - thisWeek)
        return "Best \(best) wk · " + (shields > 0 ? "🛡 \(shields) · " : "") + (left == 0 ? "Week goal hit" : "\(left) more this week")
    }
}

/// Gradient hub tile: icon tile, big value, uppercase label, one or two notes.
struct HubTile<Content: View, Corner: View>: View {
    let symbol: String
    let colors: [Color]
    let label: String
    var ink: Color = .white
    let content: Content
    let corner: Corner

    init(symbol: String, colors: [Color], label: String, ink: Color = .white,
         @ViewBuilder content: () -> Content, @ViewBuilder corner: () -> Corner = { EmptyView() }) {
        self.symbol = symbol
        self.colors = colors
        self.label = label
        self.ink = ink
        self.content = content()
        self.corner = corner()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.22)))
                .padding(.bottom, 4)
            content
            Spacer(minLength: 0)
            Text(label).font(Theme.label(11)).tracking(1).textCase(.uppercase).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(alignment: .topTrailing) { corner.padding(12) }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

private struct HubValue: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Theme.display(26)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
    }
}

private struct HubNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).opacity(0.9).lineLimit(2).multilineTextAlignment(.leading)
    }
}

