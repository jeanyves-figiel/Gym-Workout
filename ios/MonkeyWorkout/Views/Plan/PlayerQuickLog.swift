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
    let onPick: (Effort) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("How hard?").font(Theme.display(26))
            HStack(spacing: 6) {
                ForEach(Effort.allCases) { e in
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onPick(e)
                    } label: {
                        VStack(spacing: 1) {
                            Text(e.title).font(Theme.display(26))
                            Text(e.caption).font(Theme.label(9))
                        }
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(e.color))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white, lineWidth: selected == e ? 3 : 0))
                        .scaleEffect(selected == e ? 1.06 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(e == .fail ? "Failure, no reps left" : e == .easy ? "Easy, 4 or more reps left" : "\(e.rir) reps left")
                }
            }
            Text("Reps left in the tank").font(.caption).foregroundStyle(Theme.muted)
        }
        .animation(.spring(duration: 0.25), value: selected)
    }
}

/// Card for the coming set: kg and reps steppers prefilled from the load suggestion, no keyboard.
struct CurrentSetCard: View {
    @Bindable var state: SetLogState
    let set: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Set \(set + 1) of \(state.rows.count)").font(Theme.label(13)).tracking(1.2).textCase(.uppercase)
                Spacer()
                if let s = state.suggestion {
                    Text("Suggested \(LoadAdvisor.formatKg(s.kg))\(s.reps.map { " × \($0)" } ?? "")")
                        .font(Theme.label(11))
                        .opacity(0.85)
                }
            }
            HStack(spacing: 10) {
                stepper(value: state.rows.indices.contains(set) ? state.rows[set].kg : "", unit: "kg",
                        minus: { state.stepKg(set, by: -1) }, plus: { state.stepKg(set, by: 1) })
                stepper(value: state.rows.indices.contains(set) ? state.rows[set].reps : "", unit: "reps",
                        minus: { state.stepReps(set, by: -1) }, plus: { state.stepReps(set, by: 1) })
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke))
    }

    private func stepper(value: String, unit: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            stepButton("minus", label: "Less \(unit)", action: minus)
            VStack(spacing: 0) {
                Text(value.isEmpty ? "–" : value).font(Theme.display(28)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                Text(unit).font(Theme.label(10)).opacity(0.8)
            }
            .frame(maxWidth: .infinity)
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

/// What comes after the current set: the next set of this exercise or the next exercise, on its category gradient.
struct UpNextCard: View {
    let title: String
    let eyebrow: String
    let detail: String
    let exercise: Exercise?
    let colors: [Color]
    var symbol: String = "arrow.right"

    var body: some View {
        HStack(spacing: 12) {
            if let exercise {
                ExerciseThumbnail(exercise: exercise, size: 48)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .heavy))
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.2)))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow).font(Theme.label(10)).tracking(1.2).textCase(.uppercase).opacity(0.85)
                Text(title).font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.7)
                if !detail.isEmpty { Text(detail).font(Theme.label(12)).opacity(0.9).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .accessibilityElement(children: .combine)
    }
}

private func rgb(_ v: UInt32) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}
