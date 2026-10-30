import Foundation
import Testing
@testable import WorkoutEngine

/// Film my workout (#952): the move named from made-up camera frames, sets ending on rest, weights read off print.
@Suite struct FilmWorkoutTests {
    private func models(_ ids: [String]) -> [FormModel] {
        ids.compactMap { FormModel(exercise: Exercise.get($0)) }
    }

    private func frames(_ id: String, reps: Int) throws -> [FilmWorkout.Frame] {
        let m = try #require(FormModel(exercise: Exercise.get(id)))
        return FormDemo.frames(m, reps: reps).map { (time: $0.0, pose: Optional($0.1)) }
    }

    @Test func squatFramesAreNamedSquatFirst() throws {
        let all = models(["back-squat", "db-curl", "bench-press", "push-up"])
        #expect(all.count >= 2)
        let g = FilmWorkout.guess(try frames("back-squat", reps: 3), models: all)
        let top = try #require(g.first)
        #expect(top.exerciseId == "back-squat", "\(g)")
        #expect(top.reps == 3)
        #expect(g.count <= 3)
        #expect(g.map(\.confidence).reduce(0, +) <= 101)
    }

    @Test func noMovementNoGuess() {
        let still: [FilmWorkout.Frame] = (0..<90).map { (time: Double($0) / 30, pose: nil) }
        #expect(FilmWorkout.guess(still, models: models(["back-squat"])).isEmpty)
    }

    @Test func plannedMoveGetsTheEdge() throws {
        let all = models(["back-squat", "db-curl", "bench-press", "push-up"])
        let f = try frames("back-squat", reps: 3)
        let plain = FilmWorkout.guess(f, models: all)
        let planned = FilmWorkout.guess(f, models: all, planned: ["back-squat"])
        let a = try #require(plain.first), b = try #require(planned.first)
        #expect(b.exerciseId == "back-squat")
        #expect(b.confidence >= a.confidence)
    }

    @Test func setEndsAfterRest() {
        #expect(!FilmWorkout.setEnded(reps: 0, lastRepAt: nil, now: 30))
        #expect(!FilmWorkout.setEnded(reps: 5, lastRepAt: 10, now: 14))
        #expect(FilmWorkout.setEnded(reps: 5, lastRepAt: 10, now: 10 + FilmWorkout.restAfter))
    }

    @Test func weightReadOffPrint() {
        typealias S = WeightReading.Seen
        #expect(WeightReading.kg(from: [S("22.5 KG")]) == 22.5)
        #expect(WeightReading.kg(from: [S("22,5kg")]) == 22.5)
        #expect(WeightReading.kg(from: [S("50 LB")]) == 22.5)
        #expect(WeightReading.kg(from: [S("45 lbs")]) == 20.5)
        #expect(WeightReading.kg(from: [S("20")]) == 20)
        // A unit beats a bigger bare number; bigger print beats smaller.
        #expect(WeightReading.kg(from: [S("2024", size: 0.2), S("16 kg", size: 0.03)]) == 16)
        #expect(WeightReading.kg(from: [S("10", size: 0.02), S("24", size: 0.1)]) == 24)
        // Not weights: odd decimals, years, nothing.
        #expect(WeightReading.kg(from: [S("12.37")]) == nil)
        #expect(WeightReading.kg(from: [S("1999")]) == nil)
        #expect(WeightReading.kg(from: [S("Gym")]) == nil)
        #expect(WeightReading.kg(from: []) == nil)
    }

    @Test func movesSummariseTheirSets() {
        let m = FilmedMove(exerciseId: "back-squat", sets: [
            FilmedSet(reps: 8, kg: 60, form: 90), FilmedSet(reps: 8, kg: 60, form: 80), FilmedSet(reps: 8, kg: 60),
        ])
        #expect(m.summary == "3×8 · 60 kg")
        #expect(m.form == 85)
        #expect(FilmedMove(exerciseId: "push-up", sets: [FilmedSet(reps: 12, kg: 0)]).summary == "1×12")
        #expect(FilmedMove(exerciseId: "push-up").summary == "No sets")
    }
}
