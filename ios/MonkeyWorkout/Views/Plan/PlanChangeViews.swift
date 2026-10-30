import SwiftUI
import WorkoutEngine

// One-off changes to this week (#113): move a session to another day, add an extra workout.

extension Focus {
    /// Vivid tile colours for a session focus (same mapping as session cards).
    var palette: WorkoutEngine.Category {
        switch self {
        case .lower, .fullLower, .legs: .warmup
        case .upper, .fullUpper: .mobility
        case .push, .fullPower: .power
        case .conditioning: .cardio
        case .pull, .backBi: .strength
        case .chestTri: .power
        case .shouldersArms, .chestBack: .mobility
        case .posterior: .warmup
        }
    }

    /// Short name for quick-session tiles.
    var quickLabel: String {
        switch self {
        case .fullUpper, .upper: "Upper body"
        case .fullLower, .lower: "Lower body"
        case .fullPower: "Full-body power"
        case .push: "Push"
        case .pull: "Pull"
        case .legs: "Legs"
        case .conditioning: "Conditioning"
        case .chestTri, .backBi, .shouldersArms, .chestBack, .posterior: label
        }
    }
}

/// Pick another day of this week for one session; a session already there swaps days.
struct MoveSessionSheet: View {
    let sessionId: String
    /// A later week's session (#671); nil = this week.
    var later: PlanCalendar.Week? = nil
    var onMoved: (Int) -> Void = { _ in }
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    init(sessionId: String, later: PlanCalendar.Week? = nil, onMoved: @escaping (Int) -> Void = { _ in }) {
        self.sessionId = sessionId
        self.later = later
        self.onMoved = onMoved
    }

    var body: some View {
        NavigationStack {
            ScrollView { MoveDayPicker(sessionId: sessionId, later: later) { wd in onMoved(wd); dismiss() }.padding(16) }
                .readableWidth()
                .background(Theme.bg.ignoresSafeArea())
                .navigationTitle("Move to…")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { CloseToolbarItem { dismiss() } }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }
}

/// The days of this week as vivid rows: what's planned there, today marked, days off and the session's own day locked.
struct MoveDayPicker: View {
    let sessionId: String
    /// A later week's session (#671): its days, that week only; nil = this week.
    var later: PlanCalendar.Week? = nil
    let onMoved: (Int) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = model.planCalendar
        let week = later ?? model.calendarWeeks(count: 1).first
        let session = week?.plan.sessions.first { $0.id == sessionId }
        let targets = Set(later.flatMap { w in session.map { model.moveTargets($0, in: w) } } ?? model.moveTargets(sessionId))
        let today = PlanCalendar.key(Date(), cal)
        VStack(alignment: .leading, spacing: 10) {
            if let session, let week {
                header(session)
                ForEach(WeekSchedule.weekdays, id: \.self) { wd in
                    let others = week.plan.sessions.filter { $0.weekday == wd && $0.id != sessionId }
                    let row = dayRow(wd, week: week, own: session.weekday == wd, others: others, enabled: targets.contains(wd),
                                     today: week.days[wd - 1] == today, cal: cal)
                    if targets.contains(wd) {
                        Button {
                            let from = session.weekday
                            if let later { model.moveSession(sessionId, to: wd, in: later) } else { model.moveSession(sessionId, to: wd) }
                            onMoved(wd)
                            if let from { undoMove(session, from: from, to: wd) }
                        } label: { row }
                        .buttonStyle(.plain)
                    } else {
                        row
                    }
                }
                Text(later == nil ? "This week only: next week follows your plan again. A day with a session swaps with it."
                     : "That week only: the weeks after follow your plan again. A day with a session swaps with it.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            } else {
                ContentUnavailableView("Not in this week", systemImage: "calendar.badge.exclamationmark")
            }
        }
    }

    /// "Moved to Thu" with Undo (#822), as Skip and Remove have: back on its day, a session it swapped with swaps back.
    private func undoMove(_ s: Session, from: Int, to: Int) {
        let id = s.id
        let start = later?.start
        UndoCloseCenter.shared.show(UndoOffer(
            title: "Moved to \(WeekSchedule.shortName(to))", detail: s.displayTitle, symbol: "arrow.left.arrow.right",
            colors: s.focus.palette.colors, reopen: { AnyView(EmptyView()) },
            revert: { [model] in
                if let start {
                    // That later week as it is now, not the snapshot the picker had.
                    if let w = model.calendarWeeks().first(where: { $0.start == start }) { model.moveSession(id, to: from, in: w) }
                } else {
                    model.moveSession(id, to: from)
                }
            }))
    }

    private func header(_ s: Session) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 22, weight: .heavy))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 3) {
                Text(s.displayTitle).font(Theme.display(24)).lineLimit(1).minimumScaleFactor(0.8)
                Text(s.weekday.map { "Planned \(WeekSchedule.name($0))" } ?? "No day yet").font(.footnote.weight(.semibold)).opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(s.palette.gradient))
    }

    private func dayRow(_ wd: Int, week: PlanCalendar.Week, own: Bool, others: [Session], enabled: Bool, today: Bool, cal: Calendar) -> some View {
        let off = week.off[wd] != nil
        let detail: String = {
            if own { return "Planned here" }
            if off { return week.off[wd]?.title ?? "Can't train" }
            if let o = others.first { return "Swap with \(o.displayTitle)" + (others.count > 1 ? " +\(others.count - 1)" : "") }
            if week.climbing.contains(wd) { return "Climbing day" }
            return "Free"
        }()
        return HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(WeekSchedule.shortName(wd).uppercased()).font(Theme.label(10))
                Text(week.date(wd, cal).map { "\(cal.component(.day, from: $0))" } ?? "").font(Theme.display(20)).monospacedDigit()
            }
            .frame(width: 48, height: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(WeekSchedule.name(wd) + (today ? " · Today" : "")).font(.system(.headline, design: .rounded).weight(.heavy))
                Text(detail).font(.caption.weight(.semibold)).opacity(0.85).lineLimit(1)
            }
            Spacer(minLength: 4)
            if enabled {
                Image(systemName: others.isEmpty ? "arrow.down.to.line" : "arrow.left.arrow.right")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lime))
            } else if own {
                Image(systemName: "mappin.circle.fill").font(.system(size: 24))
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(off ? AnyShapeStyle(WorkoutEngine.Category.power.color.opacity(0.35))
                      : others.first.map { AnyShapeStyle($0.palette.gradient) } ?? AnyShapeStyle(Theme.card))
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.lime, lineWidth: own ? 2 : 0))
        .opacity(enabled || own ? 1 : 0.5)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
