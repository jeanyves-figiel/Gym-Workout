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
        .onChange(of: player.index) { syncCrown() }
        .onAppear { syncCrown() }
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
                if step.loggable, let row = player.currentRow, player.done < step.sets {
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
                LimeButton(title: player.mainLabel) { main() }
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
                            tint: block?.tint ?? 0xCCFF3D, tint2: block?.tint2 ?? 0x7B3DFF) { rir in
                    send(player.effort(rir))
                } onAdd: {
                    player.addRest()
                } onSkip: {
                    send(player.skipRest())
                }
            }
        }
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
    @State private var paused = false
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
                        tile(paused ? "play.fill" : "pause.fill", paused ? "Resume" : "Pause", 0xFFC23D, 0xFF7A3D, height: 62) {
                            paused ? workout.resume() : workout.pause()
                            paused.toggle()
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
