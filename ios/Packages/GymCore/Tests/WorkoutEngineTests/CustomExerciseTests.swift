import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct CustomExerciseTests {
    private func abductor(archived: Bool = false) -> CustomExercise {
        CustomExercise(
            name: "  Technogym abductor  ", category: .strength, primary: [.glutes, .glutes], secondary: [.glutes, .adductors],
            machine: " Technogym Selection 700 ", unit: .reps, cues: ["Slow return", "  "], archived: archived)
    }

    @Test func sanitizedAndExerciseShape() {
        let c = abductor().sanitized
        #expect(c.name == "Technogym abductor")
        #expect(c.primary == [.glutes])
        #expect(c.secondary == [.adductors])
        #expect(c.machine == "Technogym Selection 700")
        #expect(c.cues == ["Slow return"])
        #expect(c.isComplete)
        #expect(!CustomExercise(name: "x").isComplete)

        let e = c.exercise
        #expect(e.id == c.exerciseId)
        #expect(e.id.hasPrefix("user-"))
        #expect(CustomExercise.isCustom(e.id))
        #expect(!CustomExercise.isCustom("back-squat"))
        #expect(!e.generator)
        #expect(e.unit == nil)
        var timed = c
        timed.unit = .sec
        #expect(timed.exercise.unit == .sec)
        #expect(CustomWorkout.Measure(timed.exercise) == .seconds)
    }

    @Test func oversizedPhotoDropped() {
        var c = abductor()
        c.photo = Data(count: CustomExercise.maxPhotoBytes + 1)
        #expect(c.sanitized.photo == nil)
        c.photo = Data(count: 10)
        #expect(c.sanitized.photo?.count == 10)
    }

    @Test func codableRoundTripAndLenientDecoding() throws {
        var c = abductor().sanitized
        c.photo = Data([1, 2, 3])
        c.drawing = ExerciseDrawing(template: .seated)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(CustomExercise.self, from: enc.encode(c))
        #expect(back.id == c.id)
        #expect(back.photo == c.photo)
        #expect(back.drawing == c.drawing)
        #expect(back.primary == c.primary)

        let json = #"{"id":"\#(UUID().uuidString)","name":"Old","primary":["glutes","wings"],"equipment":["bench","teleporter"],"category":"yoga"}"#
        let old = try dec.decode(CustomExercise.self, from: Data(json.utf8))
        #expect(old.primary == [.glutes])
        #expect(old.equipment == [.bench])
        #expect(old.category == .strength)
        #expect(old.unit == .reps)
        #expect(!old.archived)
    }

    @Test func registryFindAndSearch() {
        let registry = CustomExercises()
        let live = abductor().sanitized
        var gone = abductor().sanitized
        gone.id = UUID()
        gone.name = "Old machine"
        gone.archived = true
        registry.replaceAll([live, gone])

        #expect(Exercise.find(live.exerciseId, custom: registry)?.name == "Technogym abductor")
        // Archived stays resolvable for history, but is hidden from search.
        #expect(Exercise.find(gone.exerciseId, custom: registry)?.name == "Old machine")
        #expect(registry.active.map(\.id) == [live.exerciseId])
        #expect(Exercise.search("selection", custom: registry).map(\.id) == [live.exerciseId])
        #expect(Exercise.search(custom: registry).count == Exercise.catalog.count + 1)
        #expect(Exercise.search("old machine", custom: registry).isEmpty)
        #expect(Exercise.find(live.exerciseId, custom: CustomExercises()) == nil)
        #expect(Exercise.find("back-squat", custom: registry)?.id == "back-squat")
    }

    @Test func templatesFitTheFrame() {
        for t in PoseTemplate.allCases {
            let d = ExerciseDrawing(template: t).normalized
            #expect(d.frames.count == 2)
            for f in d.frames {
                for (joint, p) in FigureGeometry.placed(f) {
                    #expect(p.x > 0 && p.x < FigureGeometry.width, "\(t) \(joint) x \(p.x)")
                    #expect(p.y > -40 && p.y <= FigureGeometry.floor + 1, "\(t) \(joint) y \(p.y)")
                }
            }
        }
    }

    @Test func draggingAJointRotatesItsSegment() {
        var p = FigurePose()
        let before = FigureGeometry.joints(p)
        p.setAngle(0, for: .elbowN)
        let after = FigureGeometry.joints(p)
        // Upper arm now points right; forearm keeps its bend relative to it.
        #expect(abs(after[.elbowN]!.y - after[.shoulder]!.y) < 0.001)
        #expect(abs((p.foreN - p.upperN) - 0) < 0.001)
        #expect(after[.kneeN] == before[.kneeN])
        p.setAngle(-90, for: .wristN)
        #expect(p.foreN == -90)
        #expect(FigureGeometry.angle(from: Point2(0, 0), to: Point2(0, -5)) == -90)
        #expect(FigureHighlight.segments(for: [.quads, .hamstrings, .chest]) == [.thigh, .torso])
    }
}
