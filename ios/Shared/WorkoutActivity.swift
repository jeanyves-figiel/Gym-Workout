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

        // Lock-screen logging + session dashboard (#371). Optional so a card started by an older build still decodes.

        /// The coming set is logged by kg × reps: the effort tiles log it from the lock screen.
        var loggable: Bool?
        /// The player's lime button when it isn't a loggable set ("START 0:30", "NEXT", "FINISH").
        var action: String?
        /// Timed set counting down to this.
        var workEnd: Date?
        /// "Next in 5" after an exercise's last set (#357).
        var autoNextEnd: Date?
        /// Exercise on screen, 1-based, of `count`.
        var position: Int?
        var count: Int?
        /// One per exercise, in order: its colour and how much of it is done.
        var segments: [Segment]?
        /// When the workout should be over (estimate, or the finish-early time).
        var doneBy: Date?
        /// Live heart rate from the Apple Watch tracking this workout.
        var heartRate: Int?
        /// kg × reps logged in this workout so far.
        var volumeKg: Double?
        /// Set once the workout is finished: the card stays on the lock screen as a summary.
        var summary: Summary?
    }

    struct Segment: Codable, Hashable {
        var tint: UInt32
        /// 0…1
        var done: Double
    }

    struct Summary: Codable, Hashable {
        var minutes: Int
        var exercises: Int
        var of: Int
        var sets: Int
        var volumeKg: Double
        /// New heaviest weights this workout.
        var prs: Int
    }

    var sessionTitle: String
    var startedAt: Date
}

extension Notification.Name {
    /// Posted by the Live Activity buttons; the workout player observes them.
    static let workoutRestAdd15 = Notification.Name("workoutRestAdd15")
    static let workoutRestSkip = Notification.Name("workoutRestSkip")
    /// Lock-screen effort tile (#371): logs the coming set with this RIR (object: Int).
    static let workoutLogSet = Notification.Name("workoutLogSet")
    /// Lock-screen − / + on the coming set's kg (object: Int, -1 or 1).
    static let workoutStepKg = Notification.Name("workoutStepKg")
    /// Lock-screen lime button: what the player's lime button does.
    static let workoutMain = Notification.Name("workoutMain")
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

/// Effort tile on the lock screen / Dynamic Island: the set is done with this many reps left (#371).
struct LogSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Log set"

    @Parameter(title: "Reps left") var rir: Int

    init() {}
    init(rir: Int) { self.rir = rir }

    func perform() async throws -> some IntentResult {
        await MainActor.run { NotificationCenter.default.post(name: .workoutLogSet, object: rir) }
        return .result()
    }
}

/// − / + beside the coming set's weight on the lock screen (#371).
struct StepKgIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Change weight"

    @Parameter(title: "Direction") var sign: Int

    init() {}
    init(sign: Int) { self.sign = sign }

    func perform() async throws -> some IntentResult {
        await MainActor.run { NotificationCenter.default.post(name: .workoutStepKg, object: sign) }
        return .result()
    }
}

/// The player's lime button from the lock screen: start/pause a timed set, next exercise, finish (#371).
struct MainActionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Next step"

    func perform() async throws -> some IntentResult {
        await MainActor.run { NotificationCenter.default.post(name: .workoutMain, object: nil) }
        return .result()
    }
}
