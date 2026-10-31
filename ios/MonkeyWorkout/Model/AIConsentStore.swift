import APIClient
import SwiftUI
import UIKit

/// Third-party AI consent (#972, App Review 5.1.2(i), design C from `ai-consent/proposals.png`): before Coach's AI first
/// sends anything to Anthropic, a sheet says what each feature sends and asks; Settings → AI & privacy keeps a switch per
/// feature. `APIClient` asks here before every AI call (`requireAI`), so no feature can skip it. Kept on this device.
@MainActor @Observable
final class AIConsentStore {
    static let shared = AIConsentStore()
    private static let key = "aiConsent.v1"

    private(set) var state: AIConsentState
    /// The feature that opened the first-use sheet (RootView shows it).
    var asking: AIFeature?
    @ObservationIgnored private var waiting: [CheckedContinuation<Void, Never>] = []

    init(defaults: UserDefaults = .standard) {
        state = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(AIConsentState.self, from: $0) } ?? AIConsentState()
    }

    /// The `APIClient` hook.
    static func consent(_ f: AIFeature) async -> Bool { await shared.ask(f) }

    func allows(_ f: AIFeature) -> Bool { state.allows(f) }

    /// Answers at once once decided; otherwise shows the sheet and waits, only with the app in front (never from Siri or
    /// the background: those calls stay on the device until the member has answered).
    func ask(_ f: AIFeature) async -> Bool {
        if state.decided { return state.allows(f) }
        guard UIApplication.shared.applicationState == .active else { return false }
        if asking == nil { asking = f }
        await withCheckedContinuation { waiting.append($0) }
        return state.allows(f)
    }

    /// Allow (the switches left on) or Not now (none).
    func answer(_ allowed: Set<AIFeature>) {
        state.answer(allowed)
        save()
        asking = nil
        resume()
    }

    /// Settings switch.
    func set(_ f: AIFeature, _ on: Bool) {
        state.set(f, on)
        save()
    }

    /// ✕ or swipe: nothing decided, that call stays on the device; the next AI use asks again.
    func dismissed() {
        asking = nil
        resume()
    }

    private func resume() {
        let w = waiting
        waiting = []
        w.forEach { $0.resume() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

extension AIFeature {
    var title: String {
        switch self {
        case .coach: "Ask & Talk to Coach"
        case .review: "Weekly review"
        case .scans: "Gym, fridge & video scans"
        case .ideas: "Plan setup & meal ideas"
        }
    }

    /// What goes to Anthropic, in one line.
    var sends: String {
        switch self {
        case .coach: "Your words, the screen you ask from, training settings, a machine photo you snap"
        case .review: "Your week: workouts, sleep, HRV and mood (health data)"
        case .scans: "The photo or screenshots, a post's link and caption"
        case .ideas: "What you tell Coach, your pantry foods and what's left to eat"
        }
    }

    var symbol: String {
        switch self {
        case .coach: "bubble.left.and.text.bubble.right.fill"
        case .review: "heart.text.square.fill"
        case .scans: "camera.viewfinder"
        case .ideas: "fork.knife"
        }
    }

    var gradient: LinearGradient {
        let c: (Color, Color) = switch self {
        case .coach: (Color(red: 0, green: 0.78, blue: 1), Color(red: 0, green: 0.45, blue: 1))
        case .review: (Color(red: 1, green: 0.25, blue: 0.42), Color(red: 1, green: 0.29, blue: 0.17))
        case .scans: (Color(red: 0.97, green: 0.59, blue: 0.12), Color(red: 1, green: 0.82, blue: 0))
        case .ideas: (Color(red: 0.48, green: 0.18, blue: 0.97), Color(red: 0.95, green: 0.03, blue: 0.64))
        }
        return LinearGradient(colors: [c.0, c.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
