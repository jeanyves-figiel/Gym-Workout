import SwiftUI
import WorkoutEngine

// Missed sessions (#266): what a member can do with a session of an earlier day this week that wasn't done.

/// Log it · Mark done · Do today · Skip, as one row of buttons.
struct MissedActionsRow: View {
    let session: Session
    var primary: Color = .white
    var primaryInk: Color = MissedStyle.ink
    let onLog: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            action("Log it", "square.and.pencil", fill: primary, ink: primaryInk, onLog)
            action("Mark done", "checkmark") { markDone() }
            action("Do today", "arrow.uturn.forward") { doToday() }
            action("Skip", "nosign") { skip() }
        }
    }

    // Each one at once with the Undo bar (#822), as Skip and Remove elsewhere.

    private func markDone() {
        let s = session
        let r = withAnimation { model.markMissedDone(s) }
        UndoCloseCenter.shared.deleted("\(s.displayTitle) done", detail: "Logged on \(s.dayLabel)", symbol: "checkmark") { [model] in
            withAnimation { _ = model.undoWorkout(r.id) }
        }
    }

    private func doToday() {
        let s = session
        let wasSkipped = model.skippedIds.contains(s.id)
        withAnimation { model.doMissedToday(s.id) }
        guard let from = s.weekday else { return }
        UndoCloseCenter.shared.deleted("\(s.displayTitle) moved to today", detail: "Back to \(WeekSchedule.name(from)) on Undo",
                                       symbol: "arrow.uturn.forward") { [model] in
            withAnimation {
                model.moveSession(s.id, to: from, swap: false)
                if wasSkipped { model.skipMissed(s.id) }
            }
        }
    }

    private func skip() {
        let s = session
        withAnimation { model.skipMissed(s.id) }
        UndoCloseCenter.shared.deleted("\(s.displayTitle) skipped", detail: "It stops asking", symbol: "nosign") { [model] in
            withAnimation { model.unskip(s.id) }
        }
    }

    private func action(_ title: String, _ symbol: String, fill: Color = .black.opacity(0.3), ink: Color = .white,
                        _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 13, weight: .heavy))
                Text(title).font(Theme.label(11)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(session.displayTitle)")
    }
}

/// Logs a missed session after the fact on its day: when, how long, sets done and kg per exercise.
struct MissedLogSheet: View {
    let session: Session
    /// Values brought back by Undo (#285).
    var restoring: Draft?
    /// Recorded on another watch (#549): its times prefill, its heart rate and calories go with the workout.
    var fromHealth: GymEntry?
    /// Day it's logged on (#592: a workout added on a past day); nil = the session's own day.
    var day: Date? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var minutes = 60
    @State private var sets: [String: Int] = [:]
    @State private var kg: [String: Double] = [:]
    @State private var baseline: Draft?
    @State private var closeGuard = CloseGuard()

    /// What's entered, kept for Undo (#285).
    struct Draft: Equatable {
        var start: Date
        var minutes: Int
        var sets: [String: Int]
        var kg: [String: Double]
    }

    private struct Row: Identifiable {
        let item: PlannedExercise
        let block: Block
        var id: String { item.uid }
        var exercise: Exercise { Exercise.get(item.exerciseId) }
        var loaded: Bool {
            [.strength, .power].contains(block.kind) && !exercise.equipment.isEmpty && exercise.unit != .sec
        }
    }

    private var rows: [Row] {
        session.blocks.filter { ![.warmup, .mobility, .cooldown].contains($0.kind) }
            .flatMap { b in b.items.map { Row(item: $0, block: b) } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    VStack(spacing: 10) {
                        DatePicker("Started", selection: $start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                            .font(Theme.label(15))
                        Stepper(value: $minutes, in: 5...240, step: 5) {
                            Text("\(minutes) min").font(Theme.label(15)).monospacedDigit()
                        }
                    }
                    .card()
                    Text("Sets done").font(Theme.label(13)).foregroundStyle(Theme.muted).textCase(.uppercase)
                    ForEach(rows) { r in row(r) }
                    Text("Warm-up and cool-down count as done. Weights update your next starting loads.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Log workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .safeAreaInset(edge: .bottom) { saveBar }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
        .onAppear(perform: prefill)
        .undoableClose(closeGuard, offer: undoOffer)
    }

    private var draft: Draft { Draft(start: start, minutes: minutes, sets: sets, kg: kg) }

    /// Undo bar when something was changed since the sheet opened (#285).
    private var undoOffer: UndoOffer? {
        guard let baseline, draft != baseline else { return nil }
        let kept = draft
        let s = self.session
        let fromHealth = self.fromHealth
        let day = self.day
        return UndoOffer(title: "Log closed", detail: undoDetail(s.displayTitle, "\(kept.minutes) min"),
                         symbol: "calendar.badge.exclamationmark", colors: WorkoutEngine.Category.power.colors) {
            AnyView(MissedLogSheet(session: s, restoring: kept, fromHealth: fromHealth, day: day))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fromHealth.map { "\($0.label) · \(session.dayLabel)" }
                 ?? day.map { "Done · \($0.formatted(.dateTime.weekday(.abbreviated).day()))" } ?? "Missed · \(session.dayLabel)").font(Theme.label(12)).tracking(1.4).textCase(.uppercase).opacity(0.85)
            Text(session.displayTitle).font(Theme.display(30)).lineLimit(1).minimumScaleFactor(0.6)
            Text("Planned \(session.estMin) min").font(.subheadline.weight(.semibold)).opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(MissedStyle.gradient))
    }

    private func row(_ r: Row) -> some View {
        let planned = max(1, r.item.prescription.sets)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.exercise.name).font(Theme.label(15)).lineLimit(1).minimumScaleFactor(0.7)
                    Text("\(planned) × \(r.item.prescription.reps)").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Stepper(value: Binding(get: { sets[r.id] ?? planned }, set: { sets[r.id] = $0 }), in: 0...planned) {
                    Text("\(sets[r.id] ?? planned)/\(planned)").font(Theme.label(15)).monospacedDigit()
                }
                .fixedSize()
            }
            if r.loaded {
                HStack {
                    Text("kg").font(Theme.label(13)).foregroundStyle(Theme.muted)
                    TextField("–", value: Binding(get: { kg[r.exercise.id] }, set: { kg[r.exercise.id] = $0 }), format: .number)
                        .keyboardType(.decimalPad)
                        .font(Theme.label(15))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(Theme.cardStrong))
                }
            }
        }
        .card(padding: 14)
    }

    private var saveBar: some View {
        Button {
            var done: [String: Int] = [:]
            for b in session.blocks { for it in b.items { done[it.uid] = max(1, it.prescription.sets) } }
            for (uid, n) in sets { done[uid] = n }
            if let fromHealth {
                model.logFromHealth(session, fromHealth, setsDone: done, weights: kg.filter { $0.value > 0 }, start: start, minutes: minutes)
            } else {
                model.logMissed(session, setsDone: done, weights: kg.filter { $0.value > 0 }, start: start, minutes: minutes)
            }
            closeGuard.done()
            dismiss()
        } label: {
            Label("Save workout", systemImage: "checkmark")
                .font(Theme.label(17)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(Capsule().fill(Theme.lime))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.bg)
    }

    private func prefill() {
        guard baseline == nil else { return }
        start = fromHealth?.start ?? day.flatMap { model.planCalendar.date(bySettingHour: 18, minute: 0, second: 0, of: $0) }
            ?? model.defaultStart(of: session)
        minutes = fromHealth.map { min(240, max(5, $0.minutes)) } ?? max(5, (session.estMin + 4) / 5 * 5)
        for r in rows where r.loaded { if kg[r.exercise.id] == nil { kg[r.exercise.id] = model.lastWeight(r.exercise.id) } }
        baseline = draft
        if let restoring {
            start = restoring.start
            minutes = restoring.minutes
            sets = restoring.sets
            kg = restoring.kg
        }
    }
}

enum MissedStyle {
    static let gradient = LinearGradient(colors: [Color(hex: 0xFF3D6E), Color(hex: 0xFF8A3D)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Type on white over the missed gradient.
    static let ink = Color(hex: 0xFF3D6E)
}

/// The week as seven day cells (design C, #266): missed days red, done days lime, today ringed, planned days lit.
/// A missed day opens the catch-up sheet; any other day is picked and the Next up card follows it (#277).
struct WeekDayStrip: View {
    /// Day the Next up card shows (#277), white in the strip; nil = the next session's.
    /// Days count from this week's Monday (#481): 1…7 = this week's weekday, 8… later weeks, 0 and below last week.
    var selected: Int? = nil
    /// Tap on any day that isn't missed (#277, #481): the Next up card follows it. Missed days open the catch-up sheet.
    var onPick: (Int) -> Void = { _ in }
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var catchUp: DayPick?
    /// Long press on a workout day (#488, design A): the same moves as This week's stages, plus Edit and Plan a sport.
    @State private var moving: SessionPick?
    @State private var editing: String?
    @State private var planningSport: String?
    @State private var addingDay: DayPick?
    /// Long press on any day, any week (#671): the same moves as its day card's tiles.
    @State private var movingLater: LaterPick?
    /// Remove… from the long press (#784).
    @State private var removing: RemoveRequest?
    @State private var movingHere: LaterDay?
    @State private var editingTrip: SportTrip?
    @State private var restRequest: SportOffRequest?

    struct DayPick: Identifiable { let id: Int }
    struct SessionPick: Identifiable { let id: String }
    struct LaterPick: Identifiable { let session: String; let week: PlanCalendar.Week; var id: String { session + week.days[0] } }
    struct LaterDay: Identifiable { let week: PlanCalendar.Week; let weekday: Int; var id: String { week.days[weekday - 1] } }

    /// Days shown are at most 1 week back and 2 weeks ahead (#464); 3 blank cells each side let the end days reach the lens (#486).
    static let daysBack = 7
    static let daysAhead = 14

    var body: some View {
        let sessions = model.plan?.sessions ?? []
        if sessions.contains(where: { $0.weekday != nil }) {
            let cal = model.planCalendar
            let weekStart = Progression.weekStart(Date(), cal)
            let todayOffset = model.todayWeekday - 1
            // Coming weeks as the calendar plans them (index 0 = this week).
            let weeks = model.calendarWeeks(count: 3)
            let pastDays = Set(model.historyItems(health: health).map { cal.startOfDay(for: $0.start) })
            // Shared lens strip (#486, #510): offsets from today, picks count from this week's Monday.
            LensDayStrip(range: -Self.daysBack...Self.daysAhead,
                         selected: selected.map { $0 - 1 - todayOffset } ?? 0,
                         onPick: { onPick(todayOffset + $0 + 1) }) { o in
                day(o, todayOffset: todayOffset, weekStart: weekStart, weeks: weeks, pastDays: pastDays, cal: cal)
            }
            .sheet(item: $catchUp) { MissedCatchUpSheet(weekday: $0.id) }
            .sheet(item: $moving) { MoveSessionSheet(sessionId: $0.id) }
            .sheet(item: Binding(get: { planningSport.map { SessionPick(id: $0) } }, set: { planningSport = $0?.id })) {
                PlanSportSheet(day: $0.id, sport: model.profile?.otherSports.first?.sport)
            }
            .sheet(item: $addingDay) { AddWorkoutSheet(weekday: $0.id) }
            .sheet(item: $movingLater) { MoveSessionSheet(sessionId: $0.session, later: $0.week) }
            .removeWorkoutFlow($removing)
            .sheet(item: $movingHere) { MoveHereSheet(week: $0.week, weekday: $0.weekday) }
            .sheet(item: $editingTrip) { PlanSportSheet(day: $0.start, editing: $0) }
            .sportOffFlow($restRequest)
            .navigationDestination(item: $editing) { SessionView(sessionId: $0) }
        }
    }

    /// Long-press menu of a workout day this week (#488): Move, Swap with, Edit workout, Plan a sport, Add workout.
    @ViewBuilder
    private func workoutMenu(_ s: Session, wd: Int, date: Date) -> some View {
        let done = model.state.done[s.id] ?? false
        if !done {
            Button("Move to…", systemImage: "arrow.left.arrow.right") { moving = SessionPick(id: s.id) }
            let swaps = model.swapDayTargets(s)
            if !swaps.isEmpty {
                Menu("Swap with…", systemImage: "arrow.up.arrow.down") {
                    ForEach(swaps, id: \.id) { o in
                        Button("\(o.displayTitle) · \(o.weekday.map(WeekSchedule.name) ?? "")") { swapWithUndo(model, s, with: o) }
                    }
                }
            }
        }
        Button("Edit workout", systemImage: "slider.horizontal.3") { editing = s.id }
        if wd >= model.todayWeekday {
            Button("Plan a sport", systemImage: "figure.snowboarding") { planningSport = PlanCalendar.key(date, model.planCalendar) }
        }
        Button("Add workout this day", systemImage: "plus") { addingDay = DayPick(id: wd) }
        if model.canSkip(s) {
            Button(wd == model.todayWeekday ? "Skip today" : "Skip \(WeekSchedule.name(wd))", systemImage: "nosign", role: .destructive) {
                skipWithUndo(model, s)
            }
        } else if model.skippedIds.contains(s.id), wd >= model.todayWeekday {
            Button("Unskip", systemImage: "arrow.uturn.backward") { withAnimation { model.unskip(s.id) } }
        }
        if !model.doneIds.contains(s.id), model.state.activeWorkout?.sessionId != s.id {
            Button("Remove…", systemImage: "trash", role: .destructive) { removing = model.removeRequest(s, weekday: wd, in: nil) }
        }
    }

    /// Long press on a later week's day (#671): a workout moves or is skipped there, that week only; a rest or sport day
    /// gets a workout moved to it, a sport planned, changed or dropped.
    @ViewBuilder
    private func laterMenu(_ s: Session?, week w: PlanCalendar.Week, wd: Int, date: Date, day: Int) -> some View {
        Button("Show in card", systemImage: "rectangle.on.rectangle") { onPick(day) }
        if let s {
            let skipped = model.isSkipped(s.id, in: w)
            Button("Move to…", systemImage: "arrow.left.arrow.right") { movingLater = LaterPick(session: s.id, week: w) }
            Button("Plan a sport", systemImage: "figure.snowboarding") { planningSport = w.days[wd - 1] }
            Button(skipped ? "Unskip" : "Skip \(WeekSchedule.name(wd))", systemImage: skipped ? "arrow.uturn.backward" : "nosign",
                   role: skipped ? nil : .destructive) { toggleSkip(model, s, in: w) }
            Button("Remove…", systemImage: "trash", role: .destructive) { removing = model.removeRequest(s, weekday: wd, in: w) }
        } else {
            Button("Workout here", systemImage: "plus") { movingHere = LaterDay(week: w, weekday: wd) }
            sportMenu(key: w.days[wd - 1], wd: wd, date: date)
        }
    }

    /// A sport day: change it or make it a rest day; a rest day: plan a sport (#671).
    @ViewBuilder
    private func sportMenu(key: String, wd: Int, date: Date) -> some View {
        if let r = model.sportOffRequest(key: key, weekday: wd, date: date) {
            if let trip = r.trip {
                Button(trip.isTrip ? "Edit sport trip" : "Edit sport day", systemImage: "arrow.triangle.2.circlepath") { editingTrip = trip }
            } else {
                Button("Change sport", systemImage: "arrow.triangle.2.circlepath") { planningSport = key }
            }
            Button("Make it a rest day", systemImage: "moon.fill", role: .destructive) { restRequest = r }
        } else {
            Button("Plan a sport", systemImage: "figure.snowboarding") { planningSport = key }
        }
    }

    /// What the long press lifts (#488): the day's workout as a gradient card.
    private func workoutPreview(_ s: Session, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                .font(Theme.label(11)).tracking(1.2).opacity(0.85)
            Text(s.displayTitle).font(Theme.display(26)).lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 10) {
                Label("\(s.estMin) min", systemImage: "clock.fill")
                Text("+\(model.xp(for: s)) XP").foregroundStyle(Theme.lime)
            }
            .font(Theme.label(13))
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(width: 280, alignment: .leading)
        .background(s.palette.gradient)
    }

    /// Leftmost cell that puts the selected day (today when none) under the lens (#486).
    /// The day `offset` days from today (#464): this week as before, later weeks from the calendar, last week from History.
    @ViewBuilder
    private func day(_ offset: Int, todayOffset: Int, weekStart: Date, weeks: [PlanCalendar.Week], pastDays: Set<Date>, cal: Calendar) -> some View {
        let fromMonday = todayOffset + offset
        let week = Int((Double(fromMonday) / 7).rounded(.down))
        let wd = fromMonday - week * 7 + 1
        let date = cal.date(byAdding: .day, value: fromMonday, to: weekStart) ?? Date()
        let n = cal.component(.day, from: date)
        let isToday = offset == 0
        let label = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if offset < -Self.daysBack || offset > Self.daysAhead {
            cell(wd, day: n, isToday: false, state: .rest).opacity(0.25).accessibilityHidden(true)
        } else if week == 0 {
            thisWeek(wd, day: n, isToday: isToday, date: date)
        } else if week > 0, week < weeks.count {
            let w = weeks[week]
            // A day is skipped once all its workouts are (#818); its menu acts on one still on.
            let daySessions = w.plan.sessions.filter { $0.weekday == wd }
            let session = daySessions.first { !model.isSkipped($0.id, in: w) } ?? daySessions.first
            // The same sport the day card shows (#670): dated days first, then weekly climbing and other sports.
            let daySport = w.off[wd] == nil ? model.daySport(onWeekday: wd, key: w.days[wd - 1], date: date) : nil
            let climb = daySport == .climbing
            let sport = climb ? nil : daySport
            let skipped = !daySessions.isEmpty && daySessions.allSatisfy { model.isSkipped($0.id, in: w) }
            // A skipped day with nothing else on it is a rest day (#698): moon, or its sport.
            let state: DayState = session != nil && !skipped ? (session?.hiit != nil ? .hiit : .planned) : climb ? .climb : sport.map { DayState.sport($0) } ?? .rest
            Button { onPick(fromMonday + 1) } label: { cell(wd, day: n, isToday: false, state: state, picked: selected == fromMonday + 1) }
                .buttonStyle(.plain)
                // Later weeks get the same moves as this week's days (#671).
                .contextMenu { laterMenu(session, week: w, wd: wd, date: date, day: fromMonday + 1) }
                .accessibilityAddTraits(selected == fromMonday + 1 ? .isSelected : [])
                .accessibilityLabel("\(label): \(session?.displayTitle ?? (climb ? "climbing day" : sport.map { "\($0.label) day" } ?? "rest day"))")
        } else if week < 0 {
            let trained = pastDays.contains(cal.startOfDay(for: date))
            let picked = selected == fromMonday + 1
            Button { onPick(fromMonday + 1) } label: {
                cell(wd, day: n, isToday: false, state: trained ? .done : .rest, picked: picked).opacity(trained || picked ? 1 : 0.6)
            }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label): \(trained ? "trained" : "no session")")
                .accessibilityAddTraits(picked ? .isSelected : [])
        } else {
            cell(wd, day: n, isToday: false, state: .rest).opacity(0.25).accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func thisWeek(_ wd: Int, day n: Int, isToday: Bool, date: Date) -> some View {
        let sessions = model.plan?.sessions ?? []
        let day = sessions.filter { $0.weekday == wd }
        let dayMissed = model.missedSessions.filter { $0.weekday == wd }
        if !dayMissed.isEmpty {
            // A day whose missed sessions were all skipped (#340) is picked like any other day.
            let allSkipped = dayMissed.allSatisfy { model.skippedIds.contains($0.id) }
            Button { if allSkipped { onPick(wd) } else { catchUp = DayPick(id: wd) } } label: {
                cell(wd, day: n, isToday: isToday, state: .missed(skipped: allSkipped), picked: allSkipped && selected == wd)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(WeekSchedule.name(wd)): \(dayMissed.map(\.displayTitle).joined(separator: ", ")) \(allSkipped ? "skipped" : "missed")")
            .accessibilityHint(allSkipped ? "" : "Log it, mark it done, do it today or skip")
        } else if let s = day.first {
            let allDone = day.allSatisfy { model.doneIds.contains($0.id) }
            // Today's or a later day skipped (#643): with nothing else on it, a rest day (#698), moon or its sport.
            let anyDone = day.contains { model.doneIds.contains($0.id) }
            let skipped = !allDone && day.allSatisfy { model.doneIds.contains($0.id) || model.skippedIds.contains($0.id) }
            let daySport = model.daySport(onWeekday: wd, key: PlanCalendar.key(date, model.planCalendar), date: date)
            let restState: DayState = daySport == .climbing ? .climb : daySport.map { DayState.sport($0) } ?? .rest
            Button { onPick(wd) } label: {
                cell(wd, day: n, isToday: isToday, state: allDone || skipped && anyDone ? .done : skipped ? restState : day.contains { $0.hiit != nil } ? .hiit : .planned,
                     picked: selected == wd)
            }
                .buttonStyle(.plain)
                .contextMenu { workoutMenu(s, wd: wd, date: date) } preview: { workoutPreview(s, date: date) }
                .accessibilityLabel("\(WeekSchedule.name(wd)): \(s.displayTitle)\(allDone ? ", done" : skipped ? ", skipped" : "")")
                .accessibilityAddTraits(selected == wd ? .isSelected : [])
        } else {
            // Climbing days of a climber show orange (#277); other sports' days (#416) show their icon. Dated days first (#658).
            let daySport = model.daySport(onWeekday: wd, key: PlanCalendar.key(date, model.planCalendar), date: date)
            let climb = daySport == .climbing
            let sport = climb ? nil : daySport
            Button { onPick(wd) } label: {
                cell(wd, day: n, isToday: isToday, state: climb ? .climb : sport.map { DayState.sport($0) } ?? .rest, picked: selected == wd)
            }
                .buttonStyle(.plain)
                // Same moves as the day card's tiles (#671); earlier days are logged on their card.
                .contextMenu {
                    if wd >= model.todayWeekday {
                        Button("Show in card", systemImage: "rectangle.on.rectangle") { onPick(wd) }
                        Button("Add workout this day", systemImage: "plus") { addingDay = DayPick(id: wd) }
                        sportMenu(key: PlanCalendar.key(date, model.planCalendar), wd: wd, date: date)
                    }
                }
                .accessibilityLabel("\(WeekSchedule.name(wd)): \(climb ? "climbing day" : sport.map { "\($0.label) day" } ?? "rest day")")
                .accessibilityHint("Add a workout")
                .accessibilityAddTraits(selected == wd ? .isSelected : [])
        }
    }

    private enum DayState: Equatable { case missed(skipped: Bool), done, planned, rest, climb, sport(Sport)
        /// A planned HIIT day (#757): ⚡ instead of the dot.
        case hiit
    }

    private func cell(_ wd: Int, day: Int, isToday: Bool, state: DayState, picked: Bool = false) -> some View {
        let base: AnyShapeStyle = switch state {
        case .missed: AnyShapeStyle(MissedStyle.gradient)
        case .done: AnyShapeStyle(Theme.lime)
        case .planned, .hiit: AnyShapeStyle(Color.white.opacity(0.2))
        case .rest: AnyShapeStyle(Color.black.opacity(0.25))
        case .climb: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFF7A3C), Color(hex: 0xFFB347)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .sport(let sp): AnyShapeStyle(sp.gradient)
        }
        let fill = picked ? AnyShapeStyle(Color.white) : base
        let ink: Color = picked ? Color(hex: 0x2A1D6E) : state == .done ? Theme.ink : state == .rest ? .white.opacity(0.55) : .white
        let symbol: String = switch state {
        case .missed(let skipped): skipped ? "minus" : "exclamationmark"
        case .done: "checkmark"
        case .planned: "circle.fill"
        case .hiit: "bolt.heart.fill"
        case .rest: "moon.fill"
        case .climb: "figure.climbing"
        case .sport(let sp): sp.symbol
        }
        return VStack(spacing: 2) {
            Text(WeekSchedule.shortName(wd).uppercased()).font(Theme.label(9)).tracking(0.5)
            Text("\(day)").font(Theme.display(15)).monospacedDigit()
            Image(systemName: symbol).font(.system(size: state == .planned ? 7 : 11, weight: .black)).frame(height: 12)
        }
        .foregroundStyle(isToday && (state == .planned || state == .hiit) && !picked ? Theme.lime : ink)
        .frame(maxWidth: .infinity)
        // Slimmer cells (#752, design C).
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill).opacity(state == .missed(skipped: true) ? 0.5 : 1))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.lime, lineWidth: isToday ? 2 : 0))
    }
}

/// Calendar day sheet for a day of a later week (#464, #473), with its Can't train / Travelling editor.
struct LaterDaySheets: ViewModifier {
    @Binding var day: DaySelection?
    @Environment(AppModel.self) private var model
    @State private var editingAway: AwayPeriod?
    @State private var awayIsNew = false

    func body(content: Content) -> some View {
        content
            .sheet(item: $day) { s in
                DaySheet(selection: s) { kind, key in
                    day = nil
                    awayIsNew = true
                    editingAway = AwayPeriod(kind: kind, start: key, end: key, setup: kind == .travel ? .hotelGym : nil)
                } onEdit: { a in
                    day = nil
                    awayIsNew = false
                    editingAway = a
                }
            }
            .sheet(item: $editingAway) { a in
                AwayEditorView(initial: a, isNew: awayIsNew) { saved in
                    if let saved { model.saveAway(saved) } else { model.deleteAway(a.id) }
                    editingAway = nil
                }
            }
    }
}

/// Catch-up sheet for a missed day: each missed session with Log it · Mark done · Do today · Skip.
/// Skip takes a session off the sheet (#340); the sheet closes once nothing is left.
struct MissedCatchUpSheet: View {
    /// The missed day; nil = every missed day (the "N missed" chips).
    let weekday: Int?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var logging: Session?

    var body: some View {
        let missed = model.missedToHandle.filter { weekday == nil || $0.weekday == weekday }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(missed) { s in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: s.focus.symbol)
                                    .font(.system(size: 20, weight: .heavy))
                                    .frame(width: 44, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.25)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.displayTitle).font(Theme.display(22)).lineLimit(1).minimumScaleFactor(0.6)
                                    Text("Missed\(weekday == nil ? " \(s.weekday.map(WeekSchedule.shortName) ?? "")" : "") · \(s.estMin) min planned")
                                        .font(.subheadline.weight(.semibold)).opacity(0.9)
                                }
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(.white)
                            MissedActionsRow(session: s, primary: Theme.lime, primaryInk: Theme.ink) { logging = s }
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(MissedStyle.gradient))
                    }
                    Text("Log it adds the workout on its day with what you did. Do today moves it next to today's session. Skip lets it go: it stays missed but stops asking.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .readableWidth()
            .glassSheetBackground()
            .navigationTitle(weekday.map { "Missed · \(WeekSchedule.name($0))" } ?? "Missed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
        .sheet(item: $logging, onDismiss: { if model.missedToHandle.allSatisfy({ weekday != nil && $0.weekday != weekday }) { dismiss() } }) { s in
            MissedLogSheet(session: s)
        }
        .onChange(of: missed.map(\.id)) { _, ids in if ids.isEmpty && logging == nil { dismiss() } }
    }
}

/// Swap with… from the strip's long press (#822): swapped at once, the Undo bar swaps back (as Focus' swap does).
@MainActor func swapWithUndo(_ model: AppModel, _ s: Session, with other: Session) {
    guard let day = s.weekday, let otherDay = other.weekday else { return }
    withAnimation { model.swapDays(s, with: other) }
    let otherId = other.id
    UndoCloseCenter.shared.show(UndoOffer(
        title: "\(other.displayTitle) on \(WeekSchedule.shortName(day))",
        detail: "\(s.displayTitle) moved to \(WeekSchedule.shortName(otherDay))",
        symbol: "arrow.up.arrow.down", colors: other.focus.palette.colors, reopen: { AnyView(EmptyView()) },
        revert: { [model] in withAnimation { model.moveSession(otherId, to: otherDay) } }))
}

/// Skips a session of today or later this week (#643): at once, with the Undo bar (no confirmation, #285).
@MainActor func skipWithUndo(_ model: AppModel, _ s: Session) {
    withAnimation { model.skipSession(s.id) }
    UndoCloseCenter.shared.deleted("\(s.displayTitle) skipped", detail: "This week only", symbol: "nosign") { [model] in
        withAnimation { model.unskip(s.id) }
    }
}
