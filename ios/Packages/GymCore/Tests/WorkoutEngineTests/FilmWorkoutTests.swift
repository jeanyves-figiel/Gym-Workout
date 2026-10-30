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

/// Film whole session (#957): sets and moves found with no tap, from made-up frames.
@Suite struct FilmSessionTests {
    private let models = ["back-squat", "db-curl", "bench-press", "push-up"].compactMap { FormModel(exercise: Exercise.get($0)) }

    private func model(_ id: String) throws -> FormModel { try #require(FormModel(exercise: Exercise.get(id))) }

    /// One set of `id` from `t0`, then `rest` seconds standing still at the start position. Returns the end time.
    @discardableResult
    private func set(_ s: inout FilmSession, _ id: String, reps: Int, from t0: Double, rest: Double = 8,
                     events: inout [FilmSession.Event]) throws -> Double {
        let m = try model(id)
        let frames = FormDemo.frames(m, reps: reps)
        var t = t0
        var named = false
        for (dt, p) in frames {
            t = t0 + dt
            if let e = s.add(p, at: t) { events.append(e) }
            // The app names the move as soon as enough frames wait (here: once, after the frames of 2+ reps).
            if !named, s.needsGuess, dt > 2 * 3.0 + 1 {
                if let e = s.accept(FilmWorkout.guess(s.pending, models: models, current: s.moves.last?.exerciseId)) { events.append(e) }
                named = s.inSet
            }
        }
        if !named, let e = s.accept(FilmWorkout.guess(s.pending, models: models, current: s.moves.last?.exerciseId)) { events.append(e) }
        let still = FormDemo.pose(m, progress: 0)
        for k in 1...Int(rest * 30) {
            if let e = s.add(still, at: t + Double(k) / 30) { events.append(e) }
        }
        return t + rest
    }

    @Test func setsAndMovesAreFoundWithoutATap() throws {
        var s = FilmSession()
        var ev: [FilmSession.Event] = []
        var t = try set(&s, "back-squat", reps: 3, from: 0, events: &ev)
        t = try set(&s, "back-squat", reps: 4, from: t, events: &ev)
        try set(&s, "push-up", reps: 3, from: t, events: &ev)
        #expect(s.moves.map(\.exerciseId) == ["back-squat", "push-up"], "\(s.moves.map(\.exerciseId))")
        #expect(s.moves.first?.sets.map(\.reps) == [3, 4])
        #expect(s.moves.last?.sets.map(\.reps) == [3])
        #expect(ev.first == .newMove(0))
        #expect(ev.contains(.sameMove(0)))
        #expect(ev.contains(.newMove(1)))
        #expect(ev.contains(.setLogged(move: 0, set: 2, reps: 4)))
        #expect(s.filmed.count == 2)
    }

    @Test func weightReadAtRestGoesToTheNextSet() throws {
        var s = FilmSession()
        var ev: [FilmSession.Event] = []
        s.read(kg: 60)
        let t = try set(&s, "back-squat", reps: 3, from: 0, events: &ev)
        #expect(s.moves.first?.kg == 60)
        #expect(s.moves.first?.kgRead == true)
        s.read(kg: 70)
        try set(&s, "back-squat", reps: 3, from: t, events: &ev)
        #expect(s.moves.first?.sets.map(\.kg) == [60, 70])
        s.fill(kg: 10, move: 0)
        #expect(s.moves.first?.kg == 70, "history never overrides a read weight")
    }

    @Test func movingThePhoneEndsTheSetAndPauses() throws {
        var s = FilmSession()
        var ev: [FilmSession.Event] = []
        try set(&s, "back-squat", reps: 3, from: 0, rest: 1, events: &ev)
        #expect(s.inSet)
        #expect(s.pause() == .setLogged(move: 0, set: 1, reps: 3))
        #expect(s.paused)
        #expect(s.add(nil, at: 100) == nil)
        #expect(s.pending.isEmpty)
        s.resume()
        #expect(!s.paused)
    }

    @Test func watchRejectSwapsToTheNextAlternative() {
        var s = FilmSession()
        s.moves = [FilmSession.Move(exerciseId: "db-curl", alternatives: ["barbell-curl", "hammer-curl"], sure: false)]
        s.reject(0)
        #expect(s.moves[0].exerciseId == "barbell-curl")
        #expect(s.moves[0].alternatives == ["hammer-curl", "db-curl"])
        #expect(s.moves[0].sure)
        s.confirm(0)
        #expect(s.moves[0].sure)
    }
}
