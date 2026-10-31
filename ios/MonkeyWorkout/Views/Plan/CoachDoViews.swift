import SwiftUI
import WorkoutEngine

/// What Coach does for the member in the chat (#999, mix A + B + C from `coach-can-act/proposals.png`):
/// one log = done card with Undo (B), one plan change = card that asks first (A), two or more = checklist with Do all (C).
struct CoachDoCard: View {
    let tasks: [CoachTask]
    /// Ticks a checklist line on or off.
    var toggle: (UUID) -> Void
    /// Does the waiting tasks that are ticked.
    var run: () -> Void
    /// Undoes everything done.
    var undo: () -> Void
    /// "Not now" on a single ask: the card goes.
    var dismiss: () -> Void

    private var waiting: Bool { tasks.contains { $0.status == .waiting } }
    private var done: Bool { tasks.contains { $0.status == .done } }

    var body: some View {
        Group {
            if tasks.count == 1, let t = tasks.first { single(t) } else { checklist }
        }
        .padding(.leading, 42)
    }

    // MARK: One task (A or B)

    private func single(_ t: CoachTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                tile(t.status == .done ? "checkmark" : t.symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(header(t)).font(Theme.label(11)).tracking(1.2).opacity(0.85)
                    Text(t.title).font(Theme.label(16)).strikethrough(t.status == .undone)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Text(t.value).font(Theme.display(30)).lineLimit(1).minimumScaleFactor(0.6)
            }
            if t.status == .waiting {
                HStack(spacing: 8) {
                    pill(t.askLabel, filled: true, id: "coach.do.run", action: run)
                    pill("Not now", filled: false, id: "coach.do.dismiss", action: dismiss)
                }
            } else if t.status == .done {
                HStack { Spacer(); pill("Undo", filled: true, id: "coach.do.undo", action: undo).fixedSize() }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(gradient(t.status == .waiting ? .ask : .done)))
        .accessibilityElement(children: .contain)
    }

    private func header(_ t: CoachTask) -> String {
        switch t.status {
        case .waiting: "COACH CAN DO IT"
        case .done: t.doneLabel
        case .undone: "UNDONE"
        case .failed: "COULDN'T DO IT, TODAY CHANGED"
        }
    }

    // MARK: Several (C)

    private var checklist: some View {
        VStack(spacing: 0) {
            ForEach(tasks) { t in
                Button { if t.status == .waiting { toggle(t.id) } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: mark(t))
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(Theme.ink.opacity(t.status == .waiting && !t.on ? 0 : 1))
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(t.on || t.status != .waiting ? 1 : 0.35)))
                        Image(systemName: t.symbol).font(.system(size: 15, weight: .bold)).frame(width: 20)
                        Text(t.title).font(Theme.label(15)).multilineTextAlignment(.leading)
                            .strikethrough(t.status == .undone || (t.status == .waiting && !t.on))
                        Spacer(minLength: 4)
                        Text(t.value).font(Theme.display(20)).lineLimit(1)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(t.on ? .isSelected : [])
                Divider().overlay(.white.opacity(0.25))
            }
            Group {
                if waiting {
                    let n = tasks.filter { $0.status == .waiting && $0.on }.count
                    pill(n == tasks.count ? "Do all \(n)" : "Do \(n)", filled: true, id: "coach.do.run", action: run)
                        .disabled(n == 0).opacity(n == 0 ? 0.5 : 1)
                } else if done {
                    pill("Undo all", filled: true, id: "coach.do.undo", action: undo)
                }
            }
            .padding(12)
        }
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(gradient(waiting ? .list : .done)))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func mark(_ t: CoachTask) -> String {
        switch t.status {
        case .waiting: "checkmark"
        case .done: "checkmark"
        case .undone: "arrow.uturn.backward"
        case .failed: "xmark"
        }
    }

    // MARK: Parts

    private enum Look { case ask, done, list }

    private func gradient(_ l: Look) -> LinearGradient {
        let c: [Color] = switch l {
        case .ask: [Color(red: 0.48, green: 0.18, blue: 0.97), Color(red: 0.95, green: 0.03, blue: 0.64)]
        case .done: [Color(red: 0.0, green: 0.79, blue: 0.42), Color(red: 0.0, green: 0.64, blue: 1.0)]
        case .list: [Color(red: 1.0, green: 0.48, blue: 0.0), Color(red: 1.0, green: 0.18, blue: 0.39)]
        }
        return LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func tile(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 20, weight: .bold))
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
    }

    private func pill(_ text: String, filled: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(Theme.label(15))
                .foregroundStyle(filled ? Theme.ink : .white)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(filled ? .white : .white.opacity(0.22)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
