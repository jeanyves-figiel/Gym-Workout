import SwiftUI
import WorkoutEngine

/// "Train" tab: the member's widgets (#260); by default the compact week + readiness card, today's session first,
/// then the week list.
struct WeekView: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var editing = false
    @State private var varying = false
    @State private var playing: Session?
    @State private var gate: ProGate?
    @State private var moving: Session?
    @State private var adding = false
    @State private var addingDay: Int?
    /// Day picked in the Next up strip (#277); nil = the next session.
    @State private var pickedDay: Int?
    @State private var removing: Session?
    @State private var swipe: (id: String, dx: CGFloat)?
    /// Editing the Train widgets (#260).
    @State private var arranging = false
    @State private var addingWidget = false
    @State private var customising = false
    @State private var showingCalendar = false
    /// CI screenshots: open in edit mode.
    var demoEditing = false
    /// Demo screens train-day-picked / train-rest-day (#277): a later planned day or a rest day picked in the strip.
    var demoPick: DemoPick?
    enum DemoPick { case planned, rest }

    var body: some View {
        ScrollView {
            if let plan = model.plan, let profile = model.profile {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if arranging {
                        TrainEditBar(onAdd: { addingWidget = true }, onList: { customising = true })
                    }
                    // The member's widgets (#260); the default layout is the Train screen as it always was.
                    let layout = model.trainLayout
                    if !layout.contains(.nextUp), !arranging { notices(plan: plan, profile: profile) }
                    ForEach(layout.rows) { row in
                        switch row {
                        case .full(let w):
                            widget(w, plan: plan, profile: profile)
                        case .pair(let a, let b):
                            HStack(alignment: .top, spacing: 12) {
                                widget(a, plan: plan, profile: profile)
                                    .frame(maxWidth: .infinity, minHeight: TrainWidgetMetrics.smallHeight, maxHeight: .infinity, alignment: .top)
                                Group {
                                    if let b {
                                        widget(b, plan: plan, profile: profile)
                                    } else {
                                        Color.clear
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: TrainWidgetMetrics.smallHeight, maxHeight: .infinity, alignment: .top)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if layout.widgets.isEmpty {
                        Button { arranging = true; addingWidget = true } label: {
                            Label("Add widgets to Train", systemImage: "plus.square.dashed")
                                .font(Theme.label(15)).foregroundStyle(Theme.lime)
                                .frame(maxWidth: .infinity).padding(.vertical, 28)
                                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(Theme.lime.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                        }
                        .buttonStyle(.plain)
                    }
                    if let e = model.syncError {
                        Label(e, systemImage: "icloud.slash").font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
                .padding(16)
                .animation(.snappy, value: model.trainLayout.widgets)
            } else {
                ContentUnavailableView("No plan yet", systemImage: "calendar.badge.plus")
            }
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Train")
        .toolbarTitleDisplayMode(.inlineLarge)
        .navigationDestination(for: String.self) { id in SessionView(sessionId: id) }
        .navigationDestination(for: ProgrammeRoute.self) { r in model.findProgramme(r.id).map { ProgrammeDetailView(programme: $0) } }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $editing) {
            NavigationStack {
                TrainingProfileView()
                    .navigationTitle("Training profile")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editing = false } } }
            }
        }
        .sheet(isPresented: $varying) {
            VariationSheet(days: Set(model.variableSessions.map(\.id)), keep: model.keptSwapUids)
        }
        .fullScreenCover(item: $playing) { s in WorkoutPlayerView(sessionId: s.id) }
        .proPaywall($gate)
        .sheet(item: $moving) { s in MoveSessionSheet(sessionId: s.id) }
        .sheet(isPresented: $adding) { AddWorkoutSheet(weekday: addingDay) }
        .navigationDestination(isPresented: $showingCalendar) { CalendarView() }
        .sheet(isPresented: $addingWidget) { TrainWidgetGallery() }
        .sheet(isPresented: $customising) { TrainCustomiseSheet() }
        .confirmationDialog(removing.map(removeTitle).map { "\($0)?" } ?? "", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { s in
            Button(removeTitle(s), role: .destructive) {
                if let id = s.planInsertId { withAnimation { model.removePlanInsert(id) } }
                removing = nil
            }
        } message: { s in
            Text(model.planInsert(for: s)?.replacing == nil ? "\(s.displayTitle) comes off this week's plan." : "This day goes back to its planned session.")
        }
        .refreshable { await model.sync() }
        .sheet(item: Bindable(model).finishedProgramme) { r in ProgrammeFinishedSheet(record: r).presentationDetents([.large]) }
        .task {
            // A new programme week (#255) builds its plan first.
            model.syncProgramme()
            model.rollWeekIfNeeded()
            if demoEditing { arranging = true }
            if let demoPick, let plan = model.plan {
                let today = model.todayWeekday
                let days = Set(plan.sessions.compactMap(\.weekday))
                pickedDay = demoPick == .rest
                    ? (today...7).first { !days.contains($0) }
                    : WeekProgress.ordered(plan).last { ($0.weekday ?? 0) > today && $0.id != model.nextSession?.id }?.weekday
            }
            // Away periods (#68): re-plan from today on (new day, period starting this week).
            model.replanCurrentWeek()
            model.persist()
        }
    }

    /// Next up (#266), or the day picked in its strip (#277): that day's workout, or a rest day with Add workout.
    @ViewBuilder private func nextUpCard(_ plan: WeekPlan) -> some View {
        let next = model.nextSession
        let pick: (Int) -> Void = { wd in
            withAnimation(.snappy) { pickedDay = pickedDay == wd || (pickedDay == nil && next?.weekday == wd) ? nil : wd }
        }
        let back = { withAnimation(.snappy) { pickedDay = nil } }
        if let d = pickedDay, let s = plan.sessions.first(where: { $0.weekday == d }) {
            NextUpCard(session: s, picked: d, onPick: pick, onBack: back) { playing = s }
        } else if let d = pickedDay {
            RestDayCard(weekday: d, onPick: pick, onBack: back) { addingDay = d; adding = true }
        } else if let next {
            NextUpCard(session: next, picked: nil, onPick: pick, onBack: back) { playing = next }
        } else {
            WeekCompleteCard(missed: model.missedSessions.count, onPick: pick)
        }
    }

    /// Touch-and-hold menu of a session (list rows and quest stages).
    @ViewBuilder private func sessionMenu(_ s: Session, day: Int?) -> some View {
        let done = model.state.done[s.id] ?? false
        if !done {
            Button("Move to…", systemImage: "arrow.left.arrow.right") { moving = s }
        }
        Button("Add workout this day", systemImage: "plus") { addingDay = day; adding = true }
        if s.isPlanInsert && !done {
            Button(removeTitle(s), systemImage: "trash", role: .destructive) { removing = s }
        }
    }

    private func removeTitle(_ s: Session) -> String {
        model.planInsert(for: s)?.replacing == nil ? "Remove from this week" : "Back to planned session"
    }

    private func swipeToRemove(_ s: Session) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                swipe = (s.id, min(0, max(v.translation.width, -110)))
            }
            .onEnded { v in
                let past = v.translation.width < -80 && abs(v.translation.width) > abs(v.translation.height) * 1.5
                withAnimation(.snappy) { swipe = nil }
                if past { removing = s }
            }
    }

    private func byDay(_ sessions: [Session], days: [String: Int]) -> [Session] {
        func key(_ i: Int) -> (Int, Int) { (sessions[i].weekday ?? days[sessions[i].id] ?? 8, i) }
        return sessions.indices.sorted { key($0) < key($1) }.map { sessions[$0] }
    }

    /// Title, edit button and LV chip; while editing, "Edit Train" and Done (#260).
    private var header: some View {
        HStack(spacing: 10) {
            Text(arranging ? "Edit Train" : "Train").font(Theme.display(34)).lineLimit(1).minimumScaleFactor(0.7)
            Spacer()
            if arranging {
                Button { withAnimation(.snappy) { arranging = false } } label: {
                    Text("Done").font(Theme.label(15)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(Theme.lime))
                }
                .buttonStyle(.plain)
            } else {
                // Calendar, Variation and Edit plan stay reachable when Quick actions is removed.
                if !model.trainLayout.contains(.actions) {
                    Menu {
                        Button("Calendar", systemImage: "calendar") { showingCalendar = true }
                        Button("Variation", systemImage: "shuffle") { ProStore.shared.run(.variation, $gate) { varying = true } }
                        Button("Edit plan", systemImage: "slider.horizontal.3") { editing = true }
                    } label: {
                        headerIcon("ellipsis")
                    }
                    .accessibilityLabel("Plan actions")
                }
                Button { withAnimation(.snappy) { arranging = true } } label: { headerIcon("square.grid.2x2.fill") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit Train")
                    .accessibilityHint("Add, remove, resize and reorder the widgets on this screen")
                LevelChip()
            }
        }
        .padding(.top, 4)
    }

    private func headerIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.white.opacity(0.14)))
    }

    /// Calendar, Variation and Edit plan as Explore-style gradient buttons in one row (#147): the Quick actions widget.
    private var actionChips: some View {
        HStack(spacing: 8) {
            NavigationLink { CalendarView() } label: {
                HeaderChip(symbol: "calendar", title: "Calendar", detail: "\(plannedCount) planned",
                           gradient: WorkoutEngine.Category.strength.gradient)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Calendar, \(plannedCount) sessions planned in the next 4 weeks")
            Button {
                ProStore.shared.run(.variation, $gate) { varying = true }
            } label: {
                HeaderChip(symbol: "shuffle", title: "Variation", detail: ProStore.shared.badged ? "New · PRO" : "New mix",
                           gradient: WorkoutEngine.Category.warmup.gradient)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New variation of this week's plan")
            Button { editing = true } label: {
                HeaderChip(symbol: "slider.horizontal.3", title: "Edit plan", detail: "Days · goals",
                           gradient: WorkoutEngine.Category.power.gradient)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit current plan: training profile")
        }
    }

    /// One widget, in edit chrome while editing.
    @ViewBuilder private func widget(_ w: TrainWidget, plan: WeekPlan, profile: Profile) -> some View {
        if arranging {
            TrainWidgetEditChrome(widget: w) { widgetContent(w, plan: plan, profile: profile) }
        } else {
            widgetContent(w, plan: plan, profile: profile)
        }
    }

    @ViewBuilder private func widgetContent(_ w: TrainWidget, plan: WeekPlan, profile: Profile) -> some View {
        let small = w.size == .small
        switch w.kind {
        case .actions:
            actionChips
        case .coach:
            if small { CoachSmallWidget() } else { MonkeyCoachCard() }
        case .week:
            if small {
                WeekSmallWidget(plan: plan, done: model.completedCount)
            } else {
                WeekHero(plan: plan, profile: profile, done: model.completedCount)
            }
        case .level:
            if small { LevelSmallWidget() } else { LevelBarCard(next: model.nextSession) }
        case .nextUp:
            if w.size == .large {
                VStack(alignment: .leading, spacing: 18) {
                    if !arranging, let undo = model.variationUndo { VariationUndoCard(undo: undo) }
                    nextUpCard(plan)
                    if !arranging { notices(plan: plan, profile: profile, undo: false) }
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    if !arranging, let undo = model.variationUndo { VariationUndoCard(undo: undo) }
                    NextUpCompactWidget(session: model.nextSession, wide: !small) { playing = $0 }
                        .frame(maxHeight: small ? .infinity : nil, alignment: .top)
                    if !arranging, !small { notices(plan: plan, profile: profile, undo: false) }
                }
            }
        case .climbing:
            if small {
                ClimbSmallWidget()
            } else if Generator.isClimber(profile) {
                ClimbSection()
            } else {
                Button { editing = true } label: {
                    WidgetTile(kind: .climbing, title: "Climbing") {
                        Text("Add climbing days").font(Theme.display(20))
                        Text("Pick climbing days in Edit plan and Train plans around them.")
                            .font(.caption.weight(.semibold)).opacity(0.9)
                    }
                }
                .buttonStyle(.plain)
            }
        case .calendar:
            CalendarWidget(look: w.resolvedLook ?? .week, size: w.size)
        case .streak:
            StreakWidget(size: w.size)
        case .volume:
            VolumeWidget(look: w.resolvedLook ?? .kg, size: w.size)
        case .records:
            RecordsWidget(size: w.size)
        case .body:
            BodyWeightWidget(size: w.size)
        case .muscles:
            MusclesWidget(size: w.size)
        case .lastWorkout:
            LastWorkoutWidget(size: w.size)
        case .programme:
            // Training programme (#255): replaces the plan while it runs; nothing to show otherwise.
            if model.activeProgramme != nil {
                ProgrammeHeroCard()
            } else if arranging {
                WidgetTile(kind: .programme) {
                    Text("No programme running").font(Theme.display(18))
                    Text("Shows here when you start a programme.").font(.caption.weight(.semibold)).opacity(0.9)
                }
            }
        case .thisWeek:
            thisWeek(plan: plan, profile: profile, quest: (w.look ?? (WatchHomePref.shared.style == .deck ? .quest : .list)) == .quest)
        }
    }

    /// Cards that only show when they apply: Undo variation, body prompt, climbing hint. Next to Next up,
    /// or on top when the member removed Next up.
    @ViewBuilder private func notices(plan: WeekPlan, profile: Profile, undo: Bool = true) -> some View {
        if undo, let u = model.variationUndo { VariationUndoCard(undo: u) }
        if health.settled && health.snapshot.weightKg == nil && model.body.weightKg == nil {
            BodyPromptCard()
        }
        // Picked climbing weekdays set the count; the Health hint would be overridden.
        if profile.climbingDays.isEmpty, let perWeek = health.snapshot.climbingPerWeek4w {
            ClimbingSyncHint(healthPerWeek: perWeek, profileDays: profile.climbingDaysPerWeek) { n in
                var p = profile
                p.climbingDaysPerWeek = n
                model.updateProfile(p)
            }
        }
    }

    /// This week's sessions as a list or the Quest map (#227), with Add workout.
    @ViewBuilder private func thisWeek(plan: WeekPlan, profile: Profile, quest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("This week").eyebrow()
                Spacer()
                Button { addingDay = nil; adding = true } label: { Label("Add workout", systemImage: "plus") }
                    .font(Theme.label(13))
                    .foregroundStyle(Theme.lime)
            }
            let days = calendarDays
            // By day, so moved and extra sessions sit where they happen (#113).
            let ordered = byDay(plan.sessions, days: days)
            let missed = Set(model.missedSessions.map(\.id))
            if quest {
                QuestMap(sessions: ordered, days: days) { s, day in sessionMenu(s, day: day) }
            } else {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { i, s in
                    let done = model.state.done[s.id] ?? false
                    let day = s.weekday ?? days[s.id]
                    let removable = s.isPlanInsert && !done
                    NavigationLink(value: s.id) {
                        SessionRowCard(session: s, done: done, climbing: profile.climbingDays, weekday: day, number: i + 1,
                                       missed: missed.contains(s.id))
                    }
                    .buttonStyle(.plain)
                    .contextMenu { sessionMenu(s, day: day) }
                    // Swipe left on an added session to remove it (#176); ScrollView has no swipeActions.
                    .offset(x: swipe?.id == s.id ? swipe!.dx : 0)
                    .background(alignment: .trailing) {
                        if removable, swipe?.id == s.id {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundStyle(.white)
                                .frame(width: 64)
                                .frame(maxHeight: .infinity)
                                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.red.gradient))
                        }
                    }
                    .simultaneousGesture(removable ? swipeToRemove(s) : nil)
                    .accessibilityAction(named: removeTitle(s)) { if removable { removing = s } }
                }
            }
            Text(quest
                 ? "Tap a stage to open it. Touch and hold to move it to another day or remove an added one."
                 : ordered.contains { $0.isPlanInsert }
                 ? "Touch and hold a session to move it to another day this week. Swipe left on an added session to remove it."
                 : "Touch and hold a session to move it to another day this week.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }

    /// Sessions still to do in the next 4 weeks (Calendar button).
    private var plannedCount: Int {
        model.calendarWeeks(count: 4).reduce(0) { $0 + $1.plan.sessions.filter { !model.doneIds.contains($0.id) }.count }
    }

    /// Weekday of each session as the training calendar places it: unscheduled plans (no gym or climbing days
    /// picked) still show the day on each card.
    private var calendarDays: [String: Int] {
        let sessions = model.calendarWeeks(count: 1).first?.plan.sessions ?? []
        return Dictionary(sessions.compactMap { s in s.weekday.map { (s.id, $0) } }, uniquingKeysWith: { a, _ in a })
    }
}

/// Gradient button in the Train header row (equal widths): icon tile, title, one-line detail.
private struct HeaderChip: View {
    let symbol: String
    let title: String
    let detail: String
    let gradient: LinearGradient

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.25)))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.display(14))
                Text(detail).font(.system(size: 10, weight: .bold, design: .rounded)).opacity(0.9)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.leading, 7)
        .padding(.trailing, 6)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(gradient))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Compact week + readiness card (#246, design C): done ring, readiness verdict as headline on a card that fades
/// from the phase colour into the readiness colour, week bar. No readiness → phase as headline, Connect Health row.
private struct WeekHero: View {
    let plan: WeekPlan
    let profile: Profile
    let done: Int
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var explainingPhase = false
    @State private var explainingReadiness = false

    /// Explore-style colour per cycle phase, its one-word job and its rule.
    private var phase: (palette: WorkoutEngine.Category, title: String, rule: String) {
        switch Generator.phaseIndex(plan.week) {
        case 0: (.cardio, "Ease in", "RPE −1")
        case 1: (.strength, "Build", "Target RPE")
        case 2: (.power, "Peak week", "+1 set on main lifts")
        default: (.stretch, "Recover", "−40% volume")
        }
    }

    var body: some View {
        let p = phase
        let readiness = Readiness.assess(health.snapshot)
        HStack(spacing: 12) {
            DoneRing(done: done, total: plan.sessions.count)
            VStack(alignment: .leading, spacing: 2) {
                Button { explainingPhase = true } label: {
                    HStack(spacing: 4) {
                        Text(readiness == nil
                             ? "Week \(plan.week) of \(Generator.mesocycleWeeks) · \(Generator.phaseName(plan.week)) · \(p.rule)"
                             : "\(p.title) · W\(plan.week)/\(Generator.mesocycleWeeks) · \(p.rule)")
                            .tracking(1.1).lineLimit(1).minimumScaleFactor(0.7)
                        Image(systemName: "info.circle.fill")
                    }
                    .font(Theme.label(10))
                    .textCase(.uppercase)
                    .opacity(0.9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Explains this week's training phase")
                if let assessed = readiness {
                    let r = assessed.0
                    Button { explainingReadiness = true } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.title).font(Theme.display(21)).lineLimit(1).minimumScaleFactor(0.7)
                            Text(model.readinessEased ? "Today's session eased: −1 RPE, 1 set less" : r.markers(health.snapshot))
                                .font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Readiness: \(r.title)")
                    .accessibilityHint("Explains readiness and each marker")
                    .sheet(isPresented: $explainingReadiness) {
                        ReadinessSheet(snapshot: health.snapshot, readiness: r, flags: assessed.1).presentationDetents([.large])
                    }
                } else {
                    Text(p.title).font(Theme.display(21)).lineLimit(1).minimumScaleFactor(0.7)
                    if health.available, health.settled, !health.connected {
                        Button { Task { await health.connect() } } label: {
                            Label("Connect Health for readiness", systemImage: "heart.fill")
                                .font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.75)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Asks Apple Health for heart rate variability, resting heart rate and sleep")
                    } else {
                        Text("\(plan.sessions.count) sessions · \(plan.sessionMinutes) min").font(.caption.weight(.semibold))
                    }
                }
                HStack(spacing: 4) {
                    ForEach(1...Generator.mesocycleWeeks, id: \.self) { w in
                        // A running programme sets the week (#255): the bar only shows it.
                        Button { model.setWeek(w) } label: {
                            Capsule()
                                .fill(.white.opacity(w == plan.week ? 1 : w < plan.week ? 0.55 : 0.3))
                                .frame(height: 4)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.runningProgramme != nil)
                        .accessibilityLabel("Week \(w)")
                    }
                }
                .padding(.bottom, -6)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(
            LinearGradient(colors: p.palette.colors + (readiness?.0.colors ?? []), startPoint: .leading, endPoint: .trailing)))
        .sheet(isPresented: $explainingPhase) { WeekPhaseSheet(week: plan.week).presentationDetents([.large]) }
    }
}

/// Sessions done this week as a ring with the count inside.
struct DoneRing: View {
    let done: Int
    let total: Int

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.3), lineWidth: 6)
            Circle()
                .trim(from: 0, to: total > 0 ? min(1, CGFloat(done) / CGFloat(total)) : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -1) {
                Text("\(done)/\(total)").font(Theme.display(15)).monospacedDigit()
                Text("DONE").font(Theme.label(7)).tracking(1)
            }
        }
        .frame(width: 54, height: 54)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total) sessions done")
    }
}

private struct NextUpCard: View {
    let session: Session
    /// Day picked in the strip (#277); nil = this is the next session.
    var picked: Int? = nil
    var onPick: (Int) -> Void = { _ in }
    var onBack: () -> Void = {}
    let onStart: () -> Void
    @Environment(AppModel.self) private var model
    @State private var logging: ClimbLog?

    /// Climbers get Log climb next to Start workout (#277, design A).
    private var climber: Bool { model.profile.map(Generator.isClimber) ?? false }

    private var lead: WorkoutEngine.Category {
        session.blocks.first { $0.kind == .strength }?.kind.category ?? .strength
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The week at a glance (#266): missed days red (tap to catch up), today ringed; any other day shows here (#277).
            WeekDayStrip(selected: picked ?? session.weekday, onPick: onPick)
            // Tapping the card opens the session page, same as the list button (#150).
            NavigationLink(value: session.id) {
                summary
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the session overview")
            actions
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [lead.colors[0].opacity(0.85), lead.colors[1].opacity(0.55), Theme.bg], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
        .sheet(item: $logging) { LogClimbView(initial: $0) }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(eyebrow).font(Theme.label(12)).tracking(1.4).foregroundStyle(.white.opacity(0.8))
                    Text(session.displayTitle).font(Theme.display(30)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Label("\(session.estMin) min", systemImage: "clock.fill").font(Theme.label(14)).foregroundStyle(.white.opacity(0.9))
                        // XP it earns (#227).
                        Text("+\(model.xp(for: session)) XP").font(Theme.label(13)).foregroundStyle(Theme.lime)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.ink.opacity(0.85)))
                    }
                }
                Spacer(minLength: 8)
                BodyMapView(side: .front, heat: session.muscleHeat, showLabel: false)
                    .frame(width: 70, height: 140)
            }
            FlowLayout(spacing: 6) {
                ForEach(session.topMuscles(4)) { MuscleChip(muscle: $0) }
            }
            BlockStripe(blocks: session.blocks)
        }
        .contentShape(Rectangle())
    }

    private var done: Bool { model.doneIds.contains(session.id) }
    private var isNext: Bool { session.id == model.nextSession?.id }

    private var eyebrow: String {
        guard let d = picked else { return "Next up · \(model.upcomingDayLabel(session))" }
        let state = done ? "done" : model.missedSessions.contains { $0.id == session.id } ? "missed"
            : isNext ? "next up" : d == model.todayWeekday ? "today" : "planned"
        return "\(WeekSchedule.name(d)) · \(state)"
    }

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if done {
                    NavigationLink(value: session.id) { Label("Done · see workout", systemImage: "checkmark.seal.fill") }
                        .buttonStyle(LimeButtonStyle())
                } else {
                    Button(action: onStart) {
                        Label(model.activeWorkout(session.id) == nil ? "Start workout" : "Resume workout", systemImage: "play.fill")
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .buttonStyle(LimeButtonStyle())
                }
                // The card itself opens the overview, so Log climb takes the list button's place for climbers.
                if climber {
                    LogClimbButton { logging = ClimbLog(start: Date().addingTimeInterval(-90 * 60)) }
                } else {
                    overviewLink
                }
            }
            if picked != nil && !isNext, let next = model.nextSession {
                BackToNextUpButton(label: "Back to next up (\(WeekSchedule.shortName(next.weekday ?? 1)))", action: onBack)
            } else if picked != nil && !isNext {
                BackToNextUpButton(label: "Back to this week", action: onBack)
            }
        }
    }

    private var overviewLink: some View {
        HStack(spacing: 10) {
            NavigationLink(value: session.id) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.white.opacity(0.15)))
            }
            .accessibilityLabel("Session overview")
        }
    }
}

/// "Back to next up" under a day picked in the strip (#277).
private struct BackToNextUpButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: "arrow.left")
                .font(Theme.label(14))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }
}

/// A rest day picked in the strip (#277): nothing planned, offer to add a workout.
private struct RestDayCard: View {
    let weekday: Int
    var onPick: (Int) -> Void = { _ in }
    var onBack: () -> Void = {}
    let onAdd: () -> Void
    @Environment(AppModel.self) private var model
    @State private var logging: ClimbLog?

    /// A climbing day of a climber: Log climb next to Add workout.
    private var climbing: Bool {
        guard let p = model.profile, Generator.isClimber(p) else { return false }
        return p.climbingDays.contains(weekday)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WeekDayStrip(selected: weekday, onPick: onPick)
            Text("\(WeekSchedule.name(weekday)) · \(climbing ? "climbing day" : "rest day")").font(Theme.label(12)).tracking(1.4).foregroundStyle(.white.opacity(0.8))
            VStack(spacing: 6) {
                Text(climbing ? "Climbing day 🧗" : "Rest day 😴").font(Theme.display(26)).foregroundStyle(.white)
                Text(climbing ? "No gym session planned. Log your climb, or add a workout." : "Nothing planned. Fancy a session?")
                    .font(.footnote).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button(action: onAdd) { Label("Add workout", systemImage: "plus").lineLimit(1).minimumScaleFactor(0.75) }
                        .buttonStyle(LimeButtonStyle())
                    if climbing {
                        LogClimbButton { logging = ClimbLog(start: Date().addingTimeInterval(-90 * 60)) }
                    }
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            }
            BackToNextUpButton(label: model.nextSession.map { "Back to next up (\(WeekSchedule.shortName($0.weekday ?? 1)))" } ?? "Back to this week",
                               action: onBack)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x3D4BD6).opacity(0.85), Color(hex: 0x5A2FA0).opacity(0.6), Theme.bg],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
        .sheet(item: $logging) { LogClimbView(initial: $0) }
    }
}

/// Orange Log climb button beside the card's main action (#277, design A).
private struct LogClimbButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Log climb", systemImage: "figure.climbing")
                .font(Theme.label(15))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0xFF6B3D), Color(hex: 0xFFA94D)],
                                                          startPoint: .leading, endPoint: .trailing)))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Log a climbing session")
    }
}

private struct WeekCompleteCard: View {
    /// Missed sessions this week (#266): the week is over for training, not complete.
    var missed = 0
    /// A day tapped in the strip (#277).
    var onPick: (Int) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 10) {
            WeekDayStrip(onPick: onPick).padding(.bottom, 6)
            Image(systemName: missed > 0 ? "moon.zzz.fill" : "trophy.fill").font(.system(size: 44)).foregroundStyle(Theme.lime)
                .symbolEffect(.bounce, options: .repeat(2))
            Text(missed > 0 ? "No more sessions this week" : "Week complete").font(Theme.display(28))
                .multilineTextAlignment(.center)
            Text(missed > 0 ? "\(missed) missed: tap the red day to log it, mark it done or do it today. A fresh week starts Monday."
                            : "A fresh week starts Monday. Rest and climb meanwhile.").font(.footnote).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 24)
    }
}

struct SessionRowCard: View {
    let session: Session
    let done: Bool
    /// Climbing weekdays, for the "climbing tomorrow" hint on weekday-scheduled sessions.
    var climbing: [Int] = []
    /// Day shown on the card; defaults to the session's scheduled weekday.
    var weekday: Int?
    /// Position in the list; defaults to the session's plan index.
    var number: Int?
    /// Planned on an earlier day this week and not done (#266).
    var missed = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(String(format: "%02d", number ?? session.index + 1))
                .font(Theme.display(34))
                .foregroundStyle(done ? Theme.lime : .white.opacity(0.9))
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(session.displayTitle).font(.system(.headline, design: .rounded).weight(.heavy))
                    Spacer()
                    if done {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.lime)
                    } else if missed {
                        Text("MISSED").font(Theme.label(11)).tracking(1).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(MissedStyle.gradient))
                    } else {
                        Text("\(session.estMin)′").font(Theme.label(14)).foregroundStyle(Theme.muted)
                    }
                }
                if let day = weekday ?? session.weekday {
                    SessionDayLine(weekday: day, climbing: climbing)
                }
                BlockStripe(blocks: session.blocks, height: 6)
                Text(session.topMuscles(4).map(\.name).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        .card()
        .opacity(done ? 0.7 : 1)
    }
}

/// Weekday of a scheduled session, plus how it sits relative to climbing days.
struct SessionDayLine: View {
    let weekday: Int
    let climbing: [Int]
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Text(WeekSchedule.name(weekday).uppercased())
                .font(Theme.label(12))
                .tracking(1)
                .foregroundStyle(Theme.lime)
            if let away = model.awayThisWeek(weekday), away.kind == .travel {
                Label(away.title, systemImage: "airplane")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WorkoutEngine.Category.cardio.color)
                    .lineLimit(1)
            } else if let note = WeekSchedule.note(weekday: weekday, climbing: climbing, prefs: model.profile?.climbPrefs ?? ClimbPrefs()) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
    }
}

/// Shown after applying a variation (#98): what changed, Undo.
private struct VariationUndoCard: View {
    let undo: VariationUndo
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shuffle")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.22)))
            Text(undo.days == 0 ? "Back to the original plan" : "New variation on \(undo.days) day\(undo.days == 1 ? "" : "s")")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
            Spacer()
            Button("Undo") { withAnimation { model.undoVariation() } }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.white))
                .foregroundStyle(Theme.ink)
            Button { withAnimation { model.variationUndo = nil } } label: {
                Image(systemName: "xmark").font(.footnote.bold()).opacity(0.8)
            }
            .accessibilityLabel("Dismiss")
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(WorkoutEngine.Category.warmup.gradient))
    }
}
