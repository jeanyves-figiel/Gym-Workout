import SwiftUI
import WorkoutEngine

/// "Train" tab: compact week header and readiness, today's session first, then the week list.
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

    var body: some View {
        ScrollView {
            if let plan = model.plan, let profile = model.profile {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    WeekHero(plan: plan, profile: profile, done: model.completedCount)
                    ReadinessCard(snapshot: health.snapshot)
                    if let undo = model.variationUndo {
                        VariationUndoCard(undo: undo)
                    }
                    if let next = model.nextSession {
                        NextUpCard(session: next) { playing = next }
                    } else {
                        WeekCompleteCard()
                    }
                    if health.snapshot.weightKg == nil && model.body.weightKg == nil {
                        BodyPromptCard()
                    }
                    // Picked climbing weekdays set the count; the Health hint would be overridden.
                    if profile.climbingDays.isEmpty, let perWeek = health.snapshot.climbingPerWeek4w {
                        ClimbingSyncHint(healthPerWeek: perWeek, profileDays: profile.climbingDaysPerWeek) { n in
                            var p = profile
                            p.climbingDaysPerWeek = n
                            model.applyProfile(p, seed: plan.seed, week: plan.week)
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
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { i, s in
                        let done = model.state.done[s.id] ?? false
                        let day = s.weekday ?? days[s.id]
                        NavigationLink(value: s.id) {
                            SessionRowCard(session: s, done: done, climbing: profile.climbingDays, weekday: day, number: i + 1)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if !done {
                                Button("Move to…", systemImage: "arrow.left.arrow.right") { moving = s }
                            }
                            Button("Add workout this day", systemImage: "plus") { addingDay = day; adding = true }
                        }
                    }
                    Text("Touch and hold a session to move it to another day this week.")
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
        .refreshable { await model.sync() }
        .task {
            // Away periods (#68): re-plan from today on (new day, period starting this week).
            model.replanCurrentWeek()
            model.persist()
        }
    }

    private func byDay(_ sessions: [Session], days: [String: Int]) -> [Session] {
        func key(_ i: Int) -> (Int, Int) { (sessions[i].weekday ?? days[sessions[i].id] ?? 8, i) }
        return sessions.indices.sorted { key($0) < key($1) }.map { sessions[$0] }
    }

    /// Title with Calendar and Plan (variation, training profile) as Explore-style gradient buttons.
    private var header: some View {
        HStack(spacing: 10) {
            Text("Train").font(Theme.display(34)).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            NavigationLink { CalendarView() } label: {
                HeaderChip(symbol: "calendar", title: "Calendar", detail: "\(plannedCount) planned",
                           gradient: WorkoutEngine.Category.strength.gradient)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Calendar, \(plannedCount) sessions planned in the next 4 weeks")
            Menu {
                Button(ProStore.shared.badged ? "New variation · PRO" : "New variation", systemImage: "shuffle") {
                    ProStore.shared.run(.variation, $gate) { varying = true }
                }
                Button("Edit training profile", systemImage: "slider.horizontal.3") { editing = true }
            } label: {
                HeaderChip(symbol: "slider.horizontal.3", title: "Plan", detail: "Variation · edit",
                           gradient: WorkoutEngine.Category.warmup.gradient)
            }
            .accessibilityLabel("Plan: new variation or edit training profile")
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

/// Small gradient button in the Train header: icon tile, title, one-line detail.
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
            .fixedSize()
        }
        .foregroundStyle(.white)
        .padding(.leading, 7)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(gradient))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct WeekHero: View {
    let plan: WeekPlan
    let profile: Profile
    let done: Int
    @Environment(AppModel.self) private var model
    @State private var explaining = false

    /// Explore-style card per cycle phase: colour, icon, one-word job and its rule.
    private var phase: (palette: WorkoutEngine.Category, symbol: String, title: String, rule: String) {
        switch Generator.phaseIndex(plan.week) {
        case 0: (.cardio, "leaf.fill", "Ease in", "RPE −1")
        case 1: (.strength, "chart.line.uptrend.xyaxis", "Build", "Target RPE")
        case 2: (.power, "flame.fill", "Peak week", "+1 set on main lifts")
        default: (.stretch, "bed.double.fill", "Recover", "−40% volume")
        }
    }

    var body: some View {
        let p = phase
        VStack(alignment: .leading, spacing: 14) {
            Button { explaining = true } label: {
                HStack(spacing: 14) {
                    IconTile(symbol: p.symbol, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text("Week \(plan.week) of \(Generator.mesocycleWeeks) · \(Generator.phaseName(plan.week))").tracking(1.2)
                            Image(systemName: "info.circle.fill")
                        }
                        .font(Theme.label(11))
                        .textCase(.uppercase)
                        .opacity(0.85)
                        Text(p.title).font(Theme.display(24)).lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(p.rule) · \(plan.sessions.count) sessions · \(plan.sessionMinutes) min")
                            .font(.footnote.weight(.semibold))
                            .opacity(0.9)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(done)/\(plan.sessions.count)").font(Theme.display(34)).monospacedDigit()
                        Text("DONE").font(Theme.label(10)).tracking(1.3).opacity(0.85)
                    }
                    .fixedSize()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Explains this week's training phase")
            HStack(spacing: 6) {
                ForEach(1...Generator.mesocycleWeeks, id: \.self) { w in
                    Button { model.setWeek(w) } label: {
                        Capsule()
                            .fill(.white.opacity(w == plan.week ? 1 : w < plan.week ? 0.55 : 0.3))
                            .frame(height: 6)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Week \(w)")
                }
            }
            .padding(.bottom, -6)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(p.palette.gradient))
        .sheet(isPresented: $explaining) { WeekPhaseSheet(week: plan.week).presentationDetents([.large]) }
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
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next up · \(session.dayLabel)").font(Theme.label(12)).tracking(1.4).foregroundStyle(.white.opacity(0.8))
                    Text(session.displayTitle).font(Theme.display(30)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                    Label("\(session.estMin) min", systemImage: "clock.fill").font(Theme.label(14)).foregroundStyle(.white.opacity(0.9))
                }
                Spacer(minLength: 8)
                BodyMapView(side: .front, heat: session.muscleHeat, showLabel: false)
                    .frame(width: 70, height: 140)
            }
            FlowLayout(spacing: 6) {
                ForEach(session.topMuscles(4)) { MuscleChip(muscle: $0) }
            }
            BlockStripe(blocks: session.blocks)
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
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [lead.colors[0].opacity(0.85), lead.colors[1].opacity(0.55), Theme.bg], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.15)))
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
