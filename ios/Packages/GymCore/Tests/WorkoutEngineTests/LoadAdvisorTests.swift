import Foundation
import Testing
@testable import WorkoutEngine

private let utc = Progression.calendar(TimeZone(identifier: "UTC")!)
private let day0 = ISO8601DateFormatter().date(from: "2026-09-07T10:00:00Z")!
private let squat = Exercise.get("back-squat")
private let goblet = Exercise.get("goblet-squat")
private let legPress = Exercise.get("leg-press")

private func rx(_ reps: String, sets: Int = 3, rpe: Int? = 8) -> Prescription {
    Prescription(sets: sets, reps: reps, restSec: 120, intensity: rpe.map { "RPE \($0)" })
}

/// One session of `reps` (one entry per set) at `kg`.
private func session(_ kg: Double, _ reps: [Int], rir: Int? = nil, day: Int = 0, week: Int? = 1, deload: Bool = false,
                     exercise: String = "back-squat") -> ExerciseSession {
    let date = day0.addingTimeInterval(Double(day) * 86_400)
    let sets = reps.enumerated().map { i, r in
        SetLog(date: date.addingTimeInterval(Double(i) * 180), exerciseId: exercise, sessionId: "w1s1", setIndex: i, kg: kg, reps: r, rir: rir)
    }
    return ExerciseSession(date: date, sessionId: "w1s1", week: week, deload: deload, sets: sets)
}

@Suite struct RepRangeTests {
    @Test func parsesRangesAndSingles() {
        #expect(rx("8–10").repRange == RepRange(low: 8, high: 10))
        #expect(rx("8-10").repRange == RepRange(low: 8, high: 10))
        #expect(rx("5").repRange == RepRange(low: 5, high: 5))
        #expect(rx("12–15 / side").repRange == RepRange(low: 12, high: 15))
        #expect(rx("30–45 s").repRange == nil)
        #expect(rx("4 min").repRange == nil)
        #expect(rx("40 s").repRange == nil)
    }

    @Test func targetRIRFromRPE() {
        #expect(rx("8–10", rpe: 8).targetRIR == 2)
        #expect(rx("8–10", rpe: nil).targetRIR == nil)
    }

    @Test func formatsKg() {
        #expect(LoadAdvisor.formatKg(80) == "80")
        #expect(LoadAdvisor.formatKg(82.5) == "82.5")
        #expect(LoadAdvisor.formatKg(101.25) == "101.25")
        #expect(LoadAdvisor.formatKg(0) == "0")
    }
}

@Suite struct LoadAdvisorTests {
    @Test func noHistoryNoSuggestion() {
        #expect(LoadAdvisor.suggest(exercise: squat, prescription: rx("8–10"), week: 2, deload: false, history: []) == nil)
    }

    @Test func allSetsAtTopAddsBarbellIncrement() throws {
        let s = try #require(LoadAdvisor.suggest(exercise: squat, prescription: rx("8–10"), week: 2, deload: false,
                                                 history: [session(80, [10, 10, 10])]))
        #expect(s.action == .increase)
        #expect(s.kg == 82.5)
        #expect(s.reps == 8)
        #expect(s.deltaKg == 2.5)
    }

    @Test func veryEasySetsJumpTwoIncrementsExceptInBaseWeek() throws {
        let easy = [session(80, [10, 10, 10], rir: 4)]
        let build = try #require(LoadAdvisor.suggest(exercise: squat, prescription: rx("8–10"), week: 2, deload: false, history: easy))
        #expect(build.kg == 85)
        let base = try #require(LoadAdvisor.suggest(exercise: squat, prescription: rx("8–10"), week: 1, deload: false, history: easy))
        #expect(base.kg == 82.5)
    }

    @Test func withinRangeHoldsAndAddsARep() throws {
        let s = try #require(LoadAdvisor.suggest(exercise: squat, prescription: rx("8–10"), week: 2, deload: false,
                                                 history: [session(80, [10, 9, 8])]))
        #expect(s.action == .hold)
        #expect(s.kg == 80)
        #expect(s.reps == 9)
    }

    @Test func someSetsBelowBottomHolds() throws {
        let s = try #require(LoadAdvisor.suggest(exercise: squat, prescription: rx("8–10"), week: 2, deload: false,
                                                 history: [session(80, [9, 7, 6])]))
        #expect(s.action == .hold)
        #expect(s.kg == 80)
        #expect(s.reps == 8)
    }

    @Test func allSetsBelowBottomDropsFivePercentRounded() throws {
        let s = try #require(LoadAdvisor.suggest(exercise: squat, prescription: rx("8–10"), week: 2, deload: false,
                                                 history: [session(100, [6, 6, 5])]))
        #expect(s.action == .decrease)
        #expect(s.kg == 95)
        let small = try #require(LoadAdvisor.suggest(exercise: squat, prescription: rx("8–10"), week: 2, deload: false,
                                                     history: [session(20, [6, 6, 5])]))
        #expect(small.kg == 17.5) // 19 rounds to 20 → forced one plate step down
    }

    @Test func dumbbellsUseSmallerIncrements() throws {
        let light = try #require(LoadAdvisor.suggest(exercise: goblet, prescription: rx("10–12"), week: 2, deload: false,
                                                     history: [session(8, [12, 12, 12], exercise: "goblet-squat")]))
        #expect(light.kg == 9)
        let heavy = try #require(LoadAdvisor.suggest(exercise: goblet, prescription: rx("10–12"), week: 2, deload: false,
                                                     history: [session(20, [12, 12, 12], exercise: "goblet-squat")]))
        #expect(heavy.kg == 22)
    }

    @Test func machinesRoundToStackSteps() throws {
        let s = try #require(LoadAdvisor.suggest(exercise: legPress, prescription: rx("10–12"), week: 2, deload: false,
                                                 history: [session(100, [12, 12, 12], exercise: "leg-press")]))
        #expect(s.kg == 102.5)
    }

    @Test func deloadWeekTakesTenPercentOff() throws {
        let s = try #require(LoadAdvisor.suggest(exercise: squat, prescription: rx("8–10"), week: 4, deload: true,
                                                 history: [session(100, [10, 10, 10])]))
        #expect(s.action == .deload)
        #expect(s.kg == 90)
        let odd = try #require(LoadAdvisor.suggest(exercise: squat, prescription: rx("8–10"), week: 4, deload: true,
                                                   history: [session(82.5, [8, 8, 8])]))
        #expect(odd.kg == 75) // 74.25 → nearest 2.5
    }

    @Test func deloadSessionsAreIgnoredAsBasis() throws {
        let hist = [session(100, [10, 10, 10], day: 0, week: 3), session(90, [8, 8], day: 7, week: 4, deload: true)]
        let s = try #require(LoadAdvisor.suggest(exercise: squat, prescription: rx("8–10"), week: 1, deload: false, history: hist))
        #expect(s.basisKg == 100)
        #expect(s.kg == 102.5)
    }

    @Test func legacyLogsWithoutRepsRepeatTheLoad() throws {
        let legacy = ExerciseSession(date: day0, sessionId: "w2s1", week: 2, deload: false,
                                     sets: [SetLog(date: day0, exerciseId: "back-squat", kg: 70)])
        let s = try #require(LoadAdvisor.suggest(exercise: squat, prescription: rx("8–10"), week: 2, deload: false, history: [legacy]))
        #expect(s.action == .hold)
        #expect(s.kg == 70)
        #expect(s.reps == 8)
    }

    @Test func onlyTopLoadSetsCount() throws {
        // Back-off set at lower load with fewer reps must not block progression.
        var hist = session(80, [10, 10])
        hist.sets.append(SetLog(date: day0.addingTimeInterval(600), exerciseId: "back-squat", sessionId: "w1s1", setIndex: 2, kg: 60, reps: 6))
        let s = try #require(LoadAdvisor.suggest(exercise: squat, prescription: rx("8–10"), week: 2, deload: false, history: [hist]))
        #expect(s.action == .increase)
    }

    @Test func timeBasedPrescriptionHolds() throws {
        let s = try #require(LoadAdvisor.suggest(exercise: squat, prescription: rx("30–45 s"), week: 2, deload: false,
                                                 history: [session(40, [1])]))
        #expect(s.action == .hold)
        #expect(s.reps == nil)
    }
}

@Suite struct ExerciseSessionGroupingTests {
    @Test func groupsBySessionAndDayDedupesSetsAndPrefersPerSetLogs() {
        let d1 = day0, d2 = day0.addingTimeInterval(7 * 86_400)
        let logs = [
            SetLog(date: d1, exerciseId: "back-squat", sessionId: "w1s1", kg: 70), // legacy, superseded
            SetLog(date: d1.addingTimeInterval(60), exerciseId: "back-squat", sessionId: "w1s1", setIndex: 0, kg: 80, reps: 8),
            SetLog(date: d1.addingTimeInterval(120), exerciseId: "back-squat", sessionId: "w1s1", setIndex: 1, kg: 80, reps: 7),
            SetLog(date: d1.addingTimeInterval(180), exerciseId: "back-squat", sessionId: "w1s1", setIndex: 1, kg: 80, reps: 8), // re-logged
            SetLog(date: d1, exerciseId: "deadlift", sessionId: "w1s1", setIndex: 0, kg: 120, reps: 5),
            SetLog(date: d2, exerciseId: "back-squat", sessionId: "w4s1", setIndex: 0, kg: 70, reps: 8),
        ]
        let s = LoadAdvisor.sessions(logs, exerciseId: "back-squat", calendar: utc)
        #expect(s.count == 2)
        #expect(s[0].sets.map(\.reps) == [8, 8])
        #expect(s[0].week == 1)
        #expect(!s[0].deload)
        #expect(s[1].week == 4)
        #expect(s[1].deload)
        #expect(s[0].bestOneRepMax == 80 * (1 + 8.0 / 30))
        #expect(s[0].volumeKg == 1280)
    }

    @Test func recordsProvideWeekAndDeload() {
        let plan = Generator.generateWeek(Profile(sessionsPerWeek: 3), week: 2, seed: 1)
        let r = WorkoutRecord.build(session: plan.sessions[0], week: 2, deload: true, setsDone: [:], weights: [:],
                                    startedAt: day0, endedAt: day0.addingTimeInterval(3600), bodyMassKg: nil)
        let logs = [SetLog(date: day0.addingTimeInterval(60), exerciseId: "back-squat", sessionId: plan.sessions[0].id, setIndex: 0, kg: 60, reps: 8)]
        let s = LoadAdvisor.sessions(logs, exerciseId: "back-squat", records: [r], calendar: utc)
        #expect(s.first?.week == 2)
        #expect(s.first?.deload == true)
    }
}
