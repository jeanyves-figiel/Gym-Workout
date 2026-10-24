import AudioToolbox
import HealthKit
import LiftSensor
import SwiftUI
import UIKit
import WorkoutEngine

// HIIT interval player (#693, design C from `hiit/proposals.png`): the whole screen takes the phase's colour (the
// format's gradient while working, cyan while resting), a huge countdown, the move with its animation, the block's
// rounds as segments, heart rate from the Watch, one Up next bar with Skip, and Pause / +1 round / Done in fixed
// spots. Beeps and haptics ring 3-2-1, work and rest; the Watch shows the same clock and its double tap pauses.
// Logged to History and Apple Health as high intensity interval training.

struct HiitPlayerView: View {
    let session: Session
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// The workout's steps, built once (#720): the clock redraws ten times a second.
    private let steps: [HiitWorkout.Step]

    init(session: Session) {
        self.session = session
        steps = (session.hiit ?? HiitWorkout(name: session.title, blocks: [])).steps
    }

    /// Seconds run before the current stretch, and when it started (nil while paused).
    @State private var banked: TimeInterval = 0
    @State private var since: Date?
    @State private var started: Date?
    @State private var cuedTo: TimeInterval = 0
    /// Work steps skipped before half of them was done (not counted as sets), by start second.
    @State private var skipped: Set<Int> = []
    /// AMRAP rounds tapped, by block.
    @State private var amrapRounds: [Int: Int] = [:]
    /// Step shown last (sends the Watch an update when it changes).
    @State private var shownStep = -1
    /// Heart rate seen from the Watch during this workout.
    @State private var beats: [Int] = []
    @State private var watchTracked = false
    @State private var record: WorkoutRecord?
    @State private var reward: GameReward?
    @State private var wins: [Win] = []
    @State private var finishedAt: TimeInterval?

    private var workout: HiitWorkout { session.hiit ?? HiitWorkout(name: session.title, blocks: []) }
    private var running: Bool { since != nil }

    private func elapsed(_ now: Date) -> TimeInterval { finishedAt ?? banked + (since.map { now.timeIntervalSince($0) } ?? 0) }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let record {
                SummaryView(session: session, elapsed: TimeInterval(record.durationSec), setsDone: record.totalSets, kcal: record.kcal,
                            healthSaved: health.connected && health.writeWorkouts, reward: reward, wins: wins, record: record) {
                    dismiss()
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                // Paused: the clock stands still, nothing to redraw (#720).
                TimelineView(.animation(minimumInterval: 0.1, paused: !running)) { ctx in
                    let e = elapsed(ctx.date)
                    let i = steps.firstIndex { Int(e) < $0.end }
                    screen(steps: steps, index: i, elapsed: e)
                        .onChange(of: Int(e * 5)) { _, _ in tick(e, steps: steps, index: i) }
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            remote(nil, index: nil)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            WatchSync.shared.sendWodRemote(nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchTimerToggle)) { _ in toggle() }
        // Back from the background (#716): the clock jumps on, the cues it slept through aren't played.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { cuedTo = elapsed(Date()) }
        }
    }

    // MARK: Screen

    @ViewBuilder
    private func screen(steps: [HiitWorkout.Step], index: Int?, elapsed e: TimeInterval) -> some View {
        let step = index.map { steps[$0] }
        let colors = tint(step)
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                Text(header(step)).font(Theme.label(13)).tracking(1.2).lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 8)
                Button { close() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.22)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Text(Hiit.clock(clockValue(step, e)))
                .font(.system(size: 96, weight: .black, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
                .contentTransition(.numericText(countsDown: true))
            figure(step)
                .frame(maxWidth: .infinity).frame(height: 190)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black.opacity(0.22)))
            moveText(step)
                .frame(height: 64)
            segments(step)
            heartRow
            Spacer(minLength: 0)
            upNext(steps: steps, index: index)
            controls(step)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .readableColumn()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.35), value: index)
    }

    private func header(_ step: HiitWorkout.Step?) -> String {
        guard started != nil, let step else {
            return "\(workout.formats.uppercased()) · \(workout.minutes)′"
        }
        let paused = running ? "" : " · PAUSED"
        switch step.kind {
        case .prep: return "GET READY" + paused
        case .warmup: return "WARM-UP · \(step.round) / \(step.rounds)" + paused
        case .cooldown: return "COOL-DOWN · \(step.round) / \(step.rounds)" + paused
        case .rest: return "REST" + paused
        case .work:
            let b = step.block.map { workout.blocks[$0] }
            let name = b?.format.label.uppercased() ?? "HIIT"
            if b?.format == .amrap { return "\(name) · ROUND \((amrapRounds[step.block ?? 0] ?? 0) + 1)" + paused }
            if b?.format == .forTime { return "\(name) · \(b?.rounds ?? 1) ROUNDS" + paused }
            return "\(name) · ROUND \(step.round) / \(step.rounds) · WORK" + paused
        }
    }

    /// Work: the format's gradient; rest: cyan; warm-up, cool-down and before the start: indigo.
    private func tint(_ step: HiitWorkout.Step?) -> [Color] {
        guard started != nil, let step else { return [Color(hex: 0x3D4BD6), Color(hex: 0x5A2FA0)] }
        switch step.kind {
        case .work:
            let t = step.block.map { workout.blocks[$0].format.tint } ?? HiitFormat.tabata.tint
            return [Color(hex: t.0), Color(hex: t.1)]
        case .rest: return [Color(hex: 0x00C7FF), Color(hex: 0x3D59FF)]
        case .prep, .warmup, .cooldown: return [Color(hex: 0x3D4BD6), Color(hex: 0x5A2FA0)]
        }
    }

    /// Seconds shown: For time counts up, the rest count down; before the start, the whole workout.
    private func clockValue(_ step: HiitWorkout.Step?, _ e: TimeInterval) -> Int {
        guard started != nil, let step else { return workout.totalSeconds }
        let s = Int(e)
        if step.kind == .work, let b = step.block, workout.blocks[b].format == .forTime { return s - step.start }
        return step.end - s
    }

    @ViewBuilder
    private func figure(_ step: HiitWorkout.Step?) -> some View {
        if let id = step?.exerciseId ?? workout.blocks.first?.moves.first?.exerciseId, let e = Exercise.find(id) {
            ExerciseMotionView(exercise: e, playTrigger: shownStep, autoPlayCycles: 8)
                .padding(10)
                .id(id)
        } else {
            Image(systemName: "bolt.heart.fill").font(.system(size: 64, weight: .bold)).opacity(0.8)
        }
    }

    @ViewBuilder
    private func moveText(_ step: HiitWorkout.Step?) -> some View {
        if started == nil || step == nil {
            VStack(spacing: 2) {
                Text(workout.name).font(Theme.display(28)).lineLimit(1).minimumScaleFactor(0.6)
                Text(workout.blocks.map(\.summary).joined(separator: " · ")).font(Theme.label(12)).opacity(0.85)
                    .lineLimit(2).multilineTextAlignment(.center)
            }
        } else if let step, step.open {
            // AMRAP / For time: the round's moves, in order.
            VStack(spacing: 1) {
                ForEach(step.moves, id: \.self) { Text($0).font(Theme.label(15)).lineLimit(1).minimumScaleFactor(0.6) }
            }
        } else if let step {
            VStack(spacing: 2) {
                if step.kind == .rest { Text("Next").font(Theme.label(12)).opacity(0.8) }
                Text(step.title).font(Theme.display(26)).lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
            }
        }
    }

    /// One segment per round of the block (warm-up / cool-down: per move); done white, current lime.
    private func segments(_ step: HiitWorkout.Step?) -> some View {
        let total = max(1, min(30, step?.rounds ?? 1))
        let current = step?.round ?? 0
        let isWork = step?.kind == .work || step?.kind == .warmup || step?.kind == .cooldown
        return HStack(spacing: 3) {
            ForEach(1...total, id: \.self) { r in
                RoundedRectangle(cornerRadius: 2)
                    .fill(r < current || (r == current && !isWork) ? Color.white : r == current ? Theme.lime : .white.opacity(0.25))
                    .frame(height: 8)
            }
        }
        .opacity(started == nil || step?.kind == .prep ? 0 : 1)
        .accessibilityHidden(true)
    }

    private var heartRow: some View {
        let bpm = WatchSync.shared.liveHeartRate
        return HStack {
            Label("Heart rate", systemImage: "heart.fill").font(Theme.label(13))
            Spacer()
            Text(bpm.map { "\($0) · Zone \(model.heartZones.zone(Double($0)))" } ?? "Open MonkeyFit on Watch")
                .font(Theme.label(13)).monospacedDigit()
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.22)))
    }

    /// One Up next bar: what comes after this step, with Skip.
    private func upNext(steps: [HiitWorkout.Step], index: Int?) -> some View {
        let next = index.flatMap { steps.indices.contains($0 + 1) ? steps[$0 + 1] : nil }
        let text: String = {
            guard started != nil, let next else { return started == nil ? "First: warm-up · \(workout.warmup.count) moves" : "Last one" }
            switch next.kind {
            case .rest: return "REST \(Hiit.short(next.seconds)) · then \(next.title)"
            case .work: return "NEXT · \(next.open ? (next.moves.first ?? next.title) : next.title)"
            case .cooldown: return "COOL-DOWN · \(next.title)"
            case .warmup: return "WARM-UP · \(next.title)"
            case .prep: return ""
            }
        }()
        return HStack {
            Text(text).font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.6)
            Spacer()
            Button { skip(steps: steps, index: index) } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 16, weight: .bold)).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(started == nil || index == nil)
            .accessibilityLabel("Skip")
        }
        .padding(.leading, 12)
        .frame(height: 52)
        .foregroundStyle(Color(hex: 0x04202A))
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x00C7FF)))
    }

    private func controls(_ step: HiitWorkout.Step?) -> some View {
        let format = step?.block.map { workout.blocks[$0].format }
        let open = step?.kind == .work && step?.open == true
        return HStack(spacing: 10) {
            Button { toggle() } label: {
                Label(running ? "Pause" : started == nil ? "Start HIIT" : "Resume", systemImage: running ? "pause.fill" : "play.fill")
                    .font(Theme.label(18)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, minHeight: 58)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.lime))
            }
            if open, running, format == .amrap, let b = step?.block {
                Button {
                    amrapRounds[b, default: 0] += 1
                    Haptics.start()
                } label: {
                    Text("+1 round").font(Theme.label(18)).frame(maxWidth: .infinity, minHeight: 58)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black.opacity(0.25)))
                }
            }
            if open, running, format == .forTime {
                Button { skip(steps: steps, index: steps.firstIndex { $0 == step }, done: true) } label: {
                    Text("Done").font(Theme.label(18)).frame(maxWidth: .infinity, minHeight: 58)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black.opacity(0.25)))
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    // MARK: Clock

    private func toggle() {
        guard record == nil else { return }
        if let s = since {
            banked += Date().timeIntervalSince(s)
            since = nil
        } else {
            if started == nil { started = Date() }
            since = Date()
        }
        Haptics.start()
        let e = elapsed(Date())
        remote(workout.step(at: e), index: steps.firstIndex { Int(e) < $0.end })
    }

    /// Moves to the next step. A work step skipped before half-way isn't counted; For time's Done counts it.
    private func skip(steps: [HiitWorkout.Step], index: Int?, done: Bool = false) {
        guard started != nil, let index, steps.indices.contains(index) else { return }
        let now = Date()
        let e = elapsed(now)
        let step = steps[index]
        if step.kind == .work, !done, !step.open, e - Double(step.start) < Double(step.seconds) / 2 { skipped.insert(step.start) }
        banked += Double(step.end) - e
        cuedTo = Double(step.end)
        if step.kind == .work { play(.rest) }
        if index + 1 >= steps.count { complete() }
    }

    private func tick(_ e: TimeInterval, steps: [HiitWorkout.Step], index: Int?) {
        if index != shownStep {
            shownStep = index ?? -1
            remote(index.map { steps[$0] }, index: index)
        }
        if let bpm = WatchSync.shared.liveHeartRate, running {
            watchTracked = true
            if beats.last != bpm { beats.append(bpm) }
        }
        guard running else { return }
        let a = Int(cuedTo), b = Int(e)
        // More than a couple of seconds missed (the app was in the background, #716): no burst of old cues.
        if b > a + 2 {
            cuedTo = e
        } else if b > a {
            for second in (a + 1)...b {
                for (k, st) in steps.enumerated() {
                    if st.kind == .work && st.start == second { play(.bell) }
                    if st.kind == .work && st.end == second && k < steps.count - 1 { play(.rest) }
                    if st.kind != .work, k + 1 < steps.count, steps[k + 1].kind == .work, (1...3).contains(st.end - second) { play(.tick) }
                }
            }
            cuedTo = e
        }
        if index == nil, started != nil { complete() }
    }

    private enum Cue { case bell, rest, tick, done }

    private func play(_ c: Cue) {
        let gen = UINotificationFeedbackGenerator()
        switch c {
        case .bell: AudioServicesPlaySystemSound(1013); gen.notificationOccurred(.success)
        case .rest: AudioServicesPlaySystemSound(1006); gen.notificationOccurred(.warning)
        case .tick: AudioServicesPlaySystemSound(1057); UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .done: AudioServicesPlaySystemSound(1025); gen.notificationOccurred(.success)
        }
    }

    // MARK: Finish

    /// Sets per item: every work interval done (skipped ones before half-way not counted), AMRAP rounds tapped,
    /// For time rounds when finished, one per warm-up and cool-down move.
    private func setsDone(at e: TimeInterval) -> [String: Int] {
        var out: [String: Int] = [:]
        let main = session.blocks.first { $0.kind == .cardio }?.items ?? []
        func uid(block: Int, move: Int) -> String? { main.first { $0.group == HiitWorkout.group(block: block, move: move) }?.uid }
        for st in steps where Double(st.end) <= e {
            switch st.kind {
            case .work:
                guard let b = st.block, !skipped.contains(st.start) else { continue }
                let block = workout.blocks[b]
                if st.open {
                    let n = block.format == .amrap ? max(1, amrapRounds[b] ?? 0) : block.rounds
                    for m in block.moves.indices { if let u = uid(block: b, move: m) { out[u, default: 0] += n } }
                } else if let m = st.moveIndex, let u = uid(block: b, move: m) {
                    out[u, default: 0] += 1
                }
            case .warmup, .cooldown:
                let kind: BlockKind = st.kind == .warmup ? .warmup : .cooldown
                if let u = session.blocks.first(where: { $0.kind == kind })?.items.first(where: { $0.exerciseId == st.exerciseId })?.uid {
                    out[u, default: 0] += 1
                }
            case .prep, .rest:
                break
            }
        }
        return out
    }

    /// Records what was done; false when nothing was.
    @discardableResult
    private func save(at e: TimeInterval) -> WorkoutRecord? {
        guard record == nil, let started else { return nil }
        let sets = setsDone(at: e)
        guard sets.values.reduce(0, +) > 0 else { return nil }
        let before = (game: model.game, badges: model.badges)
        let r = model.recordWorkout(session: session, setsDone: sets, startedAt: started,
                                    endedAt: started.addingTimeInterval(max(60, e)),
                                    bodyMassKg: health.snapshot.weightKg ?? model.body.weightKg)
        reward = GameReward(before: before.game, after: model.game, badgesBefore: before.badges, badgesAfter: model.badges)
        if reward?.weekCleared == true { model.markChestSeen() }
        wins = model.wins(for: r)
        // A Watch that sent heart rate ran its own HIIT workout and saves it to Health; else the phone does.
        if watchTracked, !beats.isEmpty {
            let avg = Double(beats.reduce(0, +)) / Double(beats.count)
            model.attachHeartRate(r.id, avg: avg, max: Double(beats.max() ?? 0))
        } else {
            Task {
                let hr = await health.save(r, activity: .highIntensityIntervalTraining)
                model.attachHeartRate(r.id, avg: hr.avg, max: hr.max)
            }
        }
        return r
    }

    private func complete() {
        guard record == nil, finishedAt == nil else { return }
        let e = elapsed(Date())
        finishedAt = e
        since = nil
        play(.done)
        remote(nil, index: nil, done: true)
        let r = save(at: e)
        withAnimation(.spring(duration: 0.5)) { record = r }
        if r == nil { dismiss() }
    }

    /// X: nothing done closes at once; else what was done is logged and the Undo bar takes it back.
    private func close() {
        let e = elapsed(Date())
        since = nil
        guard let r = save(at: e) else { return dismiss() }
        remote(nil, index: nil, done: true)
        finishedAt = e
        dismiss()
        let id = r.id
        UndoCloseCenter.shared.show(UndoOffer(
            title: "HIIT saved", detail: "\(r.totalSets) intervals · \(max(1, r.durationSec / 60))′",
            colors: Theme.hiitColors, reopen: { AnyView(EmptyView()) },
            revert: { [model] in _ = model.undoWorkout(id) }))
    }

    // MARK: Watch

    /// The Watch shows the clock (`WHiitLive` on the big screen remote, #622) and its double tap pauses.
    private func remote(_ step: HiitWorkout.Step?, index: Int?, done: Bool = false) {
        let first = workout.blocks.first?.format ?? .tabata
        let timer = WodTimer(id: session.id, name: workout.name, kind: first == .amrap ? .amrap : first == .forTime ? .forTime : .tabata,
                             work: max(5, workout.totalSeconds))
        let e = elapsed(Date())
        var live: WHiitLive?
        if let step, started != nil {
            let b = step.block.map { workout.blocks[$0] }
            let t: (UInt32, UInt32) = step.kind == .work ? (b?.format.tint ?? HiitFormat.tabata.tint) : step.kind == .rest ? (0x00C7FF, 0x3D59FF) : (0x3D4BD6, 0x5A2FA0)
            let next = index.flatMap { steps.indices.contains($0 + 1) ? steps[$0 + 1].title : nil }
            let countUp = step.kind == .work && b?.format == .forTime
            live = WHiitLive(
                phase: step.kind.rawValue, title: step.open ? (step.moves.first ?? step.title) : step.title,
                detail: header(step), next: next,
                endsAt: running ? Date().addingTimeInterval(Double(step.end) - e) : nil,
                startedAt: running && countUp ? Date().addingTimeInterval(Double(step.start) - e) : nil,
                remaining: max(0, step.end - Int(e)), countUp: countUp, tint: [t.0, t.1], done: done)
        } else {
            live = WHiitLive(phase: "ready", title: workout.name, detail: workout.formats, next: nil, endsAt: nil, startedAt: nil,
                             remaining: workout.totalSeconds, countUp: false, tint: [0x3D4BD6, 0x5A2FA0], done: done)
        }
        WatchSync.shared.sendWodRemote(WWodRemote(timer: timer, running: running, hiit: live))
    }
}
