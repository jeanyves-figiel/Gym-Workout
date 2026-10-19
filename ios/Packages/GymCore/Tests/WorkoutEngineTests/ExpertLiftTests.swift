import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct ExpertLiftTests {
    private let bench = Exercise.get("bench-press")
    private let base = Profile(goal: .strength, sessionsPerWeek: 3, experience: .advanced, climbingDaysPerWeek: 0)

    private func prescription(_ sets: Int, _ reps: String) -> Prescription {
        Prescription(sets: sets, reps: reps, restSec: 120, intensity: nil, note: nil)
    }

    // MARK: Pro Sets

    @Test func everyStyleGivesOneSetPerPrescribedSet() {
        for style in SetStyle.allCases {
            let p = ProSets.styled(prescription(4, "5"), style)
            let sets = ProSets.sets(style, prescription: p, workingKg: 100, oneRepMax: 130, exercise: bench)
            #expect(sets.count == p.sets, "\(style)")
        }
    }

    @Test func topSetThenLighterBackoffs() {
        let p = ProSets.styled(prescription(4, "5"), .topBackoff)
        let sets = ProSets.sets(.topBackoff, prescription: p, workingKg: 100, oneRepMax: nil, exercise: bench)
        #expect(sets.first?.role == .top)
        #expect(sets.first?.kg == 105)
        #expect(sets.dropFirst().allSatisfy { $0.role == .backoff && ($0.kg ?? 0) < 105 })
    }

    @Test func backoffFollowsTopSetEffort() {
        let easy = ProSets.backoffKg(topKg: 100, topReps: 3, topRIR: 3, backoffReps: 5, exercise: bench)
        let hard = ProSets.backoffKg(topKg: 100, topReps: 3, topRIR: 0, backoffReps: 5, exercise: bench)
        #expect(easy > hard)
        #expect(easy <= 100)
        #expect(ProSets.backoffKg(topKg: 100, topReps: 3, topRIR: nil, backoffReps: 3, exercise: bench) == 90)
    }

    @Test func dropSetsGetLighterWithNoRestBetween() {
        let p = ProSets.styled(prescription(3, "8"), .drop)
        #expect(p.sets == 5)
        let sets = ProSets.sets(.drop, prescription: p, workingKg: 80, oneRepMax: nil, exercise: bench)
        #expect(sets[2].restSec == 0 && sets[3].restSec == 0)
        #expect(sets[3].kg == 65 && sets[4].kg == 50)
    }

    @Test func styleSkipsBodyweightAndSupersets() {
        var plan = Generator.generateWeek(base, seed: 7)
        let ids = Set(plan.sessions.flatMap { $0.blocks.flatMap { $0.items.map(\.exerciseId) } })
        let styles = Dictionary(uniqueKeysWithValues: ids.map { ($0, SetStyle.drop) })
        let before = plan
        plan = plan.applyingSetStyles(styles)
        for (s0, s1) in zip(before.sessions, plan.sessions) {
            for (b0, b1) in zip(s0.blocks, s1.blocks) {
                for (i0, i1) in zip(b0.items, b1.items) {
                    let e = Exercise.get(i0.exerciseId)
                    let styled = b0.kind == .strength && i0.group == nil && i0.supersetWith == nil && ProSets.eligible(e)
                        && i0.prescription.repRange != nil
                    #expect(i1.prescription.sets == i0.prescription.sets + (styled ? 2 : 0), "\(i0.exerciseId)")
                }
            }
        }
    }

    @Test func platesPerSide() {
        #expect(Plates.perSide(total: 165, bar: 20) == [25, 25, 20, 2.5])
        #expect(Plates.perSide(total: 20, bar: 20) == [])
        #expect(Plates.perSide(total: 21, bar: 20) == nil)
        #expect(Plates.barKg(for: bench) == 20)
    }

    @Test func warmupsRampBelowTheWorkingWeight() {
        let w = ProSets.warmups(to: 140, exercise: bench)
        #expect(w.first?.kg == 20)
        #expect(w.map(\.kg) == w.map(\.kg).sorted())
        #expect(w.allSatisfy { $0.kg < 140 })
        #expect(ProSets.warmups(to: 30, exercise: bench).isEmpty)
    }

    // MARK: Lift Focus

    private func focus(_ t: FocusTemplate, weeks: Int) -> LiftFocus {
        LiftFocus(exerciseId: "bench-press", targetKg: 120, start: Date(timeIntervalSince1970: 1_760_918_400), weeks: weeks,
                  template: t, startOneRepMax: 112, weakPoint: .lockout)
    }

    @Test func monkeyPeakPhasesEndInTaperAndTest() {
        let f = focus(.monkeyPeak, weeks: 10)
        #expect((1...10).map { f.phase(week: $0) } == [.build, .build, .build, .deload, .build, .build, .build, .deload, .taper, .test])
        let first = f.doses(week: 1)[0][0].pct
        let last = f.doses(week: 7)[0][0].pct
        #expect(first < last)
        #expect(f.workingMax(week: 10, live: nil) == min(120, 112 * 1.05))
    }

    @Test func everyTemplateHasSetsEachWeekAndAttemptsOnTest() {
        for t in FocusTemplate.allCases {
            for weeks in t.lengths {
                let f = focus(t, weeks: weeks)
                for w in 1..<weeks {
                    #expect(!f.doses(week: w).isEmpty, "\(t) \(weeks) w\(w)")
                    for i in 0..<f.sessionsPerWeek(week: w) {
                        #expect(!f.plannedSets(week: w, index: i, live: 112, exercise: bench).isEmpty)
                    }
                }
                let test = f.plannedSets(week: weeks, index: 0, live: 112, exercise: bench)
                #expect(test.count == 3 && test.allSatisfy { $0.role == .attempt })
                #expect(test.map { $0.kg ?? 0 } == test.map { $0.kg ?? 0 }.sorted())
            }
        }
    }

    @Test func attemptsGoForTheTargetWhenWithinReach() {
        #expect(LiftFocus.attempts(oneRepMax: 118, target: 120, exercise: bench) == [105, 112.5, 120])
        #expect(LiftFocus.attempts(oneRepMax: 100, target: 140, exercise: bench).last == 102.5)
    }

    @Test func weekOnDate() {
        let f = focus(.monkeyPeak, weeks: 8)
        #expect(f.week(on: f.start) == 1)
        #expect(f.week(on: f.start.addingTimeInterval(7 * 86400)) == 2)
        #expect(f.week(on: f.start.addingTimeInterval(-86400)) == nil)
        #expect(f.week(on: f.start.addingTimeInterval(60 * 86400)) == nil)
    }

    @Test func planGetsTheLiftAccessoriesAndMaintenance() {
        let plan = Generator.generateWeek(base, seed: 11)
        let f = focus(.monkeyPeak, weeks: 10)
        let out = plan.applyingLiftFocus(f, on: f.start, equipment: Set(base.equipment))
        let withLift = out.sessions.filter { s in
            s.blocks.contains { $0.kind == .strength && $0.items.first?.prescription.intensity?.hasPrefix("Lift Focus") == true }
        }
        #expect(withLift.count == 2)
        #expect(out.liftFocusIndex(sessionId: withLift[0].id, focus: f) == 0)
        #expect(out.liftFocusIndex(sessionId: withLift[1].id, focus: f) == 1)
        let first = withLift[0].blocks.first { $0.kind == .strength }!
        #expect(first.items[0].prescription.sets == f.doses(week: 1)[0].count)
        #expect(first.items.contains { LiftFocus.accessories(for: "bench-press", .lockout).contains($0.exerciseId) })
        // Outside the block nothing changes.
        #expect(plan.applyingLiftFocus(f, on: f.start.addingTimeInterval(-86400), equipment: Set(base.equipment)) == plan)
        #expect(plan.applyingLiftFocus(nil, on: f.start, equipment: Set(base.equipment)) == plan)
    }

    @Test func predictionFollowsTheTrend() throws {
        let f = focus(.monkeyPeak, weeks: 10)
        let trend = (0..<4).map { (f.start.addingTimeInterval(Double($0) * 7 * 86400), 110.0 + Double($0)) }
        let p = try #require(f.predicted(trend: trend))
        #expect(p > 113)
        #expect(f.predicted(trend: [trend[0]]) == nil)
    }

    // MARK: Lift Lab

    @Test func repRecordsTakeHeaviestForAtLeastThatManyReps() {
        let d = Date()
        let logs = [SetLog(date: d, exerciseId: "bench-press", kg: 100, reps: 5),
                    SetLog(date: d, exerciseId: "bench-press", kg: 110, reps: 1),
                    SetLog(date: d, exerciseId: "back-squat", kg: 200, reps: 1)]
        let r = LiftLab.repRecords(exerciseId: "bench-press", logs: logs, attempts: [])
        #expect(r.first { $0.reps == 1 }?.kg == 110)
        #expect(r.first { $0.reps == 3 }?.kg == 100)
        #expect(r.first { $0.reps == 8 } == nil)
        #expect(LiftLab.heavySets(exerciseId: "bench-press", logs: logs, oneRepMax: 115, since: d.addingTimeInterval(-60)) == 2)
    }
}
