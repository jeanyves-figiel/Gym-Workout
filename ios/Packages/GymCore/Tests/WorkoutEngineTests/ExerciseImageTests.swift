import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct ExerciseImageTests {
    @Test func everyExerciseHasPhotoOrIllustration() {
        for e in Exercise.catalog { #expect(e.hasMedia, "\(e.id) has no image") }
        for id in ExerciseIllustrations.ids { #expect(Exercise.find(id) != nil, "\(id)") }
        #expect(Exercise.catalog.filter(\.hasIllustration).count == ExerciseIllustrations.ids.count)
        let n = ExerciseIllustrations.frameCount
        #expect(n >= 9 && n % 2 == 1)
        #expect(ExerciseIllustrations.keyFrames(n) == [0, n / 2, n - 1])
        // #256: more frames only for some exercises, always odd (a middle key pose) and more than the default.
        #expect(!ExerciseIllustrations.frameCounts.isEmpty)
        for (id, c) in ExerciseIllustrations.frameCounts {
            #expect(ExerciseIllustrations.ids.contains(id) && c > n && c % 2 == 1 && c <= 49, "\(id)")
        }
        #expect(ExerciseIllustrations.frameCount(of: "not-an-exercise") == 0)
    }

    @Test func illustrationAssetsExistInAppCatalog() throws {
        // Tests/WorkoutEngineTests → ios/
        let ios = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let assets = ios.appendingPathComponent("MonkeyWorkout/Resources/Illustrations.xcassets")
        for e in Exercise.catalog {
            let names = e.illustrationAssets
            #expect(names.count == (e.hasIllustration ? ExerciseIllustrations.liteFrameCount : 0), "\(e.id)")
            for name in names {
                let png = assets.appendingPathComponent("\(name).imageset/\(name).png")
                #expect(FileManager.default.fileExists(atPath: png.path), "\(png.path)")
            }
        }
        #expect(Exercise.get("back-squat").illustrationAssets == (0..<ExerciseIllustrations.liteFrameCount).map { "illustration-back-squat-\($0)" })
    }

    /// #932: every HD frame is in ios/HDAnimations (the downloaded pack); the light frames include start, middle, end.
    @Test func hdFramesAndLightFrames() {
        let ios = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let hd = ios.appendingPathComponent("HDAnimations")
        for id in ExerciseIllustrations.ids {
            let n = ExerciseIllustrations.frameCount(of: id)
            for f in 0..<n {
                #expect(FileManager.default.fileExists(atPath: hd.appendingPathComponent("\(id)/\(f).png").path), "\(id) \(f)")
            }
            #expect(!FileManager.default.fileExists(atPath: hd.appendingPathComponent("\(id)/\(n).png").path), "\(id) extra frame")
            let lite = ExerciseIllustrations.liteFrames(n)
            #expect(lite.count == ExerciseIllustrations.liteFrameCount && lite.first == 0 && lite.last == n - 1, "\(id)")
            #expect(zip(lite, lite.dropFirst()).allSatisfy { $0 < $1 }, "\(id)")
            #expect(ExerciseIllustrations.keyFrames(n).allSatisfy(lite.contains), "\(id)")
        }
        let squat = Exercise.get("back-squat").motion!
        let lite = squat.sampled(ExerciseIllustrations.liteFrames(ExerciseIllustrations.frameCount(of: "back-squat")))
        #expect(lite.points.count == ExerciseIllustrations.liteFrameCount && lite.points.first! == squat.points.first!)
    }

    /// #944: every illustrated exercise has its light movement clip in the app and its HD clip for the pack.
    @Test func everyIllustrationHasClips() {
        let ios = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let light = ios.appendingPathComponent("MonkeyWorkout/Resources/Motion")
        let hd = ios.appendingPathComponent("HDMotion")
        for id in ExerciseIllustrations.ids {
            #expect(FileManager.default.fileExists(atPath: light.appendingPathComponent("motion-\(id).mp4").path), "\(id)")
            #expect(FileManager.default.fileExists(atPath: hd.appendingPathComponent("\(id).mp4").path), "\(id)")
        }
    }

    @Test func everyIllustrationHasMotion() {
        for e in Exercise.catalog where e.hasIllustration {
            guard let m = e.motion else {
                Issue.record("\(e.id) has no motion")
                continue
            }
            #expect(m.path.isEmpty || m.points.count == ExerciseIllustrations.frameCount(of: e.id), "\(e.id)")
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

    @Test func playbackRunsRepsContinuously() {
        let p = MotionPlayback(frames: 9, cycles: 2, out: 1, back: 2, hold: 0.5)
        #expect(p.duration == 8)
        #expect(p.state(at: 0)?.position == 0)
        #expect(p.state(at: 0.5)?.position == 4)
        #expect(p.state(at: 0.5)?.outbound == true)
        #expect(p.state(at: 1.2)?.position == 8)
        #expect(p.state(at: 1.2)?.halfProgress == 1)
        #expect(p.state(at: 2.5)?.position == 4)
        #expect(p.state(at: 2.5)?.outbound == false)
        #expect(p.state(at: 4)?.rep == 2)
        #expect(p.state(at: 8) == nil)
        #expect(p.state(at: -0.1) == nil)
        // Position never jumps: sampled at 120 Hz it moves less than one frame per tick.
        var prev = 0.0
        for i in 0..<840 {
            let s = p.state(at: Double(i) / 120)!
            #expect(abs(s.position - prev) < 0.1)
            prev = s.position
        }
    }

    @Test func cyclicPlaybackWrapsForward() throws {
        // #719: a gait plays start → end every rep (its end is its start again), never back.
        let p = MotionPlayback(frames: 9, cycles: 2, out: 0.5, back: 0.5, hold: 0.35, cyclic: true)
        #expect(p.duration == 2)
        #expect(p.state(at: 0.5)?.position == 4)
        #expect((p.state(at: 0.999)?.position ?? 0) > 7.9)
        #expect(p.state(at: 1)?.position == 0 && p.state(at: 1)?.rep == 2)
        let walk = ExerciseMotion("STEP", "STRIDE", effortFirst: true, path: [], cyclic: true)
        let (a, b) = walk.phases(.strength)
        #expect(a.label == "STRIDE" && a == b && a.seconds * 2 == 1.2)
        for id in ["treadmill-run", "farmer-carry", "bike"] {
            let m = try #require(Exercise.get(id).motion)
            #expect(m.cyclic, "\(id)")
        }
        #expect(Exercise.get("back-squat").motion?.cyclic == false)
    }

    @Test func playbackLeadsInAndSettles() {
        let p = MotionPlayback(frames: 9, cycles: 1, out: 1, back: 1, hold: 0, from: 4, rest: 8, lead: 0.25, settle: 0.5)
        #expect(p.state(at: 0)?.position == 4)
        #expect(p.state(at: 0.25)?.position == 0)
        #expect(abs(p.duration - 2.75) < 1e-9)
        #expect(abs((p.state(at: 2.749)?.position ?? 0) - 8) < 0.05)
    }

    @Test func playbackBlend() {
        for (p, frames, lower, upper) in [(0.0, 9, 0, 0.0), (2.25, 9, 2, 0.25), (8, 9, 8, 0), (12, 9, 8, 0), (0.5, 1, 0, 0)] {
            let b = MotionPlayback.blend(p, frames: frames)
            #expect(b.lower == lower && b.upper == upper, "\(p)")
        }
        // Quick switch: held most of the step, then a short smooth dissolve.
        #expect(MotionPlayback.blend(2.5, frames: 9, window: 0.2).upper == 0)
        #expect(abs(MotionPlayback.blend(2.9, frames: 9, window: 0.2).upper - 0.5) < 1e-9)
        #expect(MotionPlayback.blend(2.999, frames: 9, window: 0.2).upper > 0.99)
    }

    @Test func playbackAsClipPieces() {
        // #944: start → end from the clip's first half, holds as one frame, the way back from its second half.
        let p = MotionPlayback(frames: 17, cycles: 1, out: 1, back: 2, hold: 0.5)
        let pieces = p.clipPieces(frames: 17, clipFrames: 61)
        #expect(pieces == [
            .init(start: 0, length: 60, duration: 1), .init(start: 60, length: 1, duration: 0.5),
            .init(start: 60, length: 60, duration: 2), .init(start: 120, length: 1, duration: 0.5),
        ])
        #expect(pieces.reduce(0) { $0 + $1.duration } == p.duration)
        // A glide in from the middle frame back to the start plays the second half too.
        let lead = MotionPlayback(frames: 3, cycles: 1, out: 1, back: 1, hold: 0, from: 1).clipPieces(frames: 3, clipFrames: 61)
        #expect(lead.first == .init(start: 90, length: 30, duration: 0.25))
        // A gait only plays forward.
        let walk = MotionPlayback(frames: 9, cycles: 2, out: 0.5, back: 0.5, hold: 0.35, cyclic: true).clipPieces(frames: 9)
        #expect(walk == Array(repeating: .init(start: 0, length: 60, duration: 1), count: 2))
    }
}
