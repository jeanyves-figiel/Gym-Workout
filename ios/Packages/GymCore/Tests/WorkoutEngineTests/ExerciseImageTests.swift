import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct ExerciseImageTests {
    @Test func mappingKeysAreCatalogExercises() {
        for key in ExerciseImages.ids.keys { #expect(Exercise.find(key) != nil, "\(key)") }
        let mapped = Exercise.catalog.filter { $0.imageId != nil }
        #expect(mapped.count == ExerciseImages.ids.count)
        #expect(mapped.count >= 100)
    }

    @Test func imageIdsNonEmptyAndUniquePerExercise() {
        let ids = Exercise.catalog.compactMap(\.imageId)
        #expect(Set(ids).count == ids.count)
        for id in ids {
            #expect(!id.isEmpty)
            #expect(id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }, "\(id)")
        }
    }

    @Test func urlsWellFormedAndPinnedToCommit() {
        #expect(ExerciseImages.commit.count == 40)
        #expect(ExerciseImages.commit.allSatisfy { $0.isHexDigit })
        for e in Exercise.catalog {
            guard let imageId = e.imageId else {
                #expect(e.imageURLs.isEmpty, "\(e.id)")
                continue
            }
            let urls = e.imageURLs
            #expect(urls.count == ExerciseImages.frameCount, "\(e.id)")
            for (frame, url) in urls.enumerated() {
                #expect(url.scheme == "https")
                #expect(url.absoluteString == "https://raw.githubusercontent.com/yuhonas/free-exercise-db/\(ExerciseImages.commit)/exercises/\(imageId)/\(frame).jpg", "\(e.id)")
            }
        }
        #expect(ExerciseImages.url(imageId: "", frame: 0) == nil)
        #expect(ExerciseImages.url(imageId: "Plank", frame: 2) == nil)
    }

    @Test func everyExerciseHasPhotoOrIllustration() {
        for e in Exercise.catalog { #expect(e.hasMedia, "\(e.id) has no image") }
        for id in ExerciseIllustrations.ids {
            #expect(Exercise.find(id) != nil, "\(id)")
            #expect(ExerciseImages.ids[id] == nil, "\(id) has both a photo and an illustration")
        }
        #expect(Exercise.catalog.filter(\.hasIllustration).count == ExerciseIllustrations.ids.count)
    }

    @Test func illustrationAssetsExistInAppCatalog() throws {
        // Tests/WorkoutEngineTests → ios/
        let ios = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let assets = ios.appendingPathComponent("MonkeyWorkout/Resources/Illustrations.xcassets")
        for e in Exercise.catalog where e.hasIllustration {
            let names = e.illustrationAssets
            #expect(names.count == ExerciseIllustrations.frameCount)
            for name in names {
                let svg = assets.appendingPathComponent("\(name).imageset/\(name).svg")
                #expect(FileManager.default.fileExists(atPath: svg.path), "\(svg.path)")
            }
        }
        #expect(Exercise.get("back-squat").illustrationAssets.isEmpty)
    }
}
