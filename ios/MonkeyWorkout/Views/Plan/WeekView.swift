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
    /// Date the pick was made on: a pick from an earlier day is dropped, so the strip reopens on today.
    @State private var pickedOn: String?
    @Environment(\.scenePhase) private var scenePhase
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
    /// Demo screens train-day-picked / train-rest-day (#277) / train-past-day (#592): a later planned day, a rest day
    /// or yesterday picked in the strip.
    var demoPick: DemoPick?
    enum DemoPick { case planned, rest, past }

    var body: some View {
        ScrollView {
            if let plan = model.plan, let profile = model.profile {
                // 14 pt between widgets (#337): Next up's Start workout stays above the tab bar.
                VStack(alignment: .leading, spacing: 14) {
                    header
                    // A newer build is out (#583, design A).
                    if !arranging { UpdateBanner() }
                    if arranging {
                        TrainEditBar(onAdd: { addingWidget = true }, onList: { customising = true })
                    }
                    // The member's widgets (#260); the default layout is the Train screen as it always was.
                    let layout = model.trainLayout
                    if !layout.contains(.nextUp), !arranging {
                        // Cards that only show for a while (#538) sit under Next up; on top when it was removed.
                        TrainNoticeSlot()
                        notices(plan: plan, profile: profile)
                    }
                    ForEach(layout.rows) { row in
                        switch row {
                        case .full(let w):
                            // The week card joins the Coach card (#564): no row of its own.
                            if !(w.kind == .week && weekInCoach) {
                                widget(w, plan: plan, profile: profile)
                            }
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
                            // A small Next up keeps the slot of passing cards (#538) right under its row.
                            if !arranging, a.kind == .nextUp || b?.kind == .nextUp { TrainNoticeSlot() }
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
                    .toolbar { CloseToolbarItem { editing = false } }
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
        // A pick never outlives its day: back on today after midnight or when the app comes back.
        .onChange(of: pickedDay) { pickedOn = pickedDay == nil ? nil : todayKey }
        .onChange(of: scenePhase) { if scenePhase == .active { dropStalePick() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in dropStalePick() }
        // Start on a Home Screen widget (#537): today's session straight in the player.
        .onChange(of: PlayerLaunch.shared.sessionId, initial: true) { _, id in
            guard let id else { return }
            PlayerLaunch.shared.sessionId = nil
            guard playing == nil, let s = model.session(id) else { return }
            start(s)
        }
        .proPaywall($gate)
        .sheet(item: $moving) { s in MoveSessionSheet(sessionId: s.id) }
        .sheet(isPresented: $adding) { AddWorkoutSheet(weekday: addingDay) }
        .navigationDestination(isPresented: $showingCalendar) { CalendarView() }
        .sheet(isPresented: $addingWidget) { TrainWidgetGallery() }
        .sheet(isPresented: $customising) { TrainCustomiseSheet() }
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
                pickedDay = demoPick == .past ? max(1, today - 1)
                    : demoPick == .rest
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

    private var todayKey: String { PlanCalendar.key(Date(), model.planCalendar) }

    private func dropStalePick() {
        guard pickedDay != nil, pickedOn != todayKey else { return }
        pickedDay = nil
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

    /// Today's rest-day card shows its sport block with Prep (#658): no separate prep or Wall session bar then.
    private func sportHeroToday(_ plan: WeekPlan) -> Bool {
        let today = model.todayWeekday
        // Today's card is a rest day: nothing on it or all skipped (#698), Next up later this week or next week.
        let next = model.nextSession?.weekday
        guard pickedDay == nil, !plan.sessions.contains(where: { $0.weekday == today }) || skippedOnly(plan, today) != nil,
              next.map({ $0 != today }) ?? (model.nextWeekSession() != nil) else { return false }
        return model.profile?.sport(onWeekday: today, key: PlanCalendar.key(Date(), model.planCalendar)) != nil
    }

    /// Today's prep and Wall session bars (#670) only while the card shows today, not under another picked day.
    private var showsToday: Bool { pickedDay.map { $0 == model.todayWeekday } ?? true }

    /// Next up (#266), or the day picked in its strip (#277): that day's workout, or a rest day with Add workout.
    @ViewBuilder private func nextUpCard(_ plan: WeekPlan) -> some View {
        let next = model.nextSession
        let today = model.todayWeekday
        // Nothing left this week (#698 follow-up): Next up is next week's first session, the card still opens on today.
        let later = next == nil ? model.nextWeekSession() : nil
        let laterDay = later.flatMap { l in l.day.week.date(l.day.weekday, model.planCalendar).flatMap { date in
            model.planCalendar.dateComponents([.day], from: Progression.weekStart(Date(), model.planCalendar), to: date).day.map { $0 + 1 }
        } }
        // Nothing picked = today (#538 follow-up): the strip and card open on today's date, not on a later session.
        let opensToday = (next.map { $0.weekday != nil && $0.weekday != today } ?? (laterDay != nil))
            && plan.sessions.contains { $0.weekday != nil }
        let pick: (Int) -> Void = { wd in
            withAnimation(.snappy) {
                let shown = pickedDay ?? (opensToday ? today : next?.weekday)
                // Today is the default card: picking it is no pick, so it never sticks to a later date.
                pickedDay = shown == wd || (opensToday && wd == today) ? nil : wd
            }
        }
        // From today's card, "Next up" shows the next session's day (next week's too); from any other day, back to today.
        let back = { withAnimation(.snappy) { pickedDay = pickedDay == nil && opensToday ? next?.weekday ?? laterDay : nil } }
        let nextTitle = next.flatMap { s in s.weekday.map { "\(WeekSchedule.shortName($0)) · \(s.displayTitle)" } }
            ?? later.map { "\(WeekSchedule.shortName($0.day.weekday)) · \($0.session.displayTitle)" }
        // Today skipped with nothing else on it (#698): a rest day with Unskip.
        let todaySkipped = skippedOnly(plan, today)
        Group {
            if pickedDay == nil, let skipped = todaySkipped {
                RestDayCard(weekday: today, onPick: pick, onBack: back, onAdd: { addingDay = today; adding = true },
                            backTitle: nextTitle ?? "This week", skipped: skipped)
            } else if pickedDay == nil, opensToday {
                if let s = plan.sessions.first(where: { $0.weekday == today && !model.skippedIds.contains($0.id) })
                    ?? plan.sessions.first(where: { $0.weekday == today }) {
                    NextUpCard(session: s, picked: today, onPick: pick, onBack: back) { start(s) }
                } else {
                    RestDayCard(weekday: today, onPick: pick, onBack: back,
                                onAdd: { addingDay = today; adding = true }, backTitle: nextTitle)
                }
            } else if let d = pickedDay, !(1...7).contains(d) {
                // A day of another week (#481) shows in the card too, never as a pop-up.
                otherWeekCard(d, pick: pick, back: back)
            } else if let d = pickedDay, d < today, plan.sessions.first(where: { $0.weekday == d }).map({ model.activeWorkout($0.id) == nil }) ?? true {
                // Every earlier day gets the same card (#592): what was logged, a missed session, add what was forgotten.
                let cal = model.planCalendar
                PastDayCard(day: d, date: cal.date(byAdding: .day, value: d - 1, to: Progression.weekStart(Date(), cal)) ?? Date(),
                            session: plan.sessions.first { $0.weekday == d }, onPick: pick, onBack: back)
            } else if let d = pickedDay, let skipped = skippedOnly(plan, d) {
                RestDayCard(weekday: d, onPick: pick, onBack: back, onAdd: { addingDay = d; adding = true }, skipped: skipped)
            } else if let d = pickedDay, let s = plan.sessions.first(where: { $0.weekday == d && !model.skippedIds.contains($0.id) })
                        ?? plan.sessions.first(where: { $0.weekday == d }) {
                NextUpCard(session: s, picked: d, onPick: pick, onBack: back) { start(s) }
            } else if let d = pickedDay {
                RestDayCard(weekday: d, onPick: pick, onBack: back) { addingDay = d; adding = true }
            } else if let next {
                NextUpCard(session: next, picked: nil, onPick: pick, onBack: back) { start(next) }
            } else if let later = model.nextWeekSession() {
                // This week has nothing left (#473): Next up is next week's first session, shown, not startable.
                NextUpCard(session: later.session, later: later.day, onPick: pick, onBack: back)
            } else {
                WeekCompleteCard(missed: model.missedToHandle.count, onPick: pick)
            }
        }
        // Back goes to today then, so the button says so (not "Back to next up (Thu)").
        .environment(\.trainBackToToday, opensToday && pickedDay != nil)
    }

    /// This week's day `wd` from today on whose workouts were all skipped (#698): those workouts, the day shows as a rest day.
    private func skippedOnly(_ plan: WeekPlan, _ wd: Int) -> [Session]? {
        guard wd >= model.todayWeekday else { return nil }
        let day = plan.sessions.filter { $0.weekday == wd }
        let off = day.allSatisfy { model.skippedIds.contains($0.id) && !model.doneIds.contains($0.id) && model.activeWorkout($0.id) == nil }
        return !day.isEmpty && off ? day : nil
    }

    /// Day `d` of a later week (planned session or rest day) or of last week (#481); `d` counts from this week's Monday.
    @ViewBuilder private func otherWeekCard(_ d: Int, pick: @escaping (Int) -> Void, back: @escaping () -> Void) -> some View {
        let cal = model.planCalendar
        let date = cal.date(byAdding: .day, value: d - 1, to: Progression.weekStart(Date(), cal)) ?? Date()
        let week = Int((Double(d - 1) / 7).rounded(.down))
        let wd = d - week * 7
        if week > 0 {
            let weeks = model.calendarWeeks(count: 3)
            if week < weeks.count, let s = weeks[week].plan.sessions.first(where: { $0.weekday == wd }), model.isSkipped(s.id, in: weeks[week]) {
                // Skipped that week (#698): a rest day with Unskip.
                RestDayCard(weekday: wd, day: d, date: date, onPick: pick, onBack: back, skipped: [s], skippedWeek: weeks[week])
            } else if week < weeks.count, let s = weeks[week].plan.sessions.first(where: { $0.weekday == wd }) {
                NextUpCard(session: s, picked: d, later: DaySelection(week: weeks[week], weekday: wd, current: false),
                           onPick: pick, onBack: back)
            } else {
                RestDayCard(weekday: wd, day: d, date: date, onPick: pick, onBack: back)
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
            Button(removeTitle(s), systemImage: "trash", role: .destructive) { remove(s) }
        }
    }

    private func removeTitle(_ s: Session) -> String {
        model.planInsert(for: s)?.replacing == nil ? "Remove from this week" : "Back to planned session"
    }

    /// Opens the player on a workout the member started (#541: one heavy tap, the same everywhere).
    private func start(_ s: Session) {
        Haptics.start()
        playing = s
    }

    /// Takes an added session off this week at once (#538); the Undo bar puts it back (no confirmation, #285).
    private func remove(_ s: Session) {
        guard let ins = model.planInsert(for: s) else { return }
        let extra = ins.replacing == nil
        withAnimation { model.removePlanInsert(ins.id) }
        UndoCloseCenter.shared.deleted(extra ? "\(s.displayTitle) removed" : "Back to planned session",
                                       detail: extra ? "This week's plan" : s.displayTitle, symbol: "trash") { [model] in
            if let generated = ins.generated, let wd = ins.weekday {
                _ = model.addExtra(ins.workout, generated: generated, weekday: wd)
            } else {
                _ = model.insertIntoPlan(ins.workout, replacing: ins.replacing, weekday: ins.weekday)
            }
        }
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
                if past { remove(s) }
            }
    }

    private func byDay(_ sessions: [Session], days: [String: Int]) -> [Session] {
        func key(_ i: Int) -> (Int, Int) { (sessions[i].weekday ?? days[sessions[i].id] ?? 8, i) }
        return sessions.indices.sorted { key($0) < key($1) }.map { sessions[$0] }
    }

    /// Title, plan menu, edit button and the Me pill (#560); while editing, "Edit Train" and Done (#260).
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
                CoachHeaderTile()
                // Calendar, Variation and Edit plan stay reachable when Quick actions is removed.
                if !model.trainLayout.contains(.actions) {
                    Menu {
                        Button("Calendar", systemImage: "calendar") { showingCalendar = true }
                        Button("Variation", systemImage: "shuffle") { ProStore.shared.run(.variation, $gate) { varying = true } }
                        Button("Edit plan", systemImage: "slider.horizontal.3") { editing = true }
                    } label: {
                        HeaderTile(symbol: "ellipsis")
                    }
                    .accessibilityLabel("Plan actions")
                }
                Button { withAnimation(.snappy) { arranging = true } } label: { HeaderTile(symbol: "square.grid.2x2.fill") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit Train")
                    .accessibilityHint("Add, remove, resize and reorder the widgets on this screen")
                MePill()
            }
        }
        .padding(.top, 4)
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

    /// Coach and week cards both wide (#564, design D1): the week shows as tiles inside the Coach card. Apart while editing.
    private var weekInCoach: Bool {
        let w = model.trainLayout.widgets
        return !arranging && w.contains { $0.kind == .coach && $0.size != .small } && w.contains { $0.kind == .week && $0.size != .small }
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
            if small {
                CoachSmallWidget()
            } else {
                MonkeyCoachCard(weekFooter: weekInCoach ? AnyView(WeekTiles(plan: plan, done: model.completedCount)) : nil) { start($0) }
            }
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
                    // Workout running on the Watch (#603): back to its twin player.
                    if !arranging { WatchLiveBanner() }
                    nextUpCard(plan)
                    // One slot for the cards that only show for a while (#538): Start workout never moves down for them.
                    if !arranging { TrainNoticeSlot() }
                    // Sport prep on a planned sport day (#523), unless today's sport block already has it (#658).
                    if !arranging && showsToday && !sportHeroToday(plan) { SportPrepBar() }
                    // Skill of the month practice day (#621 C).
                    if !arranging { SkillPracticeBar() }
                    // Daily routines (#689 A): stretch, hangs or mobility with a length, every day.
                    if !arranging { DailyRoutinesRow() }
                    // Run & cardio plan (#618): race countdown or Hybrid, this week's runs.
                    if !arranging { RunGoalCard() }
                    if !arranging { notices(plan: plan, profile: profile) }
                }
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    NextUpCompactWidget(session: model.nextSession, wide: !small) { start($0) }
                        .frame(maxHeight: small ? .infinity : nil, alignment: .top)
                    // A small Next up gets the slot under its row instead (#538).
                    if !arranging, !small { TrainNoticeSlot() }
                    if !arranging, !small, showsToday { SportPrepBar() }
                    if !arranging, !small { SkillPracticeBar() }
                    if !arranging, !small { DailyRoutinesRow() }
                    if !arranging, !small { RunGoalCard() }
                    if !arranging, !small { notices(plan: plan, profile: profile) }
                }
            }
        case .climbing:
            if small {
                ClimbSmallWidget()
            } else if Generator.isClimber(profile) {
                ClimbSection(arranging: arranging, wallInCard: sportHeroToday(plan) || !showsToday)
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

    /// Cards that only show when they apply: body prompt, climbing hint (Undo variation is in the slot, #538). Under
    /// Next up, or on top when the member removed Next up.
    @ViewBuilder private func notices(plan: WeekPlan, profile: Profile) -> some View {
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
                    .accessibilityAction(named: removeTitle(s)) { if removable { remove(s) } }
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

    /// Sessions still to do in the next 4 weeks (Calendar button), from today on like the Calendar widget:
    /// this week's missed days don't count as planned.
    private var plannedCount: Int {
        let done = model.doneIds, today = model.todayWeekday
        return model.calendarWeeks(count: 4).enumerated().reduce(0) { n, w in
            n + w.element.plan.sessions.filter { !done.contains($0.id) && (w.offset > 0 || ($0.weekday ?? today) >= today) }.count
        }
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

    private var phase: (palette: WorkoutEngine.Category, title: String, rule: String) { weekPhase(plan.week) }

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

/// Explore-style colour per cycle phase, its one-word job and its rule.
private func weekPhase(_ week: Int) -> (palette: WorkoutEngine.Category, title: String, rule: String) {
    switch Generator.phaseIndex(week) {
    case 0: (.cardio, "Ease in", "RPE −1")
    case 1: (.strength, "Build", "Target RPE")
    case 2: (.power, "Peak week", "+1 set on main lifts")
    default: (.stretch, "Recover", "−40% volume")
    }
}

/// The week card inside the Coach card (#564, design D1): three equal tiles, sessions done (calendar), the cycle
/// phase (its sheet) and readiness (its sheet, or today's tune).
private struct WeekTiles: View {
    let plan: WeekPlan
    let done: Int
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var explainingPhase = false
    @State private var explainingReadiness = false
    @State private var tuning = false

    var body: some View {
        let p = weekPhase(plan.week)
        let assessed = Readiness.assess(health.snapshot)
        HStack(spacing: 6) {
            NavigationLink { CalendarView() } label: {
                tile("This week", "\(done)/\(plan.sessions.count)", detail: "done ›",
                     colors: [Color(hex: 0x3D5AFF), Color(hex: 0x8A4FFF)])
            }
            .accessibilityLabel("\(done) of \(plan.sessions.count) sessions done this week").accessibilityHint("Opens the calendar")
            Button { explainingPhase = true } label: {
                tile("\(p.title) ⓘ", "W\(plan.week)/\(Generator.mesocycleWeeks)", detail: nil, colors: p.palette.colors, bars: true)
            }
            .accessibilityHint("Explains this week's training phase")
            readinessTile(assessed)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $explainingPhase) { WeekPhaseSheet(week: plan.week).presentationDetents([.large]) }
        .sheet(isPresented: $tuning) { AutoTuneSheet().presentationDetents([.large]) }
    }

    @ViewBuilder private func readinessTile(_ assessed: (Readiness, [String])?) -> some View {
        let tuned = model.tuneOn ? model.tuneChanges.count : 0
        if let assessed {
            let r = assessed.0
            Button { if model.tuneOn { tuning = true } else { explainingReadiness = true } } label: {
                tile(tuned > 0 ? "Tuned · \(tuned)" : "Ready", r.title,
                     detail: model.readinessEased ? "eased: −1 RPE" : r.markers(health.snapshot), colors: r.colors)
            }
            .accessibilityLabel("Readiness: \(r.title)")
            .accessibilityHint(model.tuneOn ? "Shows today's ready score and what Monkey tuned" : "Explains readiness and each marker")
            .sheet(isPresented: $explainingReadiness) {
                ReadinessSheet(snapshot: health.snapshot, readiness: r, flags: assessed.1).presentationDetents([.large])
            }
        } else if health.available, health.settled, !health.connected {
            Button { Task { await health.connect() } } label: {
                tile("Ready", "Health", detail: "connect ›", colors: [Color(hex: 0xFF3D8B), Color(hex: 0xFF9A5E)])
            }
            .accessibilityHint("Asks Apple Health for heart rate variability, resting heart rate and sleep")
        } else if model.tuneOn {
            Button { tuning = true } label: {
                tile("Today", tuned > 0 ? "Tuned · \(tuned)" : "Tune", detail: "light · push ›", colors: [Color(hex: 0x00C6A7), Color(hex: 0x1E9BFF)])
            }
            .accessibilityHint("Tap sore muscles or pick light, medium or push for today's workout")
        } else {
            Button { explainingPhase = true } label: {
                tile("Plan", "\(plan.sessions.count) sessions", detail: "\(plan.sessionMinutes) min", colors: [Color(hex: 0x00C6A7), Color(hex: 0x1E9BFF)])
            }
            .accessibilityHint("Explains this week's training phase")
        }
    }

    /// Same size whatever the text (#529): content in an overlay on a fixed frame.
    /// `bars`: the cycle's weeks under the value, this one brightest.
    private func tile(_ key: String, _ value: String, detail: String?, colors: [Color], bars: Bool = false) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(key).font(Theme.label(9)).tracking(0.8).textCase(.uppercase).opacity(0.9).lineLimit(1).minimumScaleFactor(0.7)
                    Text(value).font(Theme.display(value.count > 6 ? 14 : 20)).lineLimit(1).minimumScaleFactor(0.6)
                    if let detail {
                        Text(detail).font(Theme.label(9)).monospacedDigit().opacity(0.9).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    if bars {
                        HStack(spacing: 3) {
                            ForEach(1...Generator.mesocycleWeeks, id: \.self) { w in
                                Capsule().fill(.white.opacity(w == plan.week ? 1 : w < plan.week ? 0.6 : 0.3)).frame(height: 3)
                            }
                        }
                        .padding(.top, 3)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Sessions done this week as a rounded-square ring (#541) with the count inside.
struct DoneRing: View {
    let done: Int
    let total: Int
    var size: CGFloat = 54

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        ZStack {
            shape.stroke(.white.opacity(0.3), lineWidth: 6)
            shape
                .trim(from: 0, to: total > 0 ? min(1, CGFloat(done) / CGFloat(total)) : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .butt))
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
    /// Opens the player; nil = nothing to start here (a later week's day, #473).
    var onStart: (() -> Void)? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.trainCompact) private var compact
    @Environment(\.trainBackToToday) private var backToToday
    @State private var logging: SportLog?
    /// A missed day's session logged after the fact (#537).
    @State private var loggingMissed: Session?
    /// Sets logged for a workout recorded on another watch (#549).
    @State private var loggingHealth: GymEntry?
    @Environment(HealthManager.self) private var health
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
    /// Today's card: the only one with Build as I go, Log sport and Track live.
    private var isToday: Bool { later == nil && (day.map { $0 == model.todayWeekday } ?? true) }
    /// The card's day this week: the picked day, else the session's (nil = unscheduled, startable any day).
    private var day: Int? { picked ?? session.weekday }
    /// An earlier day this week (#537): its session is logged, never played.
    private var past: Bool { day.map { $0 < model.todayWeekday } ?? false }

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
            if showsJump {
                // A picked day's way back on the day's label line (#652, design A), outside the tappable summary.
                HStack(alignment: .center, spacing: 10) {
                    eyebrowText
                    Spacer(minLength: 0)
                    DayJumpChip(label: backChipTitle(model, toToday: backToToday), action: onBack)
                }
            }
            // Tapping the card opens the session page, same as the list button (#150).
            if let later {
                Button { laterDay = later } label: { summary }
                    .buttonStyle(.plain)
                    // Same long press as this week's days (#671).
                    .contextMenu { cardMenu }
                    .accessibilityHint("Opens the day")
            } else {
                NavigationLink(value: session.id) {
                    summary
                }
                .buttonStyle(.plain)
                // Long press (#643, design A): move it, or skip it without moving it.
                .contextMenu { cardMenu }
                .accessibilityHint("Opens the session overview")
            }
            // Where today happens (#700, design A): just this day or every week; Home always a choice (#703).
            if later == nil, !done, !past, let d = day {
                HStack { PlaceMenuChip(weekday: d); Spacer(minLength: 0) }
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
        .sheet(item: $loggingMissed) { MissedLogSheet(session: $0) }
        .sheet(item: $loggingHealth) { MissedLogSheet(session: session, fromHealth: $0) }
        .fullScreenCover(item: $freestyle) { WorkoutPlayerView(sessionId: $0.id) }
        .modifier(LaterDaySheets(day: $laterDay))
        .sheet(isPresented: $moving) { MoveSessionSheet(sessionId: session.id, later: later?.week) }
        .sheet(isPresented: $planningSport) { PlanSportSheet(day: dayKey ?? PlanCalendar.key(Date(), model.planCalendar), sport: model.profile?.otherSports.first?.sport) }
        .sheet(item: $editingTrip) { PlanSportSheet(day: $0.start, editing: $0) }
    }

    /// Long press (#643, #671): the same moves as the card's tiles, this week or a later one.
    @ViewBuilder private var cardMenu: some View {
        if !done && !past {
            Button("Move to…", systemImage: "arrow.left.arrow.right") { moving = true }
            // Where (#703): the day card chip's choices, also on long press.
            if later == nil, let d = day {
                Menu("Where · \(model.tripThisWeek(d)?.title ?? model.placeName(onWeekday: d))", systemImage: "mappin.and.ellipse") {
                    PlaceMenuItems(weekday: d)
                }
            }
            Button("Plan a sport", systemImage: "figure.snowboarding") { planningSport = true }
            if canToggleSkip {
                Button(skippedHere ? "Unskip" : skipTitle, systemImage: skippedHere ? "arrow.uturn.backward" : "nosign",
                       role: skippedHere ? nil : .destructive) { toggleSkip(model, session, in: later?.week) }
            }
        }
        if later != nil {
            Button("See workout", systemImage: "list.bullet") { laterDay = later }
        }
    }

    /// Skipped on its day, this week (#643) or ahead in a later week (#671).
    private var skippedHere: Bool { later.map { model.isSkipped(session.id, in: $0.week) } ?? skipped }
    private var canToggleSkip: Bool { later != nil || skipped || model.canSkip(session) }
    private var skipTitle: String {
        if let later { return "Skip \(WeekSchedule.name(later.weekday))" }
        guard let d = day else { return "Skip" }
        return d == model.todayWeekday ? "Skip today" : "Skip \(WeekSchedule.name(d))"
    }

    /// Same three tiles on every coming workout day, any week (#671, design A): Move · Plan sport · Skip.
    private var workoutTiles: some View {
        HStack(spacing: 8) {
            DayActionTile(title: "Move", detail: "another day", symbol: "arrow.left.arrow.right",
                          fill: AnyShapeStyle(Color.white.opacity(0.15))) { moving = true }
            if let trip = dayKey.flatMap({ model.profile?.sportTrip(on: $0) }) {
                DayActionTile(title: trip.title, detail: "edit", symbol: trip.sport.symbol,
                              fill: AnyShapeStyle(trip.sport.gradient)) { editingTrip = trip }
            } else {
                DayActionTile(title: "Plan sport", detail: "this day", symbol: "figure.mixed.cardio",
                              fill: AnyShapeStyle(DayActionTile.sportFill)) { planningSport = true }
            }
            DayActionTile(title: skippedHere ? "Unskip" : "Skip", detail: skippedHere ? "back on" : "this day",
                          symbol: skippedHere ? "arrow.uturn.backward" : "nosign", fill: AnyShapeStyle(MissedStyle.gradient)) {
                toggleSkip(model, session, in: later?.week)
            }
            .disabled(!canToggleSkip)
            .opacity(canToggleSkip ? 1 : 0.4)
        }
        // A done workout keeps the row in place, dimmed: nothing to move or skip.
        .disabled(done)
        .opacity(done ? 0.4 : 1)
    }

    /// Slim (#337, design A): muscle chips sit in the text column beside a smaller figure, so Start workout stays
    /// above the tab bar. Short phones drop the figure, chips and block stripe.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    if !showsJump { eyebrowText }
                    // Long titles wrap instead of shrinking or cutting off (#538).
                    Text(session.displayTitle).font(Theme.display(compact ? 26 : 30)).foregroundStyle(.white)
                        .lineLimit(3).minimumScaleFactor(0.9).fixedSize(horizontal: false, vertical: true)
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
            // Where and with what (#684, #685): lift at the day's gym, then its run, then climbing; the Coach's note.
            if let d = later?.weekday ?? day { DayComboRow(session: session, day: d, thisWeek: later == nil, showNote: !compact) }
            if !compact { BlockStripe(blocks: session.blocks) }
        }
        .contentShape(Rectangle())
    }

    private func muscleChips(_ n: Int) -> some View {
        HStack(spacing: 6) { ForEach(session.topMuscles(n)) { MuscleChip(muscle: $0) } }
    }

    private var done: Bool { model.doneIds.contains(session.id) }
    /// Skipped on today or a later day this week (#643); an earlier skipped day is the past-day card's.
    private var skipped: Bool { later == nil && !past && !done && model.skippedIds.contains(session.id) }
    /// The next session's card needs a way back too when back means today.
    private var showsJump: Bool { picked != nil && (!isNext || backToToday) }
    private var isNext: Bool { session.id == model.nextSession?.id }

    private var eyebrowText: some View {
        Text(eyebrow).font(Theme.label(12)).tracking(1.4).foregroundStyle(.white.opacity(0.8))
            .lineLimit(1).minimumScaleFactor(0.8)
    }

    private var eyebrow: String {
        if let later, let date = later.week.date(later.weekday, model.planCalendar) {
            let day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            return picked == nil ? "Next up · \(day)" : "\(day) · \(skippedHere ? "skipped" : "planned")"
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
                } else if skipped {
                    // Skipped today or later (#643): put it back on its day.
                    Button { withAnimation { model.unskip(session.id) } } label: {
                        Label("Unskip \(session.displayTitle)", systemImage: "arrow.uturn.backward").lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .buttonStyle(LimeButtonStyle(fill: .white))
                } else if ahead {
                    // A later day (#343): only its overview.
                    NavigationLink(value: session.id) { Label("See workout", systemImage: "list.bullet") }
                        .buttonStyle(LimeButtonStyle())
                } else if model.activeWorkout(session.id) == nil, let match = model.healthMatch(for: session, in: health.snapshot.recentGym) {
                    // Recorded on another watch (#549, design A): mark it done or log its sets.
                    HealthMatchBox(entry: match, onDone: { withAnimation { model.markDone(session, from: match) } },
                                   onLog: { loggingHealth = match })
                } else if let onStart, model.activeWorkout(session.id) != nil || !past && (day == nil || day == model.todayWeekday) {
                    // Only today's session starts (#537); one in progress always resumes.
                    Button(action: onStart) {
                        Label(model.activeWorkout(session.id) == nil ? "Start workout" : "Resume workout", systemImage: "play.fill")
                            .lineLimit(1).minimumScaleFactor(0.9)
                    }
                    .buttonStyle(LimeButtonStyle())
                } else if past {
                    // A missed day (#537): log what was done that day.
                    Button { loggingMissed = session } label: {
                        Label("Log it", systemImage: "square.and.pencil").lineLimit(1).minimumScaleFactor(0.9)
                    }
                    .buttonStyle(LimeButtonStyle(fill: .white))
                    .accessibilityHint("Logs this workout on its day with what you did")
                } else if let day {
                    // Next up is a later day (#537): planned, not startable yet.
                    PlannedDayBadge(weekday: day)
                }
            }
            // Every coming workout day, this week or later, today too (#671): the same three tiles.
            if !past { workoutTiles }
            // Today's sports sit under them in one split pill (#462, design C).
            if isToday {
                SportSplitPill(onFree: { Haptics.start(); freestyle = model.freestyleInProgress ?? model.startFreestyle() },
                               freeResumes: model.freestyleInProgress != nil,
                               onLog: { logging = SportLog(start: Date().addingTimeInterval(-120 * 60)) },
                               onTrack: { trackingSport = SportLog(start: Date()) })
            }
        }
    }
}

/// A gym workout another watch wrote to Apple Health on this session's day (#549, design A): source, length, heart
/// rate and calories, with Mark done and Log sets.
private struct HealthMatchBox: View {
    let entry: GymEntry
    let onDone: () -> Void
    let onLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Found in Health · \(entry.label)", systemImage: "applewatch.radiowaves.left.and.right")
                    .font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.7)
                Text("\(entry.source) · \(entry.start.formatted(date: .omitted, time: .shortened))–\(entry.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption.weight(.semibold)).opacity(0.8)
            }
            HStack(spacing: 6) {
                stat("\(entry.minutes)", "min")
                stat(entry.avgHR.map { "\(Int($0.rounded()))" } ?? "–", "avg ♥")
                stat(entry.maxHR.map { "\(Int($0.rounded()))" } ?? "–", "max ♥")
                stat(entry.kcal.map { "\(Int($0.rounded()))" } ?? "–", "kcal")
            }
            HStack(spacing: 8) {
                Button(action: onDone) { Label("Mark done", systemImage: "checkmark").lineLimit(1).minimumScaleFactor(0.8) }
                    .buttonStyle(LimeButtonStyle())
                Button(action: onLog) {
                    Label("Log sets", systemImage: "square.and.pencil").lineLimit(1).minimumScaleFactor(0.8)
                        .font(Theme.label(15)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Logs the sets you did, with this workout's time and heart rate")
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.ink.opacity(0.55)))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(Theme.display(17)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(Theme.label(9)).opacity(0.8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.1)))
    }
}

/// Any past day picked in the strip (#481, #592 design A): one card for done, rest, climbing and missed days. Everything
/// logged that day is a gradient row (tap = see or edit it), a planned session not done is a Log it row, and a
/// forgotten workout or sport can still be added.
private struct PastDayCard: View {
    /// Strip day counted from this week's Monday (below today).
    let day: Int
    let date: Date
    /// The session planned on this day (this week only).
    var session: Session? = nil
    var onPick: (Int) -> Void = { _ in }
    var onBack: () -> Void = {}
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.trainBackToToday) private var backToToday
    @State private var record: WorkoutRecord?
    @State private var climb: ClimbLog?
    @State private var newClimb: ClimbLog?
    @State private var sport: SportLog?
    @State private var newSport: SportLog?
    @State private var healthSport: SportEntry?
    /// A missed session, or a copy of one logged as an extra workout on this day.
    @State private var loggingWorkout: Session?
    @State private var loggingHealth: GymEntry?

    /// 1 = Monday … 7 = Sunday.
    private var weekday: Int { ((day - 1) % 7 + 7) % 7 + 1 }
    private var climbing: Bool {
        model.profile?.sport(onWeekday: weekday, key: PlanCalendar.key(date, model.planCalendar), date: date) == .climbing
    }
    /// 18:00 on this day: the default start of anything added here.
    private var evening: Date { model.planCalendar.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date }
    /// The planned session, when it still needs logging.
    private var missed: Session? {
        guard let session, !model.doneIds.contains(session.id), model.activeWorkout(session.id) == nil else { return nil }
        return session
    }

    var body: some View {
        let cal = model.planCalendar
        let items = model.historyItems(health: health).filter { cal.isDate($0.start, inSameDayAs: date) }.sorted { $0.start < $1.start }
        VStack(alignment: .leading, spacing: 12) {
            WeekDayStrip(selected: day, onPick: onPick)
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) · \(state(items.count))")
                        .font(Theme.label(12)).tracking(1.4).textCase(.uppercase).foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(title(items)).font(Theme.display(26)).foregroundStyle(.white)
                        .lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                DayJumpChip(label: backChipTitle(model, toToday: backToToday), action: onBack)
            }
            ForEach(items) { row($0) }
            if let missed {
                if let match = model.healthMatch(for: missed, in: health.snapshot.recentGym) {
                    // Recorded on another watch (#549): mark it done or log its sets.
                    HealthMatchBox(entry: match, onDone: { withAnimation { model.markDone(missed, from: match) } },
                                   onLog: { loggingHealth = match })
                } else {
                    DayLogRow(symbol: "square.and.pencil", title: missed.displayTitle,
                              detail: model.skippedIds.contains(missed.id) ? "skipped · log what you did" : "missed · log what you did",
                              value: "\(missed.estMin)′", caption: "LOG IT", fill: AnyShapeStyle(Color.white), ink: Theme.ink) {
                        loggingWorkout = missed
                    }
                }
            }
            HStack(spacing: 8) {
                workoutTile
                if climbing && !items.contains(where: { if case .climb = $0 { true } else { false } }) {
                    DayActionTile(title: "Log climb", detail: "this day's session", symbol: "figure.climbing",
                                  fill: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFF6B3D), Color(hex: 0xFFA94D)], startPoint: .leading, endPoint: .trailing))) {
                        newClimb = ClimbLog(start: evening)
                    }
                } else {
                    DayActionTile(title: "Sport", detail: "climb, run, ride…", symbol: "plus",
                                  fill: AnyShapeStyle(DayActionTile.sportFill)) { newSport = SportLog(start: evening) }
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x3D4BD6).opacity(0.85), Color(hex: 0x5A2FA0).opacity(0.6), Theme.bg],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
        .sheet(item: $record) { r in
            NavigationStack { HistoryDetailView(recordId: r.id).toolbar { CloseToolbarItem { record = nil } } }
        }
        .sheet(item: $climb) { LogClimbView(initial: $0, editing: true) }
        .sheet(item: $newClimb) { LogClimbView(initial: $0) }
        .sheet(item: $sport) { LogSportView(initial: $0, editing: true) }
        .sheet(item: $newSport) { LogSportView(initial: $0) }
        .sheet(item: $healthSport) { SportSessionSheet(entry: $0) }
        .sheet(item: $loggingWorkout) { MissedLogSheet(session: $0, day: date) }
        .sheet(item: $loggingHealth) { m in if let missed { MissedLogSheet(session: missed, fromHealth: m) } }
    }

    private func state(_ logged: Int) -> String {
        if logged > 0 { return "\(logged) logged" }
        if let missed { return model.skippedIds.contains(missed.id) ? "skipped" : "missed" }
        return "rest day"
    }

    private func title(_ items: [HistoryItem]) -> String {
        if let session { return session.displayTitle }
        if climbing { return "Climbing day 🧗" }
        return items.first?.title ?? "Rest day 😴"
    }

    /// A logged session: gym opens what was done, a climb or sport logged here opens to edit, Health ones their page.
    @ViewBuilder private func row(_ item: HistoryItem) -> some View {
        let fill = AnyShapeStyle(LinearGradient(colors: item.filter.colors, startPoint: .leading, endPoint: .trailing))
        let value = History.duration(item.minutes)
        switch item {
        case .gym(let r):
            DayLogRow(symbol: item.symbol, title: item.title, detail: item.subtitle, value: value, caption: "SEE ›", fill: fill) { record = r }
        case .climb(let c):
            if c.local, let log = model.climbLogs.first(where: { $0.id == c.id }) {
                DayLogRow(symbol: item.symbol, title: item.title, detail: item.subtitle, value: value, caption: "EDIT ✎", fill: fill,
                          onDelete: { deleteClimb(log.id) }) { climb = log }
            } else {
                // From Apple Health or MonkeyGrade: edited where it was recorded.
                DayLogRow(symbol: item.symbol, title: item.title, detail: item.subtitle, value: value, caption: c.source.uppercased(), fill: fill, onTap: nil)
            }
        case .sport(let e):
            if e.local, let log = model.sportLogs.first(where: { $0.id == e.id }), log.fromHealth != true {
                DayLogRow(symbol: item.symbol, title: item.title, detail: item.subtitle, value: value, caption: "EDIT ✎", fill: fill,
                          onDelete: { deleteSport(log.id) }) { sport = log }
            } else {
                DayLogRow(symbol: item.symbol, title: item.title, detail: item.subtitle, value: value, caption: "SEE ›", fill: fill) { healthSport = e }
            }
        }
    }

    private func deleteClimb(_ id: UUID) {
        withAnimation { model.deleteClimb(id) }
        Task {
            await health.deleteClimb(id)
            await health.refresh()
        }
    }

    private func deleteSport(_ id: UUID) {
        withAnimation { model.deleteSport(id) }
        Task {
            await health.deleteSport(id)
            await health.refresh()
        }
    }

    /// Add a forgotten workout: one of this week's workouts, logged on this day as an extra (the plan's stays as is).
    @ViewBuilder private var workoutTile: some View {
        let sessions = model.plan?.sessions ?? []
        if sessions.isEmpty {
            DayActionTile(title: "Workout", detail: "forgot one?", symbol: "plus", fill: AnyShapeStyle(Theme.lime), ink: Theme.ink) {
                newSport = SportLog(start: evening)
            }
        } else {
            Menu {
                Section("Log a workout on this day") {
                    ForEach(sessions) { s in
                        Button(s.displayTitle, systemImage: "dumbbell.fill") { loggingWorkout = Self.extra(s) }
                    }
                }
            } label: {
                DayActionTileLabel(title: "Workout", detail: "forgot one?", symbol: "plus", fill: AnyShapeStyle(Theme.lime), ink: Theme.ink)
            }
            .buttonStyle(.plain)
        }
    }

    /// A copy of a plan session with its own id, so logging it never marks the planned one done.
    static func extra(_ s: Session) -> Session {
        var c = s
        c.id = "extra-\(UUID().uuidString)"
        c.weekday = nil
        return c
    }
}

/// One thing logged on a past day (#592, design A): icon tile left, title over a detail line, big time right.
private struct DayLogRow: View {
    let symbol: String
    let title: String
    let detail: String
    let value: String
    /// Small caption under the time: "EDIT ✎", "SEE ›", "LOG IT" or where it was recorded.
    let caption: String
    let fill: AnyShapeStyle
    var ink: Color = .white
    /// Long press (#592): Delete under the tap's own action.
    let onDelete: (() -> Void)?
    let onTap: (() -> Void)?

    init(symbol: String, title: String, detail: String, value: String, caption: String, fill: AnyShapeStyle,
         ink: Color = .white, onDelete: (() -> Void)? = nil, onTap: (() -> Void)?) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.value = value
        self.caption = caption
        self.fill = fill
        self.ink = ink
        self.onDelete = onDelete
        self.onTap = onTap
    }

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
        // Long press edits too (#592): the same action as a tap, plus Delete for what was logged here.
        .contextMenu {
            if let onTap {
                Button(menuTitle, systemImage: caption.hasPrefix("EDIT") ? "pencil" : caption.hasPrefix("LOG") ? "square.and.pencil" : "eye",
                       action: onTap)
            }
            if let onDelete {
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
    }

    private var menuTitle: String {
        caption.hasPrefix("EDIT") ? "Edit \(title)" : caption.hasPrefix("LOG") ? "Log \(title)" : "See \(title)"
    }

    private var content: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .heavy))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.18)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.label(15)).lineLimit(1).minimumScaleFactor(0.7)
                if !detail.isEmpty {
                    Text(detail).font(Theme.label(10)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(value).font(Theme.display(22)).monospacedDigit().lineLimit(1)
                Text(caption).font(Theme.label(9)).opacity(0.85).lineLimit(1)
            }
        }
        .foregroundStyle(ink)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Short jump title for the card's header chip (#562): "Today", "Next up · Thu" or "This week".
@MainActor private func backChipTitle(_ model: AppModel, toToday: Bool) -> String {
    toToday ? "Today" : model.nextSession.map { s in s.weekday.map { "Next up · \(WeekSchedule.shortName($0))" } ?? "Next up" } ?? "This week"
}

/// Lime chip beside the day's title (#562, design B): back to today or to the next session; replaces the bottom bar.
private struct DayJumpChip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(label) ›")
                .font(Theme.label(13))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.lime))
                .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

/// One of the day card's action tiles (#562, design B): Explore-style, icon tile left, title over a detail line.
/// Tiles in a row share the width and always have the same height.
private struct DayActionTile: View {
    let title: String
    let detail: String
    let symbol: String
    let fill: AnyShapeStyle
    var ink: Color = .white
    let action: () -> Void

    static let sportFill = LinearGradient(colors: [Color(hex: 0xFF5F8F), Color(hex: 0xFF9A5C)], startPoint: .leading, endPoint: .trailing)
    /// Rest day (#671): night blue.
    static let restFill = LinearGradient(colors: [Color(hex: 0x3B3F8F), Color(hex: 0x5A4AB0)], startPoint: .leading, endPoint: .trailing)

    var body: some View {
        Button(action: action) {
            DayActionTileLabel(title: title, detail: detail, symbol: symbol, fill: fill, ink: ink)
        }
        .buttonStyle(.plain)
    }
}

/// A day action tile's face, shared with tiles that open a menu (#592).
private struct DayActionTileLabel: View {
    let title: String
    let detail: String
    let symbol: String
    let fill: AnyShapeStyle
    var ink: Color = .white

    var body: some View {
        // Content in an overlay so label lengths never change a tile's size (#529).
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .overlay(alignment: .leading) {
                HStack(spacing: 8) {
                    Image(systemName: symbol).font(.system(size: 15, weight: .heavy))
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.18)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(Theme.label(15)).lineLimit(1).minimumScaleFactor(0.6)
                        Text(detail).font(Theme.label(10)).opacity(0.8).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                .foregroundStyle(ink)
                .padding(.horizontal, 10)
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
    /// Plans a workout on this day; nil = not offered (a later week's day, #481).
    var onAdd: (() -> Void)? = nil
    /// Header chip title when the card is today's default (#538 follow-up, #562); nil = "Next up · Thu" or "Today".
    var backTitle: String? = nil
    /// Workouts skipped on this day (#698, design A): the day is a rest day with a "skipped · Unskip" line.
    var skipped: [Session] = []
    /// The later week they were skipped in; nil = this week.
    var skippedWeek: PlanCalendar.Week? = nil
    @Environment(AppModel.self) private var model
    @Environment(\.trainBackToToday) private var backToToday
    @State private var logging: ClimbLog?
    @State private var loggingSport: SportLog?
    @State private var trackingSport: SportLog?
    /// Build as I go (#490): the empty workout open in the player.
    @State private var freestyle: Session?
    /// Plan sport (#474): a sport once, every week or a trip from this day; or the dated day / trip on it.
    @State private var planningSport = false
    @State private var editingTrip: SportTrip?
    /// Around sport days (#658) opened from the sport hero's menu.
    @State private var around: Sport?
    /// Log or Track live from the sport hero (#658): the day's sport already picked.
    @State private var heroSport: HeroLog?
    /// Workout on a later week's day (#671): one of that week's workouts moved here.
    @State private var movingHere = false
    /// Rest day on a sport day (#671): just this day, every week or the whole trip.
    @State private var restRequest: SportOffRequest?

    struct HeroLog: Identifiable {
        let log: SportLog
        let live: Bool
        var id: UUID { log.id }
    }

    /// This day's key ("2026-10-21") in the current week.
    private var dayKey: String {
        let cal = model.planCalendar
        if let date { return PlanCalendar.key(date, cal) }
        let day = cal.date(byAdding: .day, value: weekday - 1, to: Progression.weekStart(Date(), cal)) ?? Date()
        return PlanCalendar.key(day, cal)
    }
    /// A dated sport day or trip on this day.
    private var trip: SportTrip? { model.profile?.sportTrip(on: dayKey) }

    /// The day's sport (#658): a dated sport day or trip beats the weekly climbing day.
    private var daySport: Sport? { model.profile?.sport(onWeekday: weekday, key: dayKey, date: date ?? Date()) }
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
        // Design B (#562): title with a jump chip, actions as equal tiles; no hint line, no dashed box.
        VStack(alignment: .leading, spacing: 12) {
            WeekDayStrip(selected: day ?? weekday, onPick: onPick)
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.label(12)).tracking(1.4).textCase(.uppercase).foregroundStyle(.white.opacity(0.8))
                    // A sport day shows its sport in the hero block below (#658, design B).
                    if daySport == nil {
                        Text("Rest day 😴").font(Theme.display(26)).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 0)
                DayJumpChip(label: backTitle ?? backChipTitle(model, toToday: backToToday), action: onBack)
            }
            if !skipped.isEmpty { skippedLine }
            if let sport = daySport {
                SportDayHero(sport: sport, trip: trip, today: isToday, past: past,
                             onChange: change,
                             onAround: { around = sport },
                             onRest: askRestDay,
                             onLog: { log(sport) },
                             onTrack: { heroSport = HeroLog(log: SportLog(sport: sport, start: Date()), live: true) })
            }
            if !laterWeek && weekday < model.todayWeekday {
                // An earlier day is logged, never planned (#537): a workout added there could only be logged.
                DayActionTile(title: "Log a workout", detail: "on this day", symbol: "square.and.pencil",
                              fill: AnyShapeStyle(Theme.lime), ink: Theme.ink) { loggingSport = SportLog(start: climbStart()) }
            } else {
                // Same three tiles on every coming rest or sport day, any week (#671, design A):
                // sport day Workout · Change · Rest day, rest day Workout · Plan sport · Recover.
                HStack(spacing: 8) {
                    workoutTile
                    if let sport = daySport {
                        DayActionTile(title: "Change", detail: trip.map { $0.isTrip ? "edit trip" : "edit day" } ?? "sport · trip",
                                      symbol: "arrow.triangle.2.circlepath", fill: AnyShapeStyle(DayActionTile.sportFill), action: change)
                        DayActionTile(title: "Rest day", detail: "no \(sport.short.lowercased())", symbol: "moon.fill",
                                      fill: AnyShapeStyle(DayActionTile.restFill), action: askRestDay)
                    } else {
                        // Plan sport (#474): once, every week or a trip from this day.
                        DayActionTile(title: "Plan sport", detail: "this day", symbol: "figure.mixed.cardio",
                                      fill: AnyShapeStyle(DayActionTile.sportFill)) { planningSport = true }
                        // Recover (#619 A, #659): a short routine for what this week loaded most.
                        let recover = model.recoverPick().template
                        NavigationLink(value: recover.sessionId) {
                            DayActionTileLabel(title: "Recover", detail: "\(recover.session.estMin) min", symbol: "figure.cooldown",
                                               fill: AnyShapeStyle(WorkoutEngine.Category.cardio.gradient), ink: Theme.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if isToday {
                if daySport == nil {
                    // Any other sport (#416), dated like a climb; Track live with a Watch (#462, design C).
                    SportSplitPill(onFree: { Haptics.start(); freestyle = model.freestyleInProgress ?? model.startFreestyle() },
                                   freeResumes: model.freestyleInProgress != nil,
                                   onLog: { loggingSport = SportLog(start: climbStart()) },
                                   onTrack: { trackingSport = SportLog(start: Date()) })
                } else {
                    // Sport actions live in the hero (#658): Freestyle stays for today's gym.
                    DayActionTile(title: "Freestyle", detail: model.freestyleInProgress != nil ? "resume" : "add as you train",
                                  symbol: "plus.square.on.square", fill: AnyShapeStyle(LinearGradient.freestyle)) {
                        Haptics.start()
                        freestyle = model.freestyleInProgress ?? model.startFreestyle()
                    }
                    .accessibilityIdentifier("train.freestyle")
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x3D4BD6).opacity(0.85), Color(hex: 0x5A2FA0).opacity(0.6), Theme.bg],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
        .sheet(item: $logging) { LogClimbView(initial: $0) }
        .sheet(item: $loggingSport) { LogSportView(initial: $0) }
        .sheet(item: $trackingSport) { LogSportView(initial: $0, live: true) }
        .sheet(item: $heroSport) { LogSportView(initial: $0.log, picked: true, live: $0.live) }
        .fullScreenCover(item: $freestyle) { WorkoutPlayerView(sessionId: $0.id) }
        .sheet(isPresented: $planningSport) { PlanSportSheet(day: dayKey, sport: model.profile?.otherSports.first?.sport) }
        .sheet(item: $editingTrip) { PlanSportSheet(day: $0.start, editing: $0) }
        .sheet(item: $around) { AroundSportView(initial: $0) }
        .sheet(isPresented: $movingHere) {
            if let week = laterWeekPlan { MoveHereSheet(week: week, weekday: weekday) }
        }
        .sportOffFlow($restRequest)
    }

    /// "Pull skipped" struck through with a small lime Unskip chip (#698, design A).
    private var skippedLine: some View {
        HStack(spacing: 8) {
            Text("\(skipped.map(\.displayTitle).joined(separator: " · ")) skipped")
                .font(Theme.label(13)).strikethrough().foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            Button {
                withAnimation {
                    for s in skipped {
                        if let skippedWeek { model.setSkipped(false, s.id, in: skippedWeek) } else { model.unskip(s.id) }
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

    /// Workout tile (#671): Add workout this week; a later week moves one of its workouts here.
    @ViewBuilder private var workoutTile: some View {
        if let onAdd {
            DayActionTile(title: "Workout", detail: ahead ? "add this day" : "add today", symbol: "plus",
                          fill: AnyShapeStyle(Theme.lime), ink: Theme.ink, action: onAdd)
        } else {
            DayActionTile(title: "Workout", detail: "move one here", symbol: "plus",
                          fill: AnyShapeStyle(Theme.lime), ink: Theme.ink) { movingHere = true }
                .disabled(laterWeekPlan == nil)
                .opacity(laterWeekPlan == nil ? 0.4 : 1)
        }
    }

    /// This day's later week as the calendar plans it; nil for this week or past the horizon.
    private var laterWeekPlan: PlanCalendar.Week? {
        guard let day, day > 7 else { return nil }
        let weeks = model.calendarWeeks(count: 3)
        let i = (day - 1) / 7
        return i < weeks.count ? weeks[i] : nil
    }

    private func change() { if let trip { editingTrip = trip } else { planningSport = true } }

    private func askRestDay() {
        restRequest = model.sportOffRequest(key: dayKey, weekday: weekday, date: date ?? dayDate)
    }

    /// This week's weekday as a date.
    private var dayDate: Date {
        let cal = model.planCalendar
        return cal.date(byAdding: .day, value: weekday - 1, to: Progression.weekStart(Date(), cal)) ?? Date()
    }

    private var isToday: Bool { date == nil && weekday == model.todayWeekday }
    /// An earlier day of this week: logged, never planned.
    private var past: Bool { !laterWeek && weekday < model.todayWeekday }

    /// Log the day's sport: a climb opens the climb log, any other sport Log sport with it picked.
    private func log(_ sport: Sport) {
        if sport == .climbing { logging = ClimbLog(start: climbStart()) } else { heroSport = HeroLog(log: SportLog(sport: sport, start: climbStart()), live: false) }
    }
}

/// The day's sport on Train (#658, design B from `around-sport/train-proposals.png`): one block in the sport's colours
/// with Change, and Track live · Log · Prep today (Log on earlier days). Gym tiles stay under it.
private struct SportDayHero: View {
    let sport: Sport
    let trip: SportTrip?
    let today: Bool
    let past: Bool
    let onChange: () -> Void
    let onAround: () -> Void
    /// Turns the day into a rest day (#671).
    let onRest: () -> Void
    let onLog: () -> Void
    let onTrack: () -> Void
    @Environment(AppModel.self) private var model
    @State private var link = WatchLink.shared

    /// Climbing's Wall session (unless turned off), else the sport's prep (#523).
    private var hasPrep: Bool {
        sport == .climbing ? model.profile?.climbDayAddon != false : SportPrep.before(sport) != nil
    }

    private var detail: String {
        let around = sport.isLightLoad ? "train as usual around it" : "\(sport.loadLabel) kept light around it"
        if sport == .climbing, hasPrep { return "Wall session · \(around)" }
        if let m = SportPrep.before(sport)?.session.estMin { return "Prep \(m)′ · \(around)" }
        return around.prefix(1).uppercased() + around.dropFirst()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: sport.symbol).font(.system(size: 22, weight: .bold))
                Text(trip?.name.flatMap { $0.isEmpty ? nil : $0 } ?? sport.label)
                    .font(Theme.display(26)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Menu {
                    Button(trip.map { $0.isTrip ? "Edit sport trip" : "Edit sport day" } ?? "Change sport",
                           systemImage: "arrow.triangle.2.circlepath", action: onChange)
                    Button("Gym around it", systemImage: "slider.horizontal.3", action: onAround)
                    Button("Make it a rest day", systemImage: "moon.fill", action: onRest)
                } label: {
                    Text("Change ›").font(Theme.label(13))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(.white.opacity(0.22)))
                }
                .accessibilityLabel("Change \(sport.label.lowercased()) day")
            }
            Text(detail).font(Theme.label(12)).opacity(0.9).lineLimit(1).minimumScaleFactor(0.8)
            if today || past {
                HStack(spacing: 6) {
                    if today && link.ready {
                        button("Track live", symbol: "applewatch.radiowaves.left.and.right", primary: true, action: onTrack)
                    }
                    button(past ? "Log \(sport.short.lowercased())" : "Log", symbol: "plus.circle.fill", primary: !(today && link.ready), action: onLog)
                    if today && hasPrep {
                        NavigationLink {
                            if sport == .climbing {
                                WallSessionPage(today: true, climbedToday: false)
                            } else {
                                SportPrepPage(sport: sport)
                            }
                        } label: {
                            label("Prep", symbol: "flame.fill", primary: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(sport.gradient))
    }

    private func button(_ title: String, symbol: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { label(title, symbol: symbol, primary: primary) }
            .buttonStyle(.plain)
    }

    private func label(_ title: String, symbol: String, primary: Bool) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(primary ? sport.colors.first ?? Theme.ink : .white)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(primary ? AnyShapeStyle(Color.white) : AnyShapeStyle(.white.opacity(0.22))))
            .contentShape(Rectangle())
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
                            : "A fresh week starts Monday. Rest or play your sport meanwhile.").font(.footnote).foregroundStyle(Theme.muted)
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
            // 44 pt target (#538) without making the card taller.
            Button { withAnimation { model.variationUndo = nil } } label: {
                Image(systemName: "xmark").font(.footnote.bold()).opacity(0.8)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(.vertical, -10)
            .padding(.trailing, -8)
            .accessibilityLabel("Dismiss")
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(WorkoutEngine.Category.warmup.gradient))
    }
}

/// One slot under Next up for the cards that only show for a while (#538, design A): a variation's Undo, the taste
/// recap, the block review, what Monkey noticed and kind streaks. One at a time: the bars show where it is, a swipe or
/// a tap on the bars shows the next, ✕ puts the current one away. Start workout never moves down for them.
private struct TrainNoticeSlot: View {
    enum Kind: Hashable { case setup, recover, addOn, variation, taste, block, noticed, kind }

    @Environment(AppModel.self) private var model
    @State private var index = 0
    /// Readiness swap kept (#619 B): the day's key, so it stays away until tomorrow.
    @AppStorage("trainRecoverSwapKept") private var recoverKeptDay = ""
    /// Sport add-on suggestion said No to (#620 B): until this time (30 days).
    @AppStorage("trainAddOnNoUntil") private var addOnNoUntil = 0.0

    private var todayKey: String { PlanCalendar.key(Date(), model.planCalendar) }
    /// Kind streak cards put away this week (they have no close of their own): the week's Monday key.
    @AppStorage("trainKindStreakHidden") private var kindHiddenWeek = ""

    private var weekKey: String {
        let cal = model.planCalendar
        return PlanCalendar.key(Progression.weekStart(Date(), cal), cal)
    }

    private var cards: [Kind] {
        var out: [Kind] = []
        // Onboarding steps not done yet (#664), first: a new member's next things to set up.
        if model.onboarding?.showsCard == true { out.append(.setup) }
        // Low readiness on a heavy day (#619 B): swap it for mobility, before anything else.
        if recoverKeptDay != todayKey, model.recoverSwap != nil { out.append(.recover) }
        // The Coach saw a sport played 3+ times in two weeks (#620 B).
        if Date().timeIntervalSince1970 > addOnNoUntil, model.sportAddOnSuggestion != nil { out.append(.addOn) }
        // New variation (#98): its Undo first.
        if model.variationUndo != nil { out.append(.variation) }
        // New week made with what the app learned (#299).
        if model.tasteRecap != nil { out.append(.taste) }
        // A new block (#495): what the last 4 weeks brought and what the next block changes.
        if model.blockReview != nil { out.append(.block) }
        // What Monkey noticed this week (#495).
        if !model.noticedBar.isEmpty { out.append(.noticed) }
        // Kind streaks (#501): welcome back, Comeback quest, a shield that saved last week.
        if kindHiddenWeek != weekKey,
           model.comeback != nil
            || Progression.stats(records: model.state.history, weights: [], targetPerWeek: model.gameTarget).shieldSavedLastWeek {
            out.append(.kind)
        }
        return out
    }

    var body: some View {
        let cards = self.cards
        if !cards.isEmpty {
            let i = min(index, cards.count - 1)
            VStack(spacing: 4) {
                card(cards[i])
                    .id(cards[i])
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                footer(cards, current: i)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 24).onEnded { v in
                    guard cards.count > 1, abs(v.translation.width) > 50,
                          abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                    withAnimation(.snappy) { index = (i + (v.translation.width < 0 ? 1 : cards.count - 1)) % cards.count }
                }
            )
            .onChange(of: model.variationUndo != nil) { _, shown in
                // A variation just applied: its Undo comes first.
                if shown { index = 0 }
            }
        }
    }

    @ViewBuilder private func card(_ k: Kind) -> some View {
        switch k {
        case .setup:
            if let p = model.onboarding { SetupCard(progress: p) }
        case .recover:
            if let swap = model.recoverSwap { RecoverSwapCard(swap: swap) { dismiss(.recover) } }
        case .addOn:
            if let s = model.sportAddOnSuggestion { SportAddOnSuggestCard(sport: s.sport, count: s.count) { dismiss(.addOn) } }
        case .variation:
            if let u = model.variationUndo { VariationUndoCard(undo: u) }
        case .taste:
            if let r = model.tasteRecap { TasteRecapCard(recap: r) }
        case .block:
            if let r = model.blockReview { BlockReviewCard(review: r) }
        case .noticed:
            NoticedBar(insights: model.noticedBar)
        case .kind:
            KindStreakCards()
        }
    }

    /// Position bars (tap for the next card) and ✕ for the one showing.
    private func footer(_ cards: [Kind], current i: Int) -> some View {
        HStack(spacing: 8) {
            if cards.count > 1 {
                Button { withAnimation(.snappy) { index = (i + 1) % cards.count } } label: {
                    HStack(spacing: 4) {
                        ForEach(cards.indices, id: \.self) { j in
                            Capsule().fill(Color.white.opacity(j == i ? 0.95 : 0.3)).frame(width: j == i ? 20 : 10, height: 4)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title(cards[i])), \(i + 1) of \(cards.count)")
                .accessibilityHint("Shows the next one")
            } else {
                Spacer(minLength: 0)
            }
            Button { dismiss(cards[i]) } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss \(title(cards[i]))")
        }
    }

    private func title(_ k: Kind) -> String {
        switch k {
        case .setup: "Set-up card"
        case .recover: "Readiness swap"
        case .addOn: "Sport add-on"
        case .variation: "Variation undo"
        case .taste: "Taste recap"
        case .block: "Block review"
        case .noticed: "What Monkey noticed"
        case .kind: "Streak news"
        }
    }

    private func dismiss(_ k: Kind) {
        withAnimation(.snappy) {
            switch k {
            case .setup: model.hideSetupCard()
            case .recover: recoverKeptDay = todayKey
            case .addOn: addOnNoUntil = Date().addingTimeInterval(30 * 86_400).timeIntervalSince1970
            case .variation: model.variationUndo = nil
            case .taste: model.dismissTasteRecap()
            case .block: if let r = model.blockReview { model.closeBlockReview(r) }
            case .noticed: model.closeNoticed()
            case .kind: kindHiddenWeek = weekKey
            }
        }
    }
}

private struct TrainCompactKey: EnvironmentKey {
    static let defaultValue = false
}

private struct TrainBackToTodayKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Train on a short phone (#337): Next up drops its figure, muscle chips and block stripe.
    var trainCompact: Bool {
        get { self[TrainCompactKey.self] }
        set { self[TrainCompactKey.self] = newValue }
    }

    /// A day picked in the Train strip while Train opens on today: its back button returns to today.
    var trainBackToToday: Bool {
        get { self[TrainBackToTodayKey.self] }
        set { self[TrainBackToTodayKey.self] = newValue }
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

extension AppModel {
    /// Only today's session can be played (#537): a planned session on its own day (or unscheduled) and not done yet;
    /// a library or freestyle workout any day; a workout in progress always resumes.
    func startableToday(_ s: Session) -> Bool {
        if activeWorkout(s.id) != nil { return true }
        guard let planned = plan?.sessions.first(where: { $0.id == s.id }) else { return true }
        if state.done[planned.id] ?? false { return false }
        return planned.weekday.map { $0 == todayWeekday } ?? true
    }
}

/// Dashed lime "Planned for Thu" in Start's place (#537, design A): a later day's session is shown, not started.
struct PlannedDayBadge: View {
    let weekday: Int
    /// Small widget size: "Thu" in a slim capsule.
    var compact = false

    var body: some View {
        Label(compact ? WeekSchedule.shortName(weekday) : "Planned for \(WeekSchedule.shortName(weekday))", systemImage: "calendar")
            .font(Theme.label(compact ? 14 : 17))
            .foregroundStyle(Theme.lime)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .padding(.horizontal, compact ? 14 : 12)
            .padding(.vertical, compact ? 9 : 18)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(Capsule().strokeBorder(Theme.lime.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Planned for \(WeekSchedule.name(weekday)). Starts on the day.")
    }
}
