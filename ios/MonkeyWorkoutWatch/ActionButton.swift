import AppIntents
import Foundation
import Observation
import WatchKit

/// Apple Watch Ultra Action button (#349). The member picks MonkeyWorkout in Watch Settings → Action Button → Workout:
/// the first press starts Next up, later presses during our workout do the next step (Smart next / Log set / Rest timer,
/// picked on the iPhone), Action + side button pauses and resumes. Intents must live in the Watch app, not an extension.
@MainActor @Observable
final class ActionButton {
    static let shared = ActionButton()

    /// First press: start Next up as soon as the root view can.
    var startRequested = false
    /// Presses during a workout run on the Watch; the player reacts to each.
    private(set) var presses = 0

    /// First press. The system needs a Health session within 30 s, which the player starts when it appears.
    func start() async {
        let workout = WorkoutManager.shared
        guard !workout.running else { return }
        if let store = WatchStore.current, store.offered || store.live != nil {
            // A workout runs on the iPhone: track it rather than starting a second one.
            await store.trackPhoneWorkout()
            return
        }
        startRequested = true
        for _ in 0..<50 where !workout.running {
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    /// Later presses: step the Watch player, or the iPhone player when the Watch tracks an iPhone workout.
    func press() {
        if WorkoutManager.shared.phoneSessionId != nil, let store = WatchStore.current {
            let resting = store.live.map { $0.effortPending || ($0.restEnd ?? .distantPast) > Date() } ?? false
            store.send(resting ? WCommand.skipRest : .main)
            WKInterfaceDevice.current().play(.click)
            return
        }
        presses += 1
    }

    /// Makes the in-workout press our next action; called once the Health session runs (Action button or app start).
    static func sessionStarted() {
        Task {
            try? await StartNextUpIntent().donate(result: .result(actionButtonIntent: ActionNextIntent()))
        }
    }
}

enum MonkeyWorkoutStyle: String, AppEnum {
    case nextUp

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Workout" }
    static var caseDisplayRepresentations: [MonkeyWorkoutStyle: DisplayRepresentation] {
        [.nextUp: DisplayRepresentation(title: "Next up", subtitle: "Your planned gym workout")]
    }
}

/// First press of the Action button: start the Next up workout.
struct StartNextUpIntent: StartWorkoutIntent {
    static var title: LocalizedStringResource { "Start workout" }
    static var suggestedWorkouts: [StartNextUpIntent] { [StartNextUpIntent()] }

    @Parameter(title: "Workout")
    var workoutStyle: MonkeyWorkoutStyle

    init() {
        workoutStyle = .nextUp
    }

    var displayRepresentation: DisplayRepresentation {
        MonkeyWorkoutStyle.caseDisplayRepresentations[workoutStyle] ?? DisplayRepresentation(title: "Next up")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await ActionButton.shared.start()
        return .result()
    }
}

/// Action button press during a MonkeyWorkout session.
struct ActionNextIntent: AppIntent {
    static var title: LocalizedStringResource { "Next step" }

    @MainActor
    func perform() async throws -> some IntentResult {
        ActionButton.shared.press()
        return .result()
    }
}

/// Action + side button.
struct PauseMonkeyWorkoutIntent: PauseWorkoutIntent {
    static var title: LocalizedStringResource { "Pause workout" }

    @MainActor
    func perform() async throws -> some IntentResult {
        WorkoutManager.shared.pause()
        return .result()
    }
}

struct ResumeMonkeyWorkoutIntent: ResumeWorkoutIntent {
    static var title: LocalizedStringResource { "Resume workout" }

    @MainActor
    func perform() async throws -> some IntentResult {
        WorkoutManager.shared.resume()
        return .result()
    }
}
