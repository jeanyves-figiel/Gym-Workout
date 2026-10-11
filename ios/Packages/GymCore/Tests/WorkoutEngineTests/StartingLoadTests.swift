import Foundation
import Testing
@testable import WorkoutEngine

private let bench = Exercise.get("bench-press")
private let incline = Exercise.get("incline-bench-press")
private let dbBench = Exercise.get("db-bench")
private let squat = Exercise.get("back-squat")
private let pullUp = Exercise.get("pull-up")
private let pulldown = Exercise.get("lat-pulldown")
private let plank = Exercise.get("plank")

private func rx(_ reps: String, rpe: Int? = 8) -> Prescription {
    Prescription(sets: 4, reps: reps, restSec: 120, intensity: rpe.map { "RPE \($0)" })
}

private func benchSession(_ kg: Double, _ reps: Int, day: Double = 0) -> ExerciseSession {
    let date = Date(timeIntervalSince1970: 1_790_000_000 + day * 86_400)
    let sets = (0..<3).map { SetLog(date: date, exerciseId: "bench-press", sessionId: "w1s1", setIndex: $0, kg: kg, reps: reps) }
    return ExerciseSession(date: date, sessionId: "w1s1", week: 1, deload: false, sets: sets)
}

@Suite struct StartingLoadTests {
    @Test func estimateIsConservativeAndRounded() throws {
        let s = try #require(StartingLoad.estimate(exercise: bench, prescription: rx("5–8", rpe: 7),
                                                   athlete: Athlete(bodyKg: 80, sex: .male, age: 30, experience: .intermediate)))
        #expect(s.source == .estimate)
        #expect(s.reps == 5)
        // 80 kg × 1.0 → 1RM 80; 5 reps + 3 RIR → ~63; −15 % → ~53 → 52.5 on a 2.5 kg step.
        #expect(s.kg == 52.5)
        #expect(s.kg.truncatingRemainder(dividingBy: 2.5) == 0)
    }

    @Test func levelSexAndAgeLowerTheLoad() throws {
        let rxBench = rx("8–10")
        let inter = try #require(StartingLoad.estimate(exercise: bench, prescription: rxBench, athlete: Athlete(bodyKg: 80, sex: .male, experience: .intermediate)))
        let beginner = try #require(StartingLoad.estimate(exercise: bench, prescription: rxBench, athlete: Athlete(bodyKg: 80, sex: .male, experience: .beginner)))
        let female = try #require(StartingLoad.estimate(exercise: bench, prescription: rxBench, athlete: Athlete(bodyKg: 80, sex: .female, experience: .intermediate)))
        let older = try #require(StartingLoad.estimate(exercise: bench, prescription: rxBench, athlete: Athlete(bodyKg: 80, sex: .male, age: 65, experience: .intermediate)))
        #expect(beginner.kg < inter.kg)
        #expect(female.kg < inter.kg)
        #expect(older.kg < inter.kg)
    }

    @Test func barbellNeverBelowTheEmptyBar() throws {
        let s = try #require(StartingLoad.estimate(exercise: bench, prescription: rx("12–15"), athlete: Athlete(bodyKg: 45, sex: .female, age: 70)))
        #expect(s.kg >= 20)
    }

    @Test func dumbbellsArePerHandAndLighter() throws {
        let a = Athlete(bodyKg: 80, sex: .male, experience: .intermediate)
        let bar = try #require(StartingLoad.estimate(exercise: bench, prescription: rx("8–10"), athlete: a))
        let db = try #require(StartingLoad.estimate(exercise: dbBench, prescription: rx("8–10"), athlete: a))
        #expect(db.kg < bar.kg / 2)
        #expect(db.kg >= 2)
    }

    @Test func noEstimateForBodyweightOrTimedWork() {
        let a = Athlete(bodyKg: 80)
        #expect(StartingLoad.estimate(exercise: pullUp, prescription: rx("5–8"), athlete: a) == nil)
        #expect(StartingLoad.estimate(exercise: plank, prescription: rx("30 s"), athlete: a) == nil)
        #expect(StartingLoad.estimate(exercise: pulldown, prescription: rx("8–10"), athlete: a) != nil)
    }

    @Test func missingBodyWeightUsesDefault() throws {
        let s = try #require(StartingLoad.estimate(exercise: squat, prescription: rx("5"), athlete: Athlete()))
        #expect(s.kg >= 20)
        #expect(s.reason.contains("70 kg"))
    }

    @Test func relatedExerciseBeatsBodyWeight() throws {
        // Bench 80 × 5 → 1RM ~93; incline (same kit, −10 %) ~84; 5 reps + 3 RIR → ~66 → 65.
        let s = try #require(StartingLoad.fromRelated(exercise: incline, prescription: rx("5–8", rpe: 7),
                                                      related: [(bench, [benchSession(70, 5), benchSession(80, 5, day: 7)])]))
        #expect(s.source == .related)
        #expect(s.kg == 65)
        #expect(s.reason.contains("bench press"))
    }

    @Test func relatedConvertsBarbellToDumbbell() throws {
        let s = try #require(StartingLoad.fromRelated(exercise: dbBench, prescription: rx("8–10"), related: [(bench, [benchSession(80, 5)])]))
        #expect(s.kg < 30)
        #expect(s.kg > 10)
    }

    @Test func relatedIgnoresItselfAndOtherPatterns() {
        #expect(StartingLoad.fromRelated(exercise: bench, prescription: rx("5"), related: [(bench, [benchSession(80, 5)])]) == nil)
        #expect(StartingLoad.fromRelated(exercise: squat, prescription: rx("5"), related: [(bench, [benchSession(80, 5)])]) == nil)
    }
}
