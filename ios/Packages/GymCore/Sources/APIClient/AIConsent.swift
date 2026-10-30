import Foundation

/// What a call to Coach's AI sends to Anthropic (#972, App Review 5.1.2(i)): one switch each in Settings → AI & privacy.
public enum AIFeature: String, Sendable, Codable, CaseIterable, Identifiable {
    /// Ask Coach (chat, snap a machine) and Talk to Coach mid-set.
    case coach
    /// Coach's week review: workouts, sleep, HRV and mood (health data).
    case review
    /// Gym, fridge, receipt and meal scans, Save from a video.
    case scans
    /// Plan setup by talking to Coach, What can I eat?
    case ideas

    public var id: String { rawValue }
}

/// The member's answers (#972). `decided` false until the first-use sheet was answered; then each feature's switch.
public struct AIConsentState: Codable, Sendable, Equatable {
    public var decided: Bool
    public var allowed: Set<AIFeature>

    public init(decided: Bool = false, allowed: Set<AIFeature> = []) {
        self.decided = decided
        self.allowed = allowed
    }

    public func allows(_ f: AIFeature) -> Bool { decided && allowed.contains(f) }

    /// The sheet's answer: `allowed` the switches left on (Allow), empty for Not now.
    public mutating func answer(_ allowed: Set<AIFeature>) {
        decided = true
        self.allowed = allowed
    }

    public mutating func set(_ f: AIFeature, _ on: Bool) {
        decided = true
        if on { allowed.insert(f) } else { allowed.remove(f) }
    }
}

extension APIError {
    /// Thrown before any byte leaves the device when the member said no to that AI feature (#972).
    public static let aiOff = APIError.server(status: 0, code: "ai_off",
                                              message: "Coach's AI is off for this. Turn it on in Settings → AI & privacy.")
}

extension APIClient {
    /// The app answers whether `feature` may send data to Anthropic, asking the member the first time (#972).
    public func setAIConsent(_ handler: @escaping @Sendable (AIFeature) async -> Bool) { aiConsent = handler }

    /// Every AI call goes through here first; without a handler (tests, tools) calls go out as before.
    func requireAI(_ feature: AIFeature) async throws {
        guard let aiConsent else { return }
        if await aiConsent(feature) { return }
        throw APIError.aiOff
    }
}
