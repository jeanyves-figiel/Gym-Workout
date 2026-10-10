import SwiftUI
import WatchKit

/// Workout on the Watch: vertical pages Metrics · Set · Controls, rest/effort overlay and summary.
struct PlayerView: View {
    @Bindable var player: WatchPlayer
    let onClose: () -> Void
    @Environment(WatchStore.self) private var store
    @Environment(WorkoutManager.self) private var workout
    @State private var page = 1
    @State private var crown = 8.0
    @State private var saved = false
    @State private var sent = false

    var body: some View {
        Group {
            if player.phase == .finished {
                SummaryView(player: player, kcal: workout.activeKcal, avgHR: workout.averageHeartRate, saved: saved, onDone: onClose)
            } else {
                TabView(selection: $page) {
                    MetricsPage(player: player).tag(0)
                    setPage.tag(1)
                    ControlsPage(player: player, onEnd: finish, onDiscard: discard) { page = 1 }.tag(2)
                }
                .tabViewStyle(.verticalPage)
                .overlay {
                    if case let .rest(end, total, effortSet) = player.phase {
                        RestOverlay(end: end, total: total, effort: effortSet != nil, next: player.upNext,
                                    tint: player.step.map { tint($0) } ?? 0xCCFF3D) { rir in
                            send(player.effort(rir))
                        } onAdd: {
                            player.addRest()
                        } onSkip: {
                            send(player.skipRest())
                        }
                    }
                }
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
        .onChange(of: player.index) { syncCrown() }
        .onAppear { syncCrown() }
    }

    private var setPage: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let step = player.step {
                Eyebrow(text: "\(step.name) · \(min(player.done + 1, step.sets))/\(step.sets)", color: W.color(tint(step)))
                if step.loggable, let row = player.currentRow, player.done < step.sets {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Button { player.adjustKg(-1) } label: { Image(systemName: "minus") }.buttonStyle(.plain).font(W.label(14))
                        Text(WatchPlayer.kg(row.kg)).font(W.display(30)).minimumScaleFactor(0.6)
                        Text("kg").font(W.label(11))
                        Button { player.adjustKg(1) } label: { Image(systemName: "plus") }.buttonStyle(.plain).font(W.label(14))
                    }
                    Text("× \(row.reps) reps").font(W.display(20))
                        .focusable()
                        .digitalCrownRotation($crown, from: 0, through: 50, by: 1, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                        .onChange(of: crown) { _, v in player.setReps(Int(v)) }
                } else if step.timedSec != nil {
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        let left = player.timedEnd.map { max(0, $0.timeIntervalSince(ctx.date)) } ?? player.timedRemaining ?? TimeInterval(step.timedSec ?? 0)
                        Text(WatchPlayer.clock(left)).font(W.display(36)).monospacedDigit()
                    }
                    Text(step.reps).font(W.label(11)).foregroundStyle(.secondary)
                } else {
                    Text(step.sets > 1 ? "\(step.sets) × \(step.reps)" : step.reps).font(W.display(28)).minimumScaleFactor(0.6)
                    if let i = step.intensity { Text(i).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) }
                }
                LimeButton(title: player.mainLabel) { main() }
                Text("Next: \(player.upNext)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tint(_ it: WItem) -> UInt32 {
        player.session.blocks.first { $0.items.contains { $0.uid == it.uid } }?.tint ?? 0xCCFF3D
    }

    private func main() {
        guard let step = player.step else { return }
        if step.timedSec != nil && player.done < step.sets {
            player.toggleTimer()
            WKInterfaceDevice.current().play(.click)
        } else {
            send(player.completeSet())
        }
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

private struct MetricsPage: View {
    let player: WatchPlayer
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        TimelineView(.periodic(from: player.started, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 2) {
                Text(WatchPlayer.clock(ctx.date.timeIntervalSince(player.started))).font(W.display(22)).foregroundStyle(W.lime).monospacedDigit()
                Text(workout.heartRate.map { "♥ \(Int($0))" } ?? "♥ --").font(W.display(30)).foregroundStyle(W.color(0xFF3D5A))
                Text("\(Int(workout.activeKcal)) kcal").font(W.display(20))
                Text("\(player.totalSets) sets · \(player.index + 1)/\(player.steps.count)").font(W.label(11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ControlsPage: View {
    let player: WatchPlayer
    let onEnd: () -> Void
    let onDiscard: () -> Void
    let onBack: () -> Void
    @Environment(WorkoutManager.self) private var workout
    @State private var paused = false

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    control(paused ? "play.fill" : "pause.fill", paused ? "Resume" : "Pause", W.color(0xFFC23D)) {
                        paused ? workout.resume() : workout.pause()
                        paused.toggle()
                    }
                    control("stop.fill", "End", W.color(0xFF3D5A), action: onEnd)
                }
                HStack(spacing: 6) {
                    control("backward.end.fill", "Back", W.card) { player.back(); onBack() }
                    control("forward.end.fill", "Skip", W.card) { _ = player.advance(); onBack() }
                }
                Button("Discard workout", role: .destructive, action: onDiscard).font(W.label(11))
            }
        }
    }

    private func control(_ symbol: String, _ title: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 18, weight: .bold))
                Text(title).font(W.label(10))
            }
            .foregroundStyle(color == W.card ? .white : W.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 14).fill(color))
        }
        .buttonStyle(.plain)
    }
}

/// After a set: one-tap effort, rest ring with haptic at 0, what's next.
struct RestOverlay: View {
    let end: Date?
    let total: Int
    let effort: Bool
    let next: String
    let tint: UInt32
    let onEffort: (Int) -> Void
    let onAdd: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if effort {
                    Text("How hard?").font(W.display(15))
                    EffortGrid(onEffort: onEffort)
                }
                if let end {
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        let left = max(0, end.timeIntervalSince(ctx.date))
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.15), lineWidth: 8)
                            Circle().trim(from: 0, to: left / Double(max(1, total)))
                                .stroke(W.lime, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Eyebrow(text: left > 0 ? "Rest" : "Go!")
                                Text(WatchPlayer.clock(left)).font(W.display(28)).monospacedDigit()
                            }
                        }
                        .frame(width: 110, height: 110)
                    }
                    HStack(spacing: 6) {
                        Button("+15 s", action: onAdd).font(W.label(12))
                        Button("Skip", action: onSkip).font(W.label(12)).tint(W.lime)
                    }
                } else {
                    Button("Continue", action: onSkip).font(W.label(12))
                }
                Text("Next: \(next)").font(.system(size: 10, weight: .semibold)).multilineTextAlignment(.center)
            }
        }
        .background(Color.black)
        .task(id: end) {
            guard let end else { return }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            if !Task.isCancelled { WKInterfaceDevice.current().play(.notification) }
        }
    }
}

private struct SummaryView: View {
    let player: WatchPlayer
    let kcal: Double
    let avgHR: Double?
    let saved: Bool
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Done", color: W.lime)
                Text("Session complete 🏆").font(W.display(18))
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        stat("\(Int((player.endedAt ?? Date()).timeIntervalSince(player.started)) / 60)′", "time")
                        stat("\(player.totalSets)", "sets")
                    }
                    GridRow {
                        stat("\(Int(kcal))", "kcal")
                        stat(avgHR.map { "♥ \(Int($0))" } ?? "--", "avg")
                    }
                }
                if saved { Label("Saved to Health", systemImage: "heart.fill").font(W.label(10)).foregroundStyle(.pink) }
                LimeButton(title: "DONE", action: onDone)
            }
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(W.display(17))
            Text(l).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        }
    }
}

/// Workout running on the iPhone: follow it and control it from the wrist.
struct MirrorView: View {
    let live: WLive
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: "On iPhone · \(live.sessionTitle)", color: W.color(live.tint))
                Text(live.exercise).font(W.display(18)).lineLimit(2).minimumScaleFactor(0.7)
                Text(live.detail.isEmpty ? live.setLabel : "\(live.setLabel) · \(live.detail)").font(W.label(12))
                if let end = live.restEnd, end > .now {
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        Text("Rest \(WatchPlayer.clock(max(0, end.timeIntervalSince(ctx.date))))").font(W.display(24)).foregroundStyle(W.lime)
                    }
                    HStack {
                        Button("+15 s") { store.send(WCommand.addRest) }
                        Button("Skip") { store.send(WCommand.skipRest) }.tint(W.lime)
                    }
                    .font(W.label(12))
                }
                if live.effortPending {
                    EffortGrid { store.send([WCommand.effort0, .effort1, .effort2, .effort3, .effort4][$0]) }
                } else if live.restEnd == nil || live.restEnd! <= .now {
                    LimeButton(title: live.action) { store.send(WCommand.main) }
                }
                Text("Next: \(live.next)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
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
        return Button { onEffort(e.rir) } label: {
            Text(e.title).font(W.label(13)).foregroundStyle(W.ink)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(RoundedRectangle(cornerRadius: 10).fill(e.color))
        }
        .buttonStyle(.plain)
    }
}
