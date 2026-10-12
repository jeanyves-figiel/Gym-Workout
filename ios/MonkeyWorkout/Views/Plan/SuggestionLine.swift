import SwiftUI
import UIKit
import WorkoutEngine

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
        var t = "\(suggestion.source == .history ? "Suggested" : "Start at") \(LoadAdvisor.formatKg(suggestion.kg)) kg"
        if let r = suggestion.reps { t += " × \(r)" }
        return t
    }

    private var symbol: String {
        if suggestion.source != .history { return "wand.and.stars" }
        return switch suggestion.action {
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
