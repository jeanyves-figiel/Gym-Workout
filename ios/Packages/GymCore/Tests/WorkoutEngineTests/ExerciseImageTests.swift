import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct ExerciseImageTests {
    @Test func everyExerciseHasPhotoOrIllustration() {
        for e in Exercise.catalog { #expect(e.hasMedia, "\(e.id) has no image") }
        for id in ExerciseIllustrations.ids { #expect(Exercise.find(id) != nil, "\(id)") }
        #expect(Exercise.catalog.filter(\.hasIllustration).count == ExerciseIllustrations.ids.count)
        #expect(ExerciseIllustrations.frameCount == 3)
    }

    @Test func illustrationAssetsExistInAppCatalog() throws {
        // Tests/WorkoutEngineTests → ios/
        let ios = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let assets = ios.appendingPathComponent("MonkeyWorkout/Resources/Illustrations.xcassets")
        for e in Exercise.catalog {
            let names = e.illustrationAssets
            #expect(names.count == ExerciseIllustrations.frameCount, "\(e.id)")
            for name in names {
                let png = assets.appendingPathComponent("\(name).imageset/\(name).png")
                #expect(FileManager.default.fileExists(atPath: png.path), "\(png.path)")
            }
        }
        #expect(Exercise.get("back-squat").illustrationAssets == [
            "illustration-back-squat-0", "illustration-back-squat-1", "illustration-back-squat-2",
        ])
    }
}
