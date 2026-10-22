import AppIntents
import SwiftUI
import WorkoutEngine
#if canImport(VisualIntelligence)
import VisualIntelligence
#endif

// Machine camera (#617 C): point Visual Intelligence (camera control or a screenshot) at a gym machine, MonkeyFit lists
// its exercises, a tap opens the exercise page.

#if canImport(VisualIntelligence)
@available(iOS 26, *)
struct MachineVisualQuery: IntentValueQuery {
    func values(for input: SemanticContentDescriptor) async throws -> [ExerciseEntity] {
        MachineMatch.exercises(labels: input.labels).map(ExerciseEntity.init)
    }
}
#endif

/// Opens an exercise page: a Visual Intelligence result, Spotlight or Shortcuts.
struct OpenExerciseIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open exercise"
    static let description = IntentDescription("Opens the exercise page in MonkeyFit.")

    @Parameter(title: "Exercise") var target: ExerciseEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        ExerciseLaunch.shared.item = ExerciseLaunch.Item(id: target.id)
        return .result()
    }
}

/// Exercise page opened from outside the app (#617); RootView shows it as a sheet.
@MainActor @Observable
final class ExerciseLaunch {
    static let shared = ExerciseLaunch()
    struct Item: Identifiable { let id: String }
    var item: Item?
}
