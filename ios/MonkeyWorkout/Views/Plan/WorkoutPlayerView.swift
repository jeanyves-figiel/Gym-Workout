import SwiftUI
import UIKit
import WorkoutEngine

/// Full-screen, one-exercise-at-a-time workout mode with set tracking, auto rest timer and finish summary.
struct WorkoutPlayerView: View {
    let sessionId: String
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @State private var record: WorkoutRecord?
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var setsDone: [String: Int] = [:]
    @State private var restEnd: Date?
    @State private var restTotal = 0
    @State private var started = Date()
    @State private var finished = false
    @State private var kgText = ""
    @State private var formFor: Exercise?

    private struct Step {
        let item: PlannedExercise
        let block: Block
        var exercise: Exercise { Exercise.get(item.exerciseId) }
    }

    private var session: Session? { model.session(sessionId) }
    private var steps: [Step] { session?.blocks.flatMap { b in b.items.map { Step(item: $0, block: b) } } ?? [] }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let session {
                if finished {
                    SummaryView(session: session, elapsed: Date().timeIntervalSince(started), setsDone: setsDone.values.reduce(0, +),
                                kcal: record?.kcal, healthSaved: health.connected && health.writeWorkouts) {
                        dismiss()
                    }
                    .transition(.scale.combined(with: .opacity))
                } else if steps.indices.contains(index) {
                    player(steps[index], session: session)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $formFor) { FormSheet(exercise: $0) }
        .animation(.spring(duration: 0.4), value: index)
        .animation(.spring(duration: 0.5), value: finished)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: Player

    @ViewBuilder
    private func player(_ step: Step, session: Session) -> some View {
        let cat = step.block.kind.category
        let sets = max(1, step.item.prescription.sets)
        let done = setsDone[step.item.uid] ?? 0

        ZStack(alignment: .top) {
            RadialGradient(colors: [cat.colors[0].opacity(0.45), .clear], center: .topLeading, startRadius: 10, endRadius: 520)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                topBar(session)
                HStack {
                    CategoryPill(category: cat, title: step.block.title)
                    Spacer()
                    Text("\(index + 1)/\(steps.count)").font(Theme.label(14)).foregroundStyle(Theme.muted).monospacedDigit()
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(step.exercise.name)
                            .font(Theme.display(40))
                            .minimumScaleFactor(0.6)
                            .lineLimit(3)
                            .id(step.item.uid)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(step.item.prescription.sets > 1 ? "\(step.item.prescription.sets) × \(step.item.prescription.reps)" : step.item.prescription.reps)
                                .font(Theme.display(30))
                                .foregroundStyle(cat.colors[1])
                            if step.item.prescription.restSec > 0 {
                                Text("rest \(Format.rest(step.item.prescription.restSec))").font(Theme.label(14)).foregroundStyle(Theme.muted)
                            }
                        }
                        EquipmentLine(equipment: step.exercise.equipment)
                        if let i = step.item.prescription.intensity { Text(i).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted) }
                        if let n = step.item.prescription.note { Text(n).font(.footnote).foregroundStyle(Theme.muted) }

                        HStack(alignment: .top, spacing: 14) {
                            HStack(spacing: 6) {
                                BodyMapView(side: .front, heat: step.exercise.heat, showLabel: false)
                                BodyMapView(side: .back, heat: step.exercise.heat, showLabel: false)
                            }
                            .frame(width: 130, height: 160)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Working").eyebrow()
                                MuscleChips(primary: step.exercise.primary, secondary: step.exercise.secondary)
                            }
                        }
                        .card(padding: 12)

                        if let paired = step.item.pairedWith.flatMap(Exercise.find) {
                            Label("During rest: \(paired.name) · 5–6 slow reps", systemImage: "figure.flexibility")
                                .font(.footnote.weight(.semibold))
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(WorkoutEngine.Category.mobility.color.opacity(0.2)))
                        }
                        if step.block.kind == .strength && !step.exercise.equipment.isEmpty && step.exercise.unit != .sec {
                            weightRow(step)
                        }
                        formCard(step)
                    }
                }

                if let next = steps.indices.contains(index + 1) ? steps[index + 1] : nil {
                    HStack(spacing: 10) {
                        Text("Next").eyebrow()
                        Image(systemName: next.block.kind.symbol).foregroundStyle(next.block.kind.category.color)
                        Text(next.exercise.name).font(.subheadline.weight(.bold)).lineLimit(1)
                        Spacer()
                    }
                    .card(padding: 12)
                }

                setDots(sets: sets, done: done, color: cat.colors[0])
                controls(step, sets: sets, done: done)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            if let end = restEnd {
                RestOverlay(end: end, total: restTotal, color: cat.colors[0]) {
                    restEnd = $0
                } onSkip: {
                    restEnd = nil
                }
            }
        }
    }

    /// Key body-position checkpoints inline; full setup/technique in a sheet.
    private func formCard(_ step: Step) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Form").eyebrow()
                Spacer()
                Button { formFor = step.exercise } label: {
                    Label("Setup & technique", systemImage: "list.bullet.clipboard")
                        .font(Theme.label(12))
                }
                .foregroundStyle(Theme.lime)
            }
            if let t = step.exercise.technique {
                ForEach(t.position.prefix(3), id: \.self) { c in
                    CheckpointRow(checkpoint: c, accent: step.block.kind.category.color)
                }
            } else {
                ForEach(step.exercise.cues, id: \.self) { Text("• \($0)").font(.footnote) }
            }
        }
        .card(padding: 14)
    }

    private func topBar(_ session: Session) -> some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .heavy))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.cardStrong))
            }
            .accessibilityLabel("Close workout")
            HStack(spacing: 3) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    Capsule()
                        .fill(i <= index ? AnyShapeStyle(s.block.kind.gradient) : AnyShapeStyle(Color.white.opacity(0.12)))
                        .frame(height: 5)
                }
            }
            TimelineView(.periodic(from: started, by: 1)) { ctx in
                Text(Format.elapsed(ctx.date.timeIntervalSince(started))).font(Theme.label(14)).monospacedDigit()
            }
        }
        .foregroundStyle(.white)
    }

    private func setDots(sets: Int, done: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<sets, id: \.self) { i in
                Capsule()
                    .fill(i < done ? AnyShapeStyle(color) : AnyShapeStyle(Color.white.opacity(0.12)))
                    .frame(height: 10)
                    .animation(.spring(duration: 0.3), value: done)
            }
        }
        .accessibilityLabel("\(done) of \(sets) sets done")
    }

    private func controls(_ step: Step, sets: Int, done: Int) -> some View {
        HStack(spacing: 12) {
            Button { go(index - 1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .heavy))
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(Theme.cardStrong))
            }
            .disabled(index == 0)
            .accessibilityLabel("Previous exercise")

            Button {
                completeSet(step, sets: sets, done: done)
            } label: {
                Text(done >= sets ? (index == steps.count - 1 ? "FINISH" : "NEXT") : "SET \(done + 1) DONE")
            }
            .buttonStyle(LimeButtonStyle())

            Button { advance(step) } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 18, weight: .heavy))
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(Theme.cardStrong))
            }
            .accessibilityLabel("Skip to next exercise")
        }
        .foregroundStyle(.white)
        .padding(.bottom, 8)
    }

    private func weightRow(_ step: Step) -> some View {
        HStack(spacing: 10) {
            TextField(model.lastWeight(step.exercise.id).map(Format.kg) ?? "kg", text: $kgText)
                .keyboardType(.decimalPad)
                .font(Theme.display(22))
                .frame(width: 90)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardStrong))
            Text("kg").font(Theme.label(14))
            Button("Log") {
                if let v = Double(kgText.replacingOccurrences(of: ",", with: ".")), v >= 0, v <= 1000 {
                    model.logWeight(exerciseId: step.exercise.id, sessionId: sessionId, kg: v)
                    kgText = ""
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .font(Theme.label(14))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Theme.lime))
            .foregroundStyle(Theme.ink)
            .disabled(kgText.isEmpty)
            if let last = model.lastWeight(step.exercise.id) {
                Text("last \(Format.kg(last))").font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: Actions

    private func completeSet(_ step: Step, sets: Int, done: Int) {
        guard done < sets else { return advance(step) }
        let now = done + 1
        setsDone[step.item.uid] = now
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if now >= sets {
            model.setTicked(step.item.uid)
        } else if step.item.prescription.restSec > 0 {
            restTotal = step.item.prescription.restSec
            restEnd = Date().addingTimeInterval(TimeInterval(restTotal))
        }
    }

    private func advance(_ step: Step) {
        if (setsDone[step.item.uid] ?? 0) >= max(1, step.item.prescription.sets) { model.setTicked(step.item.uid) }
        if index >= steps.count - 1 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if let session, record == nil {
                let r = model.recordWorkout(
                    session: session, setsDone: setsDone, startedAt: started, endedAt: Date(),
                    bodyMassKg: health.snapshot.weightKg ?? model.body.weightKg)
                record = r
                Task {
                    let hr = await health.save(r)
                    model.attachHeartRate(r.id, avg: hr.avg, max: hr.max)
                }
            }
            finished = true
        } else {
            go(index + 1)
        }
    }

    private func go(_ i: Int) {
        guard steps.indices.contains(i) else { return }
        restEnd = nil
        kgText = ""
        index = i
    }
}

/// Big countdown ring over the player.
private struct RestOverlay: View {
    let end: Date
    let total: Int
    let color: Color
    let onExtend: (Date) -> Void
    let onSkip: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            let left = max(0, end.timeIntervalSince(ctx.date))
            VStack(spacing: 24) {
                Text(left > 0 ? "Rest" : "Go!").eyebrow()
                ZStack {
                    ProgressRing(progress: left / Double(max(1, total)), lineWidth: 16, colors: [color, Theme.lime])
                    Text(Format.rest(Int(left.rounded(.up)))).font(Theme.display(64)).monospacedDigit()
                }
                .frame(width: 230, height: 230)
                HStack(spacing: 14) {
                    Button("+15 s") { onExtend(end.addingTimeInterval(15)) }
                        .font(Theme.label(15))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Theme.cardStrong))
                    Button(left > 0 ? "Skip" : "Continue") { onSkip() }
                        .font(Theme.label(15))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Theme.lime))
                        .foregroundStyle(Theme.ink)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .background(Theme.bg.opacity(0.6))
        }
        .foregroundStyle(.white)
        .transition(.opacity)
        .task(id: end) {
            let wait = end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            if !Task.isCancelled { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        }
    }
}

/// Finish screen: stats + the muscles this session hit.
private struct SummaryView: View {
    let session: Session
    let elapsed: TimeInterval
    let setsDone: Int
    let kcal: Double?
    let healthSaved: Bool
    let onDone: () -> Void
    @State private var pop = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(LinearGradient(colors: [Theme.lime, .yellow], startPoint: .top, endPoint: .bottom))
                    .scaleEffect(pop ? 1 : 0.3)
                    .symbolEffect(.bounce, value: pop)
                    .padding(.top, 30)
                Text("Session\ncomplete").font(Theme.display(48)).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    StatTile(value: Format.elapsed(elapsed), label: "Time")
                    StatTile(value: "\(setsDone)", label: "Sets")
                    if let kcal { StatTile(value: "\(Int(kcal))", label: "kcal") }
                    StatTile(value: "\(session.blocks.reduce(0) { $0 + $1.items.count })", label: "Moves")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Muscles hit").eyebrow()
                    BodyMapPair(heat: session.muscleHeat).frame(height: 260)
                    FlowLayout(spacing: 6) { ForEach(session.topMuscles(8)) { MuscleChip(muscle: $0) } }
                }
                .card()
                if healthSaved {
                    Label("Saved to Apple Health", systemImage: "heart.fill").font(Theme.label(13)).foregroundStyle(.pink)
                }
                Text("Added to your history in Progress.").font(.footnote).foregroundStyle(Theme.muted)
                Button(action: onDone) { Text("DONE") }
                    .buttonStyle(LimeButtonStyle())
            }
            .padding(20)
        }
        .onAppear { withAnimation(.spring(duration: 0.6, bounce: 0.5)) { pop = true } }
    }
}
