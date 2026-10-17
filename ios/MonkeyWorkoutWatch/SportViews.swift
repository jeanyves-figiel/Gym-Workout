import SwiftUI
import WatchKit

// Sport tracking (#418, design B + C from `other-sports/watch-proposals.png`): pick a sport and a battery mode,
// one dashboard per sport, summary with battery used.

/// Home row → sports list.
struct SportPickerView: View {
    @State private var picked: TrackedSport?

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Eyebrow(text: "Track a sport", color: W.lime)
                ForEach(TrackedSport.allCases) { s in
                    Button { picked = s } label: {
                        HomeRow(symbol: s.symbol, title: s.label, value: "›", tint: s.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .watchMargins()
        }
        .sheet(item: $picked) { SportPowerView(sport: $0) }
    }
}

/// Battery mode before the start (design C): Full or Saver, with how long each lasts.
struct SportPowerView: View {
    let sport: TrackedSport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: sport.label, color: W.color(sport.tint.1))
                if sport.usesGPS {
                    ForEach(TrackPower.allCases) { p in
                        Button { start(p) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(p.label, systemImage: p == .full ? "bolt.fill" : "battery.75percent").font(W.label(14))
                                Text(p.detail).font(W.label(10)).opacity(0.8)
                            }
                            .foregroundStyle(p == .full ? W.ink : .white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 14).fill(p == .full ? AnyShapeStyle(W.lime) : AnyShapeStyle(W.card)))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    LimeButton(title: "Start") { start(.full) }
                }
            }
            .watchMargins()
        }
    }

    private func start(_ p: TrackPower) {
        Task { await SportTracker.shared.start(sport, power: p) }
        dismiss()
    }
}

/// The running session: one screen per sport (design B), controls on the next page.
struct SportTrackView: View {
    @State private var tracker = SportTracker.shared
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        TabView {
            // Always on (#418 battery): wrist down redraws once a minute, no animation.
            TimelineView(.periodic(from: .now, by: dimmed ? 60 : 1)) { ctx in
                dashboard(now: ctx.date)
            }
            controls
        }
        .tabViewStyle(.verticalPage)
    }

    @ViewBuilder private func dashboard(now: Date) -> some View {
        if let sport = tracker.sport {
            let elapsed = Self.clock(now.timeIntervalSince(tracker.started ?? now))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(header(sport)) · \(elapsed)").font(W.label(11)).foregroundStyle(W.lime).lineLimit(1)
                if sport == .hyrox {
                    hyrox(now: now)
                } else if sport.downhill {
                    big("\(Int(tracker.speed.rounded()))", "km/h · top \(Int(tracker.topSpeed.rounded()))", sport)
                    pair(("VERT", "\(Int(tracker.down.rounded()))"), ("HR", hr))
                } else if [TrackedSport.hike, .mountaineering, .trailRun].contains(sport) {
                    big("+\(Int(tracker.up.rounded()))", "m up · \(km) km", sport)
                    pair(("SUMMIT", tracker.highest.map { "\(Int($0.rounded()))" } ?? "–"), ("HR", hr))
                } else if sport.usesGPS {
                    big(km, "km · \(Int(tracker.speed.rounded())) km/h", sport)
                    pair(("UP", "\(Int(tracker.up.rounded()))"), ("HR", hr))
                } else {
                    big(hr, "bpm", sport)
                    pair(("KCAL", "\(Int(tracker.kcal.rounded()))"), ("TIME", elapsed))
                }
                if sport.laps && sport != .hyrox && !dimmed {
                    Button { tracker.markLap() } label: { Text("LAP \(tracker.lap + 1) ›").font(W.label(12)).foregroundStyle(W.ink).frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(W.lime).buttonBorderShape(.capsule)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .watchMargins()
            .background(RadialGradient(colors: [W.color(sport.tint.0).opacity(dimmed ? 0.25 : 0.8), .black], center: .top, startRadius: 0, endRadius: 160)
                .ignoresSafeArea())
        }
    }

    private func header(_ sport: TrackedSport) -> String {
        if sport.downhill { return "RUN \(tracker.runs + 1)" }
        return sport.label.uppercased()
    }

    private var km: String { String(format: tracker.meters >= 10_000 ? "%.0f" : "%.1f", tracker.meters / 1000) }
    private var hr: String { tracker.heartRate.map { "\(Int($0.rounded()))" } ?? "–" }

    private func big(_ value: String, _ unit: String, _ sport: TrackedSport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(W.display(44)).foregroundStyle(W.light(sport.tint.1, 0.3)).minimumScaleFactor(0.5).lineLimit(1)
            Text(unit).font(W.label(11)).opacity(0.85)
        }
    }

    private func pair(_ a: (String, String), _ b: (String, String)) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) { Text(a.0).font(W.label(9)).opacity(0.75); Text(a.1).font(W.label(15)) }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) { Text(b.0).font(W.label(9)).opacity(0.75); Text(b.1).font(W.label(15)) }
        }
    }

    /// Hyrox: the current run or station, its time, the last split, and a big LAP button.
    private func hyrox(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(tracker.lap / 2 + 1) · \(tracker.hyroxStep)").font(W.label(13)).lineLimit(1).minimumScaleFactor(0.7)
            Text(Self.clock(now.timeIntervalSince(tracker.lapStart ?? now))).font(W.display(36)).monospacedDigit()
            if let last = tracker.lastLapMinutes {
                Text("last \(Self.clock(last * 60)) · ♥ \(hr)").font(W.label(10)).opacity(0.8)
            }
            if !dimmed {
                Button { tracker.markLap() } label: { Text("LAP ›").font(W.label(14)).foregroundStyle(W.ink).frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(W.lime).buttonBorderShape(.capsule)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Button { tracker.paused ? tracker.resume() : tracker.pause() } label: {
                Label(tracker.paused ? "Resume" : "Pause", systemImage: tracker.paused ? "play.fill" : "pause.fill").frame(maxWidth: .infinity)
            }
            .tint(.yellow)
            Button { Task { await tracker.finish() } } label: {
                Label("End & save", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .tint(W.lime)
            Text(tracker.power == .saver ? "Saver · GPS once a minute" : "Full GPS").font(W.label(10)).opacity(0.7)
        }
        .buttonStyle(.bordered)
        .watchMargins()
    }

    static func clock(_ s: TimeInterval) -> String {
        let t = Int(max(0, s))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// After End: the main numbers and the battery it used (design C). Rated and shown in full on the iPhone.
struct SportSummaryView: View {
    let summary: SportTracker.Summary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "\(summary.sport.label) · done", color: W.lime)
                Text(SportTrackView.clock(Double(summary.minutes) * 60)).font(W.display(30))
                if summary.km > 0 { Text(String(format: "%.1f km", summary.km)).font(W.label(14)) }
                if summary.vertical > 0 { Text("\(Int(summary.vertical.rounded())) m \(summary.sport.downhill ? "down" : "up")").font(W.label(14)) }
                if summary.sport.downhill { Text("\(summary.runs) runs · top \(Int(summary.topKmh.rounded())) km/h").font(W.label(13)) }
                if let b = summary.batteryUsed { Text("Battery used \(b) %").font(W.label(11)).opacity(0.75) }
                Text("Saved to Apple Health. Rate it on your iPhone.").font(.footnote).opacity(0.8)
                LimeButton(title: "Done") { SportTracker.shared.closeSummary() }
            }
            .watchMargins()
        }
    }
}
