import LiftSensor
import SwiftUI
import WatchKit

// WOD and combat timers (#622, design A + B + C from `apple-tech-radar/x5.png`): square kind tiles and the iPhone's
// saved timers, the running clock with round, bell and punches, and the remote for the iPhone's big screen.

/// Home row → timers: one square tile per kind, then the timers saved on the iPhone.
struct TimerPickerView: View {
    @Environment(WatchStore.self) private var store

    private let columns = [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Timers", color: W.lime)
                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach(WodTimer.presets) { t in tile(t, title: t.kind == .rounds ? "BOXING" : t.kind.label.uppercased()) }
                }
                let saved = store.snapshot.wods ?? []
                if !saved.isEmpty {
                    Eyebrow(text: "Saved on iPhone").padding(.top, 4)
                    LazyVGrid(columns: columns, spacing: 5) {
                        ForEach(saved) { t in tile(t, title: t.name.uppercased()) }
                    }
                } else {
                    Text("Build and save your own in the iPhone's Workout library › Timers.").font(W.label(9)).opacity(0.7)
                }
            }
            .watchMargins()
        }
    }

    private func tile(_ t: WodTimer, title: String) -> some View {
        Button { Task { await WodTracker.shared.start(t) } } label: {
            VStack(alignment: .leading, spacing: 1) {
                Spacer(minLength: 0)
                Text(title).font(W.label(12)).lineLimit(2).minimumScaleFactor(0.6)
                Text(t.summary).font(W.label(8)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .bottomLeading)
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(W.gradient(t.kind.tint.0, t.kind.tint.1)))
        }
        .buttonStyle(.plain)
    }
}

/// The running timer (B): round, big clock, punches, one pink pause button that double tap presses.
struct TimerRunView: View {
    @State private var tracker = WodTracker.shared
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        TabView {
            TimelineView(.periodic(from: .now, by: dimmed ? 1 : 0.25)) { ctx in clock(ctx.date) }
            controls
        }
        .tabViewStyle(.verticalPage)
    }

    @ViewBuilder private func clock(_ now: Date) -> some View {
        if let t = tracker.timer {
            let e = tracker.elapsed(now)
            let st = t.state(at: e)
            let phase = st.phase?.kind ?? .work
            let tint = phase == .rest ? (UInt32(0x3D59FF), UInt32(0x00C7FF)) : t.kind.tint
            VStack(alignment: .leading, spacing: 3) {
                Text(header(t, st)).font(W.label(11)).foregroundStyle(W.light(tint.1, 0.2)).lineLimit(1)
                Text(WodTimer.clock(t.display(at: e))).font(W.display(52)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(.white)
                if t.punches {
                    Text("🥊 \(tracker.impacts.roundPunches) punches" + (tracker.impacts.rate > 0 ? " · \(tracker.impacts.rate)/min" : ""))
                        .font(W.label(12)).lineLimit(1).minimumScaleFactor(0.7)
                } else if let move = t.moves.first, phase == .work {
                    Text(t.moves.count > 1 ? t.moves.joined(separator: " · ") : move).font(W.label(10)).lineLimit(2).opacity(0.9)
                } else if let hr = tracker.heartRate {
                    Text("♥ \(Int(hr.rounded()))").font(W.label(12))
                }
                Spacer(minLength: 0)
                action(t)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .watchMargins()
            .background(RadialGradient(colors: [W.color(tint.0).opacity(dimmed ? 0.25 : 0.75), .black], center: .top, startRadius: 0, endRadius: 170)
                .ignoresSafeArea())
        }
    }

    private func header(_ t: WodTimer, _ st: WodTimer.State) -> String {
        guard let p = st.phase else { return t.name.uppercased() }
        switch p.kind {
        case .prep: return "GET READY · \(t.name.uppercased())"
        case .rest: return "REST · NEXT ROUND \(p.round + 1) OF \(t.rounds)"
        case .work:
            switch t.kind {
            case .amrap: return "AMRAP · \(tracker.amrapRounds) ROUNDS"
            case .forTime: return "FOR TIME · CAP \(WodTimer.short(t.work))"
            default: return "ROUND \(p.round) OF \(t.rounds)"
            }
        }
    }

    /// AMRAP: +1 round; For time: Done; otherwise pause. Double tap presses it.
    @ViewBuilder private func action(_ t: WodTimer) -> some View {
        let title = tracker.paused ? "▶ resume" : t.kind == .amrap ? "+1 round" : t.kind == .forTime ? "✓ done" : "👌 pause"
        Button {
            if tracker.paused { tracker.togglePause() }
            else if t.kind == .amrap { tracker.addRound() }
            else if t.kind == .forTime { Task { await tracker.finish() } }
            else { tracker.togglePause() }
        } label: {
            Text(title).font(W.label(14)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 34)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(W.gradient(0xFF3D8B, 0xFF5F6D)))
        }
        .buttonStyle(.plain)
        .handGestureShortcut(.primaryAction)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Button { tracker.togglePause() } label: {
                Label(tracker.paused ? "Resume" : "Pause", systemImage: tracker.paused ? "play.fill" : "pause.fill").frame(maxWidth: .infinity)
            }
            .tint(.yellow)
            Button { Task { await tracker.finish() } } label: { Label("End & save", systemImage: "checkmark").frame(maxWidth: .infinity) }
                .tint(W.lime)
            Button(role: .destructive) { tracker.discard() } label: { Label("Discard", systemImage: "xmark").frame(maxWidth: .infinity) }
        }
        .buttonStyle(.bordered)
        .watchMargins()
    }
}

struct TimerSummaryView: View {
    let summary: WodTracker.Summary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "\(summary.name) · done", color: W.lime)
                Text(WodTimer.clock(summary.seconds)).font(W.display(30))
                if summary.kind == .amrap { Text("\(summary.rounds) rounds").font(W.label(14)) }
                else if summary.kind != .forTime { Text("\(summary.rounds) rounds done").font(W.label(14)) }
                if summary.punches > 0 {
                    Text("🥊 \(summary.punches) punches").font(W.label(14))
                    if !summary.roundPunches.isEmpty {
                        PunchBars(rounds: summary.roundPunches).frame(height: 34)
                    }
                }
                if summary.kcal > 0 { Text("\(summary.kcal) kcal").font(W.label(12)).opacity(0.85) }
                Text("Saved to Apple Health.").font(.footnote).opacity(0.8)
                LimeButton(title: "Done") { WodTracker.shared.closeSummary() }
            }
            .watchMargins()
        }
    }
}

/// Punches per round as yellow bars (`apple-tech-radar/t9.png` C).
struct PunchBars: View {
    let rounds: [Int]

    var body: some View {
        let top = max(1, rounds.max() ?? 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(rounds.enumerated()), id: \.offset) { _, n in
                RoundedRectangle(cornerRadius: 2).fill(W.color(0xFFC23D))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, 34 * CGFloat(n) / CGFloat(top)))
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

/// Big screen mode (C): the iPhone propped up runs the clock; double tap here starts and pauses it.
struct TimerRemoteView: View {
    let remote: WWodRemote
    @Environment(WatchStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Big screen · iPhone", color: W.lime)
            Text(remote.timer.name).font(W.display(22)).lineLimit(1).minimumScaleFactor(0.6)
            Text(remote.timer.summary).font(W.label(11)).opacity(0.85)
            Spacer(minLength: 0)
            Button { store.sendTimerToggle() } label: {
                Text(remote.running ? "👌 pause" : "👌 start").font(W.label(15)).foregroundStyle(W.ink)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(W.lime))
            }
            .buttonStyle(.plain)
            .handGestureShortcut(.primaryAction)
            Text("Double tap works too").font(W.label(9)).opacity(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .watchMargins()
        .background(W.gradient(remote.timer.kind.tint.0, remote.timer.kind.tint.1).opacity(0.5).ignoresSafeArea())
    }
}
