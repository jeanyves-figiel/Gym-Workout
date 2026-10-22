import ActivityKit
import AppIntents
import CoreSpotlight
import SwiftUI
import WorkoutEngine

// Siri, Shortcuts and Apple Intelligence (#605, designs A + B + C from `apple-tech-radar/t3.png`): ready-made App
// Shortcuts and Spotlight (A), set logging and lift stats by voice with a MonkeyFit card as the answer (B), and the
// open exercise page shared with Siri so "my best on this" or "something easier?" act on it (C).

/// An exercise of the catalog or the member's own, for Siri, Shortcuts and Spotlight.
struct ExerciseEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Exercise"
    static let defaultQuery = ExerciseEntityQuery()

    let id: String
    let name: String
    let muscles: String

    init(_ e: Exercise) {
        id = e.id
        name = e.name
        muscles = e.primary.map(\.name).joined(separator: ", ")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: muscles.isEmpty ? nil : "\(muscles)")
    }
}

struct ExerciseEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ExerciseEntity] {
        identifiers.compactMap { id in Exercise.search().first { $0.id == id }.map(ExerciseEntity.init) }
    }

    func entities(matching string: String) async throws -> [ExerciseEntity] {
        if let e = Exercise.named(string) { return [ExerciseEntity(e)] }
        return Exercise.search(string).prefix(20).map(ExerciseEntity.init)
    }

    func suggestedEntities() async throws -> [ExerciseEntity] {
        Exercise.search().filter(\.main).prefix(30).map(ExerciseEntity.init)
    }
}

enum SiriIndex {
    /// Main lifts in Spotlight: typing "bench" finds the exercise page.
    static func indexExercises() {
        let lifts = Exercise.search().filter(\.main).map(ExerciseEntity.init)
        Task { try? await CSSearchableIndex.default().indexAppEntities(lifts) }
    }
}

/// A workout runs on this iPhone: its Live Activity is up and not the finished card.
@MainActor private var workoutRunning: Bool {
    Activity<WorkoutActivityAttributes>.activities.contains { $0.content.state.summary == nil }
}

struct StartTodayWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start today's workout"
    static let description = IntentDescription("Opens today's workout in the player.")
    static let openAppWhenRun = true

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        HomeWidgetRouter.open(HomeWidgetLink.tab("today"), model: model)
        return .result()
    }
}

struct JustAteIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a meal"
    static let description = IntentDescription("Opens Just ate in Fuel.")
    static let openAppWhenRun = true

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        HomeWidgetRouter.open(HomeWidgetLink.tab("justate"), model: model)
        return .result()
    }
}

/// "Log eight at eighty": fills the coming set and logs it, like saying it to the player's mic.
struct LogSetByVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a set"
    static let description = IntentDescription("Logs the coming set of the workout in progress.")

    @Parameter(title: "Reps", inclusiveRange: (1, 100)) var reps: Int
    @Parameter(title: "Weight (kg)") var kg: Double?

    static var parameterSummary: some ParameterSummary { Summary("Log \(\.$reps) reps at \(\.$kg) kg") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard workoutRunning else {
            return .result(dialog: "No workout is running. Start one first.", view: EmptyView().eraseToAny())
        }
        NotificationCenter.default.post(name: .workoutVoiceLog, object: nil, userInfo: ["reps": reps, "kg": kg as Any])
        let weight = kg.map { " at \(WatchPlayerFormat.kg($0)) kg" } ?? ""
        return .result(dialog: "Logged \(reps) reps\(weight).",
                       view: SiriCard(eyebrow: "LOGGED", title: "\(reps) reps", big: kg.map { "\(WatchPlayerFormat.kg($0)) kg" } ?? "✓",
                                      tint: (0xFF3D7B, 0xFF8A00)).eraseToAny())
    }
}

/// "What's my best bench press?"
struct BestLiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Best lift"
    static let description = IntentDescription("Your heaviest logged set of an exercise.")

    @Parameter(title: "Exercise") var exercise: ExerciseEntity
    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let logs = model.setLogs.filter { $0.exerciseId == exercise.id && $0.kg > 0 }
        guard let best = logs.max(by: { ($0.kg, $0.reps ?? 0) < ($1.kg, $1.reps ?? 0) }) else {
            return .result(dialog: "No \(exercise.name) logged yet.", view: EmptyView().eraseToAny())
        }
        let set = "\(WatchPlayerFormat.kg(best.kg)) kg" + (best.reps.map { " × \($0)" } ?? "")
        let day = best.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return .result(dialog: "Your best \(exercise.name) is \(set), on \(day).",
                       view: SiriCard(eyebrow: "\(exercise.name.uppercased()) · BEST", title: day, big: set,
                                      tint: (0x2F6BFF, 0x8A4DFF)).eraseToAny())
    }
}

/// "Something easier?" on an exercise page: Ask Coach about it.
struct AskCoachIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Coach"
    static let description = IntentDescription("Opens Ask Coach with your question.")
    static let openAppWhenRun = true

    @Parameter(title: "Question") var question: String
    @Parameter(title: "Exercise") var exercise: ExerciseEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        let focus = exercise.map { CoachFocus(screen: "exercise", title: $0.name, detail: $0.muscles) }
        CoachAsk.shared.request = AskCoachRequest(focus: focus ?? CoachAsk.shared.current, question: question)
        return .result()
    }
}

struct MonkeyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartTodayWorkoutIntent(), phrases: [
            "Start my \(.applicationName) workout", "Start today's \(.applicationName) workout", "\(.applicationName) start",
        ], shortTitle: "Start today", systemImageName: "play.fill")
        AppShortcut(intent: LogSetByVoiceIntent(), phrases: [
            "Log a set in \(.applicationName)", "\(.applicationName) log set",
        ], shortTitle: "Log set", systemImageName: "checkmark")
        AppShortcut(intent: AddWaterIntent(), phrases: [
            "Add water in \(.applicationName)", "\(.applicationName) add a glass",
        ], shortTitle: "Add water", systemImageName: "drop.fill")
        AppShortcut(intent: JustAteIntent(), phrases: [
            "I just ate in \(.applicationName)", "Log a meal in \(.applicationName)",
        ], shortTitle: "Just ate", systemImageName: "fork.knife")
        AppShortcut(intent: BestLiftIntent(), phrases: [
            "My best \(\.$exercise) in \(.applicationName)", "\(.applicationName) best \(\.$exercise)",
            "My \(.applicationName) best lift",
        ], shortTitle: "Best lift", systemImageName: "trophy.fill")
        AppShortcut(intent: AskCoachIntent(), phrases: [
            "Ask \(.applicationName) Coach", "Ask my \(.applicationName) coach",
        ], shortTitle: "Ask Coach", systemImageName: "bubble.left.fill")
    }
}

/// Siri's answer card: gradient, eyebrow, big number (Explore look).
private struct SiriCard: View {
    let eyebrow: String
    let title: String
    let big: String
    let tint: (UInt32, UInt32)

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow).font(.system(size: 11, weight: .heavy, design: .rounded)).opacity(0.9).lineLimit(1)
                Text(title).font(.system(size: 17, weight: .black, design: .rounded)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(big).font(.system(size: 30, weight: .black, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(LinearGradient(colors: [Color(hex: tint.0), Color(hex: tint.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension View {
    func eraseToAny() -> AnyView { AnyView(self) }
}

/// "80", "82.5": kg without a trailing .0.
private enum WatchPlayerFormat {
    static func kg(_ v: Double) -> String { v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v) }
}
