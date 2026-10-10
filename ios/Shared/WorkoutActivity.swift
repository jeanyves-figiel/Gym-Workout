import ActivityKit
import AppIntents
import Foundation

/// Live Activity of the workout player (lock screen + Dynamic Island). Compiled into the app and the widget extension.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Exercise on screen in the player.
        var exercise: String
        /// "Set 2 of 4", "3 × 10", …
        var setLabel: String
        /// "82.5 kg × 8" for the coming set; empty when not logged by load.
        var detail: String
        /// Rest running from `restStart` to `restEnd`; nil while working.
        var restStart: Date?
        var restEnd: Date?
        /// Next set or exercise, e.g. "Back Squat · set 3 of 4".
        var next: String
        /// Hex of the block's category colour.
        var tint: UInt32
    }

    var sessionTitle: String
    var startedAt: Date
}

extension Notification.Name {
    /// Posted by the Live Activity buttons; the workout player observes them.
    static let workoutRestAdd15 = Notification.Name("workoutRestAdd15")
    static let workoutRestSkip = Notification.Name("workoutRestSkip")
}

/// "+15 s" on the lock screen. Live Activity intents run in the app's process.
struct AddRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add 15 seconds of rest"

    func perform() async throws -> some IntentResult {
        await MainActor.run { NotificationCenter.default.post(name: .workoutRestAdd15, object: nil) }
        return .result()
    }
}

/// "Skip rest" on the lock screen.
struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip rest"

    func perform() async throws -> some IntentResult {
        await MainActor.run { NotificationCenter.default.post(name: .workoutRestSkip, object: nil) }
        return .result()
    }
}
