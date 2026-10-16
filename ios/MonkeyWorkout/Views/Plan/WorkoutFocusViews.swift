import SwiftUI
import WorkoutEngine

// Change a planned workout's focus from its page (#342, design A + C): another session type this week or every
// week, or swap days with another workout of this week.

extension Focus {
    /// What it trains, under the tile name.
    var muscleLine: String {
        switch self {
        case .fullUpper: "Whole body · upper first"
        case .fullLower: "Whole body · legs first"
        case .fullPower: "Jumps, throws · heavy lifts"
        case .upper: "Chest · back · shoulders · arms"
        case .lower: "Quads · hams · glutes · calves"
        case .push: "Chest · shoulders · triceps"
        case .pull: "Back · biceps · rear delts"
        case .legs: "Quads · hams · glutes · calves"
        case .chestTri: "Chest · triceps"
        case .backBi: "Back · biceps"
        case .shouldersArms: "Delts · biceps · triceps"
        case .chestBack: "Chest · back"
        case .posterior: "Glutes · hams · lower back"
        case .conditioning: "Intervals · heart rate"
        }
    }
}

/// "Change focus" and "Swap day" chips under the workout's title, and their sheets.
struct WorkoutFocusChips: View {
    let session: Session
    @Environment(AppModel.self) private var model
    @State private var picking = false
    @State private var swapping = false

    var body: some View {
        if model.canChangeFocus(session) {
            let targets = model.swapDayTargets(session)
            HStack(spacing: 8) {
                chip("Change focus", symbol: "arrow.left.arrow.right") { picking = true }
                    .accessibilityHint("Train another muscle group in this workout")
                if !targets.isEmpty {
                    chip("Swap day", symbol: "calendar") { swapping = true }
                        .accessibilityHint("Do another workout of this week today")
                }
                if model.hasFocusChange(session.id) {
                    Text("This week only").font(Theme.label(11)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(WorkoutEngine.Category.cardio.gradient))
                }
            }
            .sheet(isPresented: $picking) {
                NavigationStack { FocusPickView(session: session) }.presentationDetents([.large])
            }
            .sheet(isPresented: $swapping) {
                SwapDaySheet(session: session).presentationDetents([.large])
            }
        }
    }

    private func chip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Theme.label(13))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.lime))
        }
        .buttonStyle(.plain)
    }
}

/// Design A: the 14 session types; this workout only or every week.
struct FocusPickView: View {
    let session: Session
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var everyWeek = false

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    private var dayName: String { session.weekday.map(WeekSchedule.name) ?? "Day \(session.index + 1)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("What should this workout train?").font(.subheadline).foregroundStyle(Theme.muted)
                if model.canChangeFocusEveryWeek {
                    Picker("When", selection: $everyWeek) {
                        Text("This workout").tag(false)
                        Text("Every week").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Text(everyWeek ? "\(dayName)'s workout trains this from now on. Goal → Split shows it."
                                   : "Only this week. Next week it's \(model.plannedFocus(session).label) again.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Generator.dayFoci, id: \.self) { f in
                        Button { pick(f) } label: {
                            FocusTile(focus: f, selected: f == session.focus,
                                      detail: model.climbWarning(f, on: session.weekday).map { _ in "⚠︎ Next to climbing" } ?? f.muscleLine)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(f == session.focus ? .isSelected : [])
                        .accessibilityHint(model.climbWarning(f, on: session.weekday) ?? "")
                    }
                }
                if model.isEdited(session.id) {
                    Label("Your exercise edits to this workout are set aside. Undo brings them back.", systemImage: "pencil")
                        .font(.caption).foregroundStyle(WorkoutEngine.Category.cardio.color)
                }
                if model.hasFocusChange(session.id) {
                    Button { pick(model.plannedFocus(session), everyWeek: false) } label: {
                        Label("Back to the plan · \(model.plannedFocus(session).label)", systemImage: "arrow.uturn.backward")
                            .font(Theme.label(14)).foregroundStyle(Theme.lime)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("\(dayName) focus")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
            }
        }
    }

    private func pick(_ f: Focus, everyWeek: Bool? = nil) {
        let every = everyWeek ?? self.everyWeek
        guard f != session.focus || (every && f != model.plannedFocus(session)) else { return dismiss() }
        let before = (foci: model.state.synced?.sessionFoci, profile: model.profile)
        let from = session.focus
        model.setSessionFocus(session, to: f, everyWeek: every && model.canChangeFocusEveryWeek)
        dismiss()
        UndoCloseCenter.shared.show(UndoOffer(
            title: "\(dayName): \(f.label)", detail: every ? "Every week · was \(from.label)" : "This week · was \(from.label)",
            symbol: f.symbol, colors: f.palette.colors, reopen: { AnyView(EmptyView()) },
            revert: { [model] in model.restoreFocus(before.foci, profile: before.profile) }))
    }
}

/// Design C: another workout of this week comes to this day; "Something else" opens the session types.
struct SwapDaySheet: View {
    let session: Session
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Swaps places in this week's plan. Next week is as planned.").font(.subheadline).foregroundStyle(Theme.muted)
                    row(session, current: true)
                    ForEach(model.swapDayTargets(session)) { o in
                        Button { swap(o) } label: { row(o, current: false) }.buttonStyle(.plain)
                    }
                    if model.canChangeFocus(session) {
                        NavigationLink { FocusPickView(session: session) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "square.grid.2x2.fill").font(.system(size: 18, weight: .bold))
                                    .frame(width: 40, height: 40)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Something else").font(Theme.display(17))
                                    Text("Pick any focus for this workout").font(.caption).opacity(0.9)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(WorkoutEngine.Category.cardio.gradient))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Do another workout \(session.weekday.map { "on \(WeekSchedule.name($0))" } ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ s: Session, current: Bool) -> some View {
        let warning = current ? nil : model.climbWarning(s.focus, on: session.weekday)
        HStack(spacing: 12) {
            Text(s.weekday.map { WeekSchedule.shortName($0).uppercased() } ?? "")
                .font(Theme.label(13)).frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.displayTitle).font(Theme.display(18))
                Text(warning ?? (current ? "This workout" : "\(s.estMin)′ · \(s.focus.muscleLine)"))
                    .font(.caption).opacity(0.9).lineLimit(1)
            }
            Spacer()
            Image(systemName: current ? "mappin.circle.fill" : (warning == nil ? "arrow.left.arrow.right" : "exclamationmark.triangle.fill"))
                .font(.system(size: 18, weight: .bold))
        }
        .foregroundStyle(current ? Theme.lime : .white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(current ? AnyShapeStyle(Theme.card) : AnyShapeStyle(s.focus.palette.gradient)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.lime, lineWidth: current ? 2 : 0))
        .accessibilityElement(children: .combine)
        .accessibilityHint(current ? "" : "Moves \(s.displayTitle) here")
    }

    private func swap(_ other: Session) {
        guard let day = session.weekday, let otherDay = other.weekday else { return }
        model.swapDays(session, with: other)
        dismiss()
        let otherId = other.id
        UndoCloseCenter.shared.show(UndoOffer(
            title: "\(other.displayTitle) on \(WeekSchedule.name(day))",
            detail: "\(session.displayTitle) moved to \(WeekSchedule.name(otherDay))",
            symbol: "arrow.left.arrow.right", colors: other.focus.palette.colors, reopen: { AnyView(EmptyView()) },
            revert: { [model] in model.moveSession(otherId, to: otherDay) }))
    }
}
