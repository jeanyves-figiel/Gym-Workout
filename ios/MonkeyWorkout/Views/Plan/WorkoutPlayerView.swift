import SwiftUI
import UIKit
import WorkoutEngine

/// Full-screen, one-exercise-at-a-time workout mode: current-set card with steppers, one-tap effort during rest,
/// up-next preview, Live Activity, pause/resume (#55, #57) and finish summary.
struct WorkoutPlayerView: View {
    let sessionId: String
    /// DEBUG screenshots: open on the rest screen after set 1.
    var demoRest = false
    /// DEBUG screenshots: "timed" = first timed item with its countdown running; "logged" = strength item after 1 set.
    var demoMode: String?
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var record: WorkoutRecord?
    /// What this workout earned (#227): XP, level-up, week chest, new badges.
    @State private var reward: GameReward?

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
    /// "Not here?" (#162): the planned item whose equipment the gym lacks.
    @State private var notHereFor: PlannedExercise?
    @State private var gate: ProGate?
    @State private var log = SetLogState()
    /// Done set opened for a correction in the set card.
    @State private var editingSet: Int?
    @State private var live = LiveWorkout()
    /// Finish early (#300): the remaining workout re-fitted to the time left, and the time to be done by.
    @State private var fitted: [Block]?
    @State private var fitEnd: Date?
    @State private var finishingEarly = false
    /// What the last fit changed, shown with Undo for a few seconds.
    @State private var fitBanner: String?
    /// Workout map (#361): what's done and what's left, read-only.
    @State private var mapOpen = false
    /// "Next in 5" after an exercise's last set (#357); nil = not counting.
    @State private var autoNext: AutoNext?
    @AppStorage(AutoNextPref.key) private var autoNextSec = AutoNextPref.fallback

    struct AutoNext: Equatable {
        let uid: String
        let end: Date
        let total: Int
    }

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
        /// Per-set kg × reps logging applies: loaded strength work counted in reps. Timed work and cardio machines
        /// (e.g. a cross-trainer inside a custom workout's strength block) only run the timer.
        var loggable: Bool {
            block.kind == .strength && !exercise.equipment.isEmpty && exercise.unit != .sec && timedSpec == nil
                && category == .strength
        }
        var category: WorkoutEngine.Category { ExerciseHeroCard.category(exercise, in: block) }
        /// Work time when the prescription is timed ("4 min", "30 s", intervals).
        var timedSpec: TimedSpec? { TimedSpec(item.prescription, unit: exercise.unit) }
    }

    private var session: Session? {
        guard let s = model.session(sessionId) else { return nil }
        guard let fitted else { return s }
        var out = s
        out.blocks = fitted
        out.estMin = max(1, s.estMin + Int((Double(fitted.estSec - s.blocks.estSec) / 60).rounded()))
        return out
    }
    private var steps: [Step] { session?.blocks.flatMap { b in b.items.map { Step(item: $0, block: b) } } ?? [] }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let session {
                if finished {
                    SummaryView(session: session, elapsed: Date().timeIntervalSince(started), setsDone: setsDone.values.reduce(0, +),
                                kcal: record?.kcal, healthSaved: health.connected && health.writeWorkouts, reward: reward) {
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
        .sheet(item: $notHereFor) { NotHereSheet(exerciseId: $0.exerciseId, uid: $0.uid) }
        .fullScreenCover(item: $prFor) { PRAttemptView(exerciseId: $0.id) }
        .proPaywall($gate)
        .sheet(isPresented: $finishingEarly) {
            if let base = model.session(sessionId), steps.indices.contains(index) {
                FinishEarlySheet(blocks: base.blocks, setsDone: setsDone, current: steps[index].item.uid, fitted: fitted != nil,
                                 onFit: { finishEarly(minutes: $0) }, onUndo: undoFinishEarly)
            }
        }
        .sheet(isPresented: $mapOpen) {
            if let session, steps.indices.contains(index) {
                WorkoutMapSheet(blocks: session.blocks, setsDone: setsDone, current: steps[index].item.uid)
            }
        }
        .confirmationDialog("Leave workout?", isPresented: $closing, titleVisibility: .visible) {
            Button("See what's left") { mapOpen = true }
            Button("Pause · resume later") { pauseAndClose() }
            Button("Short on time? Finish early") { finishingEarly = true }
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
            if !finished, !discarded { WatchSync.shared.endLive(.paused, sessionId: sessionId) }
        }
        .onChange(of: index) { reloadLog(); saveProgress(); updateLive() }
        .onChange(of: setsDone) { saveProgress(); updateLive() }
        .onChange(of: pause) { updateLive() }
        .onChange(of: log.rows) { updateLive() }
        .onChange(of: scenePhase) { _, p in if p != .active { saveProgress(interrupted: p == .background) } }
        .onReceive(NotificationCenter.default.publisher(for: .workoutRestAdd15)) { _ in extendRest() }
        .onReceive(NotificationCenter.default.publisher(for: .workoutRestSkip)) { _ in closePause() }
        .onReceive(NotificationCenter.default.publisher(for: .watchCommand)) { n in
            if let c = n.object as? WCommand { handle(c) }
        }
    }

    // MARK: Player

    @ViewBuilder
    private func player(_ step: Step, session: Session) -> some View {
        let cat = step.category
        let sets = step.sets
        let done = setsDone[step.item.uid] ?? 0

        ZStack(alignment: .top) {
            RadialGradient(colors: [cat.colors[0].opacity(0.35), .clear], center: .top, startRadius: 10, endRadius: 560)
                .ignoresSafeArea()

            // One screen, no scrolling (#206): the exercise card's picture takes whatever height is left, so the target, the one
            // input for this item (set card or timer), up next and the controls are always fully on screen.
            VStack(alignment: .leading, spacing: 12) {
                topBar(session)
                if let fitBanner {
                    FinishEarlyBanner(text: fitBanner, onUndo: undoFinishEarly)
                }

                ExerciseHeroCard(exercise: step.exercise, block: step.block, item: step.item,
                                 position: "\(index + 1)/\(steps.count)",
                                 onAttemptPR: step.loggable ? { ProStore.shared.run(.prAttempt, $gate) { prFor = step.exercise } } : nil,
                                 onNotHere: !step.exercise.equipment.isEmpty && model.canSwap(uid: step.item.uid) && done == 0
                                     ? { notHereFor = step.item } : nil) { formFor = step.exercise }
                    .id(step.item.uid)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    .layoutPriority(1)

                // The free space under the card shows what's coming (#361), only when it fits whole: nothing is pushed off screen.
                // An overlay on the free space takes no height of its own: the exercise picture keeps its full size.
                Color.clear
                    .frame(maxHeight: .infinity)
                    .overlay {
                        ViewThatFits(in: .vertical) {
                            ComingUpStrip(items: OverviewItem.list(session.blocks, setsDone: setsDone, current: step.item.uid),
                                          doneBy: OverviewItem.doneBy(session.blocks, setsDone: setsDone, current: step.item.uid),
                                          onPeek: { formFor = $0 }, onMap: { mapOpen = true })
                            Color.clear
                        }
                    }
                setCard(step, sets: sets, done: done, colors: cat.colors)
                if let next = upNext(after: step, done: done, sets: sets, includeSets: false) {
                    UpNextCard(title: next.title, eyebrow: next.eyebrow, detail: next.detail, exercise: next.exercise,
                               colors: next.colors, compact: true)
                }
                controls(step, sets: sets, done: done)
                    .overlay(alignment: .bottom) {
                        if let a = autoNext, a.uid == step.item.uid {
                            let next = upNext(after: step, done: done, sets: sets, includeSets: false)
                            AutoNextBar(title: next?.title ?? "", detail: next?.detail ?? "", end: a.end, total: a.total,
                                        finishing: index >= steps.count - 1,
                                        onGo: { advance(step) }, onHold: { autoNext = nil })
                                .padding(.bottom, 8)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .readableColumn()

            if let p = pause {
                PauseOverlay(
                    pause: p, color: cat.colors[0],
                    doneLabel: (step.loggable ? p.effortSet ?? max(0, done - 1) : nil).flatMap { i in
                        log.values(i).map { v in
                            "Set \(i + 1) done · \(LoadAdvisor.formatKg(v.kg)) × \(v.reps)" + (p.effort.map { " · \($0.caption.lowercased())" } ?? "")
                        }
                    } ?? "Set \(done) done",
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
        .task(id: autoNext) {
            // Countdown over: on to the next exercise (a timed one waits for START).
            guard let a = autoNext, a.uid == step.item.uid else { return }
            let wait = a.end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, autoNext == a else { return }
            advance(step)
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

    /// Next set or exercise; another exercise also says where it is (#274): same spot, or the zone to walk to.
    private func upNext(after step: Step, done: Int, sets: Int, includeSets: Bool) -> UpNext? {
        guard var next = baseUpNext(after: step, done: done, sets: sets, includeSets: includeSets) else { return nil }
        if let e = next.exercise, e.id != step.exercise.id, let to = model.gymZone(e.id) {
            let here = model.gymZone(step.exercise.id)
            let cue = here?.id == to.id ? "📍 Same spot" : here.map { _ in "📍 Walk to \(to.name)" } ?? "📍 \(to.name)"
            next.detail = [next.detail, cue].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return next
    }

    /// Next set of this exercise (when `includeSets`) or the next exercise.
    private func baseUpNext(after step: Step, done: Int, sets: Int, includeSets: Bool) -> UpNext? {
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
            // Tap the dots for the workout map (#361).
            Button { mapOpen = true } label: {
                HStack(spacing: 3) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                        Capsule()
                            .fill(i <= index ? AnyShapeStyle(s.block.kind.gradient) : AnyShapeStyle(Color.white.opacity(0.12)))
                            .frame(height: 5)
                    }
                }
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Exercise \(index + 1) of \(steps.count). Open workout map")
            // Tap the clock to finish early (#300); after a fit it counts down to the time to be done by.
            Button { finishingEarly = true } label: {
                TimelineView(.periodic(from: started, by: 1)) { ctx in
                    if let fitEnd {
                        let left = fitEnd.timeIntervalSince(ctx.date)
                        Text((left < 0 ? "+" : "−") + Format.elapsed(abs(left))).font(Theme.label(14)).monospacedDigit()
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(LinearGradient(colors: UndoOffer.warm, startPoint: .leading, endPoint: .trailing)))
                    } else {
                        Text(Format.elapsed(ctx.date.timeIntervalSince(started))).font(Theme.label(14)).monospacedDigit()
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().stroke(Theme.stroke, lineWidth: 1.5))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(fitEnd == nil ? "Workout time. Finish early" : "Time left. Change or undo finish early")
        }
        .foregroundStyle(.white)
    }

    /// The input that fits the item: kg × reps steppers for loaded strength, the countdown for timed work,
    /// set chips for other multi-set work. Exactly one place per item.
    @ViewBuilder
    private func setCard(_ step: Step, sets: Int, done: Int, colors: [Color]) -> some View {
        if step.loggable {
            if log.item?.uid == step.item.uid {
                CurrentSetCard(state: log, done: done, color: colors[0], editing: $editingSet) { i in
                    _ = log.log(i, model: model)
                }
            }
        } else if let spec = step.timedSpec {
            let run = timed.flatMap { $0.uid == step.item.uid ? $0 : nil }
                ?? TimedRun(uid: step.item.uid, total: spec.workSec, remaining: Double(spec.workSec), end: nil)
            TimedSetCard(run: run, sets: sets, done: done, easySec: spec.easySec, colors: colors)
        } else if sets > 1 {
            PlainSetCard(sets: sets, done: done, target: step.item.prescription.reps, color: colors[0])
        }
    }

    private func controls(_ step: Step, sets: Int, done: Int) -> some View {
        Group {
            if step.loggable && done < sets {
                // Loaded sets (#357): the effort tiles are the SET DONE button, so a set and its effort take one tap.
                EffortDoneStrip(setNumber: (editingSet ?? done) + 1) { e in
                    completeSet(step, sets: sets, done: done, effort: e)
                } leading: {
                    previousButton(size: 44)
                } trailing: {
                    skipButton(step, size: 44)
                }
            } else {
                HStack(spacing: 12) {
                    previousButton(size: 58)
                    Button {
                        mainAction(step, sets: sets, done: done)
                    } label: {
                        Text(mainLabel(step, sets: sets, done: done))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .buttonStyle(LimeButtonStyle())
                    skipButton(step, size: 58)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.bottom, 8)
    }

    private func previousButton(size: CGFloat) -> some View {
        Button { go(index - 1) } label: {
            Image(systemName: "chevron.left").font(.system(size: size > 50 ? 20 : 16, weight: .heavy))
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.cardStrong))
        }
        .disabled(index == 0)
        .accessibilityLabel("Previous exercise")
    }

    private func skipButton(_ step: Step, size: CGFloat) -> some View {
        Button { advance(step) } label: {
            Image(systemName: "forward.end.fill").font(.system(size: size > 50 ? 18 : 15, weight: .heavy))
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.cardStrong))
        }
        .accessibilityLabel("Skip to next exercise")
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

    /// `effort`: the tile tapped as SET DONE (#357); nil leaves the rating to the optional picker during rest.
    private func completeSet(_ step: Step, sets: Int, done: Int, effort tapped: Effort? = nil) {
        if let e = editingSet {
            editingSet = nil
            _ = log.log(e, model: model)
        }
        guard done < sets else { return advance(step) }
        let now = done + 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let onScreen = step.loggable && log.item?.uid == step.item.uid
        if onScreen, let tapped, log.rows.indices.contains(done) { log.rows[done].rir = String(tapped.rir) }
        let logged = onScreen && log.log(done, model: model)
        setsDone[step.item.uid] = now
        if now >= sets { model.setTicked(step.item.uid) }
        // Superset/circuit: on to the next member without rest, rest after the round (#78).
        let jump = groupJump(step, done: now)
        let target = jump.flatMap { $0.index == index ? nil : $0.index }
        let rest = jump?.rest ?? (now < sets ? step.timedSpec?.easySec ?? step.item.prescription.restSec : 0)
        // No rest: the next group member at once, or after the last set the "Next in" countdown (#357).
        guard rest > 0 else {
            if let target { return moveTo(target) }
            if now >= sets { nextExercise(step) }
            return
        }
        pendingJump = target
        // A set logged without a rating offers the optional picker during the rest; a rated one shows its effort.
        var effort: Effort?
        if logged, let rir = log.values(done)?.rir { effort = Effort(rir: rir) }
        pause = Pause(
            end: Date().addingTimeInterval(TimeInterval(rest)), total: rest,
            effortSet: logged && effort == nil ? done : nil, effort: effort)
    }

    /// After an exercise's last set: straight on, a "Next in N" countdown, or wait for NEXT (Settings, #357).
    private func nextExercise(_ step: Step) {
        switch autoNextSec {
        case ..<0: return
        case 0: advance(step)
        default:
            autoNext = AutoNext(uid: step.item.uid, end: Date().addingTimeInterval(TimeInterval(autoNextSec)), total: autoNextSec)
        }
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
        if (setsDone[step.item.uid] ?? 0) >= step.sets { nextExercise(step) }
    }

    private func extendRest() {
        guard var p = pause, let end = p.end else { return }
        let base = max(end, Date())
        p.end = base.addingTimeInterval(15)
        p.total += Int(base.timeIntervalSince(end)) + 15
        pause = p
    }

    private func advance(_ step: Step) {
        autoNext = nil
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
            let before = (game: model.game, badges: model.badges)
            let r = model.recordWorkout(
                session: session, setsDone: setsDone, startedAt: started, endedAt: Date(),
                bodyMassKg: health.snapshot.weightKg ?? model.body.weightKg)
            record = r
            reward = GameReward(before: before.game, after: model.game, badgesBefore: before.badges, badgesAfter: model.badges)
            // A Watch tracking this workout saves the Health workout with its heart rate (#347).
            if !WatchSync.shared.watchTracks(sessionId) {
                Task {
                    let hr = await health.save(r)
                    model.attachHeartRate(r.id, avg: hr.avg, max: hr.max)
                }
            }
        }
        model.clearActiveWorkout(sessionId)
        live.end()
        WatchSync.shared.endLive(.finished, sessionId: sessionId, record: record)
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
        WatchSync.shared.endLive(.discarded, sessionId: sessionId)
        dismiss()
    }

    private func go(_ i: Int) {
        guard steps.indices.contains(i) else { return }
        pause = nil
        pendingJump = nil
        timed = nil
        editingSet = nil
        autoNext = nil
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
            fitted = w.fitted
            fitEnd = w.fitEnd
            if w.interrupted == true, Date().timeIntervalSince(w.updatedAt) < AppModel.interruptedWindow {
                // iOS closed the app mid-workout (#359): the time away was training, and a rest may still run.
                started = w.updatedAt.addingTimeInterval(-w.elapsed)
                if let end = w.restEnd, end > Date() {
                    pause = Pause(start: end.addingTimeInterval(-TimeInterval(w.restTotal ?? 0)), end: end, total: w.restTotal ?? 0)
                }
            } else {
                started = Date().addingTimeInterval(-w.elapsed)
            }
        } else {
            model.beginWorkout(session)
            started = Date()
        }
        reloadLog()
        ready = true
        live.start(title: session.displayTitle, startedAt: started, state: liveState())
        WatchSync.shared.offerStart(sessionId: sessionId)
        #if DEBUG
        if demoRest, steps.indices.contains(index) {
            let s = steps.firstIndex { $0.loggable } ?? index
            index = s
            reloadLog()
            completeSet(steps[s], sets: steps[s].sets, done: setsDone[steps[s].item.uid] ?? 0)
        }
        if demoMode == "timed", let s = steps.firstIndex(where: { $0.timedSpec != nil && !$0.loggable }) {
            index = s
            let spec = steps[s].timedSpec!
            timed = TimedRun(uid: steps[s].item.uid, total: spec.workSec, remaining: Double(spec.workSec),
                             end: Date().addingTimeInterval(Double(spec.workSec) - 83))
        }
        if demoMode == "finish" || demoMode == "fitted", let s = steps.firstIndex(where: { $0.block.kind == .strength }) {
            index = s
            reloadLog()
            if demoMode == "finish" { finishingEarly = true } else { finishEarly(minutes: 15) }
        }
        if demoMode == "map", let s = steps.indices.dropFirst(steps.count / 2).first {
            for p in steps[..<s] { setsDone[p.item.uid] = p.sets }
            index = s
            reloadLog()
            mapOpen = true
        }
        if demoMode == "done" {
            reward = Demo.reward
            finished = true
        }
        if demoMode == "next", let s = steps.firstIndex(where: { $0.loggable }), s < steps.count - 1 {
            index = s
            reloadLog()
            setsDone[steps[s].item.uid] = steps[s].sets
            autoNext = AutoNext(uid: steps[s].item.uid, end: Date().addingTimeInterval(64), total: 80)
        }
        if demoMode == "logged", let s = steps.firstIndex(where: { $0.loggable && $0.sets > 2 }) {
            index = s
            reloadLog()
            log.log(0, model: model)
            setsDone[steps[s].item.uid] = 1
        }
        #endif
    }

    private func reloadLog() {
        guard steps.indices.contains(index), steps[index].loggable else { return }
        log.load(item: steps[index].item, sessionId: sessionId, model: model)
    }

    /// `interrupted`: the app is going to the background with the player open (#359), not a pause by the member.
    private func saveProgress(interrupted: Bool = false) {
        guard ready, !finished, !discarded else { return }
        let rest = interrupted ? pause.flatMap { p in p.end.map { (end: $0, total: p.total) } } : nil
        model.saveActiveWorkout(ActiveWorkout(
            sessionId: sessionId, index: index, setsDone: setsDone,
            elapsed: Date().timeIntervalSince(started), updatedAt: Date(), fitted: fitted, fitEnd: fitEnd,
            interrupted: interrupted ? true : nil, restEnd: rest?.end, restTotal: rest?.total))
    }

    // MARK: Finish early (#300)

    /// Re-fits what is left to the minutes given; the player stays on the same exercise.
    private func finishEarly(minutes: Int) {
        guard let base = model.session(sessionId), steps.indices.contains(index) else { return }
        let uid = steps[index].item.uid
        let fit = FinishEarly.fit(base.blocks, setsDone: setsDone, current: uid, minutes: minutes)
        fitted = fit.changed ? fit.blocks : nil
        fitEnd = Date().addingTimeInterval(TimeInterval(max(minutes * 60, fit.leftSec)))
        relocate(uid)
        let parts = [fit.skipped > 0 ? "\(fit.skipped) skipped" : nil, fit.setsCut > 0 ? "\(fit.setsCut) sets less" : nil].compactMap { $0 }
        showBanner("Done by \(fitEnd!.formatted(date: .omitted, time: .shortened))" + (parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")))
    }

    private func showBanner(_ text: String?) {
        withAnimation(.spring(duration: 0.4)) { fitBanner = text }
        guard let text, demoMode == nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(8))
            if fitBanner == text { withAnimation(.spring(duration: 0.4)) { fitBanner = nil } }
        }
    }

    /// Back to the full workout.
    private func undoFinishEarly() {
        guard steps.indices.contains(index) else { return }
        let uid = steps[index].item.uid
        fitted = nil
        fitEnd = nil
        showBanner(nil)
        relocate(uid)
    }

    /// Same item on screen after the step list changed.
    private func relocate(_ uid: String) {
        // A new index reloads the set log through onChange; the same index reloads it only when the item's sets changed.
        let before = log.item?.prescription
        let i = steps.firstIndex { $0.item.uid == uid } ?? min(index, max(0, steps.count - 1))
        if i == index, steps.indices.contains(i), steps[i].item.prescription != before { reloadLog() }
        index = i
        saveProgress()
        updateLive()
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
        guard ready, !finished, !discarded else { return WatchSync.shared.sendLive(nil) }
        let state = liveState()
        live.update(state)
        guard steps.indices.contains(index), let session else { return }
        let step = steps[index]
        WatchSync.shared.sendLive(WLive(
            sessionTitle: session.displayTitle, exercise: state.exercise, setLabel: state.setLabel, detail: state.detail,
            restEnd: state.restEnd, next: state.next, tint: state.tint,
            effortPending: pause?.effortSet != nil && pause?.effort == nil,
            action: mainLabel(step, sets: step.sets, done: setsDone[step.item.uid] ?? 0),
            sessionId: sessionId, estMin: session.estMin, exercises: session.blocks.reduce(0) { $0 + $1.items.count }))
    }

    /// Remote control from the Watch while this player runs on the iPhone.
    private func handle(_ c: WCommand) {
        guard ready, !finished, steps.indices.contains(index) else { return }
        let step = steps[index]
        switch c {
        case .main:
            if pause != nil { closePause() } else if autoNext != nil { advance(step) } else { mainAction(step, sets: step.sets, done: setsDone[step.item.uid] ?? 0) }
        case .skipRest: closePause()
        case .addRest: extendRest()
        case .effort0, .effort1, .effort2, .effort3, .effort4:
            let rir = [WCommand.effort0, .effort1, .effort2, .effort3, .effort4].firstIndex(of: c) ?? 2
            // Rating during rest, or (#357) the rating that completes the coming set.
            let done = setsDone[step.item.uid] ?? 0
            if pause == nil, step.loggable, done < step.sets {
                completeSet(step, sets: step.sets, done: done, effort: Effort(rir: rir))
            } else {
                pickEffort(Effort(rir: rir))
            }
        case .next: advance(step)
        case .previous: go(index - 1)
        }
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
                    EffortPicker(selected: pause.effort, optional: true, onPick: onEffort)
                }
                if pause.end != nil {
                    ZStack {
                        ProgressRing(progress: left / Double(max(1, pause.total)), lineWidth: 14, colors: [color, Theme.lime])
                        VStack(spacing: 0) {
                            Text(left > 3 ? "Rest" : "Get ready").eyebrow()
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
                    Button(pause.end == nil ? "Continue" : "Skip", action: onSkip)
                        .font(Theme.label(15))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Theme.lime))
                        .foregroundStyle(Theme.ink)
                }
                if let drill, pause.end != nil {
                    UpNextCard(title: drill.name, eyebrow: "During rest", detail: "5–6 slow reps", exercise: drill,
                               colors: WorkoutEngine.Category.mobility.colors, compact: true)
                }
                if let next {
                    UpNextCard(title: next.title, eyebrow: next.eyebrow, detail: next.detail, exercise: next.exercise,
                               colors: next.colors, compact: true)
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
            // 3-2-1 taps, then the rest closes by itself (#357): no Continue tap.
            guard let end = pause.end else { return }
            for tick in [3.0, 2.0, 1.0] {
                let wait = end.timeIntervalSinceNow - tick
                guard wait > -0.5 else { continue }
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled else { return }
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            }
            let wait = end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            onSkip()
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
    var reward: GameReward?
    let onDone: () -> Void
    @State private var pop = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let reward {
                    // Game look (#227): monkey dance, stage cleared / chest, or level bar.
                    GameRewardView(reward: reward).padding(.top, 20)
                } else {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 70))
                        .foregroundStyle(LinearGradient(colors: [Theme.lime, .yellow], startPoint: .top, endPoint: .bottom))
                        .scaleEffect(pop ? 1 : 0.3)
                        .symbolEffect(.bounce, value: pop)
                        .padding(.top, 30)
                    Text("Session\ncomplete").font(Theme.display(48)).multilineTextAlignment(.center)
                }
                HStack(spacing: 10) {
                    GradientStat(symbol: "stopwatch.fill", value: Format.elapsed(elapsed), label: "Time", gradient: WorkoutEngine.Category.cardio.gradient)
                    GradientStat(symbol: "square.stack.3d.up.fill", value: "\(setsDone)", label: "Sets", gradient: WorkoutEngine.Category.strength.gradient)
                    if let kcal { GradientStat(symbol: "flame.fill", value: "\(Int(kcal))", label: "kcal", gradient: WorkoutEngine.Category.warmup.gradient) }
                    GradientStat(symbol: "figure.strengthtraining.traditional", value: "\(session.blocks.reduce(0) { $0 + $1.items.count })", label: "Moves", gradient: WorkoutEngine.Category.mobility.gradient)
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
        .readableWidth()
        .onAppear { withAnimation(.spring(duration: 0.6, bounce: 0.5)) { pop = true } }
    }
}
