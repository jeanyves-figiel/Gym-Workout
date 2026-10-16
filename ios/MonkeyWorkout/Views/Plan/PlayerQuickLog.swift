import SwiftUI
import UIKit
import WorkoutEngine

/// One-tap effort as reps in reserve: Fail / 1 / 2 / 3 / 4+ left.
enum Effort: Int, CaseIterable, Identifiable {
    case fail = 0, one, two, three, easy

    var id: Int { rawValue }
    var rir: Int { rawValue }
    var title: String { self == .easy ? "4+" : "\(rawValue)" }
    var caption: String {
        switch self {
        case .fail: "FAIL"
        case .easy: "EASY"
        default: "\(rawValue) LEFT"
        }
    }

    var color: Color {
        switch self {
        case .fail: rgb(0xFF3D5A)
        case .one: rgb(0xFF7A3D)
        case .two: rgb(0xFFC23D)
        case .three: Theme.lime
        case .easy: rgb(0x3DFFB0)
        }
    }

    init(rir: Int) { self = Effort(rawValue: min(4, max(0, rir))) ?? .two }
}

/// "How hard?" row of five big buttons; tapping logs RIR for the set just done.
struct EffortPicker: View {
    let selected: Effort?
    /// Set already logged without a rating (#357): rating is a bonus, the rest closes by itself either way.
    var optional = false
    /// Landscape player (#362): tiles only, no title or caption.
    var compact = false
    let onPick: (Effort) -> Void

    var body: some View {
        VStack(spacing: 8) {
            if !compact {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("How hard?").font(Theme.display(26))
                    if optional { Text("optional").font(Theme.label(11)).foregroundStyle(Theme.muted) }
                }
            }
            HStack(spacing: 6) {
                ForEach(Effort.allCases) { e in
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onPick(e)
                    } label: {
                        VStack(spacing: 1) {
                            Text(e.title).font(Theme.display(compact ? 22 : 26))
                            Text(e.caption).font(Theme.label(compact ? 7 : 9)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 8 : 12)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(e.color))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white, lineWidth: selected == e ? 3 : 0))
                        .scaleEffect(selected == e ? 1.06 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(e == .fail ? "Failure, no reps left" : e == .easy ? "Easy, 4 or more reps left" : "\(e.rir) reps left")
                }
            }
            if !compact { Text("Reps left in the tank").font(.caption).foregroundStyle(Theme.muted) }
        }
        .animation(.spring(duration: 0.25), value: selected)
    }
}

/// Effort tiles in place of SET DONE (#357): one tap logs the coming set with its effort. "Done" without a rating
/// stays one tap too (the rest screen then offers the optional picker).
struct EffortDoneStrip<Leading: View, Trailing: View>: View {
    let setNumber: Int
    let onDone: (Effort?) -> Void
    /// The player's previous / skip buttons beside the tiles.
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Set \(setNumber) done · how hard?").font(Theme.label(11)).tracking(1).textCase(.uppercase)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button { onDone(nil) } label: {
                    Label("Done, no rating", systemImage: "checkmark").font(Theme.label(11))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.cardStrong))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set \(setNumber) done without effort rating")
            }
            HStack(spacing: 4) {
                leading().padding(.trailing, 4)
                ForEach(Effort.allCases) { e in
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onDone(e)
                    } label: {
                        VStack(spacing: 0) {
                            Text(e.title).font(Theme.display(22))
                            Text(e.caption).font(Theme.label(8)).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(e.color))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Set \(setNumber) done, " + (e == .fail ? "failure" : e == .easy ? "easy, 4 or more reps left" : "\(e.rir) reps left"))
                }
                trailing().padding(.leading, 4)
            }
        }
        .foregroundStyle(.white)
    }
}

/// How the player moves on after an exercise's last set (#357), Settings → Workout flow. Seconds of the "Next in"
/// countdown; 0 moves straight on, -1 waits for NEXT.
enum AutoNextPref {
    static let key = "player.autoNextSec"
    static let fallback = 5
    static let choices = [0, 3, 5, 10, -1]

    static func title(_ sec: Int) -> String {
        switch sec {
        case 0: "Straight on"
        case -1: "Wait for me"
        default: "Countdown \(sec) s"
        }
    }
}

/// "Next in 5" bar after an exercise's last set (#357), in the Undo bar's look (#288): tap to go now, tap the ring to stay.
struct AutoNextBar: View {
    let title: String
    let detail: String
    let end: Date
    let total: Int
    let finishing: Bool
    let onGo: () -> Void
    let onHold: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            let left = max(0, end.timeIntervalSince(ctx.date))
            HStack(spacing: 12) {
                Button(action: onGo) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finishing ? "Last one done" : "Next: \(title)").font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.7)
                        Text((detail.isEmpty ? "" : detail + " · ") + (finishing ? "finishing" : "moving") + " in \(Int(left.rounded(.up)))")
                            .font(Theme.label(11)).opacity(0.9).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(finishing ? "Finish now" : "Go to \(title) now")
                Button(action: onHold) {
                    ZStack {
                        Circle().stroke(.black.opacity(0.3), lineWidth: 4)
                        Circle().trim(from: 0, to: left / Double(max(1, total)))
                            .stroke(Theme.lime, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "pause.fill").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.lime)
                    }
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.black))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stay on this exercise")
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.48, blue: 0.27), Color(red: 0.91, green: 0.27, blue: 0.37),
                                              Color(red: 0.76, green: 0.29, blue: 0.85)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
            .shadow(color: Color(red: 0.91, green: 0.27, blue: 0.37).opacity(0.45), radius: 12, y: 6)
        }
    }
}

/// The one place to enter a set during a workout (#206): kg and reps steppers for the coming set, prefilled from
/// the load suggestion, no keyboard. Effort (RIR) is one tap after the set. Done sets show as chips; tapping one
/// opens it here for a correction.
struct CurrentSetCard: View {
    @Bindable var state: SetLogState
    /// Sets completed in the player.
    let done: Int
    let color: Color
    /// Done set being corrected; nil = the coming set.
    @Binding var editing: Int?
    /// Reps and bar speed the Watch measures for this set (#383).
    var watchLift: WLiftLive? = nil
    /// Coach (#379): the coming set is the exercise's last; the badge takes the source chip's place.
    var finalSet = false
    let onSave: (Int) -> Void

    var body: some View {
        let n = state.rows.count
        let i = editing ?? min(done, max(0, n - 1))
        let allDone = editing == nil && done >= n
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(editing != nil ? "Edit set \(i + 1)" : allDone ? "All \(n) sets done" : "Set \(i + 1) of \(n)")
                    .font(Theme.label(13)).tracking(1.2).textCase(.uppercase)
                Spacer()
                if editing != nil {
                    Button {
                        onSave(i)
                        editing = nil
                    } label: {
                        Text("Save").font(Theme.label(13)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(Theme.lime))
                    }
                    .buttonStyle(.plain)
                } else if let w = watchLift, !allDone {
                    WatchLiftPill(lift: w)
                } else if finalSet, !allDone {
                    Text("🔥 Final set").font(Theme.label(11)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.lime))
                        .accessibilityIdentifier("player.finalSet")
                } else if let s = state.suggestion, !allDone {
                    // Where the prefill comes from; values stay editable with the steppers.
                    Label(s.source == .history ? "From last time" : "Estimate",
                          systemImage: s.source == .history ? "clock.arrow.circlepath" : "wand.and.stars")
                        .font(Theme.label(11))
                        .foregroundStyle(s.source == .history ? Theme.lime : .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }
            }
            if editing == nil, done == 0, let s = state.suggestion, state.rows.first?.logged == false {
                Text(s.reason).font(.caption).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            if !allDone {
                HStack(spacing: 10) {
                    stepper(value: state.rows.indices.contains(i) ? state.rows[i].kg : "", unit: "kg",
                            minus: { state.stepKg(i, by: -1) }, plus: { state.stepKg(i, by: 1) })
                    stepper(value: state.rows.indices.contains(i) ? state.rows[i].reps : "", unit: "reps",
                            minus: { state.stepReps(i, by: -1) }, plus: { state.stepReps(i, by: 1) })
                }
            }
            if n > 1 || done > 0 {
                SetChips(count: n, done: done, current: i, color: color) { j in
                    guard state.rows.indices.contains(j) else { return nil }
                    guard let v = state.values(j), j < done || state.rows[j].logged else { return nil }
                    return "\(LoadAdvisor.formatKg(v.kg))×\(v.reps)"
                } onTap: { j in
                    editing = editing == j ? nil : j
                }
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(editing != nil ? Theme.lime : Theme.stroke))
    }

    private func stepper(value: String, unit: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            stepButton("minus", label: "Less \(unit)", action: minus)
            VStack(spacing: 0) {
                // #373: the value shrinks rather than turning into "…", and the unit never wraps ("re ps").
                Text(value.isEmpty ? "–" : value).font(Theme.display(28)).monospacedDigit().minimumScaleFactor(0.4).lineLimit(1)
                Text(unit).font(Theme.label(10)).opacity(0.8).lineLimit(1).fixedSize()
            }
            .frame(minWidth: 52, maxWidth: .infinity)
            stepButton("plus", label: "More \(unit)", action: plus)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardStrong))
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .heavy))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// One chip per set: done sets filled (with what was logged), the current one outlined, the rest dim.
struct SetChips: View {
    let count: Int
    let done: Int
    var current: Int?
    let color: Color
    /// Text inside a chip; nil shows the set number.
    var detail: (Int) -> String? = { _ in nil }
    /// Tap on a done set; nil leaves chips inert.
    var onTap: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                let isDone = i < done
                let text = detail(i) ?? (isDone ? "✓" : "\(i + 1)")
                Text(text)
                    .font(Theme.label(12))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(isDone ? .white : Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(Capsule().fill(isDone ? AnyShapeStyle(color) : AnyShapeStyle(Color.white.opacity(0.08))))
                    .overlay(Capsule().strokeBorder(Theme.lime, lineWidth: i == current && (i >= done || onTap != nil) ? 2 : 0))
                    .contentShape(Capsule())
                    .onTapGesture { if isDone { onTap?(i) } }
                    .accessibilityLabel(isDone ? "Set \(i + 1) done \(detail(i) ?? "")" : "Set \(i + 1)")
                    .accessibilityAddTraits(isDone && onTap != nil ? .isButton : [])
            }
        }
        .animation(.spring(duration: 0.3), value: done)
    }
}

/// Timed work (cardio machine, plank, intervals): the countdown is the only input; the lime button starts and pauses it.
struct TimedSetCard: View {
    let run: TimedRun
    let sets: Int
    let done: Int
    let easySec: Int?
    let colors: [Color]

    var body: some View {
        HStack(spacing: 16) {
            TimedRing(run: run, color: [colors[1], colors[0]], size: 132)
            VStack(alignment: .leading, spacing: 8) {
                Text(sets > 1 ? (done >= sets ? "All \(sets) done" : "Round \(min(done, sets - 1) + 1) of \(sets)") : "Timed")
                    .font(Theme.label(13)).tracking(1.2).textCase(.uppercase)
                Text("Work \(Format.elapsed(Double(run.total)))" + (easySec.map { " · easy \(Format.elapsed(Double($0)))" } ?? ""))
                    .font(Theme.label(13)).foregroundStyle(Theme.muted)
                Text("Nothing to log. Tap Start and go.").font(.caption).foregroundStyle(Theme.muted)
                if sets > 1 { SetChips(count: sets, done: done, current: done, color: colors[0]) }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke))
    }
}

/// Sets of unloaded work (body weight, mobility): which set is on, nothing to type.
struct PlainSetCard: View {
    let sets: Int
    let done: Int
    let target: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(done >= sets ? "All \(sets) sets done" : "Set \(done + 1) of \(sets)")
                    .font(Theme.label(13)).tracking(1.2).textCase(.uppercase)
                Spacer()
                Text(target).font(Theme.label(13)).foregroundStyle(Theme.muted)
            }
            SetChips(count: sets, done: done, current: done, color: color)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke))
    }
}

/// What comes after the current set: the next set of this exercise or the next exercise, on its category gradient.
struct UpNextCard: View {
    let title: String
    let eyebrow: String
    let detail: String
    let exercise: Exercise?
    let colors: [Color]
    var symbol: String = "arrow.right"
    /// One-line version pinned in the player (#206): smaller picture, detail beside the title.
    var compact = false

    var body: some View {
        let size: CGFloat = compact ? 34 : 48
        HStack(spacing: compact ? 10 : 12) {
            // The exercise's own art (#170) reads at 48 pt; without media, the category icon tile as on Explore.
            if let exercise, ExerciseImage.hasMedia(exercise) {
                ExerciseThumbnail(exercise: exercise, size: size)
            } else {
                Image(systemName: exercise?.category.symbol ?? symbol)
                    .font(.system(size: compact ? 15 : 20, weight: .heavy))
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.2)))
            }
            VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                Text(eyebrow).font(Theme.label(10)).tracking(1.2).textCase(.uppercase).opacity(0.85).lineLimit(1)
                if compact {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(title).font(Theme.display(15)).lineLimit(1).minimumScaleFactor(0.7)
                        if !detail.isEmpty { Text(detail).font(Theme.label(11)).opacity(0.9).lineLimit(1).layoutPriority(-1) }
                    }
                } else {
                    Text(title).font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.7)
                    if !detail.isEmpty { Text(detail).font(Theme.label(12)).opacity(0.9).lineLimit(1) }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(compact ? 8 : 12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .accessibilityElement(children: .combine)
    }
}

private func rgb(_ v: UInt32) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}
