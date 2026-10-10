import SwiftUI
import UIKit
import WorkoutEngine

/// Full-screen, one-exercise-at-a-time workout mode: current-set card with steppers, one-tap effort during rest,
/// up-next preview, Live Activity, pause/resume (#55, #57) and finish summary.
struct WorkoutPlayerView: View {
    let sessionId: String
    /// DEBUG screenshots: open on the rest screen after set 1.
    var demoRest = false
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var record: WorkoutRecord?

    @State private var index = 0
    @State private var setsDone: [String: Int] = [:]
    @State private var pause: Pause?
    @State private var timed: TimedRun?
    /// Superset/circuit: step to open when the rest/effort overlay closes (#78).
    @State private var pendingJump: Int?
    @State private var started = Date()
    @State private var finished = false
    @State private var ready = false
    @State private var closing = false
    @State private var discarded = false
    @State private var formFor: Exercise?
    @State private var prFor: Exercise?
    @State private var log = SetLogState()
    @State private var live = LiveWorkout()

    /// Overlay after a set: optional rest countdown and the one-tap effort picker for that set.
    struct Pause: Equatable {
        var start = Date()
        var end: Date?
        var total = 0
        var effortSet: Int?
        var effort: Effort?
    }

    private struct Step {
        let item: PlannedExercise
        let block: Block
        var exercise: Exercise { Exercise.get(item.exerciseId) }
        var sets: Int { max(1, item.prescription.sets) }
        /// Per-set kg × reps logging applies (loaded strength work counted in reps).
        var loggable: Bool { block.kind == .strength && !exercise.equipment.isEmpty && exercise.unit != .sec }
        /// Work time when the prescription is timed ("4 min", "30 s", intervals).
        var timedSpec: TimedSpec? { TimedSpec(item.prescription, unit: exercise.unit) }
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
                } else if ready, steps.indices.contains(index) {
                    player(steps[index], session: session)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $formFor) { FormSheet(exercise: $0) }
        .fullScreenCover(item: $prFor) { PRAttemptView(exerciseId: $0.id) }
        .confirmationDialog("Leave workout?", isPresented: $closing, titleVisibility: .visible) {
            Button("Pause · resume later") { pauseAndClose() }
            Button("Finish & save now") { finish() }
            Button("Discard workout", role: .destructive) { discard() }
        } message: {
            Text("Paused workouts continue at this exercise and set.")
        }
        .animation(.spring(duration: 0.4), value: index)
        .animation(.spring(duration: 0.5), value: finished)
        .animation(.spring(duration: 0.3), value: pause)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            resumeOrBegin()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            saveProgress()
            live.end()
        }
        .onChange(of: index) { reloadLog(); saveProgress(); updateLive() }
        .onChange(of: setsDone) { saveProgress(); updateLive() }
        .onChange(of: pause) { updateLive() }
        .onChange(of: log.rows) { updateLive() }
        .onChange(of: scenePhase) { _, p in if p != .active { saveProgress() } }
        .onReceive(NotificationCenter.default.publisher(for: .workoutRestAdd15)) { _ in extendRest() }
        .onReceive(NotificationCenter.default.publisher(for: .workoutRestSkip)) { _ in closePause() }
    }

    // MARK: Player

    @ViewBuilder
    private func player(_ step: Step, session: Session) -> some View {
        let cat = step.block.kind.category
        let sets = step.sets
        let done = setsDone[step.item.uid] ?? 0

        ZStack(alignment: .top) {
            RadialGradient(colors: [cat.colors[0].opacity(0.35), .clear], center: .top, startRadius: 10, endRadius: 560)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                topBar(session)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        ExerciseHeroCard(exercise: step.exercise, block: step.block, item: step.item,
                                         position: "\(index + 1)/\(steps.count)",
                                         onAttemptPR: step.loggable ? { prFor = step.exercise } : nil) { formFor = step.exercise }
                            .id(step.item.uid)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        if let run = timed, run.uid == step.item.uid {
                            TimedRing(run: run, color: [cat.colors[1], cat.colors[0]])
                        }
                        if step.loggable && log.item?.uid == step.item.uid {
                            SetLogCard(state: log, done: done)
                        }
                    }
                    .padding(.bottom, 4)
                }

                if step.loggable && done < sets && log.item?.uid == step.item.uid {
                    CurrentSetCard(state: log, set: done)
                }
                if let next = upNext(after: step, done: done, sets: sets, includeSets: false) {
                    UpNextCard(title: next.title, eyebrow: next.eyebrow, detail: next.detail, exercise: next.exercise, colors: next.colors)
                }
                if sets > 1 { setDots(sets: sets, done: done, color: cat.colors[0]) }
                controls(step, sets: sets, done: done)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            if let p = pause {
                PauseOverlay(
                    pause: p, color: cat.colors[0],
                    doneLabel: p.effortSet.flatMap { i in log.values(i).map { "Set \(i + 1) done · \(LoadAdvisor.formatKg($0.kg)) × \($0.reps)" } }
                        ?? "Set \(done) done",
                    drill: step.item.pairedWith.flatMap(Exercise.find),
                    next: upNext(after: step, done: done, sets: sets, includeSets: true)
                ) { effort in
                    pickEffort(effort)
                } onExtend: {
                    extendRest()
                } onSkip: {
                    closePause()
                }
            }
        }
        .task(id: timed?.end) {
            // Timed set over: count it and buzz.
            guard let run = timed, let end = run.end, run.uid == step.item.uid else { return }
            let wait = end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, timed == run else { return }
            timed = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            completeSet(step, sets: sets, done: setsDone[step.item.uid] ?? 0)
        }
    }

    struct UpNext {
        var eyebrow: String
        var title: String
        var detail: String
        var exercise: Exercise?
        var colors: [Color]
    }

    /// Next set of this exercise (when `includeSets`) or the next exercise.
    private func upNext(after step: Step, done: Int, sets: Int, includeSets: Bool) -> UpNext? {
        let cat = step.block.kind.category
        // Superset/circuit: the next member (no rest) or the round's first member (after the rest).
        if includeSets || done < sets, let j = groupJump(step, done: includeSets ? done : done + 1), j.index != index {
            guard steps.indices.contains(j.index) else { return nil }
            let n = steps[j.index]
            let inGroup = isMember(n, of: step)
            let nd = setsDone[n.item.uid] ?? 0
            return UpNext(
                eyebrow: !inGroup ? "Up next" : j.rest == 0 ? "\(n.item.group ?? "") · no rest, go" : "\(n.item.group ?? "") · next round",
                title: n.exercise.name,
                detail: inGroup ? "Set \(nd + 1) of \(n.sets) · \(n.item.prescription.reps)" : Format.prescription(n.item.prescription),
                exercise: n.exercise,
                colors: n.block.kind.category.colors)
        }
        if includeSets, done < sets {
            let detail = step.loggable ? log.values(done).map { "\(LoadAdvisor.formatKg($0.kg)) kg × \($0.reps)" } ?? "" : step.item.prescription.reps
            return UpNext(eyebrow: "Next · set \(done + 1) of \(sets)", title: step.exercise.name, detail: detail, exercise: nil, colors: cat.colors)
        }
        guard steps.indices.contains(index + 1) else { return nil }
        let n = steps[index + 1]
        let left = sets - done
        return UpNext(
            eyebrow: left > 0 && !includeSets ? "Up next · after \(left) set\(left == 1 ? "" : "s")" : "Up next",
            title: n.exercise.name,
            detail: Format.prescription(n.item.prescription),
            exercise: n.exercise,
            colors: n.block.kind.category.colors)
    }

    private func topBar(_ session: Session) -> some View {
        HStack(spacing: 12) {
            Button { closing = true } label: {
                Image(systemName: "pause.fill").font(.system(size: 16, weight: .heavy))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.cardStrong))
            }
            .accessibilityLabel("Pause or leave workout")
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
                    .frame(height: 8)
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
                mainAction(step, sets: sets, done: done)
            } label: {
                Text(mainLabel(step, sets: sets, done: done))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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

    private func mainLabel(_ step: Step, sets: Int, done: Int) -> String {
        if done >= sets { return index == steps.count - 1 ? "FINISH" : "NEXT" }
        if let spec = step.timedSpec {
            guard let run = timed, run.uid == step.item.uid else { return "START \(Format.elapsed(Double(spec.workSec)))" }
            return run.end == nil ? "RESUME" : "PAUSE"
        }
        return "SET \(done + 1) DONE"
    }

    // MARK: Actions

    /// Lime button: timed work starts / pauses its countdown (which completes the set at 0); otherwise completes the set.
    private func mainAction(_ step: Step, sets: Int, done: Int) {
        guard done < sets, let spec = step.timedSpec else { return completeSet(step, sets: sets, done: done) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard var run = timed, run.uid == step.item.uid else {
            timed = TimedRun(uid: step.item.uid, total: spec.workSec, remaining: Double(spec.workSec),
                             end: Date().addingTimeInterval(Double(spec.workSec)))
            return
        }
        if let end = run.end {
            run.remaining = max(0, end.timeIntervalSinceNow)
            run.end = nil
        } else {
            run.end = Date().addingTimeInterval(run.remaining)
        }
        timed = run
    }

    private func completeSet(_ step: Step, sets: Int, done: Int) {
        guard done < sets else { return advance(step) }
        let now = done + 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let logged = step.loggable && log.item?.uid == step.item.uid && log.log(done, model: model)
        setsDone[step.item.uid] = now
        if now >= sets { model.setTicked(step.item.uid) }
        // Superset/circuit: on to the next member without rest, rest after the round (#78).
        let jump = groupJump(step, done: now)
        let target = jump.flatMap { $0.index == index ? nil : $0.index }
        let rest = jump?.rest ?? (now < sets ? step.timedSpec?.easySec ?? step.item.prescription.restSec : 0)
        // Last set: straight on to the next exercise (after the effort tap when the set was logged).
        guard rest > 0 || logged else {
            if let target { return moveTo(target) }
            if now >= sets { advance(step) }
            return
        }
        pendingJump = target
        var effort: Effort?
        if logged, let rir = log.values(done)?.rir { effort = Effort(rir: rir) }
        pause = Pause(
            end: rest > 0 ? Date().addingTimeInterval(TimeInterval(rest)) : nil, total: rest,
            effortSet: logged ? done : nil, effort: effort)
    }

    private func pickEffort(_ e: Effort) {
        guard var p = pause, let i = p.effortSet else { return }
        log.setRIR(i, e.rir, model: model)
        p.effort = e
        // No rest running (last set): the tap closes the overlay and moves on.
        if p.end == nil { closePause() } else { pause = p }
    }

    /// Closes the rest/effort overlay; after an exercise's last set this moves to the next exercise.
    private func closePause() {
        pause = nil
        if let j = pendingJump {
            pendingJump = nil
            return moveTo(j)
        }
        guard steps.indices.contains(index) else { return }
        let step = steps[index]
        if (setsDone[step.item.uid] ?? 0) >= step.sets { advance(step) }
    }

    private func extendRest() {
        guard var p = pause, let end = p.end else { return }
        let base = max(end, Date())
        p.end = base.addingTimeInterval(15)
        p.total += Int(base.timeIntervalSince(end)) + 15
        pause = p
    }

    private func advance(_ step: Step) {
        if (setsDone[step.item.uid] ?? 0) >= step.sets { model.setTicked(step.item.uid) }
        if index >= steps.count - 1 {
            finish()
        } else {
            go(index + 1)
        }
    }

    private func finish() {
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
        model.clearActiveWorkout(sessionId)
        live.end()
        pause = nil
        finished = true
    }

    private func pauseAndClose() {
        saveProgress()
        live.end()
        dismiss()
    }

    private func discard() {
        model.clearActiveWorkout(sessionId)
        discarded = true
        live.end()
        dismiss()
    }

    private func go(_ i: Int) {
        guard steps.indices.contains(i) else { return }
        pause = nil
        pendingJump = nil
        timed = nil
        index = i
    }

    /// Step index `i`, or the finish when it is past the last step.
    private func moveTo(_ i: Int) {
        if i >= steps.count { finish() } else { go(i) }
    }

    // MARK: Supersets and circuits (#78)

    private func isMember(_ other: Step, of step: Step) -> Bool {
        step.block.groupMembers(of: step.item.uid).contains { $0.uid == other.item.uid }
    }

    /// Where a grouped exercise goes once `done` of its sets are done: the next member (rest 0), the round's first
    /// member (after the group's rest), or when the whole group is done the first unfinished step after it (an index
    /// past the last step means finish). nil for straight sets.
    private func groupJump(_ step: Step, done: Int) -> (index: Int, rest: Int)? {
        let members = step.block.groupMembers(of: step.item.uid)
        guard step.item.group != nil, members.count > 1 else { return nil }
        var sets = setsDone
        sets[step.item.uid] = done
        if let n = step.block.next(after: step.item.uid, setsDone: sets) {
            guard let i = steps.firstIndex(where: { $0.item.uid == n.uid }) else { return nil }
            return (i, n.restSec)
        }
        let uids = Set(members.map(\.uid))
        guard let first = steps.firstIndex(where: { uids.contains($0.item.uid) }) else { return nil }
        let open = steps.indices.first { i in
            i > first && !uids.contains(steps[i].item.uid) && (sets[steps[i].item.uid] ?? 0) < steps[i].sets
        }
        return (open ?? steps.count, 0)
    }

    // MARK: Progress + Live Activity

    private func resumeOrBegin() {
        guard !ready, let session else { return }
        if let w = model.activeWorkout(sessionId) {
            index = min(max(0, w.index), max(0, steps.count - 1))
            setsDone = w.setsDone
            started = Date().addingTimeInterval(-w.elapsed)
        } else {
            model.beginWorkout(session)
            started = Date()
        }
        reloadLog()
        ready = true
        live.start(title: session.displayTitle, startedAt: started, state: liveState())
        #if DEBUG
        if demoRest, steps.indices.contains(index) {
            let s = steps.firstIndex { $0.loggable } ?? index
            index = s
            reloadLog()
            completeSet(steps[s], sets: steps[s].sets, done: setsDone[steps[s].item.uid] ?? 0)
        }
        #endif
    }

    private func reloadLog() {
        guard steps.indices.contains(index), steps[index].loggable else { return }
        log.load(item: steps[index].item, sessionId: sessionId, model: model)
    }

    private func saveProgress() {
        guard ready, !finished, !discarded else { return }
        model.saveActiveWorkout(ActiveWorkout(
            sessionId: sessionId, index: index, setsDone: setsDone,
            elapsed: Date().timeIntervalSince(started), updatedAt: Date()))
    }

    private func liveState() -> WorkoutActivityAttributes.ContentState {
        guard steps.indices.contains(index) else {
            return .init(exercise: "", setLabel: "", detail: "", next: "", tint: 0xCCFF3D)
        }
        let step = steps[index]
        let done = setsDone[step.item.uid] ?? 0
        let current = min(done, step.sets - 1)
        let next = upNext(after: step, done: done, sets: step.sets, includeSets: true)
        let detail = step.loggable ? log.values(current).map { "\(LoadAdvisor.formatKg($0.kg)) × \($0.reps)" } ?? "" : ""
        return .init(
            exercise: step.exercise.name,
            setLabel: step.sets > 1 ? "Set \(current + 1) of \(step.sets)" : Format.prescription(step.item.prescription),
            detail: detail,
            restStart: pause?.end == nil ? nil : pause?.start,
            restEnd: pause?.end,
            next: next.map { $0.detail.isEmpty ? $0.title : "\($0.title) · \($0.detail)" } ?? "Finish",
            tint: step.block.kind.category.tintHex)
    }

    private func updateLive() {
        guard ready, !finished else { return }
        live.update(liveState())
    }
}

/// Over the player after a set: what was done, one-tap effort, rest countdown and what's next.
private struct PauseOverlay: View {
    let pause: WorkoutPlayerView.Pause
    let color: Color
    let doneLabel: String
    /// Mobility drill paired with this exercise, done during rest.
    let drill: Exercise?
    let next: WorkoutPlayerView.UpNext?
    let onEffort: (Effort) -> Void
    let onExtend: () -> Void
    let onSkip: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            let left = max(0, (pause.end ?? .now).timeIntervalSince(ctx.date))
            VStack(spacing: 20) {
                Spacer(minLength: 0)
                Text(doneLabel).eyebrow()
                if pause.effortSet != nil {
                    EffortPicker(selected: pause.effort, onPick: onEffort)
                }
                if pause.end != nil {
                    ZStack {
                        ProgressRing(progress: left / Double(max(1, pause.total)), lineWidth: 14, colors: [color, Theme.lime])
                        VStack(spacing: 0) {
                            Text(left > 0 ? "Rest" : "Go!").eyebrow()
                            Text(Format.rest(Int(left.rounded(.up)))).font(Theme.display(54)).monospacedDigit()
                        }
                    }
                    .frame(width: 190, height: 190)
                    .accessibilityElement(children: .combine)
                }
                HStack(spacing: 14) {
                    if pause.end != nil {
                        Button("+15 s", action: onExtend)
                            .font(Theme.label(15))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Theme.cardStrong))
                    }
                    Button(pause.end == nil ? "Continue" : left > 0 ? "Skip" : "Continue", action: onSkip)
                        .font(Theme.label(15))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Theme.lime))
                        .foregroundStyle(Theme.ink)
                }
                if let drill, pause.end != nil {
                    UpNextCard(title: drill.name, eyebrow: "During rest", detail: "5–6 slow reps", exercise: drill,
                               colors: WorkoutEngine.Category.mobility.colors)
                }
                if let next {
                    UpNextCard(title: next.title, eyebrow: next.eyebrow, detail: next.detail, exercise: next.exercise, colors: next.colors)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .background(Theme.bg.opacity(0.6))
        }
        .foregroundStyle(.white)
        .transition(.opacity)
        .task(id: pause.end) {
            guard let end = pause.end else { return }
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
