import SwiftUI
import WorkoutEngine

/// "Train" tab: week hero, next-up session, week list.
struct WeekView: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var editing = false
    @State private var playing: Session?

    var body: some View {
        ScrollView {
            if let plan = model.plan, let profile = model.profile {
                VStack(alignment: .leading, spacing: 22) {
                    WeekHero(plan: plan, profile: profile, done: model.completedCount)
                    ReadinessCard(snapshot: health.snapshot)
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
                    if let next = model.nextSession {
                        NextUpCard(session: next) { playing = next }
                    } else {
                        WeekCompleteCard()
                    }
                    if let e = model.syncError {
                        Label(e, systemImage: "icloud.slash").font(.footnote).foregroundStyle(Theme.muted)
                    }
                    Text("This week").eyebrow()
                    ForEach(plan.sessions) { s in
                        NavigationLink(value: s.id) {
                            SessionRowCard(session: s, done: model.state.done[s.id] ?? false, climbing: profile.climbingDays)
                        }
                        .buttonStyle(.plain)
                    }
                    MyWorkoutsSection()
                    Text("Example workouts").eyebrow()
                    ForEach(WorkoutTemplate.all) { t in
                        NavigationLink(value: t.sessionId) {
                            ExampleRowCard(template: t, done: model.state.done[t.sessionId] ?? false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            } else {
                ContentUnavailableView("No plan yet", systemImage: "calendar.badge.plus")
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Train")
        .toolbarTitleDisplayMode(.inlineLarge)
        .navigationDestination(for: String.self) { id in SessionView(sessionId: id) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New variation", systemImage: "shuffle") { model.newVariation() }
                    Button("Edit training profile", systemImage: "slider.horizontal.3") { editing = true }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                ProfileFormView(initial: model.profile) { p in
                    model.applyProfile(p)
                    editing = false
                }
                .navigationTitle("Training profile")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } } }
            }
        }
        .fullScreenCover(item: $playing) { s in WorkoutPlayerView(sessionId: s.id) }
        .refreshable { await model.sync() }
    }
}

private struct WeekHero: View {
    let plan: WeekPlan
    let profile: Profile
    let done: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Week").eyebrow()
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(plan.week)").font(Theme.display(84))
                        Text("/\(Generator.mesocycleWeeks)").font(Theme.display(28)).foregroundStyle(Theme.muted)
                    }
                    .padding(.top, -10)
                    Text(Generator.weekLabel(plan.week).uppercased())
                        .font(Theme.label(12))
                        .tracking(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(plan.deload ? Color.orange.opacity(0.25) : Theme.lime.opacity(0.18)))
                        .foregroundStyle(plan.deload ? .orange : Theme.lime)
                }
                Spacer()
                ZStack {
                    ProgressRing(progress: Double(done) / Double(max(1, plan.sessions.count)), lineWidth: 12)
                    VStack(spacing: 0) {
                        Text("\(done)/\(plan.sessions.count)").font(Theme.display(26)).monospacedDigit()
                        Text("done").eyebrow()
                    }
                }
                .frame(width: 110, height: 110)
            }
            HStack(spacing: 6) {
                ForEach(1...Generator.mesocycleWeeks, id: \.self) { w in
                    Button { model.setWeek(w) } label: {
                        Capsule()
                            .fill(w == plan.week ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white.opacity(w < plan.week ? 0.35 : 0.12)))
                            .frame(height: 6)
                    }
                    .accessibilityLabel("Week \(w)")
                }
            }
            Text("\(profile.goal.config.label) · \(profile.sessionsPerWeek)×/week · \(plan.sessionMinutes) min"
                + (profile.climbingDaysPerWeek > 0 ? " · \(profile.climbingDaysPerWeek) climbing days" : ""))
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }
}

private struct NextUpCard: View {
    let session: Session
    let onStart: () -> Void

    private var lead: WorkoutEngine.Category {
        session.blocks.first { $0.kind == .strength }?.kind.category ?? .strength
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next up · \(session.dayLabel)").font(Theme.label(12)).tracking(1.4).foregroundStyle(.white.opacity(0.8))
                    Text(session.focus.label).font(Theme.display(30)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
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
                    Label("Start workout", systemImage: "play.fill")
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

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(String(format: "%02d", session.index + 1))
                .font(Theme.display(34))
                .foregroundStyle(done ? Theme.lime : .white.opacity(0.9))
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(session.focus.label).font(.system(.headline, design: .rounded).weight(.heavy))
                    Spacer()
                    if done {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.lime)
                    } else {
                        Text("\(session.estMin)′").font(Theme.label(14)).foregroundStyle(Theme.muted)
                    }
                }
                if let day = session.weekday {
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

/// Ready-made example workout: name, calories, exercise count, activity points.
struct ExampleRowCard: View {
    let template: WorkoutTemplate
    let done: Bool

    var body: some View {
        let session = template.session
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(template.name).font(.system(.headline, design: .rounded).weight(.heavy))
                Spacer()
                if done {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.lime)
                } else {
                    Text("\(session.estMin)′").font(Theme.label(14)).foregroundStyle(Theme.muted)
                }
            }
            HStack {
                Text("\(template.kcal) kcal · \(template.items.count) exercises").font(.caption.weight(.semibold))
                Spacer()
                Text("\(template.activityPoints) activity points")
                    .font(Theme.label(12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.lime.opacity(0.18)))
                    .foregroundStyle(Theme.lime)
            }
            Text(session.topMuscles(4).map(\.name).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .card()
    }
}

/// Weekday of a scheduled session, plus how it sits relative to climbing days.
struct SessionDayLine: View {
    let weekday: Int
    let climbing: [Int]

    var body: some View {
        HStack(spacing: 6) {
            Text(WeekSchedule.name(weekday).uppercased())
                .font(Theme.label(12))
                .tracking(1)
                .foregroundStyle(Theme.lime)
            if let note = WeekSchedule.note(weekday: weekday, climbing: climbing) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
    }
}
