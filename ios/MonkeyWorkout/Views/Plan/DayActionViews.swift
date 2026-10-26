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
        guard let sport = profile?.sport(onWeekday: weekday, key: key, date: date) else { return nil }
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
/// the Calendar day sheet (#784).
struct SkippedLine: View {
    let sessions: [Session]
    /// The later week they were skipped in; nil = this week.
    var week: PlanCalendar.Week? = nil
    @Environment(AppModel.self) private var model

    var body: some View {
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
