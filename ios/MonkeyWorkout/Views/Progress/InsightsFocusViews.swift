import SwiftUI
import WorkoutEngine

// Insights focus (#939, design A + C from `insights-focus/`): A the full-screen grid on the first open of Insights,
// C the hero card on top of the board with a Switch sheet. A bit of everything shows a slim chip instead of the hero.

extension InsightsFocus {
    var symbol: String {
        switch self {
        case .strength: "figure.strengthtraining.traditional"
        case .muscle: "dumbbell.fill"
        case .weightLoss: "scalemass.fill"
        case .endurance: "heart.fill"
        case .mind: "brain.head.profile"
        case .sport: "figure.climbing"
        case .everything: "square.grid.2x2.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .strength: [Color(hex: 0xFF2E54), Color(hex: 0xFF70B5)]
        case .muscle: [Color(hex: 0xFF8C1A), Color(hex: 0xFF2E78)]
        case .weightLoss: [Color(hex: 0x12D98A), Color(hex: 0x0AA6C9)]
        case .endurance: [Color(hex: 0x1E7BFF), Color(hex: 0x00C8FF)]
        case .mind: [Color(hex: 0x3B3F8F), Color(hex: 0x7A2CFF)]
        case .sport: [Color(hex: 0xFFB800), Color(hex: 0xFF5E3A)]
        case .everything: [Color(hex: 0x44444C), Color(hex: 0x77777F)]
        }
    }

    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }

    /// Dark text on the gold card.
    var ink: Color { self == .sport ? Theme.ink : .white }

    /// The Insights part the hero card opens; sport opens History filtered to the sport.
    var section: ProgressSection? {
        switch self {
        case .strength: .records
        case .muscle: .muscles
        case .weightLoss: .body
        case .endurance: .training
        case .mind: .mind
        case .sport, .everything: nil
        }
    }
}

/// A: "What matters most to you?" on the first open of Insights, the plan goal's focus picked.
struct InsightsFocusPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var picked: InsightsFocus?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let suggested = model.suggestedInsightsFocus
        let current = picked ?? suggested
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What matters most to you?").font(Theme.display(30))
                        Text("Insights puts it first. Everything else stays below, change it any time.")
                            .font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
                    }
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(InsightsFocus.allCases.filter { $0 != .everything }) { f in
                            tile(f, selected: current == f, goal: f == suggested)
                        }
                    }
                    Button { pick(current) } label: {
                        Text("Show my Insights")
                            .font(Theme.label(17)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                    Button { pick(.everything) } label: {
                        Text(InsightsFocus.everything.title)
                            .font(Theme.label(15)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            // Closing keeps the suggestion, so the picker never comes back on its own.
            .toolbar { CloseToolbarItem { pick(suggested) } }
        }
    }

    private func tile(_ f: InsightsFocus, selected: Bool, goal: Bool) -> some View {
        Button { withAnimation(.snappy) { picked = f } } label: {
            VStack(alignment: .leading, spacing: 6) {
                IconTile(symbol: f.symbol, size: 38, ink: f.ink == Theme.ink)
                Spacer(minLength: 4)
                Text(f.title).font(Theme.label(17)).lineLimit(1).minimumScaleFactor(0.7)
                Text(f.detail).font(.caption.weight(.semibold)).opacity(0.85).lineLimit(2)
            }
            .foregroundStyle(f.ink)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(f.gradient))
            .overlay(alignment: .topTrailing) {
                if goal {
                    Text("YOUR GOAL").font(Theme.label(10)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.lime))
                        .padding(10)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.lime, lineWidth: selected ? 3 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(goal ? "Matches your plan goal" : "")
    }

    private func pick(_ f: InsightsFocus) {
        withAnimation(.snappy) { model.setInsightsFocus(f) }
        dismiss()
    }
}

/// C: Switch sheet, one gradient row per focus.
struct InsightsFocusSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let current = model.insightsFocus
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your focus").font(Theme.display(28))
                    Text("Insights opens on it. From your goal: \(model.suggestedInsightsFocus.title).")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
                        .padding(.bottom, 6)
                    ForEach(InsightsFocus.allCases) { f in
                        Button {
                            withAnimation(.snappy) { model.setInsightsFocus(f) }
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                IconTile(symbol: f.symbol, size: 38, ink: f.ink == Theme.ink)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.title).font(Theme.label(16))
                                    Text(f.detail).font(.caption.weight(.semibold)).opacity(0.85)
                                }
                                Spacer(minLength: 4)
                                if current == f { Image(systemName: "checkmark").font(.system(size: 15, weight: .heavy)) }
                            }
                            .foregroundStyle(f.ink)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(f.gradient))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Theme.lime, lineWidth: current == f ? 3 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(current == f ? .isSelected : [])
                    }
                    Text("A focus moves its widgets to the top. Nothing is removed: Edit Insights still adds and arranges every widget.")
                        .font(.footnote.weight(.medium)).foregroundStyle(Theme.muted)
                        .padding(.top, 6)
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar { CloseToolbarItem { dismiss() } }
        }
    }
}

/// C: the focus's key number on top of the board. Tap opens its part, Switch opens the sheet.
struct InsightsFocusHero: View {
    let focus: InsightsFocus
    let h: ProgressHighlights
    /// The first of the member's sports and its sessions, newest first (sport focus).
    let sport: Sport
    let sportItems: [HistoryItem]
    let onOpen: () -> Void
    let onSwitch: () -> Void

    private var value: (big: String, line: String) {
        switch focus {
        case .strength:
            guard let r = h.records.first else { return ("Lift", "Your best lifts show here after your first workout") }
            return (h.records.count == 1 ? "1 PR" : "\(h.records.count) PRs", "Best: \(r.name) \(r.value) \(r.unit)")
        case .muscle:
            return ("\(h.thisWeek)/\(h.target)", h.topMuscle.map { "Sessions this week · most worked: \($0)" } ?? "Sessions this week")
        case .weightLoss:
            guard let m = h.weight ?? h.featured else { return ("Log", "Weight, girths and body fat") }
            return (m.change.map(m.metric.formatChange) ?? m.metric.format(m.value), "\(m.metric.label.capitalized) now \(m.metric.format(m.value))")
        case .endurance:
            if let v = h.vo2 {
                return ("\(Int(v.value.rounded()))", "VO₂ max" + (v.change.map { $0 == 0 ? "" : " · \($0 > 0 ? "▲" : "▼") \(String(format: "%.1f", abs($0)))" } ?? ""))
            }
            return ("\(h.thisWeek)/\(h.target)", "Sessions this week")
        case .mind:
            return h.mind.map { ("\($0)", "Mind score today") } ?? ("Check in", "How do you feel? Your Mind score starts here")
        case .sport:
            let month = sportItems.filter { $0.start > Date().addingTimeInterval(-30 * 86_400) }
            let minutes = month.reduce(0) { $0 + $1.minutes }
            return ("\(month.count)", "\(sport.label) sessions in 30 days" + (minutes > 0 ? " · \(History.duration(minutes))" : ""))
        case .everything:
            return ("", "")
        }
    }

    var body: some View {
        let v = value
        // Not one big Button: Switch is a button of its own inside the card.
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text("YOUR FOCUS · \(focus.title.uppercased())").font(Theme.label(11)).opacity(0.85)
                Spacer(minLength: 8)
                Button(action: onSwitch) {
                    HStack(spacing: 4) {
                        Text("Switch")
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy))
                    }
                    .font(Theme.label(12))
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.22)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Switch focus")
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(v.big).font(Theme.display(44)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text(v.line).font(.footnote.weight(.semibold)).opacity(0.9).lineLimit(2)
                }
                Spacer(minLength: 8)
                IconTile(symbol: focus == .sport ? sport.symbol : focus.symbol, size: 52, ink: focus.ink == Theme.ink)
            }
        }
        .foregroundStyle(focus.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(focus.gradient))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open \(focus.title)", onOpen)
    }
}

/// A bit of everything: a slim chip under the title to pick a focus later.
struct InsightsFocusChip: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "scope").font(.system(size: 12, weight: .heavy))
                Text("Pick a focus").font(Theme.label(13))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.cardStrong))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Puts what matters most to you on top of Insights")
    }
}

/// A bit of everything: Pick a focus as a square on the ask bar's line, same height as the bar.
struct InsightsFocusTile: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Image(systemName: "scope").font(.system(size: 15, weight: .heavy))
                Text("Focus").font(Theme.label(10))
            }
            .foregroundStyle(.white)
            .frame(width: 50)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardStrong))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pick a focus")
        .accessibilityHint("Puts what matters most to you on top of Insights")
    }
}
