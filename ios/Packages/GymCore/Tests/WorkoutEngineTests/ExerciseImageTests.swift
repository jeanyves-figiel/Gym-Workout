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
}
