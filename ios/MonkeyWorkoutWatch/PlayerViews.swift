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
        .task { await workout.start(title: player.session.title) }
        .task(id: player.timedEnd) {
            // Timed work over: count the set.
            guard let end = player.timedEnd else { return }
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
            autoLogAt = Date().addingTimeInterval(4)
        }
        .task(id: autoLogAt) {
            guard let at = autoLogAt else { return }
            try? await Task.sleep(for: .seconds(max(0, at.timeIntervalSinceNow)))
            guard !Task.isCancelled, autoLogAt == at else { return }
            autoLogAt = nil
            complete()
        }
        .onDisappear { lift.stop() }
    }

    // MARK: Lift sensor (#383)

    private var liftMode: WatchLiftMode { store.snapshot.liftSensor ?? .default }

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
            lift.track(key: key, profile: profile, lossLimit: liftMode.lossLimit)
        } else if let spot = MachineSpot.for(name: step.name, exerciseId: step.exerciseId) {
            lift.trackMachine(key: key, exercise: step.exerciseId, family: spot.family, lossLimit: liftMode.lossLimit)
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
        return makeLiftSet(lift.stop(), sessionId: player.session.id, exerciseId: step.exerciseId, setIndex: player.done,
                           kg: row.kg, machine: machine)
    }

    /// Completes the current set (SET DONE, automatic log), with its measured reps.
    private func complete() {
        let measured = takeLift()
        let before = player.totalSets
        send(player.completeSet())
        if let measured, player.totalSets > before {
            store.send(.liftSet(measured))
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
        if let lastLift { lines.append(liftLine(lastLift)) }
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
                    lift.strapped(exercise: step.exerciseId, family: spot.family, lossLimit: liftMode.lossLimit)
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
                    Text(block.title.uppercased()).font(W.label(8)).tracking(0.5).lineLimit(1)
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
                    LiftPanel(lift: lift, reps: row.reps, tint: block?.tint ?? 0x7B2FF7)
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
                        let left = player.timedEnd.map { max(0, $0.timeIntervalSince(ctx.date)) } ?? player.timedRemaining ?? TimeInterval(step.timedSec ?? 0)
                        Text(WatchPlayer.clock(left)).font(W.display(34)).monospacedDigit().foregroundStyle(light)
                    }
                    HStack {
                        Text(step.reps).font(W.label(11)).opacity(0.8)
                        Spacer(minLength: 0)
                        SetDots(done: player.done, total: step.sets)
                    }
                } else {
                    Text(step.sets > 1 ? "\(step.sets) × \(step.reps)" : step.reps).font(W.display(24)).minimumScaleFactor(0.6)
                    if let i = step.intensity { Text(i).font(.system(size: 10, weight: .semibold)).opacity(0.8) }
                }
                if let autoLogAt, let row = player.currentRow {
                    AutoLogBanner(title: "\(WatchPlayer.kg(row.kg)) × \(row.reps) logging", end: autoLogAt, onUndo: undoAutoLog)
                } else {
                    LimeButton(title: player.mainLabel) { main() }
                }
                HStack(spacing: 5) {
                    Text("NEXT").font(W.label(8)).tracking(1).foregroundStyle(.secondary)
                    Text(player.upNext).font(W.label(10)).lineLimit(1)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(0.1)))
            }
        }
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
                            note: restNote, heartRate: workout.heartRate) { rir in
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
        if let measured, player.totalSets > before {
            store.send(.liftSet(measured))
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
                kcal: saved ? workout.activeKcal : nil, savedToHealth: saved)))
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
                .background(Circle().fill(.white.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }
}

/// Swipe right from the workout page: pause / resume, end & save (3 s to cancel), back / skip, discard (confirmed).
private struct ControlsPage: View {
    let player: WatchPlayer
    let onEnd: () -> Void
    let onDiscard: () -> Void
    let onBack: () -> Void
    @Environment(WorkoutManager.self) private var workout
    @State private var confirmDiscard = false
    /// Set while the End countdown runs; a mistaken tap can still be cancelled (#133).
    @State private var endingAt: Date?

    var body: some View {
        ScrollView {
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
                Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                    GridRow {
                        tile(workout.paused ? "play.fill" : "pause.fill", workout.paused ? "Resume" : "Pause", 0xFFC23D, 0xFF7A3D, height: 62) {
                            workout.paused ? workout.resume() : workout.pause()
                        }
                        tile("stop.fill", "End", 0xFF3D5A, 0xB0105A, height: 62) {
                            endingAt = Date().addingTimeInterval(3)
                            WKInterfaceDevice.current().play(.click)
                        }
                    }
                    GridRow {
                        tile("backward.end.fill", "Back", 0x3D5AFF, 0x7B3DFF, height: 50) { player.back(); onBack() }
                        tile("forward.end.fill", "Skip", 0x1E9BFF, 0x3DFFB0, height: 50) { _ = player.advance(); onBack() }
                    }
                }
                Button { confirmDiscard = true } label: {
                    Label("Discard workout", systemImage: "xmark").font(W.label(11)).foregroundStyle(W.color(0xFF6D85))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .background(RadialGradient(colors: [W.color(0x3A1030), .black], center: .top, startRadius: 0, endRadius: 170).ignoresSafeArea())
        .overlay {
            if let endingAt { EndCountdown(end: endingAt) { self.endingAt = nil } }
        }
        .task(id: endingAt) {
            guard let end = endingAt else { return }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled, endingAt == end else { return }
            endingAt = nil
            WKInterfaceDevice.current().play(.stop)
            onEnd()
        }
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive, action: onDiscard)
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Not saved to Apple Health.")
        }
    }

    /// Explore-style tile: icon tile top left, heavy label bottom left, vivid gradient.
    private func tile(_ symbol: String, _ title: String, _ a: UInt32, _ b: UInt32, height: CGFloat,
                      action: @escaping () -> Void) -> some View {
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
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(W.gradient(a, b)))
        }
        .buttonStyle(.plain)
    }
}

/// "Ending in 3 · 2 · 1" with a big Cancel, shown after End is tapped.
private struct EndCountdown: View {
    let end: Date
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                let left = max(0, end.timeIntervalSince(ctx.date))
                ZStack {
                    Circle().stroke(W.color(0xFF3D5A).opacity(0.18), lineWidth: 10)
                    Circle().trim(from: 0, to: left / 3)
                        .stroke(W.color(0xFF3D5A), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Eyebrow(text: "Ending", color: W.light(0xFF3D5A))
                        Text("\(Int(left.rounded(.up)))").font(W.display(38)).monospacedDigit()
                    }
                }
                .frame(width: 104, height: 104)
            }
            LimeButton(title: "CANCEL", action: onCancel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RadialGradient(colors: [W.color(0x5A0A20), .black], center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 150)
            .ignoresSafeArea())
    }
}

/// After a set: one-tap effort, gradient rest ring with haptic at 0, next set or exercise as a card.
struct RestOverlay: View {
    let end: Date?
    let total: Int
    let effort: Bool
    let next: String
    let tint: UInt32
    var tint2: UInt32 = 0x7B3DFF
    /// Lift sensor (#383): the set just measured, machine → wrist reminder.
    var note: String?
    var heartRate: Double?
    let onEffort: (Int) -> Void
    let onAdd: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if effort {
                    Text("How hard?").font(W.display(16))
                    EffortGrid(onEffort: onEffort)
                }
                if let end {
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        let left = max(0, end.timeIntervalSince(ctx.date))
                        ZStack {
                            Circle().stroke(W.lime.opacity(0.12), lineWidth: 11)
                            Circle().trim(from: 0, to: left / Double(max(1, total)))
                                .stroke(LinearGradient(colors: [W.lime, W.color(0x3DFFB0)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                        style: StrokeStyle(lineWidth: 11, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Eyebrow(text: left > 0 ? "Rest" : "Go!", color: W.lime)
                                Text(WatchPlayer.clock(left)).font(W.display(30)).monospacedDigit()
                            }
                        }
                        .frame(width: 118, height: 118)
                    }
                    HStack(spacing: 5) {
                        pill("+15 s", fill: .white.opacity(0.16), text: .white, action: onAdd)
                        pill("Skip", fill: W.lime, text: W.ink, action: onSkip)
                    }
                } else {
                    pill("Continue", fill: W.lime, text: W.ink, action: onSkip)
                }
                if note != nil || heartRate != nil {
                    VStack(spacing: 1) {
                        if let note { Text(note).font(W.label(10)).multilineTextAlignment(.center).lineLimit(3) }
                        if let heartRate { Text("♥ \(Int(heartRate))").font(W.label(10)).foregroundStyle(W.color(0xFF5A75)).monospacedDigit() }
                    }
                    .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("NEXT").font(W.label(8)).tracking(1).opacity(0.85)
                    Text(next).font(W.label(12)).lineLimit(2)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(W.gradient(tint, tint2)))
            }
        }
        .background(RadialGradient(colors: [W.color(effort ? 0x24301A : 0x1D3A10), .black], center: UnitPoint(x: 0.5, y: 0.35),
                                   startRadius: 0, endRadius: 160).ignoresSafeArea())
        .task(id: end) {
            guard let end else { return }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            if !Task.isCancelled { WKInterfaceDevice.current().play(.notification) }
        }
    }

    private func pill(_ title: String, fill: Color, text: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(W.label(12)).foregroundStyle(text)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
    }
}

/// Fail / 1 / 2 / 3 left in two columns, "4+ easy" full width.
struct EffortGrid: View {
    let onEffort: (Int) -> Void

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
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [e.color, W.effortEnd[i]], startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .buttonStyle(.plain)
    }
}
