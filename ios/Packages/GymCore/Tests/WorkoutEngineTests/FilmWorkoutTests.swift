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

    /// One set of `id` from `t0`: getting into the start position and holding it a moment, the reps, then `rest`
    /// seconds standing still at the start position. Returns the end time.
    @discardableResult
    private func set(_ s: inout FilmSession, _ id: String, reps: Int, from t0: Double, rest: Double = 8,
                     events: inout [FilmSession.Event]) throws -> Double {
        let m = try model(id)
        let still = FormDemo.pose(m, progress: 0)
        let lead = 1.2
        for k in 0..<Int(lead * 30) {
            if let e = s.add(still, at: t0 + Double(k) / 30) { events.append(e) }
        }
        let frames = FormDemo.frames(m, reps: reps)
        var t = t0 + lead
        var named = false
        for (dt, p) in frames {
            t = t0 + lead + dt
            if let e = s.add(p, at: t) { events.append(e) }
            // The app names the move as soon as enough frames wait (here: once, after the frames of 2+ reps).
            if !named, s.needsGuess, dt > 2 * 3.0 + 1 {
                if let e = s.accept(FilmWorkout.guess(s.pending, models: models, current: s.moves.last?.exerciseId)) { events.append(e) }
                named = s.inSet
            }
        }
        if !named, let e = s.accept(FilmWorkout.guess(s.pending, models: models, current: s.moves.last?.exerciseId)) { events.append(e) }
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

    @Test func enteredWeightFillsTheSetsWithoutOne() {
        var s = FilmSession()
        var m = FilmSession.Move(exerciseId: "back-squat")
        m.sets = [FilmedSet(reps: 5, kg: 0), FilmedSet(reps: 5, kg: 80)]
        s.moves = [m]
        s.enter(kg: 60, move: 0)
        #expect(s.moves[0].kg == 60)
        #expect(s.moves[0].sets.map(\.kg) == [60, 80])
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

/// Better detection (#969): moves named and reps counted from any camera spot, in-frame guidance, weight only when needed.
@Suite struct FilmDetectTests {
    private static let names: [(FormJoint, String)] = [
        (.nose, "head"), (.neck, "neck"), (.leftShoulder, "shoulderN"), (.rightShoulder, "shoulderF"),
        (.leftElbow, "elbowN"), (.rightElbow, "elbowF"), (.leftWrist, "wristN"), (.rightWrist, "wristF"),
        (.leftHip, "hipN"), (.rightHip, "hipF"), (.leftKnee, "kneeN"), (.rightKnee, "kneeF"),
        (.leftAnkle, "ankleN"), (.rightAnkle, "ankleF"),
    ]

    /// `id`'s guide between its start and main position, in 3D, filmed from the front (the picture shows z and y).
    private func frontPose(_ id: String, progress p: Double) throws -> FormPose {
        let pos = try #require(Exercise.get(id).position)
        let a = pos.keys[0], b = pos.keys[pos.mainKey]
        var world: [FormJoint: SIMD3<Double>] = [:]
        var picture: [FormJoint: SIMD2<Double>] = [:]
        for (j, n) in Self.names {
            guard let x = a[n], let y = b[n] else { continue }
            let v = x + (y - x) * p
            world[j] = v
            picture[j] = SIMD2(v.z, v.y)
        }
        return FormPose(picture, world: world)
    }

    /// `reps` reps from the front at 30 fps: 0.6 s still, then 2.4 s down and up per rep.
    private func frontFrames(_ id: String, reps: Int) throws -> [FilmWorkout.Frame] {
        var out: [FilmWorkout.Frame] = []
        var t = 0.0
        while t <= Double(reps) * 3 + 0.6 {
            let inRep = t.truncatingRemainder(dividingBy: 3) - 0.6
            let p = inRep > 0 && Int(t / 3) < reps ? (1 - cos(2 * .pi * inRep / 2.4)) / 2 : 0
            out.append((time: t, pose: try frontPose(id, progress: p)))
            t += 1.0 / 30
        }
        return out
    }

    private let models = ["back-squat", "db-curl", "bench-press", "push-up"].compactMap { FormModel(exercise: Exercise.get($0)) }

    @Test func squatFilmedFromTheFrontIsNamed() throws {
        let g = FilmWorkout.guess(try frontFrames("back-squat", reps: 3), models: models)
        let top = try #require(g.first)
        #expect(top.exerciseId == "back-squat", "\(g)")
        #expect(top.reps == 3)
    }

    @Test func curlFilmedFromTheFrontIsNamedAndCounted() throws {
        let f = try frontFrames("db-curl", reps: 4)
        let top = try #require(FilmWorkout.guess(f, models: models).first)
        #expect(top.exerciseId == "db-curl")
        var c = try #require(MoveCounter(exercise: Exercise.get("db-curl")))
        for x in f { c.add(x.pose, at: x.time) }
        #expect(c.reps.count == 4)
    }

    @Test func ownMovementCountsWithoutAModel() throws {
        var r = RepTracker(joint: .knee)
        for x in try frontFrames("back-squat", reps: 5) { r.add(x.pose, at: x.time) }
        #expect(r.count == 5)
        #expect(r.range > 40)
        // Twitches and still frames are not reps.
        var still = RepTracker(joint: .knee)
        let p = try frontPose("back-squat", progress: 0)
        for k in 0..<120 { still.add(p, at: Double(k) / 30) }
        #expect(still.count == 0)
    }

    @Test func frameCheckSaysWhatToMove() {
        func body(dx: Double = 0, scale: Double = 0.8, feet: Bool = true) -> FormPose {
            var p: [FormJoint: SIMD2<Double>] = [
                .nose: SIMD2(0.28, 0.9), .neck: SIMD2(0.28, 0.82), .leftShoulder: SIMD2(0.22, 0.8), .rightShoulder: SIMD2(0.34, 0.8),
                .leftWrist: SIMD2(0.18, 0.5), .rightWrist: SIMD2(0.38, 0.5), .leftHip: SIMD2(0.25, 0.5), .rightHip: SIMD2(0.31, 0.5),
                .leftKnee: SIMD2(0.25, 0.3), .rightKnee: SIMD2(0.31, 0.3),
            ]
            if feet { p[.leftAnkle] = SIMD2(0.25, 0.1); p[.rightAnkle] = SIMD2(0.31, 0.1) }
            return FormPose(p.mapValues { SIMD2(0.28 + ($0.x - 0.28) * scale / 0.8 + dx, 0.5 + ($0.y - 0.5) * scale / 0.8) })
        }
        let a = 9.0 / 16
        #expect(FrameCheck.issue(nil, aspect: a, mirrored: true) == .nobody)
        #expect(FrameCheck.issue(body(), aspect: a, mirrored: true) == nil)
        #expect(FrameCheck.issue(body(feet: false), aspect: a, mirrored: true) == .feetCut)
        #expect(FrameCheck.issue(body(scale: 1.3), aspect: a, mirrored: true) == .tooClose)
        #expect(FrameCheck.issue(body(scale: 0.2), aspect: a, mirrored: true) == .tooFar)
        // Off the picture's right: a mirror shows the member's right there, so they move left; the back camera the other way.
        #expect(FrameCheck.issue(body(dx: 0.25), aspect: a, mirrored: true) == .moveLeft)
        #expect(FrameCheck.issue(body(dx: 0.25), aspect: a, mirrored: false) == .moveRight)
    }

    @Test func weightAskedOnlyWhenNeeded() {
        #expect(FilmWorkout.needsWeight("back-squat", kg: nil))
        #expect(!FilmWorkout.needsWeight("back-squat", kg: 60))
        #expect(!FilmWorkout.needsWeight("push-up", kg: nil))
    }

    @Test func barInTheHandsTellsBarFromDumbbells() {
        func frame(_ t: Double, gap: Double) -> FilmWorkout.Frame {
            (time: t, pose: FormPose([.leftShoulder: SIMD2(0.4, 0.8), .rightShoulder: SIMD2(0.6, 0.8),
                                      .leftWrist: SIMD2(0.5 - gap / 2, 0.5 + t / 10), .rightWrist: SIMD2(0.5 + gap / 2, 0.5 + t / 10)]))
        }
        #expect(KitHint((0..<30).map { frame(Double($0) / 30, gap: 0.3) }) == .bar)
        #expect(KitHint((0..<30).map { frame(Double($0) / 30, gap: 0.2 + Double($0 % 10) / 20) }) == .free)
        #expect(KitHint.bar.nudge([.barbell]) > 0)
        #expect(KitHint.bar.nudge([.dumbbells]) < 0)
    }
}
