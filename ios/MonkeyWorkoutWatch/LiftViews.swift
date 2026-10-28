import LiftSensor
import SwiftUI
import WatchKit

// Lift sensor screens (#383), design A + B from `watch-gpath/proposals.png` (speed coach + hands-free logger)
// and machine mode A + B from `watch-gpath/machine-proposals.png` (strap prompt, placement, test rep).

/// During a set: big rep count (Crown corrects it), speed of the last rep with its zone, one dot per rep.
/// Turns red with "Rack it" when the velocity-loss limit is reached.
struct LiftPanel: View {
    let lift: LiftTracker
    let reps: Int
    let tint: UInt32
    /// Racked and waiting for the member's tap (Tap ✓ logging, #410).
    var waiting = false

    var body: some View {
        let stop = lift.lossReached
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(reps)").font(W.display(40)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(waiting ? "TAP ✓ TO LOG" : stop ? "RACK IT" : lift.machine ? "REPS · MACHINE" : "REPS · AUTO")
                    .font(W.label(8)).tracking(0.5).lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                if let v = lift.lastVelocity {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(String(format: "%.2f", v)).font(W.display(22)).monospacedDigit()
                        Text("m/s").font(W.label(8))
                    }
                    ZoneBar(position: SpeedZone.position(v))
                    Text(stop ? "−\(Int((lift.velocityLoss * 100).rounded())) %" : SpeedZone.of(v).title)
                        .font(W.label(8)).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .overlay(alignment: .bottomLeading) {
            RepBars(ranges: lift.reps.map(\.range), velocities: lift.reps.map(\.meanVelocity), limit: lift.lossLimit).padding(.leading, 8).padding(.bottom, -4)
        }
        .padding(.bottom, 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(stop ? W.gradient(0xFF2D2D, 0xFF9A00) : W.gradient(tint, 0x00C6FF)))
        .animation(.spring(duration: 0.3), value: reps)
    }
}

/// Where a speed sits between strength (blue) and speed (orange).
struct ZoneBar: View {
    let position: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(LinearGradient(colors: [W.color(0x3B82F6), W.color(0x22C55E), W.color(0xFACC15), W.color(0xF97316)],
                                          startPoint: .leading, endPoint: .trailing))
                .frame(width: 58, height: 5)
            Capsule().fill(.white).frame(width: 3, height: 10).offset(x: 55 * position)
        }
        .frame(width: 58, height: 10)
    }
}

/// Rep speed graph (#611 A, `apple-tech-radar/t9.png`): one bar per rep, its height the rep's speed against the
/// fastest, so fatigue shows as the bars shrink; a rep `limit` slower than the first turns red ("stop here").
/// A short yellow bar is probably not a full rep (#410): turn the Crown to fix the count; the Watch learns from it.
struct RepBars: View {
    let ranges: [Double]
    var velocities: [Double] = []
    var limit: Double?

    var body: some View {
        let sorted = ranges.sorted()
        let median = sorted.isEmpty ? 1 : max(0.01, sorted[sorted.count / 2])
        let top = max(0.01, velocities.max() ?? 0)
        let first = velocities.first ?? 0
        let shown = Array(ranges.indices.suffix(12))
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(shown, id: \.self) { i in
                let r = ranges[i]
                let v = i < velocities.count ? velocities[i] : nil
                let slow = v.map { limit != nil && first > 0 && $0 <= first * (1 - limit!) } ?? false
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(r < 0.6 * median ? W.color(0xFFE14D) : slow ? W.color(0xFF2D2D) : .white)
                    .frame(width: 4, height: v.map { max(2, 10 * $0 / top) } ?? max(2, min(10, 8 * r / median)))
            }
        }
        .frame(height: 10, alignment: .bottom)
    }
}

/// Small chip while the Watch listens for the first rep.
struct SensingChip: View {
    let machine: Bool

    var body: some View {
        Label(machine ? "On machine" : "Sensing", systemImage: machine ? "gearshape.2.fill" : "waveform.path")
            .font(W.label(9)).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(.white.opacity(0.18)))
            .symbolEffect(.pulse, options: .repeating)
    }
}

/// The bar is racked: the set logs itself when the ring runs out ("8 reps · in 5 s"). Undo = the set goes on.
struct AutoLogBanner: View {
    let title: String
    let end: Date
    var total = WatchLiftLogging.countdown
    let onUndo: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            let left = max(0, end.timeIntervalSince(ctx.date))
            // At 0 the set is logged: say so and drop Undo instead of "Logs in 0 s" (#824).
            let logged = left <= 0
            HStack(spacing: 6) {
                ZStack {
                    Circle().stroke(W.ink.opacity(0.2), lineWidth: 3)
                    Circle().trim(from: 0, to: logged ? 1 : left / total).stroke(W.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .black))
                }
                .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(logged ? "Logged" : "Logs in \(Int(left.rounded(.up))) s").font(W.label(12)).monospacedDigit()
                    Text(title).font(W.label(9)).opacity(0.8)
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                if !logged {
                    Button(action: onUndo) {
                        Text("Undo").font(W.label(11)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Capsule().fill(W.ink.opacity(0.85)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .foregroundStyle(W.ink)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Capsule().fill(W.lime))
    }
}

/// Machine mode A + B: strap the Watch on the moving part, then one slow test rep.
struct StrapPrompt: View {
    let exercise: String
    let spot: MachineSpot
    let onReady: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: exercise, color: .white.opacity(0.9))
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: spot.symbol).font(.system(size: 20, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.25)))
                    Text("Strap me on \(spot.place)").font(W.display(17)).lineLimit(3).minimumScaleFactor(0.7)
                }
                Text("Band loop, screen up, tight. Leave me still a second, then push slowly once and let it come back.")
                    .font(.system(size: 11, weight: .semibold)).opacity(0.9)
                LimeButton(title: "READY") { onReady() }
                Button("Log by hand", action: onSkip).font(W.label(11)).buttonStyle(.plain).frame(maxWidth: .infinity)
            }
            .foregroundStyle(.white)
            .watchMargins()
        }
        .background(W.gradient(0xFF3D6E, 0xFF8A00).ignoresSafeArea())
    }
}

/// Machine mode: learning the axis from the test rep.
struct TestRepView: View {
    let calibrated: Bool
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Eyebrow(text: calibrated ? "Ready" : "Test rep", color: .white.opacity(0.9))
            if calibrated {
                Image(systemName: "checkmark").font(.system(size: 34, weight: .black))
                Text("Got it. Go!").font(W.display(18))
            } else {
                Text("Push slowly once").font(W.display(19)).multilineTextAlignment(.center)
                Text("Hold still first, then push and let it come back.").font(.system(size: 11, weight: .semibold))
                    .multilineTextAlignment(.center).opacity(0.9)
                Button("Log by hand", action: onSkip).font(W.label(11)).buttonStyle(.plain).padding(.top, 4)
            }
        }
        .foregroundStyle(calibrated ? W.ink : .white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((calibrated ? W.gradient(0x00B46E, 0x9CFF3D) : W.gradient(0x7B2FF7, 0x00C6FF)).ignoresSafeArea())
    }
}

/// After a Crown correction (#410): "Counted 5, you said 4 · stricter next time".
func correctionLine(_ set: WLiftSet) -> String? {
    guard let logged = set.logged, logged != set.reps else { return nil }
    return "Counted \(set.reps), you said \(logged) · \(set.reps > logged ? "stricter" : "looser") next time"
}

/// Practice mode (#410): the iPhone's Try it screen counts here; the graph and the level are on the iPhone.
struct PracticeView: View {
    let level: Double
    /// CI screenshots: reps shown without sensors.
    var demo: [Double]? = nil
    @Environment(WatchStore.self) private var store
    @State private var lift = LiftTracker()

    var body: some View {
        VStack(spacing: 4) {
            Eyebrow(text: "Practice", color: .white.opacity(0.9))
            Text("\(lift.count)").font(W.display(48)).monospacedDigit().contentTransition(.numericText())
            RepBars(ranges: lift.reps.map(\.range), velocities: lift.reps.map(\.meanVelocity))
            // "Watch the iPhone" read oddly on a Watch (#824).
            Text((lift.lastVelocity.map { String(format: "%.2f m/s · ", $0) } ?? "") + "Graph on iPhone")
                .font(.system(size: 11, weight: .semibold)).opacity(0.9).lineLimit(1).minimumScaleFactor(0.7)
            Button("Done") { store.practice = nil }.font(W.label(12)).buttonStyle(.plain).padding(.top, 4)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(W.gradient(0xFF3D6E, 0xFF8A00).ignoresSafeArea())
        .animation(.spring(duration: 0.3), value: lift.count)
        .onAppear {
            #if DEBUG
            if let demo {
                lift.demo(demo)
                return
            }
            #endif
            if LiftTracker.available { lift.practice(level: level) }
        }
        .onChange(of: level) { _, l in lift.recount(level: l) }
        .task {
            // A few times a second: trace and reps to the iPhone.
            while !Task.isCancelled {
                if let state = lift.practiceState() { store.send(state) }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        .onDisappear { lift.stop() }
    }
}

/// Short line for a measured set, shown during the rest: "8 reps · best 0.71 m/s · −21 %".
func liftLine(_ set: WLiftSet) -> String {
    var parts = ["\(set.reps) reps"]
    if let b = set.best { parts.append(String(format: "best %.2f m/s", b)) }
    if set.reps >= 2 { parts.append("−\(Int((set.velocityLoss * 100).rounded())) %") }
    return parts.joined(separator: " · ")
}

/// Builds the record of a measured set.
func makeLiftSet(_ reps: [LiftRep], sessionId: String, exerciseId: String, setIndex: Int, kg: Double, machine: Bool) -> WLiftSet? {
    guard !reps.isEmpty else { return nil }
    return WLiftSet(sessionId: sessionId, exerciseId: exerciseId, setIndex: setIndex, date: Date(), kg: kg,
                    velocities: reps.map(\.meanVelocity), peaks: reps.map(\.peakVelocity), ranges: reps.map(\.range),
                    concentric: reps.map(\.concentricSec), eccentric: reps.map { $0.eccentricSec ?? 0 }, machine: machine)
}
