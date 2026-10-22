import LiftSensor
import SwiftUI
import WatchKit

// Swimming (#615 design A + B + C from `apple-tech-radar/t13.png`, #624 A from `x7.png`): today's swim from the
// iPhone's plan, pool / open water / snorkel, the swim player under Water Lock, and the summary.

/// Home row → swim: today's planned swim on top, then the free modes.
struct SwimSetupView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let swim = store.snapshot.swim ?? WSwim()
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: swim.plan ?? "Swim", color: W.lime)
                if let today = swim.today {
                    Button { start(.pool(swim.pool), today, swim) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("TODAY · \(today.totalMeters) M").font(W.label(10)).opacity(0.9)
                            Text(today.summary).font(W.label(14)).lineLimit(3).minimumScaleFactor(0.7)
                            Text("Sets with send-off buzz · \(today.minutes)′").font(W.label(9)).opacity(0.85)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(W.gradient(0x00A3C4, 0x3D59FF)))
                    }
                    .buttonStyle(.plain)
                } else if let next = swim.next, let day = swim.nextDay {
                    Text("Next swim \(day.formatted(.dateTime.weekday(.abbreviated))) · \(next.summary)").font(W.label(10)).opacity(0.8)
                }
                Button { start(.pool(swim.pool), nil, swim) } label: {
                    HomeRow(symbol: "figure.pool.swim", title: "Pool \(swim.pool) m", value: "›", tint: (0x00A3C4, 0x7DF9FF))
                }
                .buttonStyle(.plain)
                Button { start(.pool(swim.pool == 25 ? 50 : 25), nil, swim) } label: {
                    HomeRow(symbol: "figure.pool.swim", title: "Pool \(swim.pool == 25 ? 50 : 25) m", value: "›", tint: (0x3D59FF, 0x00C7FF))
                }
                .buttonStyle(.plain)
                Button { start(.openWater, nil, swim) } label: {
                    HomeRow(symbol: "water.waves", title: "Open water", value: "›", tint: (0x00B86B, 0x3DD9FF))
                }
                .buttonStyle(.plain)
                if SwimTracker.depthAvailable {
                    Button { start(.snorkel, nil, swim) } label: {
                        HomeRow(symbol: "water.waves.and.arrow.down", title: "Snorkel · depth", value: "›", tint: (0x7D4DFF, 0x3D59FF))
                    }
                    .buttonStyle(.plain)
                }
                Text("Water Lock turns on. Turn the Digital Crown to unlock and end.").font(W.label(9)).opacity(0.7)
            }
            .watchMargins()
        }
    }

    private func start(_ mode: SwimTracker.Mode, _ workout: SwimWorkout?, _ swim: WSwim) {
        Task { await SwimTracker.shared.start(mode, workout: workout, buddyMinutes: swim.buddyMinutes) }
    }
}

/// The swim player: one main page per mode, depth page on Ultra, controls last.
struct SwimRunView: View {
    @State private var tracker = SwimTracker.shared
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        TabView {
            TimelineView(.periodic(from: .now, by: dimmed ? 60 : 1)) { ctx in main(ctx.date) }
            if tracker.workout != nil, tracker.mode?.isPool == true {
                TimelineView(.periodic(from: .now, by: dimmed ? 60 : 1)) { ctx in poolPage(ctx.date) }
            }
            if SwimTracker.depthAvailable || tracker.maxDepth > 0 {
                TimelineView(.periodic(from: .now, by: dimmed ? 60 : 1)) { ctx in depthPage(ctx.date) }
            }
            controls
        }
        .tabViewStyle(.verticalPage)
    }

    @ViewBuilder private func main(_ now: Date) -> some View {
        switch tracker.mode ?? .pool(25) {
        case .openWater: openWaterPage(now)
        case .snorkel: depthPage(now)
        default:
            if tracker.workout != nil { setsPage(now) } else { poolPage(now) }
        }
    }

    /// A: laps, distance, pace per 100 m, stroke and SWOLF.
    private func poolPage(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(tracker.mode?.title ?? "POOL").foregroundStyle(W.lime)
                Text("💧 LOCK").foregroundStyle(W.color(0x7DF9FF))
            }
            .font(W.label(11))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(tracker.laps)").font(W.display(46)).monospacedDigit()
                Text("laps").font(W.label(13))
            }
            Text("\(Int(tracker.meters.rounded())) m · \(tracker.pace.map { WodTimer.clock($0) } ?? "–")/100 m").font(W.label(13))
            Text("\(tracker.stroke ?? "Swim") · SWOLF \(tracker.swolf.map(String.init) ?? "–")").font(W.label(13)).opacity(0.9)
            Spacer(minLength: 0)
            Text(SportTrackView.clock(tracker.elapsed(now))).font(W.label(11)).opacity(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .watchMargins()
    }

    /// X7 A: the set being swum, the rep, the send-off and the time to the next start.
    @ViewBuilder private func setsPage(_ now: Date) -> some View {
        if let w = tracker.workout {
            let c = w.clock(at: tracker.elapsed(now))
            let set = w.sets[c.set]
            VStack(alignment: .leading, spacing: 2) {
                Text(c.finished ? "DONE · \(w.totalMeters) M" : "SET \(c.set + 1) · \(set.title.uppercased())").font(W.label(11))
                    .foregroundStyle(W.lime).lineLimit(1).minimumScaleFactor(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(c.rep)").font(W.display(52)).monospacedDigit()
                    Text("/\(set.reps)").font(W.display(22)).opacity(0.85)
                }
                Text("send-off \(WodTimer.clock(set.sendOff)) · next in \(WodTimer.clock(c.nextIn))").font(W.label(12)).lineLimit(2)
                if c.set + 1 < w.sets.count, !dimmed {
                    Text("Then \(w.sets[c.set + 1].full)").font(W.label(10)).opacity(0.75).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                Text("\(tracker.laps) laps · \(Int(tracker.meters.rounded())) m").font(W.label(11)).opacity(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .watchMargins()
        }
    }

    /// T13 B: water temperature tile, distance, time.
    private func openWaterPage(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WATER \(tracker.waterTemp.map { String(format: "%.1f °C", $0) } ?? "– °C")").font(W.label(11)).foregroundStyle(W.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(W.gradient(0x00B86B, 0x3DD9FF)))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.2f", tracker.meters / 1000)).font(W.display(44)).monospacedDigit()
                Text("km").font(W.label(13))
            }
            Text("\(Int(tracker.elapsed(now) / 60))′ · \(tracker.heartRate.map { "♥ \(Int($0.rounded()))" } ?? "💧 LOCK")").font(W.label(13))
            Spacer(minLength: 0)
            Text("Your iPhone alerts if you're not back in time").font(W.label(9)).opacity(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .watchMargins()
    }

    /// T13 C: depth now, max depth and time under water.
    private func depthPage(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DEPTH").font(W.label(11)).foregroundStyle(W.color(0xFFC23D))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", tracker.depth ?? 0)).font(W.display(50)).monospacedDigit()
                Text("m").font(W.label(14))
            }
            Text(String(format: "max %.1f m · %@", tracker.maxDepth, SportTrackView.clock(tracker.under(now)))).font(W.label(13))
            if let t = tracker.waterTemp { Text(String(format: "%.1f °C", t)).font(W.label(11)).opacity(0.8) }
            Spacer(minLength: 0)
            Text("Shallow depth: up to 6 m").font(W.label(9)).opacity(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .watchMargins()
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Button { Task { await tracker.finish() } } label: { Label("End & save", systemImage: "checkmark").frame(maxWidth: .infinity) }
                .tint(W.lime)
            Button(role: .destructive) { tracker.discard() } label: { Label("Discard", systemImage: "xmark").frame(maxWidth: .infinity) }
            Button { WKInterfaceDevice.current().enableWaterLock() } label: { Label("Water Lock", systemImage: "drop.fill").frame(maxWidth: .infinity) }
        }
        .buttonStyle(.bordered)
        .watchMargins()
    }
}

struct SwimSummaryView: View {
    let summary: SwimTracker.Summary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "\(summary.workout ?? "Swim") · done", color: W.lime)
                Text(SportTrackView.clock(Double(summary.minutes) * 60)).font(W.display(30))
                if summary.meters > 0 { Text("\(summary.meters) m" + (summary.laps > 0 ? " · \(summary.laps) laps" : "")).font(W.label(14)) }
                if let p = summary.pace { Text("\(WodTimer.clock(p)) /100 m" + (summary.swolf.map { " · SWOLF \($0)" } ?? "")).font(W.label(13)) }
                if summary.maxDepth > 0 { Text(String(format: "Max depth %.1f m", summary.maxDepth)).font(W.label(13)) }
                if let t = summary.waterTemp { Text(String(format: "Water %.1f °C", t)).font(W.label(12)) }
                Text("Saved to Apple Health.").font(.footnote).opacity(0.8)
                LimeButton(title: "Done") { SwimTracker.shared.closeSummary() }
            }
            .watchMargins()
        }
    }
}
