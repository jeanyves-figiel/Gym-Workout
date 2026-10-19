import SwiftUI
import WorkoutEngine

// Kind streaks + Wins you missed (#501): rewards for members who struggle, start out or come back.

/// Vivid gradient row: icon tile left, title + detail, big number right; optional progress squares.
struct KindRewardCard: View {
    let symbol: String
    let colors: [Color]
    let title: String
    let detail: String
    let value: String
    let unit: String
    /// Progress squares: done of total.
    var squares: (done: Int, total: Int)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.25)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.label(16)).lineLimit(1).minimumScaleFactor(0.8)
                Text(detail).font(.caption.weight(.semibold)).opacity(0.9).lineLimit(2).minimumScaleFactor(0.85)
                if let squares {
                    HStack(spacing: 4) {
                        ForEach(0..<squares.total, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(i < squares.done ? Color.white : Color.black.opacity(0.28))
                                .frame(width: 16, height: 16)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 0) {
                Text(value).font(Theme.display(26)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(Theme.label(10)).opacity(0.85).lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .accessibilityElement(children: .combine)
    }
}

enum KindRewardStyle {
    static let teal = [Color(red: 0, green: 0.78, blue: 0.65), Color(red: 0.12, green: 0.61, blue: 1)]
    static let indigo = [Color(red: 0.24, green: 0.35, blue: 1), Color(red: 0.54, green: 0.31, blue: 1)]
    static let pink = [Color(red: 1, green: 0.24, blue: 0.55), Color(red: 1, green: 0.6, blue: 0.37)]
    static let purple = [Color(red: 0.7, green: 0.24, blue: 1), Color(red: 1, green: 0.31, blue: 0.85)]
    static let orange = [Color(red: 1, green: 0.62, blue: 0.11), Color(red: 1, green: 0.24, blue: 0.35)]

    static func colors(_ k: Win.Kind) -> [Color] {
        switch k {
        case .comeback, .feel: teal
        case .heavier, .moreSets: pink
        case .weekGoal, .shield: indigo
        case .allSets, .newMove: purple
        case .sessionCount, .minutes, .muscles, .sets: orange
        }
    }

    static func symbol(_ k: Win.Kind) -> String {
        switch k {
        case .comeback: "arrow.counterclockwise"
        case .heavier: "chart.line.uptrend.xyaxis"
        case .weekGoal: "shippingbox.fill"
        case .shield: "shield.fill"
        case .allSets: "checkmark.seal.fill"
        case .moreSets: "plus.square.fill"
        case .newMove: "sparkles"
        case .feel: "face.smiling.inverse"
        case .sessionCount: "figure.strengthtraining.traditional"
        case .minutes: "stopwatch.fill"
        case .muscles: "figure.arms.open"
        case .sets: "square.stack.3d.up.fill"
        }
    }
}

/// Train (#501): "Welcome back" after a break, the Comeback quest while it runs, and a streak shield that saved
/// last week. Nothing shows on an ordinary week.
struct KindStreakCards: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = Progression.stats(records: model.state.history, weights: [], targetPerWeek: model.gameTarget)
        let comeback = model.comeback
        if comeback != nil || stats.shieldSavedLastWeek {
            VStack(spacing: 8) {
                if let c = comeback { comebackCard(c) }
                if stats.shieldSavedLastWeek {
                    let n = stats.currentStreakWeeks
                    KindRewardCard(symbol: "shield.fill", colors: KindRewardStyle.indigo, title: "Streak shield used",
                                   detail: "A missed week kept your streak · \(stats.streakShields) shield\(stats.streakShields == 1 ? "" : "s") left",
                                   value: "\(n)", unit: n == 1 ? "week" : "weeks")
                }
            }
        }
    }

    private func comebackCard(_ c: Comeback) -> some View {
        let n = Comeback.sessions
        return KindRewardCard(
            symbol: "arrow.counterclockwise", colors: KindRewardStyle.teal,
            title: c.done == 0 ? "Welcome back" : "Comeback quest",
            detail: c.done == 0
                ? "\(c.daysAway) days away. \(n) sessions back, loads eased · +\(Comeback.xpPerSession) XP each"
                : "Session \(c.done + 1) of \(n) next · +\(Comeback.xpPerSession) XP",
            value: "\(c.done)/\(n)", unit: "+\(n * Comeback.xpPerSession) XP",
            squares: (c.done, n))
    }
}

/// Finish sheet (#501): three personal wins, then how the member feels now.
struct WinsCard: View {
    let wins: [Win]
    var recordId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(wins.count) win\(wins.count == 1 ? "" : "s") today").font(Theme.display(24))
            ForEach(wins) { w in
                KindRewardCard(symbol: KindRewardStyle.symbol(w.kind), colors: KindRewardStyle.colors(w.kind),
                               title: w.title, detail: w.detail, value: w.value, unit: w.unit)
            }
            if let recordId { FeelRow(recordId: recordId) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "How do you feel now?": four faces, saved with the session (on this iPhone) and used for later wins.
struct FeelRow: View {
    let recordId: UUID
    @Environment(AppModel.self) private var model

    var body: some View {
        let picked = model.feel(of: recordId)
        HStack(spacing: 6) {
            Text(picked.map { "Feeling \($0.label.lowercased())" } ?? "How do you feel now?")
                .font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            ForEach(Feel.allCases, id: \.self) { f in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(duration: 0.3)) { model.setFeel(f, for: recordId) }
                } label: {
                    Text(f.emoji).font(.system(size: picked == f ? 30 : 24))
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(picked == f ? Theme.lime.opacity(0.9) : Color.white.opacity(0.08)))
                        .opacity(picked == nil || picked == f ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(f.label)
                .accessibilityAddTraits(picked == f ? .isSelected : [])
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}
