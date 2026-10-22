import SwiftUI
import TipKit
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
    /// Compact = iPhone on its side (#362): the cockpit layout.
    @Environment(\.verticalSizeClass) private var verticalSize
    /// Height of the upright player: under 720 pt (iPhone Duo outer screen, #594) the hero and timer go short.
    @State private var playerHeight: CGFloat = 0
    @State private var record: WorkoutRecord?
    /// What this workout earned (#227): XP, level-up, week chest, new badges.
    @State private var reward: GameReward?
    /// Wins you missed (#501) on the finish sheet.
    @State private var wins: [Win] = []
    /// Instant recap (#608 B), reworded by the on-device model when it can.
    @State private var recap: WorkoutRecap?
    @State private var recapOnDevice = false

    @State private var index = 0
    @State private var setsDone: [String: Int] = [:]
    @State private var pause: Pause?
    @State private var timed: TimedRun?
    /// Superset/circuit: step to open when the rest/effort overlay closes (#78).
    @State private var pendingJump: Int?
    @State private var started = Date()
    @State private var finished = false
    @State private var askRing = false
    @State private var ready = false
    @State private var discarded = false
    /// Finish, Finish early or Discard picked in the workout map (#538): run once the sheet has closed.
    @State private var mapAction: MapAction?
    @State private var formFor: Exercise?
    @State private var prFor: Exercise?
    /// "Not here?" (#162): the planned item whose equipment the gym lacks.
    @State private var notHereFor: PlannedExercise?
    /// Change (#391): the item whose Swap / Remove / Not here? sheet is open, and what was picked there.
    @State private var changeFor: PlannedExercise?
    @State private var changeChoice: ChangeExerciseSheet.Choice?
    @State private var setupFor: MachineNoteTarget?
    @State private var setupPhotoFor: MachineNote?
    @State private var gate: ProGate?
    @State private var log = SetLogState()
    /// Done set opened for a correction in the set card.
    @State private var editingSet: Int?
    /// Reps and bar speed the Watch measures for the current set (#383).
    @State private var watchLift: WLiftLive?
    @State private var live = LiveWorkout()
    /// Finish early (#300): the remaining workout re-fitted to the time left, and the time to be done by.
    @State private var fitted: [Block]?
    @State private var fitEnd: Date?
    @State private var finishingEarly = false
    /// What the last fit changed, shown with Undo for a few seconds.
    @State private var fitBanner: String?
    /// Landscape set ring (#362): when the current set began (last rest closed or exercise opened).
    @State private var setStart = Date()
    /// Superset split mid-workout (#352): what to put back on Undo, shown for a few seconds.
    @State private var splitUndo: SplitUndo?
    /// Superset chip (#352): the item whose "machines not next to each other?" sheet is open, and what was picked there.
    @State private var groupFix: PlannedExercise?
    @State private var groupChoice: SupersetFixSheet.Choice?
    @State private var swapPartner: PlannedExercise?
    @State private var zonesOpen = false
    /// Build as I go (#490): the catalog open to add exercises, and whether the pick is played at once.
    @State private var freeBrowse: FreeBrowse?
    @State private var zoneDraft: (layout: GymLayout?, equipment: [Equipment]) = (nil, [])
    /// Workout map (#361): what's done and what's left, read-only.
    @State private var mapOpen = false
    /// Zone found busy ("Taken?", #406): the swap sheet offers exercises elsewhere.
    @State private var takenZone: GymLayout.Zone?
    /// "Free weights cleared" beat when the member leaves a zone for good (#406).
    @State private var zoneCleared: ZoneHop?
    /// "Next in 5" after an exercise's last set (#357); nil = not counting.
    @State private var autoNext: AutoNext?
    @AppStorage(AutoNextPref.key) private var autoNextSec = AutoNextPref.fallback
    /// Coach Monkey in the player (#379): voice, subtitle bubble, record burst, Final set badge.
    @State private var coach = WorkoutCoach()
    /// Hands-free mic (#412 C) and a question for Coach about this exercise.
    @State private var listener = CoachListener()
    @State private var asking: AskCoachRequest?
    /// #402: the coach voice setup sheet (A) and the toast after an automatic pick (C).
    @State private var voiceSetup = false
    @State private var voiceToast: String?
    /// Items that already had their record burst this workout.
    @State private var coachRecorded: Set<String> = []

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

    enum MapAction { case finish, finishEarly, discard, close }

    struct SplitUndo: Equatable {
        var text: String
        var uid: String
        var edit: [Block]?
        var fitted: [Block]?
        var symbol = "scissors"
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
    /// Read many times per render: rebuilt only when the session changes (an unchanged session compares in O(1),
    /// its block arrays are shared with the cached plan).
    private var steps: [Step] {
        let s = session
        if stepsMemo.filled, stepsMemo.session == s { return stepsMemo.steps }
        let out = s?.blocks.flatMap { b in b.items.map { Step(item: $0, block: b) } } ?? []
        stepsMemo.session = s
        stepsMemo.steps = out
        stepsMemo.filled = true
        return out
    }
    @State private var stepsMemo = StepsMemo()

    /// Last steps built and the session they came from (not observed: a cache, never drawn from).
    private final class StepsMemo {
        var session: Session?
        var steps: [Step] = []
        var filled = false
    }
    /// Build as I go (#490): started empty, exercises added in the player.
    private var isFree: Bool { Freestyle.isFreestyle(sessionId) }

    // Split in three so the Xcode 27 type-checker handles it (one chain timed out, #158).
    var body: some View {
        remoteControls(lifecycle(screen))
    }

    private var screen: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let session {
                if finished {
                    SummaryView(session: session, elapsed: Date().timeIntervalSince(started), setsDone: setsDone.values.reduce(0, +),
                                kcal: record?.kcal, healthSaved: health.connected && health.writeWorkouts, reward: reward,
                                wins: wins, record: record, recap: recap, recapOnDevice: recapOnDevice) {
                        dismiss()
                    }
                    .transition(.scale.combined(with: .opacity))
                } else if ready, steps.indices.contains(index) {
                    player(steps[index], session: session)
                } else if ready, isFree, steps.isEmpty {
                    let picks = model.freestylePicks(sessionId)
                    FreestyleStartView(
                        started: started, picks: picks,
                        recent: model.recentExerciseIds(limit: 6).compactMap(Exercise.find).filter { e in !picks.contains { $0.id == e.id } },
                        onPick: { addFree([$0], jump: true) },
                        onBrowse: { freeBrowse = FreeBrowse(group: $0, jump: true) },
                        // Pause: keep for later or discard (#538), with nothing added yet.
                        onClose: { mapOpen = true })
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $formFor) { FormSheet(exercise: $0) }
        .sheet(item: $freeBrowse) { b in
            ExercisePickerView(limit: 10, group: b.group) { addFree($0, jump: b.jump) }
        }
        .sheet(item: $notHereFor) { NotHereSheet(exerciseId: $0.exerciseId, uid: $0.uid) }
        .sheet(item: $changeFor, onDismiss: runChange) { item in
            if let step = steps.first(where: { $0.item.uid == item.uid }) {
                let done = setsDone[item.uid] ?? 0
                ChangeExerciseSheet(exercise: step.exercise, setsDone: done, canSwap: canSwapHere(step),
                                    canRemove: canRemoveHere(step), canNotHere: canNotHere(step),
                                    takenZone: homeZone(step.exercise.id)?.name) { changeChoice = $0 }
            }
        }
        .sheet(item: $setupFor) { MachineNoteSheet(exerciseId: $0.exerciseId, gym: $0.gym) }
        .fullScreenCover(item: $setupPhotoFor) { n in
            MachineNotePhotoViewer(note: n) {
                setupFor = MachineNoteTarget(exerciseId: n.exerciseId, gym: GymRef(id: n.gymId, name: n.gymName, address: ""))
            }
        }
        .sheet(item: $groupFix, onDismiss: runGroupChoice) { item in
            if let step = steps.first(where: { $0.item.uid == item.uid }) {
                SupersetFixSheet(title: groupTitle(step), partner: swappablePartner(step).map { Exercise.get($0.exerciseId).name },
                                 canZones: model.trip(forItem: item.uid) == nil, zonesSet: model.profile?.gymLayout != nil) {
                    groupChoice = $0
                }
            }
        }
        .sheet(item: $swapPartner, onDismiss: { takenZone = nil }) { partner in
            SwapExerciseSheet(exerciseId: partner.exerciseId, uid: partner.uid, busyZone: takenZone, onPick: { id in
                let here = steps.indices.contains(index) ? steps[index].item.uid : partner.uid
                model.swapInSession(sessionId, uid: partner.uid, to: id)
                fitted?.swap(partner.uid, to: id)
                relocate(here)
            })
        }
        .sheet(isPresented: $zonesOpen, onDismiss: {
            model.setGymLayoutDuringWorkout(zoneDraft.layout, equipment: zoneDraft.equipment)
        }) {
            EquipmentSheet(equipment: Binding(get: { zoneDraft.equipment }, set: { zoneDraft.equipment = $0 }),
                           layout: Binding(get: { zoneDraft.layout }, set: { zoneDraft.layout = $0 }))
        }
        .fullScreenCover(item: $prFor) { PRAttemptView(exerciseId: $0.id) }
        .proPaywall($gate)
        .sheet(isPresented: $finishingEarly) {
            if let base = model.session(sessionId), steps.indices.contains(index) {
                FinishEarlySheet(blocks: base.blocks, setsDone: setsDone, current: steps[index].item.uid, fitted: fitted != nil,
                                 onFit: { finishEarly(minutes: $0) }, onUndo: undoFinishEarly)
            }
        }
        .sheet(isPresented: $voiceSetup) { CoachVoiceSetupSheet() }
        .sheet(item: $asking) { CoachChatView(ask: $0).remotePaused(.askCoach) }
        .overlay(alignment: .top) { if listener.listening || listener.problem != nil { heardPill.padding(.top, 60) } }
        .sheet(isPresented: $mapOpen, onDismiss: runMapAction) {
            if let session, steps.indices.contains(index) {
                // Finish, Finish early and Discard live here (#538), not in a dialog behind the pause button.
                WorkoutMapSheet(blocks: session.blocks, setsDone: setsDone, current: steps[index].item.uid)
                    .safeAreaInset(edge: .bottom) { mapActions }
            } else if isFree, steps.isEmpty {
                // Build as I go before the first exercise (#490): nothing to map, but it can be kept or discarded.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Workout map").eyebrow()
                    Text("Nothing added yet").font(Theme.display(26))
                    Text("Keep it for later, or discard it.").font(.subheadline).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
                .background(Theme.bg.ignoresSafeArea())
                .foregroundStyle(.white)
                .preferredColorScheme(.dark)
                .safeAreaInset(edge: .bottom) { mapActions }
                .presentationDetents([.medium])
            }
        }
        .animation(.spring(duration: 0.4), value: index)
        .animation(.spring(duration: 0.5), value: finished)
        .animation(.spring(duration: 0.3), value: pause)
    }

    private func lifecycle(_ content: some View) -> some View {
        content
        .onAppear {
            // Back in the player (Undo, or Resume on Train) before a discard went through: keep the workout.
            PendingDiscard.cancel(sessionId)
            UIApplication.shared.isIdleTimerDisabled = true
            OrientationLock.allowLandscape(true)
            coach.call = model.coachCallName
            Task { await CoachVoiceStore.shared.fetchCall(model: model) }
            resumeOrBegin()
            askCoachVoice()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            OrientationLock.allowLandscape(false)
            saveProgress()
            live.end()
            coach.stop()
            listener.cancel()
            if !finished, !discarded { WatchSync.shared.endLive(.paused, sessionId: sessionId) }
            model.replanAfterWorkoutIfDone()
        }
        .onChange(of: index) { reloadLog(); saveProgress(); updateLive() }
        .onChange(of: setsDone) { saveProgress(); updateLive() }
        .onChange(of: pause) { updateLive() }
        .onChange(of: pause == nil) { _, free in
            if free {
                setStart = Date()
                coachFinalSetIfDue()
            }
        }
        .onChange(of: index) { coachHalfwayIfDue() }
        .onChange(of: coach.watchLine) { updateLive() }
        .onChange(of: index) { setStart = Date() }
        .onChange(of: log.rows) { updateLive() }
        .onChange(of: scenePhase) { _, p in if p != .active { saveProgress(interrupted: p == .background) } }
    }

    /// Lock screen, Dynamic Island and Watch commands.
    private func remoteControls(_ content: some View) -> some View {
        content
        .onReceive(NotificationCenter.default.publisher(for: .workoutRestAdd15)) { _ in extendRest() }
        .onReceive(NotificationCenter.default.publisher(for: .workoutRestSkip)) { _ in closePause() }
        // "+30 s" on the rest alarm (#613 A).
        .onReceive(NotificationCenter.default.publisher(for: .workoutRestAdd30)) { _ in extendRest(by: 30) }
        // Ring through Silent? (#613 C): asked once, the first time a rest or timed block runs.
        .onChange(of: pause?.end != nil || timed?.end != nil) { _, running in
            if running, TimerAlarms.shared.shouldAsk, demoMode == nil, !model.demo { askRing = true }
        }
        .sheet(isPresented: $askRing) { RingThroughSilentAsk() }
        // Lock screen / Dynamic Island (#371): effort tile logs the set, − / + kg, lime button.
        .onReceive(NotificationCenter.default.publisher(for: .workoutLogSet)) { n in
            let efforts: [WCommand] = [.effort0, .effort1, .effort2, .effort3, .effort4]
            handle(efforts[min(4, max(0, n.object as? Int ?? 2))])
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutStepKg)) { n in stepKgFromLockScreen(n.object as? Int ?? 0) }
        .onReceive(NotificationCenter.default.publisher(for: .workoutMain)) { _ in handle(.main) }
        .onReceive(NotificationCenter.default.publisher(for: .workoutVoiceLog)) { n in
            siriLog(reps: n.userInfo?["reps"] as? Int, kg: n.userInfo?["kg"] as? Double)
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchHeartRate)) { _ in updateLive() }
        .onChange(of: timed) { updateLive() }
        .onChange(of: autoNext) { updateLive() }
        .onReceive(NotificationCenter.default.publisher(for: .watchCommand)) { n in
            if let c = n.object as? WCommand { handle(c) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchLift)) { n in
            if let l = n.object as? WLiftLive { applyWatchLift(l) }
        }
        .onChange(of: setsDone) { watchLift = nil }
        .onChange(of: index) { watchLift = nil }
        .onChange(of: index) { old, new in zoneHop(from: old, to: new) }
    }

    // MARK: Player

    /// Upright, or the cockpit when the phone lies on its side (#362). Both read and change the same state.
    @ViewBuilder
    private func player(_ step: Step, session: Session) -> some View {
        Group {
            if verticalSize == .compact {
                cockpit(step, session: session)
            } else {
                upright(step, session: session)
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
        .task(id: pause?.end) {
            // Coach, every-set voice (#379): 10 s before a rest of 30 s or more ends.
            guard let p = pause, let end = p.end, p.total >= 30 else { return }
            let wait = end.timeIntervalSinceNow - 10
            guard wait > 0 else { return }
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, pause?.end == end else { return }
            coach.say(.restEnding(seconds: 10), once: "rest-\(p.start.timeIntervalSince1970)")
        }
        .task(id: timed?.end) {
            // Timed set over: count it and buzz.
            guard let run = timed, let end = run.end, run.uid == step.item.uid else { return }
            let wait = end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, timed == run else { return }
            timed = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            completeSet(step, sets: step.sets, done: setsDone[step.item.uid] ?? 0)
        }
    }

    private var short: Bool { playerHeight > 0 && playerHeight < 720 }

    @ViewBuilder
    private func upright(_ step: Step, session: Session) -> some View {
        let cat = step.category
        let sets = step.sets
        let done = setsDone[step.item.uid] ?? 0

        ZStack(alignment: .top) {
            RadialGradient(colors: [cat.colors[0].opacity(0.35), .clear], center: .top, startRadius: 10, endRadius: 560)
                .ignoresSafeArea()

            // One screen, no scrolling (#206): the exercise card's picture takes whatever height is left, so the target, the one
            // input for this item (set card or timer), up next and the controls are always fully on screen (#373: and always
            // in the same place).
            VStack(alignment: .leading, spacing: 12) {
                topBar(session)
                if isFree { freeTrail }
                if let splitUndo {
                    FinishEarlyBanner(text: splitUndo.text, symbol: splitUndo.symbol, onUndo: undoSplit)
                } else if let fitBanner {
                    FinishEarlyBanner(text: fitBanner, onUndo: undoFinishEarly)
                } else if let zoneCleared {
                    ZoneClearedBanner(zone: zoneCleared.cleared, next: zoneCleared.next)
                }

                let setupGym = model.gymRef(forItem: step.item.uid)
                let setupTarget = MachineNoteTarget(exerciseId: step.exercise.id, gym: setupGym)
                let setup = model.machineNote(exerciseId: step.exercise.id, gymId: setupGym.id)
                ExerciseHeroCard(exercise: step.exercise, block: step.block, item: step.item,
                                 position: isFree ? "" : "\(index + 1)/\(steps.count)",
                                 onAttemptPR: step.loggable ? { ProStore.shared.run(.prAttempt, $gate) { prFor = step.exercise } } : nil,
                                 onChange: canChange(step) ? { changeFor = step.item } : nil,
                                 setup: setup,
                                 onSetup: step.exercise.equipment.isEmpty ? nil : { setupFor = setupTarget },
                                 onSetupPhoto: { setupPhotoFor = setup },
                                 onSplit: canSplit(step) ? { split(step) } : nil,
                                 onGroup: canSplit(step) ? { groupFix = step.item } : nil,
                                 onAdd: isFree ? { freeBrowse = FreeBrowse(group: nil, jump: false) } : nil,
                                 short: short) { formFor = step.exercise }
                    .id(step.item.uid)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    .layoutPriority(1)

                // #373: no free space left over: the card's picture takes it. Set card, Up next and the controls keep their
                // places at the bottom whatever the exercise shows.
                if let p = pause {
                    // Rest takes the set card's slot (#538, design A): same place, at least the same size.
                    restSlot(p, step: step, sets: sets, done: done, colors: cat.colors)
                } else {
                    setCard(step, sets: sets, done: done, colors: cat.colors)
                }
                upNextBar(step, done: done, sets: sets, session: session)
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

            // Coach (#379): over the picture, never in the layout, so nothing moves.
            if let r = coach.record {
                CoachRecordBurst(record: r) { withAnimation(.spring(duration: 0.3)) { coach.record = nil } }
                    .frame(maxHeight: 340)
                    .padding(.horizontal, 20)
                    .padding(.top, 66)
                    .readableColumn()
            } else if let b = coach.bubble {
                CoachBubble(call: b)
                    .padding(.horizontal, 36)
                    .padding(.top, 150)
            }
            if let v = voiceToast {
                CoachVoiceToast(name: v) {
                    voiceToast = nil
                    voiceSetup = true
                }
                .padding(.horizontal, 20)
                .padding(.top, 66)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { playerHeight = $0 }
        .animation(.spring(duration: 0.35), value: voiceToast)
        .animation(.spring(duration: 0.35), value: coach.bubble)
        .animation(.spring(duration: 0.35), value: coach.record)
    }

    /// Rest in the set card's slot (#538): the set card stays underneath, hidden, so the slot keeps its size and Up next
    /// and the controls don't move.
    private func restSlot(_ p: Pause, step: Step, sets: Int, done: Int, colors: [Color]) -> some View {
        ZStack(alignment: .topLeading) {
            setCard(step, sets: sets, done: done, colors: colors)
                .hidden()
                .accessibilityHidden(true)
            RestSlotCard(
                pause: p, colors: colors,
                doneLabel: (step.loggable ? p.effortSet ?? max(0, done - 1) : nil).flatMap { i in
                    log.values(i).map { v in
                        "Set \(i + 1) · \(LoadAdvisor.formatKg(v.kg)) × \(v.reps)" + (p.effort.map { " · \($0.caption.lowercased())" } ?? "")
                    }
                } ?? "Set \(done) done",
                onEffort: pickEffort, onExtend: extendRest, onDone: closePause)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(colors[0], lineWidth: 1.5))
        .transition(.opacity)
    }

    /// Workout map footer (#538): Finish and Discard side by side, Finish early under them. Each runs once the map closed.
    /// An empty Build as I go workout gets Keep for later in Finish's place.
    private var mapActions: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                if steps.isEmpty {
                    Button {
                        mapAction = .close
                        mapOpen = false
                    } label: {
                        Label("Keep for later", systemImage: "pause.fill").lineLimit(1).minimumScaleFactor(0.9)
                    }
                    .buttonStyle(LimeButtonStyle())
                } else {
                    Button {
                        mapAction = .finish
                        mapOpen = false
                    } label: {
                        Label("Finish", systemImage: "flag.checkered").lineLimit(1).minimumScaleFactor(0.9)
                    }
                    .buttonStyle(LimeButtonStyle())
                    .accessibilityHint("Saves the workout as it is now")
                }
                Button {
                    mapAction = .discard
                    mapOpen = false
                } label: {
                    Label("Discard", systemImage: "trash")
                        .font(Theme.label(17)).foregroundStyle(Color(hex: 0xFF6B8A))
                        .lineLimit(1).minimumScaleFactor(0.9)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(Capsule().fill(Color(hex: 0x3A1420)))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Closes without saving. Undo for a few seconds.")
            }
            if !steps.isEmpty {
                Button {
                    mapAction = .finishEarly
                    mapOpen = false
                } label: {
                    Label("Short on time? Finish early", systemImage: "timer")
                        .font(Theme.label(14)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            moveToWatch
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, steps.isEmpty ? 8 : 0)
        .background(Theme.bg.ignoresSafeArea())
    }

    /// Hand-off (#603, design C): the Watch takes the workout over so the phone can go in the locker. The Watch tracks
    /// it and mirrors its session back, which keeps this player answering the Watch with the screen off.
    @ViewBuilder private var moveToWatch: some View {
        if WatchSync.shared.watchTracks(sessionId) {
            Label("On your Watch too · phone can sleep", systemImage: "applewatch.radiowaves.left.and.right")
                .font(Theme.label(13)).foregroundStyle(Theme.lime)
                .frame(maxWidth: .infinity, minHeight: 36)
        } else if WatchSync.shared.watchReady {
            Button {
                WatchSync.shared.offerStart(sessionId: sessionId, asked: true)
            } label: {
                Label("Move to Watch", systemImage: "applewatch")
                    .font(Theme.label(14)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Your Watch takes over: log sets and rest from the wrist, the phone can sleep")
        }
    }

    private func runMapAction() {
        guard let a = mapAction else { return }
        mapAction = nil
        switch a {
        case .finish: finish()
        case .close: closeWorkout()
        case .finishEarly: finishingEarly = true
        case .discard: discardWithUndo()
        }
    }

    /// #402: no studio voice on the device yet → ask (A); a voice the app picked on its own → say so once (C).
    private func askCoachVoice() {
        guard demoMode == nil, !model.demo else { return }
        let store = CoachVoiceStore.shared
        if store.shouldAsk {
            voiceSetup = true
        } else if let v = UserDefaults.standard.string(forKey: CoachVoicePref.announceKey) {
            UserDefaults.standard.removeObject(forKey: CoachVoicePref.announceKey)
            voiceToast = store.catalog?.voices.first(where: { $0.id == v })?.name ?? v
            Task {
                try? await Task.sleep(for: .seconds(5))
                voiceToast = nil
            }
        }
    }

    // MARK: Landscape (#362)

    /// #373 (A + C mix from `player-layout/landscape-mix.png`): the exercise card at full height on the left; on the right
    /// the one input and the controls, and the smart Up next bar at the bottom. Rest takes the set card's slot, as upright (#538).
    private func cockpit(_ step: Step, session: Session) -> some View {
        let cat = step.category
        let sets = step.sets
        let done = setsDone[step.item.uid] ?? 0

        return ZStack(alignment: .top) {
            RadialGradient(colors: [cat.colors[0].opacity(0.35), .clear], center: .topLeading, startRadius: 10, endRadius: 700)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                topBar(session)
                if isFree { freeTrail }
                HStack(alignment: .top, spacing: 12) {
                    let setupGym = model.gymRef(forItem: step.item.uid)
                    let setupTarget = MachineNoteTarget(exerciseId: step.exercise.id, gym: setupGym)
                    let setup = model.machineNote(exerciseId: step.exercise.id, gymId: setupGym.id)
                    ExerciseHeroCard(exercise: step.exercise, block: step.block, item: step.item,
                                     position: isFree ? "" : "\(index + 1)/\(steps.count)",
                                     onAttemptPR: step.loggable ? { ProStore.shared.run(.prAttempt, $gate) { prFor = step.exercise } } : nil,
                                     onChange: canChange(step) ? { changeFor = step.item } : nil,
                                     setup: setup,
                                     onSetup: step.exercise.equipment.isEmpty ? nil : { setupFor = setupTarget },
                                     onSetupPhoto: { setupPhotoFor = setup },
                                     onSplit: canSplit(step) ? { split(step) } : nil,
                                     onGroup: canSplit(step) ? { groupFix = step.item } : nil,
                                     onAdd: isFree ? { freeBrowse = FreeBrowse(group: nil, jump: false) } : nil,
                                     compact: true) { formFor = step.exercise }
                        .id(step.item.uid)
                        .transition(.opacity)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay {
                            // Coach (#379) over the exercise card only.
                            if let r = coach.record {
                                CoachRecordBurst(record: r) { withAnimation(.spring(duration: 0.3)) { coach.record = nil } }
                            } else if let b = coach.bubble {
                                CoachBubble(call: b).padding(12)
                            }
                        }
                        .animation(.spring(duration: 0.35), value: coach.bubble)
                        .animation(.spring(duration: 0.35), value: coach.record)

                    VStack(spacing: 8) {
                        if let splitUndo {
                            FinishEarlyBanner(text: splitUndo.text, symbol: splitUndo.symbol, onUndo: undoSplit)
                        } else if let fitBanner {
                            FinishEarlyBanner(text: fitBanner, onUndo: undoFinishEarly)
                        } else if let zoneCleared {
                            ZoneClearedBanner(zone: zoneCleared.cleared, next: zoneCleared.next)
                        }
                        if let p = pause {
                            restSlot(p, step: step, sets: sets, done: done, colors: cat.colors)
                        } else {
                            setCard(step, sets: sets, done: done, colors: cat.colors)
                        }
                        Spacer(minLength: 0)
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
                        upNextBar(step, done: done, sets: sets, session: session)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("player.cockpit")
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
    }

    /// The smart Up next bar (#373), same in both orientations: the next set or exercise, the two after it, what's left.
    @ViewBuilder
    private func upNextBar(_ step: Step, done: Int, sets: Int, session: Session) -> some View {
        let next = upNext(after: step, done: done, sets: sets, includeSets: false)
        let items = OverviewItem.list(session.blocks, setsDone: setsDone, current: step.item.uid)
        if isFree {
            // Build as I go (#581, design C): the Coach's next picks always hold Up next's place (what's queued shows in
            // the trail); lit up once this exercise is done.
            FreestyleNextBar(picks: model.freestylePicks(sessionId), ready: done >= sets, onPick: { addFree([$0], jump: true) },
                             onMore: { freeBrowse = FreeBrowse(group: nil, jump: true) })
        } else {
            SmartUpNextBar(next: next,
                              then: SmartUpNextBar.after(items, current: step.item.uid, next: next?.exercise),
                              left: items.filter { $0.state == .left }.count,
                              doneBy: OverviewItem.doneBy(session.blocks, setsDone: setsDone, current: step.item.uid),
                              fallback: step.category.colors,
                              walk: walk(from: step.exercise, to: next?.exercise)) { mapOpen = true }
        }
    }

    /// Gym Map (#406): the walk to the next exercise's zone, drawn in Up next when the member has a floor plan.
    private func walk(from here: Exercise, to next: Exercise?) -> GymWalk? {
        guard let next, let layout = model.profile?.gymLayout, layout.hasPlan,
              let to = homeZone(next.id), to.rect != nil else { return nil }
        let from = homeZone(here.id)
        guard from?.id != to.id else { return nil }
        return GymWalk(layout: layout, from: from?.id, to: to.id)
    }

    /// Zone in the home gym (#274); nil on a trip, where the home gym's zones don't apply.
    private func homeZone(_ exerciseId: String) -> GymLayout.Zone? {
        guard steps.indices.contains(index), model.trip(forItem: steps[index].item.uid) == nil else { return nil }
        return model.gymZone(exerciseId)
    }

    struct ZoneHop: Equatable {
        let id = UUID()
        let cleared: GymLayout.Zone
        let next: GymLayout.Zone?
    }

    /// "Zone cleared" (#406): moving on to another zone with nothing left in the one just finished.
    private func zoneHop(from old: Int, to new: Int) {
        guard new > old, steps.indices.contains(old), steps.indices.contains(new),
              let was = homeZone(steps[old].exercise.id), let now = homeZone(steps[new].exercise.id), now.id != was.id,
              !steps[new...].contains(where: { homeZone($0.exercise.id)?.id == was.id }) else { return }
        let hop = ZoneHop(cleared: was, next: now)
        withAnimation(.spring(duration: 0.4)) { zoneCleared = hop }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            try? await Task.sleep(for: .seconds(3))
            if zoneCleared == hop { withAnimation(.spring(duration: 0.4)) { zoneCleared = nil } }
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
        HStack(spacing: 10) {
            // Workout menu: the workout map with Finish, Finish early and Discard (#538). Not a pause icon:
            // the ✕ is what pauses (#556, design A from `player-topbar/proposals.png`).
            Button { mapOpen = true } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .heavy))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.cardStrong))
            }
            .disabled(steps.isEmpty)
            .accessibilityLabel("Workout menu")
            .accessibilityHint("Finish, finish early or discard the workout")
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
            // Coach voice (#379): glows while talking, tap mutes it for this workout.
            if coach.hasVoice { CoachPill(coach: coach) }
            // Hands-free (#412 C): say a command, or ask Coach about this exercise.
            if AskCoachPref.playerMic { micButton }
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
                // 44 pt target (#538) around the small pill.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(steps.isEmpty)
            .accessibilityLabel(fitEnd == nil ? "Workout time. Finish early" : "Time left. Change or undo finish early")
            // Closes at once (#538): the workout stays paused to resume, with Undo on Train.
            Button(action: closeWorkout) {
                Image(systemName: "xmark").font(.system(size: 16, weight: .heavy))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.cardStrong))
            }
            .accessibilityLabel("Close workout")
            .accessibilityHint("Pauses it. Resume from Train.")
            .accessibilityIdentifier("player.close")
        }
        .foregroundStyle(.white)
    }

    // MARK: Hands-free (#412 C)

    private var micButton: some View {
        Button { listener.listening ? listener.finish() : listenForCommand() } label: {
            Image(systemName: listener.listening ? "waveform" : "mic.fill").font(.system(size: 15, weight: .heavy))
                .foregroundStyle(listener.listening ? Theme.ink : .white)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(listener.listening ? Theme.lime : Theme.cardStrong))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(listener.listening ? "Stop listening" : "Talk to Coach")
        .accessibilityHint("Say done, a weight, reps, skip rest, next, or ask a question")
        .accessibilityIdentifier("player.mic")
        .popoverTip(VoiceLogTip())
    }

    /// What the mic hears, under the top bar.
    private var heardPill: some View {
        HStack(spacing: 8) {
            if listener.listening { ListeningBars() }
            Text(listener.problem ?? (listener.text.isEmpty ? "Say \"done\", \"80 kg\", \"skip rest\" or ask…" : listener.text))
                .font(.subheadline.weight(.semibold)).lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.85)))
        .overlay(Capsule().stroke(Theme.lime, lineWidth: 1.5))
        .padding(.horizontal, 16)
        .onTapGesture { listener.problem = nil }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func listenForCommand() {
        coach.stop()
        listener.start { said in runVoice(said) }
    }

    /// Siri "log 8 at 80" (#605): the coming set's reps and kg, then logged as the lime button does.
    private func siriLog(reps: Int?, kg: Double?) {
        guard ready, !finished, steps.indices.contains(index) else { return }
        let step = steps[index]
        let done = setsDone[step.item.uid] ?? 0
        if step.loggable, log.item?.uid == step.item.uid, !log.rows.isEmpty {
            let row = min(done, log.rows.count - 1)
            if let kg { log.setKg(row, kg) }
            if let reps { log.setReps(row, reps) }
        }
        handle(.main)
    }

    /// Runs what the member said: set done (with effort), weight, reps, rest, next / previous; anything else is a question.
    private func runVoice(_ said: String) {
        guard ready, !finished, steps.indices.contains(index), let command = VoiceCommand.parse(said) else { return }
        let step = steps[index]
        let done = setsDone[step.item.uid] ?? 0
        let onCard = step.loggable && log.item?.uid == step.item.uid && !log.rows.isEmpty
        let row = min(done, max(0, log.rows.count - 1))
        let efforts: [WCommand] = [.effort0, .effort1, .effort2, .effort3, .effort4]
        switch command {
        case let .done(rir):
            handle(rir.map { efforts[min(4, max(0, $0))] } ?? .main)
        case let .kg(kg):
            guard onCard else { return coach.reply("No weight on this one.") }
            log.setKg(row, kg)
            coach.reply("\(log.rows[row].kg) kilos.")
        case let .kgBy(delta):
            guard onCard else { return coach.reply("No weight on this one.") }
            log.setKg(row, (SetLogState.parseKg(log.rows[row].kg) ?? 0) + delta)
            coach.reply("\(log.rows[row].kg) kilos.")
        case let .kgStep(sign):
            guard onCard else { return coach.reply("No weight on this one.") }
            log.stepKg(row, by: Double(sign))
            coach.reply("\(log.rows[row].kg) kilos.")
        case let .reps(n):
            guard onCard else { return coach.reply("No reps to log on this one.") }
            log.setReps(row, n)
            coach.reply("\(log.rows[row].reps) reps.")
        case let .set(reps, kg):
            // "Eight at eighty" (#617): both values in, set logged.
            guard onCard else { return coach.reply("No weight on this one.") }
            log.setKg(row, kg)
            log.setReps(row, reps)
            coach.reply("\(log.rows[row].reps) at \(log.rows[row].kg).")
            handle(.main)
        case .skipRest: handle(.skipRest)
        case .addRest:
            handle(.addRest)
            coach.reply("Fifteen more seconds.")
        case .next: handle(.next)
        case .previous: handle(.previous)
        case let .ask(q):
            let detail = onCard ? "set \(row + 1) of \(step.sets), \(log.rows[row].kg) kg × \(log.rows[row].reps)" : "set \(done + 1) of \(step.sets)"
            ProStore.shared.run(.generateWorkout, $gate) {
                asking = AskCoachRequest(focus: CoachFocus(screen: "player", title: step.exercise.name, detail: "during the workout, " + detail),
                                         question: q, spoken: true)
            }
        }
    }

    /// The input that fits the item: kg × reps steppers for loaded strength, the countdown for timed work,
    /// set chips for other multi-set work. Exactly one place per item.
    @ViewBuilder
    private func setCard(_ step: Step, sets: Int, done: Int, colors: [Color]) -> some View {
        if step.loggable {
            if log.item?.uid == step.item.uid {
                CurrentSetCard(state: log, done: done, color: colors[0], editing: $editingSet,
                               watchLift: watchLift.flatMap { $0.exerciseId == step.item.exerciseId && $0.setIndex == done ? $0 : nil },
                               finalSet: coach.enabled && sets > 1 && done == sets - 1) { i in
                    _ = log.log(i, model: model)
                }
            }
        } else if let spec = step.timedSpec {
            let run = timed.flatMap { $0.uid == step.item.uid ? $0 : nil }
                ?? TimedRun(uid: step.item.uid, total: spec.workSec, remaining: Double(spec.workSec), end: nil)
            TimedSetCard(run: run, sets: sets, done: done, easySec: spec.easySec, colors: colors, short: short)
        } else if sets > 1 {
            PlainSetCard(sets: sets, done: done, target: step.item.prescription.reps, color: colors[0])
        }
    }

    private func controls(_ step: Step, sets: Int, done: Int) -> some View {
        Group {
            if let p = pause {
                // Resting (#538): one lime SKIP REST in the controls' place; the rest card sits in the set card's slot.
                HStack(spacing: 12) {
                    previousButton(size: 58)
                    Button(action: closePause) {
                        Text(p.end == nil ? "CONTINUE" : "SKIP REST").lineLimit(1).minimumScaleFactor(0.9)
                    }
                    .buttonStyle(LimeButtonStyle())
                    skipButton(step, size: 58)
                }
            } else if step.loggable && done < sets {
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
                            .minimumScaleFactor(0.9)
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
                .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Theme.cardStrong))
        }
        .disabled(index == 0)
        .accessibilityLabel("Previous exercise")
    }

    private func skipButton(_ step: Step, size: CGFloat) -> some View {
        // Build as I go (#581, design C): search for the next exercise in skip's place (the trail goes to queued ones).
        let pickNext = isFree
        return Button { pickNext ? (freeBrowse = FreeBrowse(group: nil, jump: true)) : advance(step) } label: {
            Image(systemName: pickNext ? "magnifyingglass" : "forward.end.fill").font(.system(size: size > 50 ? 18 : 15, weight: .heavy))
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Theme.cardStrong))
        }
        // Nothing left to skip to: it would finish and save the workout, which is the main button's job.
        .disabled(nextStep == nil && !pickNext)
        .accessibilityLabel(pickNext ? "Pick the next exercise" : "Skip to next exercise")
    }

    private func mainLabel(_ step: Step, sets: Int, done: Int) -> String {
        if done >= sets {
            if isFree { return nextStep == nil ? "FINISH WORKOUT" : "NEXT" }
            return index == steps.count - 1 ? "FINISH" : "NEXT"
        }
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
        // Watch counted this set and the member changed the reps (#410): the exercise learns to count stricter or looser.
        if onScreen, let w = watchLift, w.exerciseId == step.item.exerciseId, w.setIndex == done, w.reps > 0,
           log.rows.indices.contains(done), let reps = Int(log.rows[done].reps) {
            LiftLearning.shared.correct(w.exerciseId, counted: w.reps, logged: reps)
        }
        let logged = onScreen && log.log(done, model: model)
        setsDone[step.item.uid] = now
        if logged { coachSet(step, index: done, of: sets) }
        if now >= sets { model.setTicked(step.item.uid) }
        // Superset/circuit: on to the next member without rest, rest after the round (#78).
        let jump = groupJump(step, done: now)
        let target = jump.flatMap { $0.index == index ? nil : $0.index }
        // Pro Sets (#499): drops and minis have their own short rest.
        let planRest = onScreen ? log.restAfter(done, fallback: step.item.prescription.restSec) : step.item.prescription.restSec
        let rest = jump?.rest ?? (now < sets ? step.timedSpec?.easySec ?? planRest : 0)
        // No rest: the next group member at once, or after the last set the "Next in" countdown (#357).
        guard rest > 0 else {
            if let target { return moveTo(target) }
            if now >= sets { nextExercise(step) } else { coachFinalSetIfDue() }
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
        // Build as I go (#490): nothing queued, so wait for the next pick or FINISH.
        if isFree, !steps.indices.contains(index + 1) { return }
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

    private func extendRest(by seconds: Int = 15) {
        guard var p = pause, let end = p.end else { return }
        let base = max(end, Date())
        p.end = base.addingTimeInterval(TimeInterval(seconds))
        p.total += Int(base.timeIntervalSince(end)) + seconds
        pause = p
    }

    /// Next step with sets left: after a superset split mid-round (#352) a member done earlier is passed over.
    private var nextStep: Int? {
        steps.indices.first { $0 > index && (setsDone[steps[$0].item.uid] ?? 0) < steps[$0].sets }
    }

    private func advance(_ step: Step) {
        autoNext = nil
        if (setsDone[step.item.uid] ?? 0) >= step.sets { model.setTicked(step.item.uid) }
        if let next = nextStep { go(next) } else { finish() }
    }

    private func finish() {
        // Build as I go (#490): nothing done, nothing to keep.
        if isFree, record == nil, setsDone.values.reduce(0, +) == 0 { return discard() }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if let session, record == nil {
            let before = (game: model.game, badges: model.badges)
            let r = model.recordWorkout(
                session: session, setsDone: setsDone, startedAt: started, endedAt: Date(),
                bodyMassKg: health.snapshot.weightKg ?? model.body.weightKg)
            record = r
            coach.say(.finish(sets: r.totalSets, volumeKg: r.volumeKg, minutes: max(1, r.durationSec / 60)), once: "finish")
            reward = GameReward(before: before.game, after: model.game, badgesBefore: before.badges, badgesAfter: model.badges)
            if reward?.weekCleared == true { model.markChestSeen() }
            wins = model.wins(for: r)
            if let base = WorkoutRecap.build(r, history: model.history) {
                recap = base
                Task {
                    guard let better = await OnDeviceCoach.recap(base) else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        recap = better
                        recapOnDevice = true
                    }
                }
            }
            // A Watch tracking this workout saves the Health workout with its heart rate (#347).
            if !WatchSync.shared.watchTracks(sessionId) {
                Task {
                    let hr = await health.save(r)
                    model.attachHeartRate(r.id, avg: hr.avg, max: hr.max)
                }
            }
        }
        model.clearActiveWorkout(sessionId)
        live.finish(finishedState())
        WatchSync.shared.endLive(.finished, sessionId: sessionId, record: record)
        pause = nil
        finished = true
    }

    /// X (#538): closes at once and keeps the workout paused to resume; the Undo bar on Train reopens it.
    private func closeWorkout() {
        // Build as I go with nothing logged: nothing to resume, so X discards it (Undo still brings it back).
        if isFree, setsDone.values.reduce(0, +) == 0 { return discardWithUndo() }
        let id = sessionId
        let title = session?.displayTitle ?? ""
        saveProgress()
        live.end()
        dismiss()
        UndoCloseCenter.shared.show(UndoOffer(
            title: "Workout closed", detail: undoDetail(title, "saved · resume from Train"), symbol: "pause.fill",
            colors: [Color(hex: 0xFF2D55), Color(hex: 0xA64DFF)], fullScreen: true) {
            AnyView(WorkoutPlayerView(sessionId: id))
        })
    }

    /// Discard from the workout map (#538): closes at once like X, and the workout is only thrown away once its Undo bar
    /// is gone. Undo (or opening the player again) keeps it.
    private func discardWithUndo() {
        let id = sessionId
        let title = session?.displayTitle ?? ""
        saveProgress()
        live.end()
        PendingDiscard.schedule(id, model: model)
        // Gone from Train at once (no "resume" while the Undo bar shows); closing must not save it back.
        discarded = true
        dismiss()
        UndoCloseCenter.shared.show(UndoOffer(
            title: "Workout discarded", detail: undoDetail(title, "not saved"), symbol: "trash",
            colors: [Color(hex: 0xFF3D6E), Color(hex: 0xB0105A)], fullScreen: true) {
            AnyView(WorkoutPlayerView(sessionId: id))
        })
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

    // MARK: Split a superset (#352)

    /// Grouped item of a workout the member can edit: plan days, extras, quick sessions, library workouts.
    private func canSplit(_ step: Step) -> Bool {
        step.item.group != nil && step.block.groupMembers(of: step.item.uid).count > 1 && model.editableBlocks(sessionId) != nil
    }

    /// Straight sets from here: this exercise's sets first, then the others in list order. Saved as this workout's edit,
    /// so the session page, history and the Watch follow; a finish-early fit splits too.
    private func split(_ step: Step) {
        guard var blocks = model.editableBlocks(sessionId) else { return }
        let uid = step.item.uid
        let others = step.block.groupMembers(of: uid).filter { $0.uid != uid }.map { Exercise.get($0.exerciseId).name }
        let undo = SplitUndo(text: "Straight sets · \(others.joined(separator: ", ")) after", uid: uid,
                             edit: model.isEdited(sessionId) ? blocks : nil, fitted: fitted)
        blocks.split(uid)
        model.saveSessionEdit(sessionId, blocks: blocks)
        fitted?.split(uid)
        pendingJump = nil
        autoNext = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        relocate(uid)
        withAnimation(.spring(duration: 0.4)) { splitUndo = undo }
        guard demoMode == nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(8))
            if splitUndo == undo { withAnimation(.spring(duration: 0.4)) { splitUndo = nil } }
        }
    }

    /// "Superset A1 + A2" / "Circuit A1 + A2 + A3".
    private func groupTitle(_ step: Step) -> String {
        let members = step.block.groupMembers(of: step.item.uid)
        return (members.count == 2 ? "Superset " : "Circuit ") + members.compactMap(\.group).joined(separator: " + ")
    }

    /// The next other member with no set done yet: it can still be swapped for an exercise nearby.
    private func swappablePartner(_ step: Step) -> PlannedExercise? {
        let members = step.block.groupMembers(of: step.item.uid)
        guard let i = members.firstIndex(where: { $0.uid == step.item.uid }) else { return nil }
        let order = members[(i + 1)...] + members[..<i]
        return order.first { (setsDone[$0.uid] ?? 0) == 0 }
    }

    /// Runs the choice from the superset sheet once it has closed, so the next sheet can open.
    private func runGroupChoice() {
        guard let choice = groupChoice, steps.indices.contains(index) else { return }
        groupChoice = nil
        let step = steps[index]
        switch choice {
        case .split: split(step)
        case .swap: swapPartner = swappablePartner(step)
        case .zones:
            zoneDraft = (model.profile?.gymLayout, model.profile?.equipment ?? [])
            zonesOpen = true
        }
    }

    // MARK: Build as I go (#490)

    /// Build as I go (#581, design C): what was done, this exercise and what's queued, in order; tap one to go there.
    private var freeTrail: some View {
        FreestyleTrail(items: steps.enumerated().map { i, s in
            FreestyleTrail.Item(uid: s.item.uid, name: s.exercise.name,
                                state: i == index ? .now : (setsDone[s.item.uid] ?? 0) >= s.sets ? .done : .queued)
        }, onTap: { uid in
            if let i = steps.firstIndex(where: { $0.item.uid == uid }) { go(i) }
        }, onAdd: { freeBrowse = FreeBrowse(group: nil, jump: false) })
    }

    struct FreeBrowse: Identifiable {
        let id = UUID()
        let group: MuscleGroup?
        /// Play the first pick at once when the current exercise is done; otherwise it waits in Up next.
        let jump: Bool
    }

    /// Adds the picks at the end of the workout, in order. The first exercise opens at once; with `jump` (a Coach pick
    /// or More) the first pick is played at once, done with the current exercise or not (a cardio timer never run
    /// would otherwise hold the workout on it); Add (`jump` false) queues them in Up next.
    private func addFree(_ picked: [Exercise], jump: Bool) {
        guard isFree, !picked.isEmpty else { return }
        let wasEmpty = steps.isEmpty
        var first: String?
        for e in picked {
            let id = UUID()
            let uid = model.addToFreestyle(sessionId, e, id: id)
            if let f = fitted { fitted = Freestyle.adding(e, to: f, sessionId: sessionId, id: id).blocks }
            if first == nil { first = uid }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard let first else { return }
        if wasEmpty {
            setStart = Date()
            relocate(first)
        } else if jump {
            if let i = steps.firstIndex(where: { $0.item.uid == first }) { go(i) }
        } else {
            updateLive()
        }
    }

    // MARK: Change: swap / remove / not here (#391)

    /// The workout's list can change (saved as its edit), or the gym's equipment can still be reported missing.
    private func canChange(_ step: Step) -> Bool {
        model.editableBlocks(sessionId) != nil || canNotHere(step)
    }

    private func canSwapHere(_ step: Step) -> Bool {
        (setsDone[step.item.uid] ?? 0) == 0 && model.editableBlocks(sessionId) != nil
    }

    private func canRemoveHere(_ step: Step) -> Bool {
        canSwapHere(step) && steps.contains { $0.item.uid != step.item.uid && $0.item.supersetWith != step.item.uid }
    }

    private func canNotHere(_ step: Step) -> Bool {
        !step.exercise.equipment.isEmpty && model.canSwap(uid: step.item.uid) && (setsDone[step.item.uid] ?? 0) == 0
    }

    /// Runs the choice from the Change sheet once it has closed, so the next sheet can open.
    private func runChange() {
        guard let choice = changeChoice, steps.indices.contains(index) else { return }
        changeChoice = nil
        let step = steps[index]
        switch choice {
        case .swap: swapPartner = step.item
        case .remove: remove(step)
        case .notHere: notHereFor = step.item
        case .taken:
            // Gym Map (#406): remember the zone was busy now, then swap to the same muscles elsewhere.
            guard let z = homeZone(step.exercise.id) else { return }
            model.logBusy(z)
            takenZone = z
            swapPartner = step.item
        }
    }

    /// Takes the exercise out of this workout (saved as its edit, so the session page and the Watch follow) and moves
    /// to the next one still in it; Undo puts it back on the same spot.
    private func remove(_ step: Step) {
        guard canRemoveHere(step) else { return }
        let uid = step.item.uid
        let gone: (Step) -> Bool = { $0.item.uid == uid || $0.item.supersetWith == uid }
        let next = steps[index...].first { !gone($0) } ?? steps[..<index].last { !gone($0) }
        let fittedBefore = fitted
        let before = model.removeFromSession(sessionId, uid: uid)
        let undo = SplitUndo(text: "\(step.exercise.name) removed", uid: uid, edit: before, fitted: fittedBefore, symbol: "trash")
        fitted?.remove(uid)
        if timed?.uid == uid { timed = nil }
        pendingJump = nil
        autoNext = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let next { relocate(next.item.uid) }
        withAnimation(.spring(duration: 0.4)) { splitUndo = undo }
        guard demoMode == nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(8))
            if splitUndo == undo { withAnimation(.spring(duration: 0.4)) { splitUndo = nil } }
        }
    }

    /// Back to the superset as it was, on the same exercise and set.
    private func undoSplit() {
        guard let u = splitUndo else { return }
        model.restoreSessionEdit(sessionId, to: u.edit)
        fitted = u.fitted
        withAnimation(.spring(duration: 0.4)) { splitUndo = nil }
        relocate(u.uid)
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
            if !steps.isEmpty { coach.say(.start(exercises: steps.count), once: "start") }
        }
        reloadLog()
        if steps.filter({ (setsDone[$0.item.uid] ?? 0) >= $0.sets }).count * 2 >= steps.count { coach.markSaid("half") }
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
        if demoMode == "setup", let s = steps.firstIndex(where: { $0.block.kind == .strength && !$0.exercise.equipment.isEmpty }) {
            index = s
            reloadLog()
        }
        // Superset chip (#352): on the first grouped item; "superset-fix" opens its sheet, "superset-split" splits it.
        if demoMode?.hasPrefix("superset") == true, let s = steps.firstIndex(where: { $0.item.group != nil }) {
            index = s
            reloadLog()
            if demoMode == "superset-fix" { groupFix = steps[s].item }
            if demoMode == "superset-split" { split(steps[s]) }
        }
        if demoMode == "map", let s = steps.indices.dropFirst(steps.count / 2).first {
            for p in steps[..<s] { setsDone[p.item.uid] = p.sets }
            index = s
            reloadLog()
            mapOpen = true
        }
        if demoMode == "done" {
            reward = Demo.reward
            wins = Demo.wins
            recap = Demo.recap
            finished = true
        }
        if demoMode == "next", let s = steps.firstIndex(where: { $0.loggable }), s < steps.count - 1 {
            index = s
            reloadLog()
            setsDone[steps[s].item.uid] = steps[s].sets
            autoNext = AutoNext(uid: steps[s].item.uid, end: Date().addingTimeInterval(64), total: 80)
        }
        // Coach (#379): "coach" = final set coming with the subtitle bubble; "coach-record" = the record burst.
        if demoMode?.hasPrefix("coach") == true, let s = steps.firstIndex(where: { $0.loggable && $0.sets > 1 }) {
            index = s
            reloadLog()
            coach.hold = true
            setsDone[steps[s].item.uid] = steps[s].sets - 1
            let name = steps[s].exercise.name
            if demoMode == "coach-record" {
                coach.say(.record(exercise: name, kg: 62.5, reps: 8, heavierBy: 2.5))
            } else {
                coach.say(.finalSet(exercise: name))
            }
        }
        if demoMode == "logged", let s = steps.firstIndex(where: { $0.loggable && $0.sets > 2 }) {
            index = s
            reloadLog()
            log.log(0, model: model)
            setsDone[steps[s].item.uid] = 1
        }
        #endif
    }

    // MARK: Coach (#379)

    /// After a logged set: a record (once per exercise) or, at the every-set voice level, how it compares with last time.
    private func coachSet(_ step: Step, index i: Int, of sets: Int) {
        guard coach.enabled, let v = log.values(i) else { return }
        let id = step.exercise.id
        let earlier = model.exerciseSessions(id).filter {
            !($0.sessionId == sessionId && Calendar.current.isDateInToday($0.date)) && !PRPlanner.isPRSession($0.sessionId)
        }
        let best = CoachLines.record(kg: v.kg, reps: v.reps, history: earlier.flatMap(\.sets))
        if best.isRecord, !coachRecorded.contains(step.item.uid) {
            coachRecorded.insert(step.item.uid)
            return coach.say(.record(exercise: step.exercise.name, kg: v.kg, reps: v.reps, heavierBy: best.heavierBy))
        }
        let last = earlier.last?.sets.first { $0.setIndex == i }
        coach.say(.setLogged(set: i + 1, of: sets, kg: v.kg, reps: v.reps, lastKg: last?.kg, lastReps: last?.reps))
    }

    /// The final set of an exercise with several sets is next (said once per exercise).
    private func coachFinalSetIfDue() {
        guard steps.indices.contains(index), pause == nil else { return }
        let step = steps[index]
        guard step.sets > 1, (setsDone[step.item.uid] ?? 0) == step.sets - 1 else { return }
        coach.say(.finalSet(exercise: step.exercise.name), once: "final-\(step.item.uid)")
    }

    /// Half the exercises done (workouts of 4 or more).
    private func coachHalfwayIfDue() {
        guard steps.count >= 4 else { return }
        let done = steps.filter { (setsDone[$0.item.uid] ?? 0) >= $0.sets }.count
        guard done * 2 >= steps.count, done < steps.count else { return }
        coach.say(.halfway(left: steps.count - done), once: "half")
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
        // The coming set can be logged from the lock screen (#371): kg × reps known, no rest or countdown running.
        let logging = step.loggable && done < step.sets && pause == nil && autoNext == nil && log.item?.uid == step.item.uid
            && log.values(done) != nil
        var state = WorkoutActivityAttributes.ContentState(
            exercise: step.exercise.name,
            setLabel: step.sets > 1 ? "Set \(current + 1) of \(step.sets)" : Format.prescription(step.item.prescription),
            detail: detail,
            restStart: pause?.end == nil ? nil : pause?.start,
            restEnd: pause?.end,
            next: next.map { $0.detail.isEmpty ? $0.title : "\($0.title) · \($0.detail)" } ?? "Finish",
            tint: step.block.kind.category.tintHex)
        state.loggable = logging
        if !logging, pause == nil {
            state.action = autoNext != nil ? (index == steps.count - 1 ? "FINISH" : "NEXT") : mainLabel(step, sets: step.sets, done: done)
        }
        state.workEnd = timed.flatMap { $0.uid == step.item.uid ? $0.end : nil }
        state.autoNextEnd = autoNext?.end
        state.position = index + 1
        state.count = steps.count
        if steps.count <= 30 {
            state.segments = steps.map { s in
                WorkoutActivityAttributes.Segment(tint: s.block.kind.category.tintHex, done: Double(min(setsDone[s.item.uid] ?? 0, s.sets)) / Double(s.sets))
            }
        }
        if let session {
            let by = fitEnd ?? started.addingTimeInterval(TimeInterval(session.estMin * 60))
            state.doneBy = by > Date() ? by : nil
        }
        state.heartRate = WatchSync.shared.liveHeartRate
        state.volumeKg = model.liveLifts(sessionId: sessionId, since: started).volumeKg
        return state
    }

    /// Lock-screen card once the workout is saved (#371).
    private func finishedState() -> WorkoutActivityAttributes.ContentState {
        var state = liveState()
        let lifts = model.liveLifts(sessionId: sessionId, since: started)
        state.restStart = nil
        state.restEnd = nil
        state.summary = .init(
            minutes: max(1, Int((Date().timeIntervalSince(started) / 60).rounded())),
            exercises: steps.filter { (setsDone[$0.item.uid] ?? 0) > 0 }.count, of: steps.count,
            sets: setsDone.values.reduce(0, +), volumeKg: lifts.volumeKg, prs: lifts.prs)
        return state
    }

    /// − / + on the lock screen: the coming set's weight, by the stepper's step.
    private func stepKgFromLockScreen(_ sign: Int) {
        guard ready, !finished, sign != 0, steps.indices.contains(index) else { return }
        let step = steps[index]
        let done = setsDone[step.item.uid] ?? 0
        guard step.loggable, done < step.sets, log.item?.uid == step.item.uid else { return }
        log.stepKg(done, by: Double(sign))
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
            sessionId: sessionId, estMin: session.estMin, exercises: session.blocks.reduce(0) { $0 + $1.items.count },
            exerciseId: step.item.exerciseId, setIndex: setsDone[step.item.uid] ?? 0, loggable: step.loggable && step.timedSpec == nil,
            kg: log.item?.uid == step.item.uid ? log.values(min(setsDone[step.item.uid] ?? 0, max(0, log.rows.count - 1)))?.kg : nil,
            coach: coach.watchLine?.text, coachAt: coach.watchLine?.at))
    }

    /// Reps counted by the Watch fill the coming set's reps (#383); the member still confirms with an effort tile.
    private func applyWatchLift(_ l: WLiftLive) {
        guard ready, !finished, steps.indices.contains(index), l.sessionId == sessionId else { return }
        let step = steps[index]
        let done = setsDone[step.item.uid] ?? 0
        guard l.exerciseId == step.item.exerciseId, l.setIndex == done, pause == nil else { return }
        watchLift = l
        if l.reps > 0, editingSet == nil, log.item?.uid == step.item.uid, log.rows.indices.contains(done) {
            log.rows[done].reps = String(l.reps)
        }
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
        case .kgDown: stepKgFromLockScreen(-1)
        case .kgUp: stepKgFromLockScreen(1)
        }
    }
}

/// Rest in the set card's slot (#538, design A): what was just done, a big timer with a square progress bar, +15 s and
/// the optional effort for that set. Up next and the controls (SKIP REST) stay where they are. 3-2-1 taps, then the rest
/// closes by itself (#357); VoiceOver hears 10 s and 3 s left.
private struct RestSlotCard: View {
    let pause: WorkoutPlayerView.Pause
    let colors: [Color]
    let doneLabel: String
    let onEffort: (Effort) -> Void
    let onExtend: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(pause.end == nil ? doneLabel : "Rest · \(doneLabel)")
                    .font(Theme.label(12)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if pause.end != nil {
                    Button(action: onExtend) {
                        Text("+15 s").font(Theme.label(14)).foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(minWidth: 44, minHeight: 36)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.cardStrong))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -4)
                    .accessibilityLabel("Add 15 seconds of rest")
                }
            }
            if let end = pause.end {
                TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
                    let left = max(0, end.timeIntervalSince(ctx.date))
                    let secs = Int(left.rounded(.up))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Format.rest(secs)).font(Theme.display(48)).monospacedDigit()
                            .foregroundStyle(left > 3 ? .white : Theme.lime)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.white.opacity(0.1))
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                                    .frame(width: g.size.width * min(1, max(0, left / Double(max(1, pause.total)))))
                            }
                        }
                        .frame(height: 10)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(left > 3 ? "Rest" : "Get ready")
                    .accessibilityValue("\(secs) second\(secs == 1 ? "" : "s") left")
                }
            }
            if pause.effortSet != nil {
                if pause.end == nil {
                    Text("How hard? (optional)").font(Theme.label(12)).foregroundStyle(Theme.muted)
                }
                EffortPicker(selected: pause.effort, optional: true, compact: true, onPick: onEffort)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .task(id: pause.end) {
            guard let end = pause.end else { return }
            // VoiceOver: 10 s left (rests long enough to have them).
            let wait10 = end.timeIntervalSinceNow - 10
            if wait10 > 0 {
                try? await Task.sleep(for: .seconds(wait10))
                guard !Task.isCancelled else { return }
                Self.announce("10 seconds of rest left")
            }
            // 3-2-1 taps, then the rest closes by itself (#357): no Continue tap.
            for tick in [3.0, 2.0, 1.0] {
                let wait = end.timeIntervalSinceNow - tick
                guard wait > -0.5 else { continue }
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled else { return }
                if tick == 3 { Self.announce("3 seconds") }
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            }
            let wait = end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            onDone()
        }
    }

    private static func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}

/// Discard with Undo (#538): the workout is put away at once and only thrown away once its Undo bar is gone.
/// Opening the player for it again (Undo, or Resume on Train) cancels the discard.
@MainActor
enum PendingDiscard {
    private static var tasks: [String: Task<Void, Never>] = [:]
    /// The discarded run, put back when Undo (or opening the player again) keeps it.
    private static var kept: [String: (model: AppModel, run: ActiveWorkout)] = [:]

    /// The run leaves Train at once (Freestyle no longer says resume); Watch and re-plan follow once Undo is gone.
    static func schedule(_ sessionId: String, model: AppModel) {
        tasks[sessionId]?.cancel()
        if let run = model.activeWorkout(sessionId) { kept[sessionId] = (model, run) }
        model.clearActiveWorkout(sessionId)
        tasks[sessionId] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(UndoCloseCenter.seconds + 0.5))
            guard !Task.isCancelled else { return }
            PendingDiscard.tasks[sessionId] = nil
            PendingDiscard.kept[sessionId] = nil
            WatchSync.shared.endLive(.discarded, sessionId: sessionId)
            model.replanAfterWorkoutIfDone()
        }
    }

    static func cancel(_ sessionId: String) {
        tasks.removeValue(forKey: sessionId)?.cancel()
        guard let k = kept.removeValue(forKey: sessionId), k.model.state.activeWorkout == nil else { return }
        k.model.saveActiveWorkout(k.run)
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
    var wins: [Win] = []
    var record: WorkoutRecord?
    var recap: WorkoutRecap?
    var recapOnDevice = false
    let onDone: () -> Void
    @State private var pop = false

    private var recordId: UUID? { record?.id }

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
                // Wins you missed (#501): three personal wins, even on a weak day, and how you feel now.
                if !wins.isEmpty { WinsCard(wins: wins, recordId: recordId) }
                if let recap { RecapCard(recap: recap, onDevice: recapOnDevice) }
                // Effort to Apple Health (#614 A).
                if let record { EffortCard(record: record) }
                HStack(spacing: 10) {
                    GradientStat(symbol: "stopwatch.fill", value: Format.elapsed(elapsed), label: "Time", gradient: WorkoutEngine.Category.cardio.gradient)
                    GradientStat(symbol: "square.stack.3d.up.fill", value: "\(setsDone)", label: "Sets", gradient: WorkoutEngine.Category.strength.gradient)
                    if let kcal { GradientStat(symbol: "flame.fill", value: "\(Int(kcal))", label: "kcal", gradient: WorkoutEngine.Category.warmup.gradient, ink: WorkoutEngine.Category.warmup.ink) }
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
                // Fuel (#496): what to eat next.
                RecoveryFuelCard()
                Text("Added to your history in Progress.").font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(20)
        }
        .readableWidth()
        // DONE always on screen (#538): pinned under the scrolling summary.
        .safeAreaInset(edge: .bottom) {
            Button(action: onDone) { Text("DONE") }
                .buttonStyle(LimeButtonStyle())
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .readableColumn()
                .background(Theme.bg.ignoresSafeArea())
        }
        .onAppear { withAnimation(.spring(duration: 0.6, bounce: 0.5)) { pop = true } }
    }
}
