import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct VideoImportTests {
    private let source = WorkoutSource(platform: "tiktok", url: "https://www.tiktok.com/@fitwithlea/video/1", author: "@fitwithlea")

    @Test func buildsWorkoutFromMatchedMovesOnly() {
        let moves = [
            ImportedMove(said: "Hip thrust", exerciseId: "hip-thrust", sets: 4, reps: 12, unit: .reps, sure: true),
            ImportedMove(said: "Plank", exerciseId: "plank", sets: 3, reps: 1, unit: .min, sure: true),
            ImportedMove(said: "Row", exerciseId: "rower", sets: 1, reps: 600, unit: .sec, sure: true),
            ImportedMove(said: "Moon walk", exerciseId: "", sets: 3, reps: 10, unit: .reps, sure: true),
        ]
        #expect(moves[3].exerciseId == nil && !moves[3].sure)
        let w = CustomWorkout(importing: "Glute burner", moves: moves, source: source)
        #expect(w.items.map(\.exerciseId) == ["hip-thrust", "plank", "rower"])
        #expect(w.items.map(\.sets) == [4, 3, 1])
        #expect(w.items.map(\.reps) == [12, 60, 10])
        #expect(w.source?.label == "@fitwithlea · TikTok")
    }

    @Test func keepsSourceThroughCodingAndCopies() throws {
        let w = CustomWorkout(importing: "Glute burner", moves: [], source: source)
        let back = try JSONDecoder().decode(CustomWorkout.self, from: JSONEncoder().encode(w))
        #expect(back.source == source)
        #expect(w.duplicated().source == source)
        #expect(CustomWorkout(name: "x", source: WorkoutSource(platform: "web", url: "javascript:alert(1)")).sanitized.source == nil)
        #expect(WorkoutSource(platform: "web", url: "https://www.example.com/p").label == "example.com")
    }
}
