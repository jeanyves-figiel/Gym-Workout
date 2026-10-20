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
    /// Week chest opened without its reveal (Watch or logged workout, #476).
    @State private var chestReveal = false
    /// Height the Train screen shows between the safe areas: short phones get a tighter Next up (#337).
    @State private var visibleHeight: CGFloat = 800
    /// CI screenshots: open in edit mode.
    var demoEditing = false
    /// Demo screens train-day-picked / train-rest-day (#277): a later planned day or a rest day picked in the strip.
    var demoPick: DemoPick?
    enum DemoPick { case planned, rest }

    var body: some View {
        ScrollView {
            if let plan = model.plan, let profile = model.profile {
                // 14 pt between widgets (#337): Next up's Start workout stays above the tab bar.
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if arranging {
                        TrainEditBar(onAdd: { addingWidget = true }, onList: { customising = true })
                    }
                    // New week made with what the app learned (#299): the coach says what changed.
                    if !arranging, let recap = model.tasteRecap { TasteRecapCard(recap: recap) }
                    // A new block (#495): what the last 4 weeks brought and what the next block changes.
                    if !arranging, let review = model.blockReview { BlockReviewCard(review: review) }
                    // What Monkey noticed this week (#495): one slim bar, the growth path behind it.
                    if !arranging {
                        let notices = model.noticedBar
                        if !notices.isEmpty { NoticedBar(insights: notices) }
                    }
                    // Kind streaks (#501): welcome back, Comeback quest, a shield that saved last week.
                    if !arranging { KindStreakCards() }
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
                        HStack(spacing: 8) {
                            Label(e, systemImage: "icloud.slash").font(.footnote).foregroundStyle(Theme.muted)
                            Spacer(minLength: 4)
                            ReportErrorButton(error: e, area: "Sync & account")
                        }
                    }
                }
                .padding(16)
                .animation(.snappy, value: model.trainLayout.widgets)
            } else {
                ContentUnavailableView("No plan yet", systemImage: "calendar.badge.plus")
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height - $0.safeAreaInsets.top - $0.safeAreaInsets.bottom } action: { visibleHeight = $0 }
        .environment(\.trainCompact, visibleHeight < 670)
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .statusBarScrim()
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
        .fullScreenCover(isPresented: $chestReveal) {
            ChestReveal(sessions: Progression.stats(records: model.state.history, weights: [], targetPerWeek: model.gameTarget).thisWeek) {
                chestReveal = false
            }
            .presentationBackground(.clear)
        }
        .onChange(of: model.state.history.count) { revealChestIfNeeded() }
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
            resumeInterruptedOnce()
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
            revealChestIfNeeded()
            // MonkeyGrade climbs feed the climbing widget's hard-climb note (#521: the widget may not be on screen).
            let mg = MonkeyGradeLink.shared
            if mg.isConnected(for: model.user?.id) { await mg.refresh() }
        }
    }

    /// Opens the week chest the member hasn't seen open yet (#476); never over the player.
    private func revealChestIfNeeded() {
        #if DEBUG
        if Demo.enabled { return }
        #endif
        guard playing == nil, !chestReveal, model.chestRevealPending else { return }
        model.markChestSeen()
        chestReveal = true
    }

    /// Next up (#266), or the day picked in its strip (#277): that day's workout, or a rest day with Add workout.
    @ViewBuilder private func nextUpCard(_ plan: WeekPlan) -> some View {
        let next = model.nextSession
        let pick: (Int) -> Void = { wd in
            withAnimation(.snappy) { pickedDay = pickedDay == wd || (pickedDay == nil && next?.weekday == wd) ? nil : wd }
        }
        let back = { withAnimation(.snappy) { pickedDay = nil } }
        if let d = pickedDay, !(1...7).contains(d) {
            // A day of another week (#481) shows in the card too, never as a pop-up.
            otherWeekCard(d, pick: pick, back: back)
        } else if let d = pickedDay, let s = plan.sessions.first(where: { $0.weekday == d }) {
            NextUpCard(session: s, picked: d, onPick: pick, onBack: back) { playing = s }
        } else if let d = pickedDay {
            RestDayCard(weekday: d, onPick: pick, onBack: back) { addingDay = d; adding = true }
        } else if let next {
            NextUpCard(session: next, picked: nil, onPick: pick, onBack: back) { playing = next }
        } else if let later = model.nextWeekSession() {
            // This week has nothing left (#473): Next up is next week's first session, shown, not startable.
            NextUpCard(session: later.session, later: later.day, onPick: pick, onBack: back) {}
        } else {
            WeekCompleteCard(missed: model.missedToHandle.count, onPick: pick)
        }
    }

    /// Day `d` of a later week (planned session or rest day) or of last week (#481); `d` counts from this week's Monday.
    @ViewBuilder private func otherWeekCard(_ d: Int, pick: @escaping (Int) -> Void, back: @escaping () -> Void) -> some View {
        let cal = model.planCalendar
        let date = cal.date(byAdding: .day, value: d - 1, to: Progression.weekStart(Date(), cal)) ?? Date()
        let week = Int((Double(d - 1) / 7).rounded(.down))
        let wd = d - week * 7
        if week > 0 {
            let weeks = model.calendarWeeks(count: 3)
            if week < weeks.count, let s = weeks[week].plan.sessions.first(where: { $0.weekday == wd }) {
                NextUpCard(session: s, picked: d, later: DaySelection(week: weeks[week], weekday: wd, current: false),
                           onPick: pick, onBack: back) {}
            } else {
                RestDayCard(weekday: wd, day: d, date: date, onPick: pick, onBack: back) {}
            }
        } else {
            PastDayCard(day: d, date: date, onPick: pick, onBack: back)
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
                SettingsAvatar()
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
        let planned = plannedCount
        return HStack(spacing: 8) {
            NavigationLink { CalendarView() } label: {
                HeaderChip(symbol: "calendar", title: "Calendar", detail: "\(planned) planned",
                           gradient: WorkoutEngine.Category.strength.gradient)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Calendar, \(planned) sessions planned in the next 4 weeks")
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
            if small { CoachSmallWidget() } else { MonkeyCoachCard { playing = $0 } }
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
                    // Sport prep on a planned sport day (#523).
                    if !arranging { SportPrepBar() }
                    if !arranging { notices(plan: plan, profile: profile, undo: false) }
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    if !arranging, let undo = model.variationUndo { VariationUndoCard(undo: undo) }
                    NextUpCompactWidget(session: model.nextSession, wide: !small) { playing = $0 }
                        .frame(maxHeight: small ? .infinity : nil, alignment: .top)
                    if !arranging, !small { SportPrepBar() }
                    if !arranging, !small { notices(plan: plan, profile: profile, undo: false) }
                }
            }
        case .climbing:
            if small {
                ClimbSmallWidget()
            } else if Generator.isClimber(profile) {
                ClimbSection(arranging: arranging)
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
        case .move:
            MoveWidget(size: w.size, arranging: arranging)
        case .fuel:
            FuelWidget(size: w.size)
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
        let done = model.doneIds
        return model.calendarWeeks(count: 4).reduce(0) { $0 + $1.plan.sessions.filter { !done.contains($0.id) }.count }
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
    /// Daily auto-tune (#495): today's score, level, sore muscles and changes.
    @State private var tuning = false

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
            DoneRing(done: done, total: plan.sessions.count, size: 48)
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
                    let tuned = model.tuneOn ? model.tuneChanges.count : 0
                    let markers = Text(tuned > 0 ? "Monkey tuned today: \(tuned) change\(tuned == 1 ? "" : "s") ›"
                                       : model.readinessEased ? "Today's session eased: −1 RPE, 1 set less" : r.markers(health.snapshot))
                        .font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1)
                    Button { if model.tuneOn { tuning = true } else { explainingReadiness = true } } label: {
                        // Verdict and markers on one line when they fit (#337), else stacked.
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(r.title).font(Theme.display(19)).lineLimit(1)
                                markers
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.title).font(Theme.display(19)).lineLimit(1).minimumScaleFactor(0.7)
                                markers.minimumScaleFactor(0.75)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Readiness: \(r.title)")
                    .accessibilityHint(model.tuneOn ? "Shows today's ready score and what Monkey tuned" : "Explains readiness and each marker")
                    .sheet(isPresented: $explainingReadiness) {
                        ReadinessSheet(snapshot: health.snapshot, readiness: r, flags: assessed.1).presentationDetents([.large])
                    }
                } else {
                    Text(p.title).font(Theme.display(19)).lineLimit(1).minimumScaleFactor(0.7)
                    if health.available, health.settled, !health.connected {
                        Button { Task { await health.connect() } } label: {
                            Label("Connect Health for readiness", systemImage: "heart.fill")
                                .font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.75)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Asks Apple Health for heart rate variability, resting heart rate and sleep")
                    } else if model.tuneOn {
                        Button { tuning = true } label: {
                            let n = model.tuneChanges.count
                            Text("\(plan.sessions.count) sessions · " + (n > 0 ? "tuned: \(n) change\(n == 1 ? "" : "s") ›" : "Tune today ›"))
                                .font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.75)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Tap sore muscles or pick light, medium or push for today's workout")
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
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(
            LinearGradient(colors: p.palette.colors + (readiness?.0.colors ?? []), startPoint: .leading, endPoint: .trailing)))
        .sheet(isPresented: $explainingPhase) { WeekPhaseSheet(week: plan.week).presentationDetents([.large]) }
        .sheet(isPresented: $tuning) { AutoTuneSheet().presentationDetents([.large]) }
    }
}

/// Sessions done this week as a ring with the count inside.
struct DoneRing: View {
    let done: Int
    let total: Int
    var size: CGFloat = 54

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
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total) sessions done")
    }
}

private struct NextUpCard: View {
    let session: Session
    /// Day picked in the strip (#277); nil = this is the next session.
    var picked: Int? = nil
    /// Day of a later week (#473): its session is shown (opens the calendar day sheet), not started.
    var later: DaySelection? = nil
    var onPick: (Int) -> Void = { _ in }
    var onBack: () -> Void = {}
    let onStart: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.trainCompact) private var compact
    @State private var logging: SportLog?
    @State private var trackingSport: SportLog?
    /// Build as I go (#490): the empty workout open in the player.
    @State private var freestyle: Session?
    @State private var laterDay: DaySelection?
    @State private var moving = false
    /// Plan sport on a later day with a workout (#481); or the dated sport day / trip on it.
    @State private var planningSport = false
    @State private var editingTrip: SportTrip?
    /// A later day picked in the strip (#343): nothing can be started or logged in advance.
    private var ahead: Bool { later != nil || (picked.map { $0 > model.todayWeekday } ?? false) }

    /// This card's day counted from this week's Monday (#481), for the strip.
    private var stripDay: Int? {
        if let picked { return picked }
        guard let later else { return session.weekday }
        let cal = model.planCalendar
        let weeks = cal.dateComponents([.day], from: Progression.weekStart(Date(), cal), to: later.week.start).day.map { Int((Double($0) / 7).rounded()) } ?? 0
        return weeks * 7 + later.weekday
    }

    /// Day key of the session's day ("2026-10-22").
    private var dayKey: String? {
        let cal = model.planCalendar
        if let later { return later.week.days[later.weekday - 1] }
        guard let wd = session.weekday, let day = cal.date(byAdding: .day, value: wd - 1, to: Progression.weekStart(Date(), cal)) else { return nil }
        return PlanCalendar.key(day, cal)
    }

    private var lead: WorkoutEngine.Category {
        session.blocks.first { $0.kind == .strength }?.kind.category ?? .strength
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The week at a glance (#266): missed days red (tap to catch up), today ringed; any other day shows here (#277).
            WeekDayStrip(selected: stripDay, onPick: onPick)
            // Tapping the card opens the session page, same as the list button (#150).
            if let later {
                Button { laterDay = later } label: { summary }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the day")
            } else {
                NavigationLink(value: session.id) {
                    summary
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the session overview")
            }
            actions
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [lead.colors[0].opacity(0.85), lead.colors[1].opacity(0.55), Theme.bg], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
        .sheet(item: $logging) { LogSportView(initial: $0) }
        .sheet(item: $trackingSport) { LogSportView(initial: $0, live: true) }
        .fullScreenCover(item: $freestyle) { WorkoutPlayerView(sessionId: $0.id) }
        .modifier(LaterDaySheets(day: $laterDay))
        .sheet(isPresented: $moving) { MoveSessionSheet(sessionId: session.id) }
        .sheet(isPresented: $planningSport) { PlanSportSheet(day: dayKey ?? PlanCalendar.key(Date(), model.planCalendar), sport: model.profile?.otherSports.first?.sport) }
        .sheet(item: $editingTrip) { PlanSportSheet(day: $0.start, editing: $0) }
    }

    /// Slim (#337, design A): muscle chips sit in the text column beside a smaller figure, so Start workout stays
    /// above the tab bar. Short phones drop the figure, chips and block stripe.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow).font(Theme.label(12)).tracking(1.4).foregroundStyle(.white.opacity(0.8))
                    Text(session.displayTitle).font(Theme.display(compact ? 26 : 30)).foregroundStyle(.white)
                        .lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Label("\(session.estMin) min", systemImage: "clock.fill").font(Theme.label(14)).foregroundStyle(.white.opacity(0.9))
                        // XP it earns (#227).
                        Text("+\(model.xp(for: session)) XP").font(Theme.label(13)).foregroundStyle(Theme.lime)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.ink.opacity(0.85)))
                    }
                    if !compact {
                        // As many of the top muscles as fit on one line.
                        ViewThatFits(in: .horizontal) {
                            muscleChips(3)
                            muscleChips(2)
                            muscleChips(1)
                        }
                    }
                }
                Spacer(minLength: 8)
                if !compact {
                    BodyMapView(side: .front, heat: session.muscleHeat, showLabel: false)
                        .frame(width: 55, height: 110)
                }
            }
            if !compact { BlockStripe(blocks: session.blocks) }
        }
        .contentShape(Rectangle())
    }

    private func muscleChips(_ n: Int) -> some View {
        HStack(spacing: 6) { ForEach(session.topMuscles(n)) { MuscleChip(muscle: $0) } }
    }

    private var done: Bool { model.doneIds.contains(session.id) }
    private var isNext: Bool { session.id == model.nextSession?.id }

    private var eyebrow: String {
        if let later, let date = later.week.date(later.weekday, model.planCalendar) {
            let day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            return picked == nil ? "Next up · \(day)" : "\(day) · planned"
        }
        guard let d = picked else { return "Next up · \(model.upcomingDayLabel(session))" }
        let state = done ? "done" : model.skippedIds.contains(session.id) ? "skipped"
            : model.missedSessions.contains { $0.id == session.id } ? "missed"
            : isNext ? "next up" : d == model.todayWeekday ? "today" : "planned"
        return "\(WeekSchedule.name(d)) · \(state)"
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Group {
                if let later {
                    Button { laterDay = later } label: { Label("See workout", systemImage: "list.bullet") }
                        .buttonStyle(LimeButtonStyle())
                } else if done {
                    NavigationLink(value: session.id) { Label("Done · see workout", systemImage: "checkmark.seal.fill") }
                        .buttonStyle(LimeButtonStyle())
                } else if ahead {
                    // A later day (#343): only its overview.
                    NavigationLink(value: session.id) { Label("See workout", systemImage: "list.bullet") }
                        .buttonStyle(LimeButtonStyle())
                } else {
                    Button(action: onStart) {
                        Label(model.activeWorkout(session.id) == nil ? "Start workout" : "Resume workout", systemImage: "play.fill")
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .buttonStyle(LimeButtonStyle())
                }
            }
            // Start workout gets the full width; sports sit under it in one split pill (#462, design C).
            if !ahead {
                SportSplitPill(onFree: { freestyle = model.freestyleInProgress ?? model.startFreestyle() },
                               freeResumes: model.freestyleInProgress != nil,
                               onLog: { logging = SportLog(start: Date().addingTimeInterval(-120 * 60)) },
                               onTrack: { trackingSport = SportLog(start: Date()) })
            } else if !done {
                // A later day with a workout (#481, design A): plan a sport there too, or move the workout (this week).
                HStack(spacing: 10) {
                    if let trip = dayKey.flatMap({ model.profile?.sportTrip(on: $0) }) {
                        Button { editingTrip = trip } label: {
                            Label(trip.title, systemImage: trip.sport.symbol).lineLimit(1).minimumScaleFactor(0.7)
                                .font(Theme.label(14)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Capsule().fill(trip.sport.gradient))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { planningSport = true } label: {
                            Label("Plan a sport", systemImage: "figure.skiing.downhill").lineLimit(1).minimumScaleFactor(0.7)
                                .font(Theme.label(14)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0xFF5F8F), Color(hex: 0xFF9A5C)], startPoint: .leading, endPoint: .trailing)))
                        }
                        .buttonStyle(.plain)
                    }
                    if later == nil {
                        Button { moving = true } label: {
                            Label("Move", systemImage: "arrow.left.arrow.right").lineLimit(1)
                                .font(Theme.label(14)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Capsule().fill(Color.white.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if picked != nil && !isNext, let next = model.nextSession {
                BackToNextUpButton(label: backLabel(next), action: onBack)
            } else if picked != nil && !isNext {
                BackToNextUpButton(label: "Back to this week", action: onBack)
            }
        }
    }
}

/// A day of last week picked in the strip (#481): what was trained that day, with History one tap away.
private struct PastDayCard: View {
    /// Strip day counted from this week's Monday (0 and below).
    let day: Int
    let date: Date
    var onPick: (Int) -> Void = { _ in }
    var onBack: () -> Void = {}
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var showsHistory = false

    var body: some View {
        let cal = model.planCalendar
        let items = model.historyItems(health: health).filter { cal.isDate($0.start, inSameDayAs: date) }
        VStack(alignment: .leading, spacing: 14) {
            WeekDayStrip(selected: day, onPick: onPick)
            Text("\(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) · \(items.isEmpty ? "rest day" : "done")")
                .font(Theme.label(12)).tracking(1.4).foregroundStyle(.white.opacity(0.8))
            if items.isEmpty {
                Text("Rest day 😴").font(Theme.display(26)).foregroundStyle(.white)
            } else {
                ForEach(items) { it in
                    Text(it.title).font(Theme.display(26)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            Button { showsHistory = true } label: { Label("See in History", systemImage: "clock.arrow.circlepath") }
                .buttonStyle(LimeButtonStyle())
            BackToNextUpButton(label: model.nextSession.map(backLabel) ?? "Back to this week", action: onBack)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x3D4BD6).opacity(0.85), Color(hex: 0x5A2FA0).opacity(0.6), Theme.bg],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
        .sheet(isPresented: $showsHistory) {
            NavigationStack { HistoryView().toolbar { CloseToolbarItem { showsHistory = false } } }
        }
    }
}

/// "Back to next up (Thu)"; no day for an unscheduled session.
private func backLabel(_ next: Session) -> String {
    next.weekday.map { "Back to next up (\(WeekSchedule.shortName($0)))" } ?? "Back to next up"
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
    /// Strip day counted from this week's Monday (#481); this week's weekday by default.
    var day: Int? = nil
    /// Date of a day in a later week (#481); nil = this week's weekday.
    var date: Date? = nil
    var onPick: (Int) -> Void = { _ in }
    var onBack: () -> Void = {}
    let onAdd: () -> Void
    @Environment(AppModel.self) private var model
    @State private var logging: ClimbLog?
    @State private var loggingSport: SportLog?
    @State private var trackingSport: SportLog?
    /// Build as I go (#490): the empty workout open in the player.
    @State private var freestyle: Session?
    /// Plan sport (#474): a sport once, every week or a trip from this day; or the dated day / trip on it.
    @State private var planningSport = false
    @State private var editingTrip: SportTrip?

    /// This day's key ("2026-10-21") in the current week.
    private var dayKey: String {
        let cal = model.planCalendar
        if let date { return PlanCalendar.key(date, cal) }
        let day = cal.date(byAdding: .day, value: weekday - 1, to: Progression.weekStart(Date(), cal)) ?? Date()
        return PlanCalendar.key(day, cal)
    }
    /// A dated sport day or trip on this day.
    private var trip: SportTrip? { model.profile?.sportTrip(on: dayKey) }

    /// Climbers get Log climb next to Add workout on every rest day (#304).
    private var climber: Bool { model.profile.map(Generator.isClimber) ?? false }
    /// One of the climber's planned climbing days.
    private var climbing: Bool { climber && (model.profile?.climbingDays.contains(weekday) ?? false) }
    /// A later day (#343): a workout can be planned, a climb is only logged on or after its day.
    private var ahead: Bool { date != nil || weekday > model.todayWeekday }
    /// A day of a later week (#481): Add workout only plans this week, so it's left out.
    private var laterWeek: Bool { date != nil }
    private var title: String {
        date.map { $0.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) } ?? WeekSchedule.name(weekday)
    }

    /// A climb logged from an earlier day this week is dated that day (18:00); otherwise it just ended.
    private func climbStart(now: Date = Date()) -> Date {
        let cal = model.planCalendar
        guard weekday < model.todayWeekday,
              let day = cal.date(byAdding: .day, value: weekday - 1, to: Progression.weekStart(now, cal)) else {
            return now.addingTimeInterval(-90 * 60)
        }
        return cal.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WeekDayStrip(selected: day ?? weekday, onPick: onPick)
            Text("\(title) · \(trip.map { $0.isTrip ? "sport trip" : "sport day" } ?? (climbing ? "climbing day" : "rest day"))").font(Theme.label(12)).tracking(1.4).foregroundStyle(.white.opacity(0.8))
            VStack(spacing: 6) {
                if let trip {
                    Button { editingTrip = trip } label: {
                        Label(trip.title, systemImage: trip.sport.symbol).font(Theme.display(24)).foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Capsule().fill(trip.sport.gradient))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit this sport day")
                } else {
                    Text(climbing ? "Climbing day 🧗" : "Rest day 😴").font(Theme.display(26)).foregroundStyle(.white)
                }
                Text(trip != nil ? (ahead ? "No gym that day. Log or track it on the day." : "No gym today. Log or track it.")
                     : laterWeek ? (climbing ? "Climb planned. Log it on the day." : "Nothing planned. Plan a sport?")
                     : ahead ? (climbing ? "Climb planned. Log it on the day, or plan a workout." : "Nothing planned. Plan a workout or a sport?")
                     : climbing ? "No gym session planned. Log your climb, or add a workout."
                     : climber ? "Nothing planned. Train or climb?" : "Nothing planned. Fancy a session?")
                    .font(.footnote).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    if !laterWeek {
                        Button(action: onAdd) { Label("Add workout", systemImage: "plus").lineLimit(1).minimumScaleFactor(0.75) }
                            .buttonStyle(LimeButtonStyle())
                    }
                    if climbing && !ahead {
                        LogClimbButton { logging = ClimbLog(start: climbStart()) }
                    }
                }
                .padding(.top, 6)
                if trip == nil && (laterWeek || weekday >= model.todayWeekday) {
                    // Plan sport (#474): once, every week or a trip from this day.
                    Button { planningSport = true } label: {
                        Label("Plan sport", systemImage: "figure.mixed.cardio").font(Theme.label(14)).foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Capsule().fill(Color.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                }
                if !climbing && !ahead {
                    // Any other sport (#416), dated like a climb; Track live with a Watch (#462, design C).
                    SportSplitPill(onFree: { freestyle = model.freestyleInProgress ?? model.startFreestyle() },
                                   freeResumes: model.freestyleInProgress != nil,
                                   onLog: { loggingSport = SportLog(start: climbStart()) },
                                   onTrack: { trackingSport = SportLog(start: Date()) })
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            }
            BackToNextUpButton(label: model.nextSession.map(backLabel) ?? "Back to this week",
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
        .sheet(item: $loggingSport) { LogSportView(initial: $0) }
        .sheet(item: $trackingSport) { LogSportView(initial: $0, live: true) }
        .fullScreenCover(item: $freestyle) { WorkoutPlayerView(sessionId: $0.id) }
        .sheet(isPresented: $planningSport) { PlanSportSheet(day: dayKey, sport: model.profile?.otherSports.first?.sport) }
        .sheet(item: $editingTrip) { PlanSportSheet(day: $0.start, editing: $0) }
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

private struct TrainCompactKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Train on a short phone (#337): Next up drops its figure, muscle chips and block stripe.
    var trainCompact: Bool {
        get { self[TrainCompactKey.self] }
        set { self[TrainCompactKey.self] = newValue }
    }
}

extension WeekView {
    @MainActor private static var checkedInterrupted = false

    /// First Train screen after launch (#359): iOS closed the app during a workout, so reopen the player where it was;
    /// otherwise clear a Live Activity such a run left on the lock screen.
    private func resumeInterruptedOnce() {
        guard !Self.checkedInterrupted, !model.demo else { return }
        Self.checkedInterrupted = true
        if let s = model.interruptedWorkout() { playing = s } else { LiveWorkout.endLeftovers() }
    }
}
