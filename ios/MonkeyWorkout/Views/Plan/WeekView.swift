import SwiftUI
import WorkoutEngine

/// "Train" tab: compact week + readiness card, today's session first, then the week list.
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
    @State private var removing: Session?
    @State private var swipe: (id: String, dx: CGFloat)?

    var body: some View {
        ScrollView {
            if let plan = model.plan, let profile = model.profile {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    // Game look (#227), same pick as the Watch style.
                    let style = WatchHomePref.shared.style
                    if style == .coach { MonkeyCoachCard() }
                    // Training programme (#255): replaces the plan while it runs.
                    ProgrammeHeroCard()
                    WeekHero(plan: plan, profile: profile, done: model.completedCount)
                    if style == .rings { LevelBarCard(next: model.nextSession) }
                    if let undo = model.variationUndo {
                        VariationUndoCard(undo: undo)
                    }
                    if let next = model.nextSession {
                        NextUpCard(session: next) { playing = next }
                    } else {
                        WeekCompleteCard()
                    }
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
                    if Generator.isClimber(profile) {
                        ClimbSection()
                    }
                    if let e = model.syncError {
                        Label(e, systemImage: "icloud.slash").font(.footnote).foregroundStyle(Theme.muted)
                    }
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
                    if style == .deck {
                        QuestMap(sessions: ordered, days: days) { s, day in sessionMenu(s, day: day) }
                    } else {
                        ForEach(Array(ordered.enumerated()), id: \.element.id) { i, s in
                            let done = model.state.done[s.id] ?? false
                            let day = s.weekday ?? days[s.id]
                            let removable = s.isPlanInsert && !done
                            NavigationLink(value: s.id) {
                                SessionRowCard(session: s, done: done, climbing: profile.climbingDays, weekday: day, number: i + 1)
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
                    Text(style == .deck
                         ? "Tap a stage to open it. Touch and hold to move it to another day or remove an added one."
                         : ordered.contains { $0.isPlanInsert }
                         ? "Touch and hold a session to move it to another day this week. Swipe left on an added session to remove it."
                         : "Touch and hold a session to move it to another day this week.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(16)
            } else {
                ContentUnavailableView("No plan yet", systemImage: "calendar.badge.plus")
            }
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Train")
        .toolbarTitleDisplayMode(.inlineLarge)
        .navigationDestination(for: String.self) { id in SessionView(sessionId: id) }
        .navigationDestination(for: ProgrammeRoute.self) { r in Programme.find(r.id).map { ProgrammeDetailView(programme: $0) } }
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
            // Away periods (#68): re-plan from today on (new day, period starting this week).
            model.replanCurrentWeek()
            model.persist()
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

    /// Title, then Calendar, Variation and Edit plan as Explore-style gradient buttons in one row (#147).
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Train").font(Theme.display(34)).lineLimit(1)
                Spacer()
                LevelChip()
            }
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
        .padding(.top, 4)
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
private struct DoneRing: View {
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
    let onStart: () -> Void
    @Environment(AppModel.self) private var model

    private var lead: WorkoutEngine.Category {
        session.blocks.first { $0.kind == .strength }?.kind.category ?? .strength
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next up · \(session.dayLabel)").font(Theme.label(12)).tracking(1.4).foregroundStyle(.white.opacity(0.8))
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

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: onStart) {
                Label(model.activeWorkout(session.id) == nil ? "Start workout" : "Resume workout", systemImage: "play.fill")
            }
            .buttonStyle(LimeButtonStyle())
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

private struct WeekCompleteCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "trophy.fill").font(.system(size: 44)).foregroundStyle(Theme.lime)
                .symbolEffect(.bounce, options: .repeat(2))
            Text("Week complete").font(Theme.display(28))
            Text("Move to the next week from the bar above, or rest and climb.").font(.footnote).foregroundStyle(Theme.muted)
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
