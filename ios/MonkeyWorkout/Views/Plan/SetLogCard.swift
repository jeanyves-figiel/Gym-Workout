import SwiftUI
import UIKit
import WorkoutEngine

/// Per-set logging table in the workout player: kg × reps and optional RIR for every set, for review and corrections.
/// Rows live in `SetLogState`, shared with the current-set card and the one-tap effort picker.
struct SetLogCard: View {
    @Bindable var state: SetLogState
    /// Sets completed in the player; highlights the next row.
    let done: Int
    @Environment(AppModel.self) private var model
    @FocusState private var focus: Field?

    enum Field: Hashable {
        case kg(Int), reps(Int), rir(Int)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Log sets").eyebrow()
                Spacer()
                Text("kg × reps · RIR").font(Theme.label(11)).foregroundStyle(Theme.muted)
            }
            if let s = state.suggestion { SuggestionLine(suggestion: s) }
            ForEach(state.rows.indices, id: \.self) { i in row(i) }
        }
        .card(padding: 14)
    }

    private func row(_ i: Int) -> some View {
        let current = i == done && !state.rows[i].logged
        return HStack(spacing: 8) {
            Text("\(i + 1)")
                .font(Theme.label(14))
                .foregroundStyle(current ? Theme.lime : Theme.muted)
                .frame(width: 20)
            field($state.rows[i].kg, placeholder: "kg", keyboard: .decimalPad, focus: .kg(i), width: 70)
            Text("×").font(Theme.label(14)).foregroundStyle(Theme.muted)
            field($state.rows[i].reps, placeholder: "reps", keyboard: .numberPad, focus: .reps(i), width: 50)
            field($state.rows[i].rir, placeholder: "RIR", keyboard: .numberPad, focus: .rir(i), width: 46)
            Spacer(minLength: 0)
            Button { log(i) } label: {
                Image(systemName: state.rows[i].logged ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(state.rows[i].logged ? Theme.lime : Color.white.opacity(0.5))
            }
            .disabled(state.values(i) == nil)
            .accessibilityLabel(state.rows[i].logged ? "Update set \(i + 1)" : "Log set \(i + 1)")
        }
    }

    private func field(_ text: Binding<String>, placeholder: String, keyboard: UIKeyboardType, focus f: Field, width: CGFloat) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .focused($focus, equals: f)
            .multilineTextAlignment(.center)
            .font(Theme.display(18))
            .frame(width: width)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardStrong))
    }

    private func log(_ i: Int) {
        guard state.log(i, model: model) else { return }
        focus = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// "82.5 kg × 8" with the reason behind it.
struct SuggestionLine: View {
    let suggestion: LoadSuggestion

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.label(15))
                Text(suggestion.reason).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        var t = "Suggested \(LoadAdvisor.formatKg(suggestion.kg)) kg"
        if let r = suggestion.reps { t += " × \(r)" }
        return t
    }

    private var symbol: String {
        switch suggestion.action {
        case .increase: "arrow.up.circle.fill"
        case .hold: "equal.circle.fill"
        case .decrease: "arrow.down.circle.fill"
        case .deload: "leaf.circle.fill"
        }
    }

    private var color: Color {
        switch suggestion.action {
        case .increase: Theme.lime
        case .hold: .white
        case .decrease: .orange
        case .deload: .mint
        }
    }
}
