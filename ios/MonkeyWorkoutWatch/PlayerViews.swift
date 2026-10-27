import LiftSensor
import SwiftUI
import WatchKit

/// Workout on the Watch (#131): one workout page with metrics and the current set; swipe right for
/// controls (pause, end, discard), swipe left for Now Playing. Rest / effort overlay sits on the workout page.
struct PlayerView: View {
    @Bindable var player: WatchPlayer
    let onClose: () -> Void
    @Environment(WatchStore.self) private var store
    @Environment(WorkoutManager.self) private var workout
    @State private var page = 1
    @State private var crown = 8.0
    @State private var saved = false
    @State private var sent = false
    /// What the last Action button press did (#349), shown briefly.
    @State private var actionLabel: String?
    /// Lift sensor (#383): reps and bar speed of the current set.
    @State private var lift = LiftTracker()
    /// The bar is racked: the set logs itself at this time unless undone.
    @State private var autoLogAt: Date?
    /// Exercises the member chose to log by hand instead of machine mode.
    @State private var byHand: Set<String> = []
    /// Last measured set, shown during the rest.
    @State private var lastLift: WLiftSet?
    /// Counting levels learned from corrections in this workout (#410), ahead of the phone's next snapshot.
    @State private var learnedHere: [String: Double] = [:]

    var body: some View {
        Group {
            if player.phase == .finished {
                SummaryView(player: player, kcal: workout.activeKcal, avgHR: workout.averageHeartRate, saved: saved, onDone: onClose)
            } else {
                TabView(selection: $page) {
                    ControlsPage(player: player, onEnd: finish, onDiscard: discard) { page = 1 }.tag(0)
                    workoutPage.tag(1)
                    NowPlayingView().tag(2)
                }
                .tabViewStyle(.page)
            }
        }
        .task {
            // Still tracking an iPhone workout paused there (#820): end it, this workout gets its own Health session.
            if workout.phoneSessionId != nil { store.stopTracking() }
            await workout.start(title: player.session.title)
        }
        .task(id: player.timedEnd) {
            // Timed work over: count the set.
            guard let end = player.timedEnd else { return }
            // Guided per-side hold (#619 C): a tap on the wrist halfway, other side.
            if let sw = player.sideSwitch(endingAt: end), sw > Date() {
                try? await Task.sleep(for: .seconds(sw.timeIntervalSinceNow))
                guard !Task.isCancelled, player.timedEnd == end else { return }
                WKInterfaceDevice.current().play(.directionUp)
            }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled, player.timedEnd == end else { return }
            send(player.completeSet())
        }
        .onChange(of: player.phase) { _, p in if p == .finished { finish() } }
        .onChange(of: ActionButton.shared.presses) { actionPress() }
        .overlay(alignment: .top) {
            if let actionLabel {
                Text(actionLabel).font(W.label(13)).foregroundStyle(W.ink).lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(W.lime).shadow(color: W.lime.opacity(0.5), radius: 6))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .task(id: actionLabel) {
            guard actionLabel != nil else { return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation { actionLabel = nil }
        }
        .onChange(of: player.index) { syncCrown() }
        .onAppear { syncCrown() }
        .onChange(of: liftKey, initial: true) { _, key in syncLift(key) }
        .onChange(of: lift.count) { _, n in
            guard lift.mode == .tracking, n > 0 else { return }
            player.setReps(n)
            crown = Double(n)
        }
        .onChange(of: lift.endedAt) { _, at in
            guard at != nil, autoLogAt == nil, lift.count > 0 else { return }
            switch liftLogging {
            case .auto: autoLogAt = Date().addingTimeInterval(WatchLiftLogging.countdown)
            case .confirm: WKInterfaceDevice.current().play(.notification)
            case .manual: break
            }
        }
        .task(id: autoLogAt) {
            guard let at = autoLogAt else { return }
            try? await Task.sleep(for: .seconds(max(0, at.timeIntervalSinceNow)))
            guard !Task.isCancelled, autoLogAt == at else { return }
            autoLogAt = nil
            complete()
        }
        .onDisappear { lift.stop() }
        // iPhone twin player (#603): what this page shows goes to the phone; its presses come back.
        .onChange(of: mirrorState, initial: true) { _, s in workout.sendMirror(s) }
        .onReceive(NotificationCenter.default.publisher(for: .mirrorCommand)) { n in
            if let c = n.object as? WCommand { remote(c) }
        }
    }

    // MARK: iPhone twin player (#603)

    private var mirrorState: WMirrorState {
        let step = player.step
        let block = step.flatMap { blockOf($0) }
        var detail = ""
        if let step {
            if step.loggable, let row = player.currentRow, player.done < step.sets {
                detail = "\(WatchPlayer.kg(row.kg)) kg × \(row.reps)"
            } else if let sec = step.timedSec {
                detail = WatchPlayer.clock(player.timedRemaining ?? TimeInterval(sec))
            } else {
                detail = step.sets > 1 ? "\(step.sets) × \(step.reps)" : step.reps
            }
        }
        var restEnd: Date?
        if case let .rest(end, _, _) = player.phase { restEnd = end }
        let setLabel = step.map { s in
            let set = s.sets > 1 ? "SET \(min(player.done + 1, s.sets)) OF \(s.sets)" : ""
            return [block?.title.uppercased() ?? "", set].filter { !$0.isEmpty }.joined(separator: " · ")
        } ?? ""
        return WMirrorState(
            sessionId: player.session.id, title: player.session.title, exercise: step?.name ?? "Done", setLabel: setLabel,
            detail: detail, next: player.upNext, restEnd: restEnd, tint: block?.tint ?? 0x2F6BFF, tint2: block?.tint2 ?? 0x8A4DFF,
            action: player.mainLabel, loggable: step?.loggable == true && player.done < (step?.sets ?? 0),
            position: player.index + 1, count: player.steps.count, finished: player.phase == .finished)
    }

    private func remote(_ c: WCommand) {
        switch c {
        case .main:
            if case .rest = player.phase { send(player.skipRest()) } else { main() }
        case .skipRest: send(player.skipRest())
        case .addRest: player.addRest()
        case .effort0, .effort1, .effort2, .effort3, .effort4:
            send(player.effort([WCommand.effort0, .effort1, .effort2, .effort3, .effort4].firstIndex(of: c) ?? 2))
        case .next: send(player.advance())
        case .previous: player.back()
        case .kgDown: player.adjustKg(-1)
        case .kgUp: player.adjustKg(1)
        // Finish workout on the iPhone's twin player (#822): ends here, the summary shows and the phone gets the record.
        case .finish: finish()
        }
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: Lift sensor (#383)

    private var liftMode: WatchLiftMode { store.snapshot.liftSensor ?? .default }
    private var liftLogging: WatchLiftLogging { store.snapshot.liftLogging ?? .default }

    /// Counting level for an exercise (#410): the member's setting plus what the exercise learned.
    private func strictness(_ exerciseId: String) -> Double {
        Strictness.level(setting: (store.snapshot.liftCounting ?? .default).level, learned: learned(exerciseId))
    }

    private func learned(_ exerciseId: String) -> Double {
        learnedHere[exerciseId] ?? store.snapshot.liftLearned?[exerciseId] ?? 0
    }

    /// Racked, waiting for the member's tap (Tap ✓ logging).
    private var waitingForTap: Bool {
        liftLogging == .confirm && lift.mode == .tracking && lift.endedAt != nil && lift.count > 0
    }

    /// The set the sensor should measure now: a loaded, untimed set being done.
    private var liftKey: String? {
        guard liftMode.on, LiftTracker.available, player.phase == .work, let step = player.step, step.loggable,
              step.timedSec == nil, player.done < step.sets, !byHand.contains(step.uid) else { return nil }
        return "\(step.uid)#\(player.done)"
    }

    private func syncLift(_ key: String?) {
        autoLogAt = nil
        guard let key, let step = player.step else {
            if lift.mode != .idle { lift.stop() }
            return
        }
        if let profile = LiftProfile.for(name: step.name, exerciseId: step.exerciseId) {
            lift.track(key: key, profile: profile, lossLimit: liftMode.lossLimit, strictness: strictness(step.exerciseId))
        } else if let spot = MachineSpot.for(name: step.name, exerciseId: step.exerciseId) {
            lift.trackMachine(key: key, exercise: step.exerciseId, family: spot.family, lossLimit: liftMode.lossLimit,
                              strictness: strictness(step.exerciseId))
        } else if lift.mode != .idle {
            lift.stop()
        }
    }

    /// Measured reps of the set being completed, sent to the phone after the set's own event.
    private func takeLift() -> WLiftSet? {
        guard lift.mode == .tracking, let step = player.step, let row = player.currentRow else {
            if lift.mode != .idle { lift.stop() }
            return nil
        }
        let machine = lift.machine
        var set = makeLiftSet(lift.stop(), sessionId: player.session.id, exerciseId: step.exerciseId, setIndex: player.done,
                              kg: row.kg, machine: machine)
        // Crown correction (#410): the phone learns from it; this workout already counts with it.
        if let counted = set?.reps, counted != row.reps {
            set?.logged = row.reps
            learnedHere[step.exerciseId] = Strictness.learn(learned(step.exerciseId), counted: counted, logged: row.reps)
        }
        return set
    }

    /// Completes the current set (SET DONE, automatic log), with its measured reps.
    private func complete() {
        let measured = takeLift()
        let before = player.totalSets
        send(player.completeSet())
        if player.totalSets > before {
            if let measured { store.send(.liftSet(measured)) }
            lastLift = measured
        }
        syncLift(liftKey)
    }

    private func undoAutoLog() {
        autoLogAt = nil
        lift.resume()
        WKInterfaceDevice.current().play(.click)
    }

    private var restNote: String? {
        var lines: [String] = []
        if let lastLift {
            lines.append(liftLine(lastLift))
            if let fix = correctionLine(lastLift) { lines.append(fix) }
        }
        // Machine mode just ended and the next lift is measured on the wrist.
        if lastLift?.machine == true, let next = player.done >= (player.step?.sets ?? 0) ? player.nextStep : player.step,
           LiftProfile.for(name: next.name, exerciseId: next.exerciseId) != nil {
            lines.append("⌚ Back on your wrist")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    @ViewBuilder private var liftOverlay: some View {
        if let step = player.step, player.phase == .work {
            if lift.mode == .strap, let spot = MachineSpot.for(name: step.name, exerciseId: step.exerciseId) {
                StrapPrompt(exercise: step.name, spot: spot) {
                    lift.strapped(exercise: step.exerciseId, family: spot.family, lossLimit: liftMode.lossLimit,
                                  strictness: strictness(step.exerciseId))
                } onSkip: {
                    byHand.insert(step.uid)
                }
            } else if lift.mode == .testRep || lift.calibratedAt != nil {
                TestRepView(calibrated: lift.mode == .tracking) {
                    byHand.insert(step.uid)
                }
                .task(id: lift.calibratedAt) {
                    // Show "Got it" briefly, then the set.
                    guard lift.calibratedAt != nil else { return }
                    try? await Task.sleep(for: .seconds(1.6))
                    lift.clearCalibrated()
                }
            }
        }
    }

    private var workoutPage: some View {
        let block = player.step.flatMap { blockOf($0) }
        let accent = W.color(block?.tint ?? 0xCCFF3D)
        let light = W.light(block?.tint ?? 0xCCFF3D)
        return VStack(alignment: .leading, spacing: 3) {
            StepBar(index: player.index, count: player.steps.count)
            HStack(spacing: 4) {
                if let block {
                    Text((block.title + (player.guidedPosition.map { " · \($0.index) of \($0.count)" } ?? "")).uppercased())
                        .font(W.label(8)).tracking(0.5).lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(accent))
                }
                Spacer(minLength: 0)
                MetricChips(player: player)
            }
            if let step = player.step {
                Text(step.name).font(W.display(18)).lineLimit(1).minimumScaleFactor(0.6)
                if step.loggable, let row = player.currentRow, player.done < step.sets, lift.mode == .tracking, lift.count > 0 {
                    Text("\(WatchPlayer.kg(row.kg)) kg · set \(player.done + 1) of \(step.sets)").font(W.label(10)).opacity(0.85)
                    LiftPanel(lift: lift, reps: row.reps, tint: block?.tint ?? 0x7B2FF7, waiting: waitingForTap)
                        .focusable()
                        .digitalCrownRotation($crown, from: 0, through: 50, by: 1, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                        .onChange(of: crown) { _, v in player.setReps(Int(v)) }
                } else if step.loggable, let row = player.currentRow, player.done < step.sets {
                    HStack(alignment: .center, spacing: 5) {
                        RoundIcon(symbol: "minus") { player.adjustKg(-1) }
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(WatchPlayer.kg(row.kg)).font(W.display(32)).foregroundStyle(light)
                            Text("kg").font(W.label(10))
                        }
                        .lineLimit(1).minimumScaleFactor(0.5)
                        Spacer(minLength: 0)
                        RoundIcon(symbol: "plus") { player.adjustKg(1) }
                    }
                    HStack {
                        Text("× \(row.reps) reps").font(W.display(16))
                            .focusable()
                            .digitalCrownRotation($crown, from: 0, through: 50, by: 1, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                            .onChange(of: crown) { _, v in player.setReps(Int(v)) }
                        Spacer(minLength: 0)
                        if lift.mode == .tracking { SensingChip(machine: lift.machine) }
                        SetDots(done: player.done, total: step.sets)
                    }
                } else if step.timedSec != nil {
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        let left = player.timedEnd.map { max(0, $0.timeIntervalSince(ctx.date)) } ?? player.timedRemaining ?? TimeInterval(player.workSec(step) ?? 0)
                        // Guided per-side hold (#619 C): the clock counts each side down on its own.
                        let side = TimeInterval(step.timedSec ?? 0)
                        let both = player.bothSides(step)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(WatchPlayer.clock(both && left > side ? left - side : left)).font(W.display(34)).monospacedDigit().foregroundStyle(light)
                            if both { Text(left > side ? "LEFT" : "RIGHT").font(W.label(11)).foregroundStyle(light) }
                        }
                    }
                    HStack {
                        Text(player.isGuided(step) ? "Guided · haptic at each change" : step.reps).font(W.label(11)).opacity(0.8)
                        Spacer(minLength: 0)
                        SetDots(done: player.done, total: step.sets)
                    }
                } else {
                    Text(step.sets > 1 ? "\(step.sets) × \(step.reps)" : step.reps).font(W.display(24)).minimumScaleFactor(0.6)
                    if let i = step.intensity { Text(i).font(.system(size: 10, weight: .semibold)).opacity(0.8) }
                }
                if let autoLogAt, let row = player.currentRow {
                    AutoLogBanner(title: "\(WatchPlayer.kg(row.kg)) kg × \(row.reps)", end: autoLogAt, onUndo: undoAutoLog)
                } else if waitingForTap, let row = player.currentRow {
                    LimeButton(title: "✓ LOG \(row.reps) REPS", pinch: pinchOnPage) { main() }
                } else {
                    LimeButton(title: player.mainLabel, pinch: pinchOnPage) { main() }
                }
                HStack(spacing: 5) {
                    Text("NEXT").font(W.label(8)).tracking(1).foregroundStyle(.secondary)
                    Text(player.upNext).font(W.label(10)).lineLimit(1)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(0.1)))
            }
        }
        .watchMargins()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Colour wash of the block, like the phone player.
        .background(alignment: .top) {
            LinearGradient(colors: [accent.opacity(0.85), W.color(block?.tint2 ?? 0x000000).opacity(0.45), .black],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.75))
                .ignoresSafeArea()
        }
        .overlay {
            if case let .rest(end, total, effortSet) = player.phase {
                RestOverlay(end: end, total: total, effort: effortSet != nil, next: player.upNext,
                            tint: block?.tint ?? 0xCCFF3D, tint2: block?.tint2 ?? 0x7B3DFF,
                            note: restNote, advice: player.wristAdvice, onApply: { kg in
                                player.applyKg(kg)
                                WKInterfaceDevice.current().play(.click)
                            }) { rir in
                    send(player.effort(rir))
                } onAdd: {
                    player.addRest()
                } onSkip: {
                    send(player.skipRest())
                }
            }
        }
        .overlay { liftOverlay }
    }

    /// Double tap (#604) presses the page's big button unless the rest or a sensor prompt covers it.
    private var pinchOnPage: Bool {
        if case .rest = player.phase { return false }
        return lift.mode != .strap && lift.mode != .testRep && lift.calibratedAt == nil
    }

    private func blockOf(_ it: WItem) -> WBlock? {
        player.session.blocks.first { $0.items.contains { $0.uid == it.uid } }
    }

    private func main() {
        guard let step = player.step else { return }
        if step.timedSec != nil && player.done < step.sets {
            player.toggleTimer()
            WKInterfaceDevice.current().play(.click)
        } else {
            autoLogAt = nil
            complete()
        }
    }

    /// Action button press (#349): the step the member's mode calls for (Settings → Apple Watch on the iPhone).
    private func actionPress() {
        autoLogAt = nil
        let measured = takeLift()
        let before = player.totalSets
        guard let r = player.actionPress(store.snapshot.actionButton ?? .default) else { return syncLift(liftKey) }
        send(r.events)
        if player.totalSets > before {
            if let measured { store.send(.liftSet(measured)) }
            lastLift = measured
        }
        syncLift(liftKey)
        withAnimation { actionLabel = r.label }
    }

    private func syncCrown() {
        crown = Double(player.currentRow?.reps ?? 8)
    }

    private func send(_ events: [WatchEvent]) {
        for e in events { store.send(e) }
    }

    private func finish() {
        if player.phase != .finished { player.phase = .finished; player.endedAt = Date() }
        guard !sent else { return }
        sent = true
        Task {
            saved = await workout.finish(sets: player.totalSets)
            store.send(.finished(WFinished(
                sessionId: player.session.id, setsDone: player.setsDone, start: player.started, end: player.endedAt ?? Date(),
                avgHeartRate: workout.averageHeartRate, maxHeartRate: workout.maxHeartRate,
                kcal: saved ? workout.activeKcal : nil, savedToHealth: saved, title: player.session.title)))
        }
    }

    private func discard() {
        workout.discard()
        onClose()
    }
}

/// Elapsed time and heart rate as small chips at the top of the workout page.
private struct MetricChips: View {
    let player: WatchPlayer
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        TimelineView(.periodic(from: player.started, by: 1)) { ctx in
            HStack(spacing: 3) {
                chip(WatchPlayer.clock(ctx.date.timeIntervalSince(player.started)), W.lime)
                chip(workout.heartRate.map { "♥\(Int($0))" } ?? "♥--", W.color(0xFF5A75))
            }
        }
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(W.label(10)).monospacedDigit().foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(.black.opacity(0.35)))
    }
}

/// Position in the session: one segment per exercise (a bar when there are many).
private struct StepBar: View {
    let index: Int
    let count: Int

    var body: some View {
        Group {
            if count <= 14 {
                HStack(spacing: 2) {
                    ForEach(0..<max(count, 1), id: \.self) { i in
                        Capsule().fill(i <= index ? W.lime : .white.opacity(0.25)).frame(height: 3)
                    }
                }
            } else {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(W.lime).frame(width: g.size.width * Double(index + 1) / Double(count))
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 18)
    }
}

/// Sets of the current exercise: lime for done.
private struct SetDots: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<min(total, 8), id: \.self) { i in
                Circle().fill(i < done ? W.lime : .clear)
                    .overlay(Circle().stroke(i < done ? W.lime : .white.opacity(0.4), lineWidth: 1.5))
                    .frame(width: 7, height: 7)
            }
        }
    }
}

private struct RoundIcon: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .heavy))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }
}

/// Swipe right from the workout page: pause / resume, end & save (3 s to cancel), back / skip, discard (5 s to undo).
/// One screen, no scrolling (#538): the tiles share the height there is.
private struct ControlsPage: View {
    let player: WatchPlayer
    let onEnd: () -> Void
    let onDiscard: () -> Void
    let onBack: () -> Void
    @Environment(WorkoutManager.self) private var workout
    /// Set while the End countdown runs; a mistaken tap can still be cancelled (#133).
    @State private var endingAt: Date?
    /// Set while the Discard countdown runs (#538): no dialog, an Undo tile for a few seconds instead.
    @State private var discardingAt: Date?

    var body: some View {
        VStack(spacing: 5) {
            TimelineView(.periodic(from: player.started, by: 1)) { ctx in
                HStack(alignment: .firstTextBaseline) {
                    Text(WatchPlayer.clock(ctx.date.timeIntervalSince(player.started))).font(W.display(20)).foregroundStyle(W.lime)
                    Spacer(minLength: 0)
                    Text(workout.heartRate.map { "♥ \(Int($0))" } ?? "♥ --").font(W.label(11)).foregroundStyle(W.color(0xFF5A75))
                    Text("\(Int(workout.activeKcal))kcal").font(W.label(11))
                }
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
            HStack(spacing: 5) {
                tile(workout.paused ? "play.fill" : "pause.fill", workout.paused ? "Resume" : "Pause", 0xFFC23D, 0xFF7A3D) {
                    workout.paused ? workout.resume() : workout.pause()
                }
                tile("stop.fill", "End", 0xFF3D5A, 0xB0105A) {
                    endingAt = Date().addingTimeInterval(3)
                    WKInterfaceDevice.current().play(.click)
                }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 5) {
                tile("backward.end.fill", "Back", 0x3D5AFF, 0x7B3DFF) { player.back(); onBack() }
                tile("forward.end.fill", "Skip", 0x1E9BFF, 0x3DFFB0) { _ = player.advance(); onBack() }
            }
            .frame(maxHeight: .infinity)
            Button {
                discardingAt = Date().addingTimeInterval(Self.discardSeconds)
                WKInterfaceDevice.current().play(.click)
            } label: {
                Label("Discard workout", systemImage: "xmark").font(W.label(11)).foregroundStyle(W.color(0xFF6D85))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .watchMargins()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RadialGradient(colors: [W.color(0x3A1030), .black], center: .top, startRadius: 0, endRadius: 170).ignoresSafeArea())
        .overlay {
            if let endingAt {
                EndCountdown(end: endingAt) { self.endingAt = nil }
            } else if let discardingAt {
                EndCountdown(end: discardingAt, title: "Discarding", button: "UNDO", seconds: Self.discardSeconds) {
                    self.discardingAt = nil
                }
            }
        }
        .task(id: endingAt) {
            guard let end = endingAt else { return }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled, endingAt == end else { return }
            endingAt = nil
            WKInterfaceDevice.current().play(.stop)
            onEnd()
        }
        .task(id: discardingAt) {
            guard let end = discardingAt else { return }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled, discardingAt == end else { return }
            discardingAt = nil
            WKInterfaceDevice.current().play(.stop)
            onDiscard()
        }
    }

    private static let discardSeconds: Double = 5

    /// Explore-style tile: icon tile top left, heavy label bottom left, vivid gradient; as tall as its row.
    private func tile(_ symbol: String, _ title: String, _ a: UInt32, _ b: UInt32, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading) {
                Image(systemName: symbol).font(.system(size: 12, weight: .heavy))
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.28)))
                Spacer(minLength: 0)
                Text(title).font(W.display(14)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .padding(7)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(W.gradient(a, b)))
        }
        .buttonStyle(.plain)
    }
}

/// "Ending in 3 · 2 · 1" with a big Cancel, shown after End is tapped; "Discarding" with Undo after Discard (#538).
private struct EndCountdown: View {
    let end: Date
    var title = "Ending"
    var button = "CANCEL"
    var seconds: Double = 3
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                let left = max(0, end.timeIntervalSince(ctx.date))
                // Rounded square with square ends (#541), like the other rings.
                let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
                ZStack {
                    shape.stroke(W.color(0xFF3D5A).opacity(0.18), lineWidth: 10)
                    shape.trim(from: 0, to: left / max(1, seconds))
                        .stroke(W.color(0xFF3D5A), style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                    VStack(spacing: 0) {
                        Eyebrow(text: title, color: W.light(0xFF3D5A))
                        Text("\(Int(left.rounded(.up)))").font(W.display(38)).monospacedDigit()
                    }
                }
                .frame(width: 104, height: 104)
            }
            LimeButton(title: button, action: onCancel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RadialGradient(colors: [W.color(0x5A0A20), .black], center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 150)
            .ignoresSafeArea())
    }
}

/// After a set (#538): one fixed screen, no scrolling. A gradient rest tile (time, +15 / Skip, a bar that drains) with
/// a haptic at 0, then the one-tap effort or what's next.
struct RestOverlay: View {
    let end: Date?
    let total: Int
    let effort: Bool
    let next: String
    let tint: UInt32
    var tint2: UInt32 = 0x7B3DFF
    /// Lift sensor (#383): the set just measured, machine → wrist reminder.
    var note: String?
    /// Wrist Coach (#608 C): the question and its answer, Apply sets the weight.
    var advice: WristCoach.Advice?
    var onApply: (Double) -> Void = { _ in }
    let onEffort: (Int) -> Void
    /// Read here, not passed in, so each heart rate sample redraws this overlay instead of the whole player.
    @Environment(WorkoutManager.self) private var workout
    private var heartRate: Double? { workout.heartRate }
    let onAdd: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            if let end {
                restTile(end)
            } else {
                if effort { Text("How hard?").font(W.display(14)).lineLimit(1) }
                pill("Continue", fill: W.lime, text: W.ink, pinch: true, action: onSkip)
            }
            if effort {
                EffortGrid(onEffort: onEffort, rowHeight: 28)
            } else {
                if let advice {
                    coachTile(advice)
                } else if note != nil || heartRate != nil {
                    VStack(spacing: 1) {
                        if let note { Text(note).font(W.label(10)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8) }
                        if let heartRate { Text("♥ \(Int(heartRate))").font(W.label(10)).foregroundStyle(W.color(0xFF5A75)).monospacedDigit() }
                    }
                    .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("NEXT").font(W.label(8)).tracking(1).opacity(0.85)
                    Text(next).font(W.label(12)).lineLimit(2).minimumScaleFactor(0.8)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.12)))
            }
            Spacer(minLength: 0)
        }
        .watchMargins()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RadialGradient(colors: [W.color(effort ? 0x24301A : 0x1D3A10), .black], center: UnitPoint(x: 0.5, y: 0.35),
                                   startRadius: 0, endRadius: 160).ignoresSafeArea())
        .task(id: end) {
            guard let end else { return }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            if !Task.isCancelled { WKInterfaceDevice.current().play(.notification) }
        }
    }

    /// Wrist Coach (#608 C): question, answer, Apply.
    private func coachTile(_ a: WristCoach.Advice) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text("🐵 \"\(a.question)\"").font(W.label(9)).foregroundStyle(W.lime).lineLimit(1)
                Text(a.answer).font(W.label(11)).lineLimit(2).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let kg = a.kg {
                Button { onApply(kg) } label: {
                    Text("Apply").font(W.label(11)).foregroundStyle(W.ink).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: 46, height: 30)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(W.lime))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Apply \(WatchPlayer.kg(kg)) kilos")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.14)))
        .accessibilityElement(children: .contain)
    }

    /// Rest as a block-coloured tile (#538): time left, +15 and Skip as squares, a bar draining underneath.
    private func restTile(_ end: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let left = max(0, end.timeIntervalSince(ctx.date))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 4) {
                    VStack(alignment: .leading, spacing: 0) {
                        Eyebrow(text: left > 0 ? "Rest" : "Go!", color: ink.opacity(0.85))
                        Text(WatchPlayer.clock(left)).font(W.display(26)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Rest")
                    .accessibilityValue("\(Int(left.rounded(.up))) seconds left")
                    Spacer(minLength: 2)
                    square("+15", fill: .black.opacity(0.28), text: .white, action: onAdd)
                        .accessibilityLabel("Add 15 seconds")
                    square("Skip", fill: W.lime, text: W.ink, pinch: true, action: onSkip)
                        .accessibilityLabel("Skip rest")
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(.black.opacity(0.3))
                        RoundedRectangle(cornerRadius: 2).fill(ink)
                            .frame(width: g.size.width * min(1, left / Double(max(1, total))))
                    }
                }
                .frame(height: 5)
            }
            .foregroundStyle(ink)
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(W.gradient(tint, tint2)))
        }
    }

    /// Type on the rest tile (#540): dark on a light block colour (warm-up yellow, lime), white on the rest.
    private var ink: Color {
        let r = Double((tint >> 16) & 0xFF) / 255, g = Double((tint >> 8) & 0xFF) / 255, b = Double(tint & 0xFF) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.6 ? W.ink : .white
    }

    private func square(_ title: String, fill: Color, text: Color, pinch: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(title).font(W.label(12)).lineLimit(1).minimumScaleFactor(0.7)
                if pinch { PinchMark() }
            }
            .foregroundStyle(text)
            .frame(width: 40, height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill))
        }
        .buttonStyle(.plain)
        .pinch(pinch)
    }

    private func pill(_ title: String, fill: Color, text: Color, pinch: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(W.label(12))
                if pinch { PinchMark() }
            }
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
        .pinch(pinch)
    }
}

/// Fail / 1 / 2 / 3 left in two columns, "4+ easy" full width.
struct EffortGrid: View {
    let onEffort: (Int) -> Void
    /// Tile height; the rest screen uses shorter tiles so everything fits without scrolling (#538).
    var rowHeight: CGFloat = 36

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow { button(0); button(1) }
            GridRow { button(2); button(3) }
            GridRow { button(4).gridCellColumns(2) }
        }
    }

    private func button(_ i: Int) -> some View {
        let e = W.efforts[i]
        // Hard efforts on dark-ending gradients read white, easy ones dark.
        let dark = i >= 2
        return Button { onEffort(e.rir) } label: {
            Text(i == 4 ? "\(e.title) 😎" : e.title).font(W.display(13)).foregroundStyle(dark ? W.ink : .white)
                .frame(maxWidth: .infinity, minHeight: rowHeight)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [e.color, W.effortEnd[i]], startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .buttonStyle(.plain)
    }
}
