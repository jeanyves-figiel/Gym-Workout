import Foundation
import Observation

/// My tabs (#1004, design A + C): tabs a member hid. Train is always on. A hidden tab's cards, widgets, Coach links,
/// tour stop and share prompts go too; its data stays and comes back when the tab is shown again.
@Observable
final class TabsPref {
    static let shared = TabsPref()
    private static let key = "hiddenTabs"

    /// Tabs a member can hide, in tab bar order.
    static let hideable: [MainTab] = [.explore, .progress, .fuel, .community]

    private(set) var hidden: Set<MainTab>

    private init() {
        let raw = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        hidden = Set(raw.compactMap(MainTab.init(rawValue:))).subtracting([.train])
    }

    func shows(_ tab: MainTab) -> Bool { !hidden.contains(tab) }

    func set(_ tab: MainTab, shown: Bool) {
        guard tab != .train else { return }
        if shown { hidden.remove(tab) } else { hidden.insert(tab) }
        UserDefaults.standard.set(hidden.map(\.rawValue).sorted(), forKey: Self.key)
    }

    /// Tab bar summary for the Settings row, e.g. "4 of 5".
    var summary: String { "\(5 - hidden.count) of 5" }
}

extension MainTab {
    /// Name on the tab bar.
    var title: String {
        switch self {
        case .train: "Train"
        case .explore: "Explore"
        case .progress: "Insights"
        case .fuel: "Fuel"
        case .community: "Social"
        }
    }

    var symbol: String {
        switch self {
        case .train: "bolt.heart.fill"
        case .explore: "figure.arms.open"
        case .progress: "sparkles"
        case .fuel: "fork.knife"
        case .community: "person.3.fill"
        }
    }

    /// One line under the name in My tabs.
    var blurb: String {
        switch self {
        case .train: "Always shown"
        case .explore: "Exercises, machines, programmes"
        case .progress: "Body, Mind, lifts and records"
        case .fuel: "Meals, water, supplements"
        case .community: "Feed, friends, challenges"
        }
    }
}
