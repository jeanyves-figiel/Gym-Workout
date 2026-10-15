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
    /// Set for weighted strength work: opens the PR attempt flow (#60).
    var onAttemptPR: (() -> Void)?
    /// Set while the gym's equipment can still be reported missing (before the first set).
    var onNotHere: (() -> Void)?
    /// Landscape player (#362): smaller type, the picture takes all the height left, no muscle chips or note.
    var compact = false
    let onForm: () -> Void

    /// Colour and label of the item: a cardio, mobility or stretch move inside a strength block (custom and example
    /// workouts keep everything in one block) shows as what it is, not as strength.
    static func category(_ exercise: Exercise, in block: Block) -> WorkoutEngine.Category {
        block.kind == .strength && [.cardio, .mobility, .stretch].contains(exercise.category) ? exercise.category : block.kind.category
    }

    private var label: String {
        let cat = Self.category(exercise, in: block)
        guard cat == block.kind.category, !block.title.isEmpty else {
            return cat == .warmup ? "Warm-up" : cat.rawValue.capitalized
        }
        return block.title
    }

    var body: some View {
        let cat = Self.category(exercise, in: block)
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack {
                Label(label.uppercased(), systemImage: cat.symbol).font(Theme.label(11)).tracking(1.2)
                Spacer()
                Text(position).font(Theme.label(12)).monospacedDigit()
            }
            .opacity(0.9)
            Text(exercise.name)
                .font(Theme.display(compact ? 22 : 30))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.prescription.sets > 1 ? "\(item.prescription.sets)×\(item.prescription.reps)" : item.prescription.reps)
                    .font(Theme.display(compact ? 26 : 40))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                VStack(alignment: .leading, spacing: 0) {
                    if let i = item.prescription.intensity { Text(i) }
                    if item.prescription.restSec > 0 { Text("rest \(Format.rest(item.prescription.restSec))") }
                }
                .font(Theme.label(11))
                .opacity(0.85)
                Spacer(minLength: 4)
                // Beside the target, so nothing sits over the picture's muscle map (top-left) or "Play movement" tag.
                if let onAttemptPR {
                    Button(action: onAttemptPR) {
                        Label("Attempt PR", systemImage: "trophy.fill")
                            .font(Theme.label(12))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                }
            }
            // Plays the movement a few times when the exercise shows, then rests on the start; tap replays. Its "Play movement" tag sits
            // bottom-left, Form bottom-right, Not here? top-right. The picture takes the height left on screen (#206: the player
            // never scrolls), so it shrinks on small phones while the target, set card and buttons stay whole.
            ExerciseMotionView(exercise: exercise)
                .frame(maxWidth: .infinity)
                .frame(minHeight: compact ? 40 : 56, maxHeight: compact ? .infinity : 180)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if let onNotHere {
                        Button(action: onNotHere) {
                            Label("Not here?", systemImage: "questionmark.circle")
                                .font(Theme.label(12))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(.black.opacity(0.55)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Not at this gym?")
                        .padding(8)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Button(action: onForm) {
                        Label("Form", systemImage: "info.circle.fill")
                            .font(Theme.label(12))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.black.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Setup and technique")
                    .padding(8)
                }
            if !compact {
                HeroMuscleChips(primary: exercise.primary, secondary: exercise.secondary)
                if let n = item.prescription.note { Text(n).font(.caption.weight(.semibold)).opacity(0.85).lineLimit(1) }
            }
        }
        .foregroundStyle(.white)
        .padding(compact ? 12 : 16)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(cat.gradient))
        .shadow(color: cat.color.opacity(0.35), radius: 18, y: 8)
    }
}

/// Muscle chips readable on a gradient: primary dark with lime text, secondary translucent.
private struct HeroMuscleChips: View {
    let primary: [Muscle]
    let secondary: [Muscle]

    var body: some View {
        // One line: what doesn't fit is dropped rather than wrapping and pushing the set card down.
        ViewThatFits(in: .horizontal) {
            row(secondaryCount: 3)
            row(secondaryCount: 1)
            row(secondaryCount: 0)
        }
    }

    private func row(secondaryCount: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(primary.prefix(3)) { chip($0.name, primary: true) }
            ForEach(secondary.filter { !primary.contains($0) }.prefix(secondaryCount)) { chip($0.name, primary: false) }
        }
    }

    private func chip(_ name: String, primary: Bool) -> some View {
        Text(name)
            .font(Theme.label(11))
            .lineLimit(1)
            .fixedSize()
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
    var size: CGFloat = 170

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            let left = run.left(at: ctx.date)
            ZStack {
                ProgressRing(progress: left / Double(max(1, run.total)), lineWidth: 14, colors: color)
                VStack(spacing: 0) {
                    Text(run.end != nil ? "Remaining" : left < Double(run.total) ? "Paused" : "Ready").eyebrow()
                    Text(Format.elapsed(left.rounded(.up))).font(Theme.display(size * 0.26)).monospacedDigit()
                    Text("of \(Format.elapsed(Double(run.total)))").font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
    }
}
