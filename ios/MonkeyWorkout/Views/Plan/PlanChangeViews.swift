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
        case .pull: .strength
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
        }
    }
}

private let dayFormat: Date.FormatStyle = .dateTime.weekday(.wide).day().month(.abbreviated)

/// Pick another day of this week for one session; a session already there swaps days.
struct MoveSessionSheet: View {
    let sessionId: String
    var onMoved: (Int) -> Void = { _ in }
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    init(sessionId: String, onMoved: @escaping (Int) -> Void = { _ in }) {
        self.sessionId = sessionId
        self.onMoved = onMoved
    }

    var body: some View {
        NavigationStack {
            ScrollView { MoveDayPicker(sessionId: sessionId) { wd in onMoved(wd); dismiss() }.padding(16) }
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
    let onMoved: (Int) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = model.planCalendar
        let week = model.calendarWeeks(count: 1).first
        let session = week?.plan.sessions.first { $0.id == sessionId }
        let targets = Set(model.moveTargets(sessionId))
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
                            model.moveSession(sessionId, to: wd)
                            onMoved(wd)
                        } label: { row }
                        .buttonStyle(.plain)
                    } else {
                        row
                    }
                }
                Text("This week only: next week follows your plan again. A day with a session swaps with it.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            } else {
                ContentUnavailableView("Not in this week", systemImage: "calendar.badge.exclamationmark")
            }
        }
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
                    .background(Circle().fill(Theme.lime))
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

/// Add an unplanned workout to a day of this week: quick generated session, library workout, or a climb.
struct AddWorkoutSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var weekday: Int
    @State private var logging: ClimbLog?
    @State private var showAll = false
    @State private var climbsBefore = 0

    init(weekday: Int? = nil) {
        let today = WeekSchedule.fromCalendar(Calendar.current.component(.weekday, from: Date()))
        _weekday = State(initialValue: weekday ?? today)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    dayPicker
                    Text("Quick session").eyebrow().padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Generator.quickFoci, id: \.self) { f in
                            Button { addQuick(f) } label: { focusTile(f) }.buttonStyle(.plain)
                        }
                    }
                    Text("Built for your equipment and this week's phase. Counts in your week and history.")
                        .font(.caption).foregroundStyle(Theme.muted)
                    Text("From your library").eyebrow().padding(.top, 8)
                    let library = model.myLibrary + model.builtInLibrary
                    ForEach(showAll ? library : Array(library.prefix(4))) { e in
                        Button { addLibrary(e) } label: { LibraryCard(entry: e) }.buttonStyle(.plain)
                    }
                    if library.count > 4 && !showAll {
                        Button("Show all \(library.count)") { showAll = true }
                            .font(Theme.label(14)).foregroundStyle(Theme.lime)
                    }
                    Text("Climbing").eyebrow().padding(.top, 8)
                    Button {
                        climbsBefore = model.climbLogs.count
                        logging = ClimbLog(start: climbStart)
                    } label: { climbRow }.buttonStyle(.plain)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Add workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .sheet(item: $logging, onDismiss: { if model.climbLogs.count > climbsBefore { dismiss() } }) {
                LogClimbView(initial: $0)
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private var dayDate: Date {
        let cal = model.planCalendar
        return cal.date(byAdding: .day, value: weekday - 1, to: Progression.weekStart(Date(), cal)) ?? Date()
    }

    /// 18:00 that day, or 90 min ago today.
    private var climbStart: Date {
        let cal = model.planCalendar
        if cal.isDateInToday(dayDate) { return Date().addingTimeInterval(-90 * 60).rounded(minutes: 5) }
        return cal.date(bySettingHour: 18, minute: 0, second: 0, of: dayDate) ?? dayDate
    }

    private var dayPicker: some View {
        let cal = model.planCalendar
        let week = model.calendarWeeks(count: 1).first
        return VStack(alignment: .leading, spacing: 8) {
            Text(dayDate.formatted(dayFormat)).font(Theme.display(26))
            HStack(spacing: 4) {
                ForEach(WeekSchedule.weekdays, id: \.self) { wd in
                    let off = week?.off[wd] != nil
                    let busy = week?.plan.sessions.contains { $0.weekday == wd } ?? false
                    Button { weekday = wd } label: {
                        VStack(spacing: 1) {
                            Text(WeekSchedule.shortName(wd).uppercased()).font(Theme.label(9))
                            Text(week?.date(wd, cal).map { "\(cal.component(.day, from: $0))" } ?? "").font(Theme.display(17)).monospacedDigit()
                            Circle().fill(busy ? Color.white : .clear).frame(width: 5, height: 5)
                        }
                        .foregroundStyle(weekday == wd ? Theme.ink : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(weekday == wd ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white.opacity(off ? 0.03 : 0.08))))
                        .opacity(off ? 0.45 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(off)
                    .accessibilityLabel(WeekSchedule.name(wd) + (off ? ", can't train" : busy ? ", has a session" : ""))
                }
            }
        }
    }

    private func focusTile(_ f: Focus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: f == .conditioning ? "heart.circle.fill" : "bolt.fill").font(.system(size: 20, weight: .bold))
            Text(f.quickLabel).font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.7)
            Text("Add").font(Theme.label(11)).tracking(1).opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(f.palette.gradient))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Add quick \(f.quickLabel) session")
    }

    private var climbRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.climbing")
                .font(.system(size: 24, weight: .bold))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.15)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Log a climb").font(Theme.display(21))
                Text("Boulder, lead, top rope or outdoor, saved to Apple Health").font(.footnote.weight(.semibold)).opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.ink)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WorkoutEngine.Category.warmup.gradient))
    }

    private func addQuick(_ f: Focus) {
        guard let s = model.quickSession(f) else { return }
        model.addExtra(CustomWorkout(name: "Extra · \(f.quickLabel)"), generated: s, weekday: weekday)
        dismiss()
    }

    private func addLibrary(_ e: LibraryEntry) {
        guard let w = model.libraryWorkout(for: e.session) else { return }
        model.addExtra(w, weekday: weekday)
        dismiss()
    }
}

private extension Date {
    func rounded(minutes: Int) -> Date {
        let step = Double(minutes * 60)
        return Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate / step).rounded(.down) * step)
    }
}
