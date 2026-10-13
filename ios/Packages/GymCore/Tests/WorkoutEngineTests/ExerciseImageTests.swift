import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct ExerciseImageTests {
    @Test func everyExerciseHasPhotoOrIllustration() {
        for e in Exercise.catalog { #expect(e.hasMedia, "\(e.id) has no image") }
        for id in ExerciseIllustrations.ids { #expect(Exercise.find(id) != nil, "\(id)") }
        #expect(Exercise.catalog.filter(\.hasIllustration).count == ExerciseIllustrations.ids.count)
        #expect(ExerciseIllustrations.frameCount == 9)
        #expect(ExerciseIllustrations.keyFrames == [0, 4, 8])
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
        #expect(Exercise.get("back-squat").illustrationAssets == (0..<9).map { "illustration-back-squat-\($0)" })
    }

    @Test func everyIllustrationHasMotion() {
        for e in Exercise.catalog where e.hasIllustration {
            guard let m = e.motion else {
                Issue.record("\(e.id) has no motion")
                continue
            }
            #expect(m.path.isEmpty || m.points.count == ExerciseIllustrations.frameCount, "\(e.id)")
            for p in m.points {
                #expect((-0.1...1.1).contains(p.x) && (-0.1...1.1).contains(p.y), "\(e.id) path leaves the picture")
            }
            #expect(!m.first.isEmpty && !m.second.isEmpty && m.first != m.second, "\(e.id)")
        }
        #expect(ExerciseMotion.table.count == ExerciseIllustrations.ids.count)
    }

    @Test func motionPhasesAndTempo() throws {
        let squat = try #require(Exercise.get("back-squat").motion)
        let (down, up) = squat.phases(.strength)
        #expect(down.label == "DOWN" && !down.effort && down.seconds == 2 && down.text == "DOWN 2s")
        #expect(up.label == "UP" && up.effort && up.seconds == 1 && up.text == "UP 1s")
        let curl = try #require(Exercise.get("db-curl").motion)
        #expect(curl.phases(.strength).0.text == "UP 1s")
        let pulldown = try #require(Exercise.get("lat-pulldown").motion)
        #expect(pulldown.phases(.strength).0.effort, "pulling the bar down is the work")
        let power = ExerciseMotion("UP", "DOWN", effortFirst: true, path: [])
        #expect(power.phases(.power).0.text == "UP FAST")
        #expect(power.phases(.power).1.text == "DOWN 1.4s")
        #expect(power.phases(.mobility).0.seconds == 1.5)
        #expect(ExerciseMotion.showsTempo(.strength) && ExerciseMotion.showsTempo(.power))
        #expect(!ExerciseMotion.showsTempo(.stretch) && !ExerciseMotion.showsTempo(.mobility))
    }

    @Test func motionPathPointBetweenFrames() {
        let m = ExerciseMotion("UP", "DOWN", effortFirst: true, path: [0, 0, 1, 0.5])
        #expect(m.points.count == 2)
        let mid = m.point(at: 0.5)
        #expect(mid?.x == 0.5 && mid?.y == 0.25)
        #expect(m.point(at: 9)?.x == 1)
        #expect(ExerciseMotion("UP", "DOWN", effortFirst: true, path: []).point(at: 0) == nil)
    }
}
