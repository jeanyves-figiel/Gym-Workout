import LiftSensor
import SwiftUI
import WatchKit

// Hyrox race mode (#426, design A from `other-sports/hyrox-proposals.png`): pick a race or sim, 3-2-1, then one
// glowing screen per step that moves on by itself (or by double tap / Action button / the big button), and a
// confetti finish with the PB.

/// Colours of each part of the race.
enum HyroxLook {
    static let run: (UInt32, UInt32) = (0x3D59FF, 0x7DF9FF)
    static let station: (UInt32, UInt32) = (0xFF3D8B, 0xFF9A5E)
    static let roxzone: (UInt32, UInt32) = (0xFFB03D, 0xFFE07D)

    static func tint(_ step: HyroxStep?, between: Bool) -> (UInt32, UInt32) {
        if between { return roxzone }
        return step?.isRun == false ? station : run
    }

    static func symbol(_ s: HyroxStation) -> String {
        switch s {
        case .skiErg: "figure.skiing.crosscountry"
        case .sledPush: "arrow.right.to.line"
        case .sledPull: "arrow.left.to.line"
        case .burpeeBroadJumps: "figure.jumprope"
        case .rowing: "figure.rower"
        case .farmersCarry: "figure.strengthtraining.functional"
        case .sandbagLunges: "figure.step.training"
        case .wallBalls: "basketball.fill"
        }
    }
}

/// Watch home → Track a sport → Hyrox: the race or a training sim.
struct HyroxSetupView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var station: HyroxStation = .sledPush

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Hyrox · \(store.snapshot.hyrox?.division.label ?? "Open Men")", color: W.color(HyroxLook.station.1))
                option("Full race", detail: store.snapshot.hyrox?.goalSeconds.map { "Goal \(HyroxTime.clock($0))" } ?? "8 × 1 km + 8 stations",
                       tint: HyroxLook.station, format: .full)
                option("Sim · first half", detail: "4 runs · SkiErg → Burpees", tint: HyroxLook.run, format: .half(second: false))
                option("Sim · second half", detail: "4 runs · Rowing → Wall balls", tint: HyroxLook.run, format: .half(second: true))
                Eyebrow(text: "Compromised run", color: W.color(HyroxLook.roxzone.1))
                Picker("Station", selection: $station) {
                    ForEach(HyroxStation.allCases) { Text($0.name).tag($0) }
                }
                .frame(height: 48)
                option("4 × 1 km + \(station.name)", detail: "Run, station, repeat", tint: HyroxLook.roxzone,
                       format: .compromised(station, rounds: 4))
            }
            .watchMargins()
        }
    }

    private func option(_ title: String, detail: String, tint: (UInt32, UInt32), format: HyroxFormat) -> some View {
        Button {
            Task { await HyroxTracker.shared.start(format, settings: store.snapshot.hyrox) }
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(W.label(14)).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(W.label(10)).opacity(0.85).lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [W.color(tint.0), W.color(tint.1)],
                                                                                startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .buttonStyle(.plain)
    }
}

/// The race: countdown, then one screen per step. Wrist down redraws once a minute.
struct HyroxRaceView: View {
    @State private var tracker = HyroxTracker.shared
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        if let n = tracker.countdown {
            countdown(n)
        } else {
            TabView {
                TimelineView(.periodic(from: .now, by: dimmed ? 60 : 1)) { ctx in race(now: ctx.date) }
                controls
            }
            .tabViewStyle(.verticalPage)
        }
    }

    /// 3-2-1 ring.
    private func countdown(_ n: Int) -> some View {
        ZStack {
            Circle().stroke(W.lime.opacity(0.25), lineWidth: 10)
            Circle().trim(from: 0, to: CGFloat(n) / 3).stroke(W.lime, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.9), value: n)
            Text("\(n)").font(W.display(64)).foregroundStyle(W.lime).shadow(color: W.lime, radius: 12)
        }
        .padding(18)
        .background(Color.black.ignoresSafeArea())
    }

    @ViewBuilder private func race(now: Date) -> some View {
        let tint = HyroxLook.tint(tracker.current, between: tracker.between)
        let stepTime = now.timeIntervalSince(tracker.stepStart ?? now)
        let total = now.timeIntervalSince(tracker.started ?? now)
        VStack(alignment: .leading, spacing: 2) {
            Text(header(total: total)).font(W.label(11)).foregroundStyle(W.light(tint.1, 0.2)).lineLimit(1).minimumScaleFactor(0.7)
            if tracker.between {
                Text(HyroxTime.clock(stepTime)).font(W.display(44)).foregroundStyle(W.color(tint.1)).shadow(color: W.color(tint.0), radius: dimmed ? 0 : 10)
                Text("Roxzone · next \(tracker.current?.label ?? "")").font(W.label(11)).lineLimit(1).minimumScaleFactor(0.7)
            } else if let step = tracker.current, step.isRun {
                Text(pace(stepTime)).font(W.display(42)).foregroundStyle(W.color(tint.1)).shadow(color: W.color(tint.0), radius: dimmed ? 0 : 10)
                Text("/km · \(Int(tracker.runMeters)) m · \(HyroxTime.clock(stepTime))").font(W.label(11))
            } else if let s = tracker.current?.station {
                HStack(spacing: 4) {
                    Image(systemName: HyroxLook.symbol(s))
                    Text(s.name).lineLimit(1).minimumScaleFactor(0.6)
                }
                .font(W.label(12))
                Text(HyroxTime.clock(stepTime)).font(W.display(40)).foregroundStyle(.white).shadow(color: W.color(tint.0), radius: dimmed ? 0 : 10)
                Text(stationLine(s)).font(W.label(10)).opacity(0.9).lineLimit(1).minimumScaleFactor(0.7)
            }
            HStack {
                if let d = tracker.delta(now: now) {
                    Text("\(HyroxTime.delta(d)) vs plan").foregroundStyle(d <= 0 ? Color.green : Color(red: 1, green: 0.45, blue: 0.45))
                }
                Spacer()
                Text("♥ \(tracker.heartRate.map { "\(Int($0))" } ?? "–")")
            }
            .font(W.label(11))
            if !dimmed { nextButton }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .watchMargins()
        .background(RadialGradient(colors: [W.color(tint.0).opacity(dimmed ? 0.2 : 0.85), .black], center: .top, startRadius: 0, endRadius: 170)
            .ignoresSafeArea())
    }

    private func header(total: Double) -> String {
        let n = tracker.steps.count
        let label = tracker.current.map { $0.isRun ? "RUN \(runNumber($0))/\(n / 2)" : "STATION \(stationNumber)/\(n / 2)" } ?? ""
        return "\(label) · \(HyroxTime.clock(total))"
    }

    private func runNumber(_ step: HyroxStep) -> Int { if case let .run(k, _) = step { k } else { 0 } }
    private var stationNumber: Int { tracker.steps.prefix(tracker.index + 1).filter { !$0.isRun }.count }

    private func pace(_ seconds: Double) -> String {
        guard tracker.runMeters >= 50 else { return HyroxTime.clock(seconds) }
        return HyroxTime.clock(seconds / tracker.runMeters * 1000)
    }

    private func stationLine(_ s: HyroxStation) -> String {
        var parts = [s.work]
        if let load = tracker.division.load(s) { parts.append(load) }
        if s.counts, tracker.reps > 0 { parts.append("\(tracker.reps) \(s == .wallBalls ? "reps" : s == .burpeeBroadJumps ? "jumps" : "strokes")") }
        if let t = tracker.target { parts.append("target \(HyroxTime.clock(t))") }
        return parts.joined(separator: " · ")
    }

    /// Big button; double tap does the same.
    private var nextButton: some View {
        let title = tracker.asking ? "\(tracker.current?.label ?? "Next")? ✓" : tracker.between ? "START ›" : "DONE ›"
        return Button { tracker.advance() } label: {
            Text(title).font(W.label(13)).foregroundStyle(W.ink).frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.6)
        }
        .buttonStyle(.borderedProminent).tint(tracker.asking ? .yellow : W.lime).buttonBorderShape(.capsule)
        .handGestureShortcut(.primaryAction)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Text("Steps move on by themselves. Double tap or the Action button if one is missed.").font(W.label(10)).opacity(0.75)
            Button { Task { await tracker.finish() } } label: {
                Label("End race", systemImage: "flag.checkered").frame(maxWidth: .infinity)
            }
            .tint(W.lime)
            Button(role: .destructive) { tracker.discard() } label: {
                Label("Discard", systemImage: "xmark").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .watchMargins()
    }
}

/// The finish line: big time, PB burst, confetti, runs / stations / Roxzone.
struct HyroxFinishView: View {
    let race: HyroxRace
    let pb: Double?
    @State private var burst = false

    var body: some View {
        ZStack {
            Confetti(on: burst).allowsHitTesting(false)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "🏁 \(race.format.label) · \(race.division.label)", color: W.lime)
                    Text(HyroxTime.clock(race.total)).font(W.display(36)).foregroundStyle(W.lime).shadow(color: W.lime, radius: 12)
                        .scaleEffect(burst ? 1 : 0.6).animation(.spring(response: 0.5, dampingFraction: 0.5), value: burst)
                    if let pb {
                        Text(pb < 0 ? "PB \(HyroxTime.delta(pb)) 🎉" : "\(HyroxTime.delta(pb)) vs last").font(W.label(14))
                            .foregroundStyle(pb < 0 ? Color.green : .white)
                    }
                    Text("Runs \(HyroxTime.clock(race.runSeconds)) · Stations \(HyroxTime.clock(race.stationSeconds))").font(W.label(11))
                    Text("Roxzone \(HyroxTime.clock(race.roxzone))").font(W.label(11))
                    if let hr = race.avgHR { Text("♥ avg \(Int(hr)) · max \(Int(race.maxHR ?? hr))").font(W.label(11)) }
                    Text("Saved. Full report on your iPhone.").font(.footnote).opacity(0.8)
                    LimeButton(title: "Done") { HyroxTracker.shared.closeResult() }
                }
                .watchMargins()
            }
        }
        .onAppear {
            burst = true
            WKInterfaceDevice.current().play(.success)
        }
    }
}

/// Falling bits in the race colours.
private struct Confetti: View {
    let on: Bool
    private let bits: [(x: CGFloat, delay: Double, color: UInt32, size: CGFloat)] = (0..<26).map { i in
        let colors: [UInt32] = [0xD6FF3D, 0xFF3D8B, 0x7DF9FF, 0xFFB03D, 0xE040FB]
        return (CGFloat((i * 37) % 100) / 100, Double(i % 7) * 0.12, colors[i % colors.count], CGFloat(4 + i % 4))
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(bits.indices, id: \.self) { i in
                let b = bits[i]
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(W.color(b.color))
                    .frame(width: b.size, height: b.size * 1.6)
                    .rotationEffect(.degrees(on ? Double(i * 47) : 0))
                    .position(x: b.x * geo.size.width, y: on ? geo.size.height + 20 : -20)
                    .animation(.easeIn(duration: 1.8).delay(b.delay), value: on)
            }
        }
    }
}
