import SwiftUI
import WorkoutEngine

// Same day actions everywhere (#671, design A from `day-card-consistency/proposals.png`): the day card's three tiles
// and the strip day's long press offer the same moves for a workout, sport or rest day, this week or a later one.

/// A sport day to turn into a rest day: asks just this day, every week (weekly sport) or the whole trip.
struct SportOffRequest: Identifiable {
    let key: String
    let weekday: Int
    let date: Date
    let sport: Sport
    let trip: SportTrip?
    var id: String { key }
}

extension View {
    /// Shows the Rest day choice for `request`, then turns the day into a rest day with an Undo toast.
    func sportOffFlow(_ request: Binding<SportOffRequest?>) -> some View { modifier(SportOffFlow(request: request)) }
}

private struct SportOffFlow: ViewModifier {
    @Binding var request: SportOffRequest?
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.confirmationDialog("Make it a rest day", isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }),
                                   titleVisibility: .visible, presenting: request) { r in
            Button("Just \(r.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))") { drop(r, .day) }
            if let trip = r.trip {
                if trip.isTrip { Button("Whole \(trip.title.lowercased())") { drop(r, .wholeTrip) } }
            } else {
                Button("Every \(WeekSchedule.name(r.weekday))") { drop(r, .everyWeek) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { r in
            Text("No \(r.sport.label.lowercased()) that day: a normal rest day with Recover.")
        }
    }

    private func drop(_ r: SportOffRequest, _ scope: AppModel.SportOffScope) {
        let detail = switch scope {
        case .day: r.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        case .everyWeek: "Every \(WeekSchedule.name(r.weekday))"
        case .wholeTrip: r.trip?.title ?? ""
        }
        guard let before = withAnimation(.snappy, { model.dropSport(on: r.key, weekday: r.weekday, scope: scope) }) else { return }
        UndoCloseCenter.shared.deleted("\(r.sport.label) off", detail: detail, symbol: "moon.fill") { [model] in
            withAnimation(.snappy) { model.restoreSportDay(before) }
        }
    }
}

extension AppModel {
    /// The Rest day request for day `key` when it holds a sport; nil on a rest or can't-train day.
    func sportOffRequest(key: String, weekday: Int, date: Date) -> SportOffRequest? {
        guard let sport = daySport(onWeekday: weekday, key: key, date: date) else { return nil }
        return SportOffRequest(key: key, weekday: weekday, date: date, sport: sport, trip: profile?.sportTrip(on: key))
    }
}

/// Skips or unskips a session of this week or of a later `week`, with Undo for a skip.
@MainActor func toggleSkip(_ model: AppModel, _ s: Session, in week: PlanCalendar.Week?) {
    guard let week else {
        if model.skippedIds.contains(s.id) { withAnimation { model.unskip(s.id) } } else if model.canSkip(s) { skipWithUndo(model, s) }
        return
    }
    if model.isSkipped(s.id, in: week) {
        withAnimation { model.setSkipped(false, s.id, in: week) }
    } else {
        withAnimation { model.setSkipped(true, s.id, in: week) }
        UndoCloseCenter.shared.deleted("\(s.displayTitle) skipped", detail: "That week only", symbol: "nosign") { [model] in
            withAnimation { model.setSkipped(false, s.id, in: week) }
        }
    }
}

/// Workout on a later week's rest or sport day: one of that week's workouts moved here (Add workout plans this week only).
struct MoveHereSheet: View {
    let week: PlanCalendar.Week
    let weekday: Int
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let sessions = week.plan.sessions.filter { $0.weekday != nil && $0.weekday != weekday }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sessions) { s in
                        Button {
                            withAnimation(.snappy) { model.moveSession(s.id, to: weekday, in: week) }
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.weekday.map(WeekSchedule.name)?.uppercased() ?? "").font(Theme.label(11)).tracking(1.2).opacity(0.8)
                                    Text(s.displayTitle).font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.7)
                                    Text("\(s.estMin) min").font(Theme.label(12)).opacity(0.85)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.right.circle.fill").font(.title2.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(s.palette.gradient))
                        }
                        .buttonStyle(.plain)
                    }
                    if sessions.isEmpty {
                        ContentUnavailableView("No other workout that week", systemImage: "calendar.badge.exclamationmark")
                    }
                    Text("That week only: a workout already on this day swaps to the other day.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Workout on \(week.date(weekday, model.planCalendar)?.formatted(.dateTime.weekday(.abbreviated).day()) ?? WeekSchedule.name(weekday))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

/// "Pull skipped" struck through with a small lime Unskip chip (#698, design A), on Train's rest day card and in
/// the Calendar day sheet (#784). Workouts removed from the day show nothing.
struct SkippedLine: View {
    let sessions: [Session]
    /// The later week they were skipped in; nil = this week.
    var week: PlanCalendar.Week? = nil
    @Environment(AppModel.self) private var model

    var body: some View {
        // Removed ones (#784) leave no line.
        let shown = sessions.filter { !model.isRemoved($0.id, in: week) }
        if !shown.isEmpty { line(shown) }
    }

    private func line(_ sessions: [Session]) -> some View {
        HStack(spacing: 8) {
            Text("\(sessions.map(\.displayTitle).joined(separator: " · ")) skipped")
                .font(Theme.label(13)).strikethrough().foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            Button {
                withAnimation {
                    for s in sessions {
                        if let week { model.setSkipped(false, s.id, in: week) } else { model.unskip(s.id) }
                    }
                }
            } label: {
                Label("Unskip", systemImage: "arrow.uturn.backward").font(Theme.label(12)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.lime))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("train.unskip")
            Spacer(minLength: 0)
        }
    }
}

// MARK: Remove a workout (#784, design B from `remove-workout/proposals.png`)

/// A workout to remove: from its day only, every week on its weekday, or just skipped. `week` nil = this week.
struct RemoveRequest: Identifiable {
    let session: Session
    let week: PlanCalendar.Week?
    let weekday: Int
    let date: Date
    var id: String { session.id }
}

extension View {
    /// Shows the Remove choice for `request`, then removes with an Undo toast.
    func removeWorkoutFlow(_ request: Binding<RemoveRequest?>, onDone: @escaping () -> Void = {}) -> some View {
        sheet(item: request) { RemoveWorkoutSheet(request: $0, onDone: onDone) }
    }
}

extension AppModel {
    /// The Remove request for `s` on `weekday` of this week (`week` nil) or a later week.
    func removeRequest(_ s: Session, weekday: Int, in week: PlanCalendar.Week?) -> RemoveRequest {
        let cal = planCalendar
        let date = week?.date(weekday, cal)
            ?? cal.date(byAdding: .day, value: weekday - 1, to: Progression.weekStart(Date(), cal)) ?? Date()
        return RemoveRequest(session: s, week: week, weekday: weekday, date: date)
    }
}

private struct RemoveWorkoutSheet: View {
    let request: RemoveRequest
    let onDone: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let s = request.session
        let n = model.profile?.sessionsPerWeek ?? 3
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("Remove \(s.displayTitle)").font(Theme.display(24)).lineLimit(2).minimumScaleFactor(0.8)
                option("Just \(request.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))",
                       detail: "rest day, plan carries on", symbol: "1.square.fill", fill: AnyShapeStyle(MissedStyle.gradient)) {
                    // An added workout of this week (#818) comes off the plan, as its own Remove does (#538).
                    if request.week == nil, let ins = model.planInsert(for: s), ins.replacing == nil {
                        return removeExtra(ins)
                    }
                    withAnimation(.snappy) { model.removeSession(s.id, in: request.week) }
                    let week = request.week
                    UndoCloseCenter.shared.deleted("\(s.displayTitle) removed", detail: dayName, symbol: "trash") { [model] in
                        withAnimation(.snappy) { model.restoreSession(s.id, in: week) }
                    }
                }
                .accessibilityIdentifier("remove.day")
                // Every week only for a regular gym day's workout (#818) or a planned HIIT day (#841): not an added or moved one.
                if everyWeek {
                    option("Every \(WeekSchedule.name(request.weekday))", detail: everyWeekDetail(n),
                           symbol: "arrow.triangle.2.circlepath",
                           fill: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x9A3BD8), Color(hex: 0x5A4AB0)], startPoint: .leading, endPoint: .trailing))) {
                        let hiit = model.isPlannedHiit(s)
                        guard let before = withAnimation(.snappy, { model.removeEveryWeek(request.weekday, hiit: hiit) }) else { return }
                        UndoCloseCenter.shared.deleted("No more \(WeekSchedule.name(request.weekday)) \(hiit ? "HIIT" : "workouts")", detail: "My plan updated", symbol: "trash") { [model] in
                            withAnimation(.snappy) { model.updateProfile(before) }
                        }
                    }
                    .accessibilityIdentifier("remove.everyWeek")
                }
                if !skipped {
                    option("Just skip it", detail: "keeps \"skipped · Unskip\"", symbol: "nosign", fill: AnyShapeStyle(Color.white.opacity(0.14))) {
                        skip()
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bg.ignoresSafeArea())
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.height(CGFloat(380 - (skipped ? 80 : 0) - (everyWeek ? 0 : 80)))])
    }

    /// What Every <weekday> does: a HIIT day (#841) changes HIIT days only.
    private func everyWeekDetail(_ n: Int) -> String {
        if model.isPlannedHiit(request.session) {
            let h = model.profile?.hiit?.days ?? 1
            return h > 1 ? "HIIT \(h - 1)× a week instead of \(h)" : "no more HIIT days in your plan"
        }
        return n > 2 ? "train \(n - 1)× a week instead of \(n)" : "keeps \(n)× a week, on other days"
    }

    private var everyWeek: Bool { model.canRemoveEveryWeek(request.session, weekday: request.weekday, in: request.week) }

    /// Takes an added workout off this week (#818), with Undo putting it back.
    private func removeExtra(_ ins: PlanInsert) {
        let s = request.session
        withAnimation(.snappy) { model.removePlanInsert(ins.id) }
        UndoCloseCenter.shared.deleted("\(s.displayTitle) removed", detail: dayName, symbol: "trash") { [model] in
            withAnimation(.snappy) {
                if let generated = ins.generated, let wd = ins.weekday {
                    _ = model.addExtra(ins.workout, generated: generated, weekday: wd)
                } else {
                    _ = model.insertIntoPlan(ins.workout, replacing: ins.replacing, weekday: ins.weekday)
                }
            }
        }
    }

    private var dayName: String { request.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) }

    private var skipped: Bool {
        request.week.map { model.isSkipped(request.session.id, in: $0) } ?? model.skippedIds.contains(request.session.id)
    }

    private func skip() {
        let s = request.session
        if let week = request.week {
            withAnimation { model.setSkipped(true, s.id, in: week) }
        } else {
            withAnimation { model.skipSession(s.id) }
        }
        let week = request.week
        UndoCloseCenter.shared.deleted("\(s.displayTitle) skipped", detail: dayName, symbol: "nosign") { [model] in
            withAnimation { if let week { model.setSkipped(false, s.id, in: week) } else { model.unskip(s.id) } }
        }
    }

    private func option(_ title: String, detail: String, symbol: String, fill: AnyShapeStyle, action: @escaping () -> Void) -> some View {
        Button {
            dismiss()
            action()
            onDone()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 17, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.25)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.label(16)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(detail).font(.caption.weight(.semibold)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(fill))
        }
        .buttonStyle(.plain)
    }
}
