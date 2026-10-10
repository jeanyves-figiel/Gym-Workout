import SwiftUI
import WorkoutEngine

/// Work time of a timed prescription: "4 min", "30 s", "45 s/side", "1 min hard / 1 min easy" (easy part = rest).
struct TimedSpec: Equatable {
    var workSec: Int
    var easySec: Int?

    init?(_ p: Prescription, unit: WorkoutEngine.Unit?) {
        let parts = p.reps.components(separatedBy: "/")
        // Exercises counted in seconds may give a bare number ("30").
        guard let work = Self.seconds(parts[0]) ?? (unit == .sec ? Int(parts[0].trimmingCharacters(in: .whitespaces)) : nil),
              work > 0 else { return nil }
        workSec = work
        easySec = parts.count > 1 ? Self.seconds(parts[1]) : nil
    }

    /// Leading "<n> s" or "<n> min"; nil for rep counts and ranges.
    static func seconds(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let m = t.firstMatch(of: #/^(\d+)\s*(s|sec|min)\b/#), let n = Int(m.1) else { return nil }
        return m.2 == "min" ? n * 60 : n
    }
}

/// Countdown of a timed set; `end` nil while paused or not started.
struct TimedRun: Equatable {
    var uid: String
    var total: Int
    var remaining: TimeInterval
    var end: Date?

    func left(at now: Date) -> TimeInterval { end.map { max(0, $0.timeIntervalSince(now)) } ?? remaining }
}

/// The exercise on screen: one card in the block's gradient with name, target, picture and muscles.
struct ExerciseHeroCard: View {
    let exercise: Exercise
    let block: Block
    let item: PlannedExercise
    let position: String
    let onForm: () -> Void

    var body: some View {
        let cat = block.kind.category
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(block.title.uppercased(), systemImage: cat.symbol).font(Theme.label(11)).tracking(1.2)
                Spacer()
                Text(position).font(Theme.label(12)).monospacedDigit()
            }
            .opacity(0.9)
            Text(exercise.name)
                .font(Theme.display(32))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.prescription.sets > 1 ? "\(item.prescription.sets)×\(item.prescription.reps)" : item.prescription.reps)
                    .font(Theme.display(44))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                VStack(alignment: .leading, spacing: 0) {
                    if let i = item.prescription.intensity { Text(i) }
                    if item.prescription.restSec > 0 { Text("rest \(Format.rest(item.prescription.restSec))") }
                }
                .font(Theme.label(11))
                .opacity(0.85)
            }
            ZStack(alignment: .bottomTrailing) {
                // Start position; tap plays the movement once (no looping frames).
                ExerciseMotionView(exercise: exercise)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Button(action: onForm) {
                    Label("Form", systemImage: "info.circle.fill")
                        .font(Theme.label(12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.black.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel("Setup and technique")
            }
            HeroMuscleChips(primary: exercise.primary, secondary: exercise.secondary)
            if let n = item.prescription.note { Text(n).font(.caption.weight(.semibold)).opacity(0.85) }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(cat.gradient))
        .shadow(color: cat.color.opacity(0.35), radius: 18, y: 8)
    }
}

/// Muscle chips readable on a gradient: primary dark with lime text, secondary translucent.
private struct HeroMuscleChips: View {
    let primary: [Muscle]
    let secondary: [Muscle]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(primary) { chip($0.name, primary: true) }
            ForEach(secondary.filter { !primary.contains($0) }.prefix(3)) { chip($0.name, primary: false) }
        }
    }

    private func chip(_ name: String, primary: Bool) -> some View {
        Text(name)
            .font(Theme.label(11))
            .foregroundStyle(primary ? Theme.lime : .white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(.black.opacity(primary ? 0.6 : 0.2)))
    }
}

/// Big countdown for timed work (rower, plank, intervals).
struct TimedRing: View {
    let run: TimedRun
    let color: [Color]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            let left = run.left(at: ctx.date)
            ZStack {
                ProgressRing(progress: left / Double(max(1, run.total)), lineWidth: 14, colors: color)
                VStack(spacing: 0) {
                    Text(run.end == nil && left < Double(run.total) ? "Paused" : "Remaining").eyebrow()
                    Text(Format.elapsed(left.rounded(.up))).font(Theme.display(44)).monospacedDigit()
                    Text("of \(Format.elapsed(Double(run.total)))").font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
        .frame(width: 170, height: 170)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
