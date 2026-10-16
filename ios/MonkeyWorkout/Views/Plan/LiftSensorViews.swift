import LiftSensor
import SwiftUI
import WorkoutEngine

/// Set card header while the Watch measures the set (#383): reps counted, last rep's speed, speed loss;
/// in machine mode, where to strap the Watch.
struct WatchLiftPill: View {
    let lift: WLiftLive

    var body: some View {
        Group {
            if let hint = lift.strapHint {
                Label(hint, systemImage: "applewatch").lineLimit(1).minimumScaleFactor(0.7)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: lift.machine ? "gearshape.2.fill" : "applewatch")
                    Text(lift.reps == 0 ? "Sensing" : "\(lift.reps) reps")
                    if let v = lift.lastVelocity { Text(String(format: "%.2f m/s", v)).monospacedDigit() }
                    if lift.reps >= 2, lift.velocityLoss >= 0.05 { Text("−\(Int((lift.velocityLoss * 100).rounded())) %") }
                    if lift.ended { Image(systemName: "checkmark.circle.fill") }
                }
            }
        }
        .font(Theme.label(11))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(lift.velocityLoss >= 0.2 ? Color(hex: 0xFF9A3D) : Theme.lime))
        .accessibilityLabel(lift.strapHint ?? "Apple Watch: \(lift.reps) reps")
    }
}

/// Exercise page (#383): bar speed per rep of the last measured day, estimated 1RM from load and speed, power.
struct BarSpeedSection: View {
    let exercise: Exercise

    var body: some View {
        let day = LiftSets.shared.lastDay(exerciseId: exercise.id)
        if !day.isEmpty {
            GradientSection(symbol: "applewatch.radiowaves.left.and.right", title: "Bar speed",
                            gradient: LinearGradient(colors: [Color(hex: 0x7B2FF7), Color(hex: 0x00C6FF)], startPoint: .topLeading, endPoint: .bottomTrailing)) {
                HStack(spacing: 8) {
                    if let e = LiftSets.shared.estimatedOneRepMax(exercise: exercise) {
                        chip("e1RM \(LoadAdvisor.formatKg(e)) kg")
                    }
                    if let best = day.compactMap(\.best).max() { chip(String(format: "Best %.2f m/s", best)) }
                    if let p = day.compactMap(\.power).max() { chip("Power \(Int(p.rounded())) W") }
                }
                ForEach(day) { set in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Set \(set.setIndex + 1) · \(LoadAdvisor.formatKg(set.kg)) kg × \(set.reps)").font(Theme.label(13))
                            Spacer()
                            Text(set.mean.map { String(format: "%.2f m/s", $0) } ?? "").font(Theme.label(13)).monospacedDigit()
                        }
                        SpeedBars(velocities: set.velocities)
                        HStack(spacing: 10) {
                            if set.reps >= 2 { Text("−\(Int((set.velocityLoss * 100).rounded())) % speed") }
                            if let r = set.meanRange { Text(set.machine ? "Range \(Int((r * 100).rounded())) cm · machine" : "Range \(Int((r * 100).rounded())) cm") }
                            let ecc = set.eccentric.filter { $0 > 0 }
                            if !ecc.isEmpty { Text(String(format: "Down %.1f s", ecc.reduce(0, +) / Double(ecc.count))) }
                        }
                        .font(.caption.weight(.semibold))
                        .opacity(0.85)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.16)))
                }
                Text("Measured by your Apple Watch (beta). Speeds are best compared with your own sets.")
                    .font(.caption).opacity(0.8)
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(Theme.label(12)).padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(.black.opacity(0.25)))
    }
}

/// One bar per rep, heights relative to the fastest; yellow from 20 % slower.
struct SpeedBars: View {
    let velocities: [Double]

    var body: some View {
        let best = velocities.max() ?? 1
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(velocities.enumerated()), id: \.offset) { _, v in
                VStack(spacing: 2) {
                    Text(String(format: "%.2f", v).replacingOccurrences(of: "0.", with: ".")).font(.system(size: 9, weight: .heavy)).monospacedDigit()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(best > 0 && 1 - v / best >= 0.2 ? Color(hex: 0xFFE14D) : .white.opacity(0.92))
                        .frame(height: 46 * (best > 0 ? v / best : 0))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 62, alignment: .bottom)
    }
}
