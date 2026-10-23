import Foundation

/// New member onboarding (#664): the guided steps, in order. Each one can be skipped and run again later.
public enum OnboardingStep: String, Codable, CaseIterable, Sendable, Identifiable {
    case gym, machines, map, plan, tour

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gym: "Your gym"
        case .machines: "Machines"
        case .map: "Gym map"
        case .plan: "Your plan"
        case .tour: "App tour"
        }
    }

    /// Short name for tiles and the step dots.
    public var short: String {
        switch self {
        case .gym: "Gym"
        case .machines: "Machines"
        case .map: "Map"
        case .plan: "Plan"
        case .tour: "Tour"
        }
    }

    public var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    public var next: OnboardingStep? {
        let all = Self.allCases
        guard let i = all.firstIndex(of: self), i + 1 < all.count else { return nil }
        return all[i + 1]
    }
}

/// What the member finished of onboarding (#664). nil on members from before it, so they get no set-up card.
/// A step not done (skipped, or the app closed before it) waits on the Train set-up card and in Settings → Onboarding.
public struct OnboardingProgress: Codable, Equatable, Sendable {
    /// Steps finished, in the order they were done.
    public var done: [OnboardingStep]
    /// The set-up card was closed with ✕: the steps left stay in Settings → Onboarding as "Later".
    public var cardHidden: Bool

    public init(done: [OnboardingStep] = [], cardHidden: Bool = false) {
        self.done = done
        self.cardHidden = cardHidden
    }

    public func isDone(_ step: OnboardingStep) -> Bool { done.contains(step) }

    public mutating func complete(_ step: OnboardingStep) {
        if !done.contains(step) { done.append(step) }
    }

    /// Steps still to do, in step order.
    public var later: [OnboardingStep] { OnboardingStep.allCases.filter { !done.contains($0) } }

    public var finished: Bool { later.isEmpty }

    /// The Train set-up card: steps left and not closed.
    public var showsCard: Bool { !cardHidden && !finished }

    /// 0…1 for the card's progress bar.
    public var fraction: Double { Double(OnboardingStep.allCases.count - later.count) / Double(OnboardingStep.allCases.count) }
}
