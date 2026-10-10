import Foundation
import Testing
@testable import WorkoutEngine

private let bench = Exercise.get("bench-press")
private let day0 = ISO8601DateFormatter().date(from: "2026-09-07T10:00:00Z")!

private func log(_ kg: Double, _ reps: Int, day: Int = 0, exercise: String = "bench-press") -> SetLog {
    SetLog(date: day0.addingTimeInterval(Double(day) * 86_400), exerciseId: exercise, sessionId: "w1s\(day)", setIndex: 0, kg: kg, reps: reps)
}

@Suite struct PRPlannerTests {
    @Test func kindsDependOnLoad() {
        #expect(PRPlanner.kinds(for: bench) == [.oneRepMax, .repMax, .maxReps])
        #expect(PRPlanner.kinds(for: Exercise.get("pull-up")) == [.maxReps])
        #expect(PRPlanner.kinds(for: Exercise.get("weighted-pull-up")) == [.oneRepMax, .repMax, .maxReps])
        #expect(PRPlanner.kinds(for: Exercise.get("plank")).isEmpty)
    }

    @Test func oneRepMaxTargetBeatsBestSingleOrEstimate() {
        // 80 × 5 → e1RM 93.3 → 92.5 single, above the 85 kg best single + 2.5.
        let p = PRPlanner.plan(exercise: bench, kind: .oneRepMax, logs: [log(80, 5), log(85, 1, day: 1)], attempts: [])
        #expect(p.kg == 92.5)
        #expect(p.best == 85)
        #expect(p.reps == 1)
        // Best single 95 > estimate → best + one increment.
        let q = PRPlanner.plan(exercise: bench, kind: .oneRepMax, logs: [log(80, 5), log(95, 1, day: 1)], attempts: [])
        #expect(q.kg == 97.5)
        #expect(q.safety.contains("spotter"))
    }

    @Test func repMaxUsesInverseEpley() {
        let p = PRPlanner.plan(exercise: bench, kind: .repMax, reps: 5, logs: [log(90, 1)], attempts: [])
        // 90 × 1 → 1RM 90 → 5RM ≈ 77.1 → 75 (rounded down); no 5-rep set yet.
        #expect(p.kg == 75)
        #expect(p.best == nil)
    }

    @Test func maxRepsGoalBeatsBest() {
        let p = PRPlanner.plan(exercise: Exercise.get("pull-up"), kind: .maxReps,
                               logs: [log(0, 9, exercise: "pull-up"), log(0, 11, day: 1, exercise: "pull-up")], attempts: [])
        #expect(p.kg == 0)
        #expect(p.reps == 12)
        #expect(p.ramp.isEmpty)
    }

    @Test func rampIsIncreasingAboveEmptyBarAndBelowTarget() {
        let r = PRPlanner.ramp(to: 100, kind: .oneRepMax, exercise: bench)
        #expect(r.map(\.kg) == [40, 55, 70, 80, 90])
        let light = PRPlanner.ramp(to: 30, kind: .oneRepMax, exercise: bench)
        #expect(light.first?.kg == 20)
        #expect(zip(light, light.dropFirst()).allSatisfy { $0.kg < $1.kg })
        #expect(light.allSatisfy { $0.kg < 30 })
    }

    @Test func finishDetectsRecords() {
        let sets = [PRSet(kg: 40, reps: 8, warmup: true), PRSet(kg: 92.5, reps: 1), PRSet(kg: 95, reps: 1, made: false)]
        let a = PRPlanner.finish(exerciseId: "bench-press", kind: .oneRepMax, targetReps: 1, sets: sets, previousBest: 90)
        #expect(a.kg == 92.5)
        #expect(a.success && a.isRecord)
        let missed = PRPlanner.finish(exerciseId: "bench-press", kind: .oneRepMax, targetReps: 1,
                                      sets: [PRSet(kg: 95, reps: 1, made: false)], previousBest: 90)
        #expect(!missed.success && !missed.isRecord)
        let same = PRPlanner.finish(exerciseId: "bench-press", kind: .oneRepMax, targetReps: 1, sets: [PRSet(kg: 90, reps: 1)], previousBest: 90)
        #expect(same.success && !same.isRecord)
        let reps = PRPlanner.finish(exerciseId: "pull-up", kind: .maxReps, targetReps: nil, sets: [PRSet(kg: 0, reps: 13)], previousBest: 12)
        #expect(reps.isRecord && reps.reps == 13 && reps.label == "Max reps")
    }

    @Test func recordsKeepLatestPerLabelAndAttemptsCount() {
        let a = PRPlanner.finish(exerciseId: "bench-press", kind: .oneRepMax, targetReps: 1, sets: [PRSet(kg: 90, reps: 1)], previousBest: nil, date: day0)
        let b = PRPlanner.finish(exerciseId: "bench-press", kind: .oneRepMax, targetReps: 1, sets: [PRSet(kg: 92.5, reps: 1)], previousBest: 90,
                                 date: day0.addingTimeInterval(86_400))
        let c = PRPlanner.finish(exerciseId: "bench-press", kind: .repMax, targetReps: 5, sets: [PRSet(kg: 80, reps: 5)], previousBest: nil, date: day0)
        #expect(PRPlanner.records([a, b, c]).map(\.label) == ["1RM", "5RM"])
        #expect(PRPlanner.records([a, b, c]).first?.kg == 92.5)
        #expect(PRPlanner.bestKg(forReps: 1, logs: [], attempts: [a, b]) == 92.5)
        #expect(PRPlanner.isPRSession(b.sessionId))
        #expect(!PRPlanner.isPRSession("w1s1"))
    }

    @Test func attemptRoundTripsThroughJSON() throws {
        let a = PRPlanner.finish(exerciseId: "bench-press", kind: .repMax, targetReps: 3, sets: [PRSet(kg: 85, reps: 3)], previousBest: 82.5)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let json = try enc.encode(a)
        let obj = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        #expect(obj?["kind"] as? String == "repMax")
        #expect(obj?["isRecord"] as? Bool == true)
        let back = try dec.decode(PRAttempt.self, from: json)
        #expect(back.kg == 85 && back.targetReps == 3)
    }
}
