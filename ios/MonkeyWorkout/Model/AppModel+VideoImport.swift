import APIClient
import Foundation
import WorkoutEngine

/// What Coach read from a video (#909): name, moves (matched, near or unknown) and the post it came from.
struct VideoImportRead {
    var name: String
    var moves: [ImportedMove]
    var source: WorkoutSource?
}

/// Save a workout seen on TikTok / Instagram (#909): link, caption, screenshots and/or the member's words → Coach.
extension AppModel {
    func readVideoWorkout(link: String?, caption: String?, text: String?, photos: [Data]) async throws -> VideoImportRead {
        #if DEBUG
        if demo { return Self.demoVideoImport }
        #endif
        let catalog = Exercise.search().map { GymScanItem(id: $0.id, label: String($0.name.prefix(60))) }
        let r = try await api.workoutImport(link: link, caption: caption, text: text, photos: photos, catalog: Array(catalog.prefix(600)))
        return VideoImportRead(
            name: r.name,
            moves: r.items.map {
                ImportedMove(said: $0.said, exerciseId: $0.id, sets: $0.sets, reps: $0.reps, unit: ImportedMove.Unit(rawValue: $0.unit) ?? .reps, sure: $0.sure)
            },
            source: r.source.map { WorkoutSource(platform: $0.platform, url: $0.url, author: $0.author) })
    }

    static var demoVideoImport: VideoImportRead {
        VideoImportRead(
            name: "Glute burner",
            moves: [
                ImportedMove(said: "Hip thrust", exerciseId: "hip-thrust", sets: 4, reps: 12, unit: .reps, sure: true),
                ImportedMove(said: "Bulgarian split squat", exerciseId: "bulgarian-split-squat", sets: 3, reps: 10, unit: .reps, sure: true),
                ImportedMove(said: "Cable kickback", exerciseId: "cable-pull-through", sets: 3, reps: 15, unit: .reps, sure: false),
                ImportedMove(said: "Frog pumps", exerciseId: "glute-bridge", sets: 2, reps: 30, unit: .reps, sure: false),
            ],
            source: WorkoutSource(platform: "tiktok", url: "https://www.tiktok.com/@fitwithlea/video/1", author: "@fitwithlea"))
    }
}
