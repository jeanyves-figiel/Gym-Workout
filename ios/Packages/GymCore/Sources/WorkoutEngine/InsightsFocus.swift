import Foundation

// Insights focus (#939, design A + C from `insights-focus/proposal-a.png` / `proposal-c.png`): what matters most to
// the member. Picked once on the first open of Insights (preselected from the plan goal), changed from the hero card.
// A focus only moves its widgets to the top of the board: nothing is removed, Edit still arranges everything.

public enum InsightsFocus: String, Codable, CaseIterable, Sendable, Identifiable {
    case strength, muscle, weightLoss, endurance, mind, sport
    /// No focus: the board as it is, no hero card.
    case everything

    public var id: String { rawValue }

    /// A focus from a newer app reads as no focus instead of failing the whole profile.
    public init(from decoder: Decoder) throws {
        self = InsightsFocus(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .everything
    }

    public var title: String {
        switch self {
        case .strength: "Strength"
        case .muscle: "Muscle"
        case .weightLoss: "Weight loss"
        case .endurance: "Endurance"
        case .mind: "Mind & recovery"
        case .sport: "My sport"
        case .everything: "A bit of everything"
        }
    }

    public var detail: String {
        switch self {
        case .strength: "Records, lifts and your programme"
        case .muscle: "Muscles worked, sessions and body"
        case .weightLoss: "Weight, girths and consistency"
        case .endurance: "Training, VO₂ max and consistency"
        case .mind: "Mind score, Body + Mind and mood"
        case .sport: "Your sports' sessions first"
        case .everything: "Insights as it is"
        }
    }

    /// The focus a plan goal points to, so the picker opens on it (onboarding asked already).
    public static func suggested(for goal: Goal?) -> InsightsFocus {
        switch goal {
        case .strength: .strength
        case .build: .muscle
        case .endurance: .endurance
        case .climbing: .sport
        case .balanced, .athletic, nil: .everything
        }
    }

    /// Widgets this focus puts first, in order; sport focus puts the member's sports (up to 2) first.
    public func leading(sports: [Sport]) -> [ProgressWidget] {
        switch self {
        case .strength: [ProgressWidget(.records), ProgressWidget(.programmes), ProgressWidget(.weekly), ProgressWidget(.training)]
        case .muscle: [ProgressWidget(.muscles), ProgressWidget(.weekly), ProgressWidget(.body), ProgressWidget(.records)]
        case .weightLoss: [ProgressWidget(.body), ProgressWidget(.weekly), ProgressWidget(.consistency), ProgressWidget(.training)]
        case .endurance: [ProgressWidget(.training), ProgressWidget(.consistency), ProgressWidget(.weekly), ProgressWidget(.body)]
        case .mind: [ProgressWidget(.today), ProgressWidget(.mind), ProgressWidget(.mood), ProgressWidget(.streak)]
        case .sport:
            (sports.isEmpty ? [Sport.climbing] : Array(sports.prefix(2))).enumerated().map { i, s in ProgressWidget.sport(s, size: i == 0 ? .large : .wide) }
                + [ProgressWidget(.history)]
        case .everything: []
        }
    }
}

extension ProgressBoard {
    /// The board with `focus`'s widgets on top (missing ones added, existing ones keep their size), then every
    /// other widget in its order. Nothing is removed.
    public func focused(on focus: InsightsFocus, sports: [Sport]) -> ProgressBoard {
        let lead = focus.leading(sports: sports).map { l in
            widgets.first { $0.kind == l.kind && $0.sport == l.sport } ?? l
        }
        let rest = widgets.filter { w in !lead.contains { $0.kind == w.kind && $0.sport == w.sport } }
        return ProgressBoard(lead + rest)
    }
}
