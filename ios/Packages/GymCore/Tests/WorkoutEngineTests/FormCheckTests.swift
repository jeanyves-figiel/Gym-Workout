import Foundation
import Testing
@testable import WorkoutEngine

/// Form check (#833): reps, faults, score and report from made-up camera frames.
@Suite struct FormCheckTests {
    private func model(_ id: String = "back-squat") throws -> FormModel {
        try #require(FormModel(exercise: Exercise.get(id)))
    }

    private func run(_ m: FormModel, _ frames: [(Double, FormPose)]) -> FormAnalyzer {
        var a = FormAnalyzer(model: m)
        for (t, p) in frames { a.add(p, at: t) }
        return a
    }

    @Test func squatCountsOnTheKneeOrHipFromTheSide() throws {
        let m = try model()
        #expect(m.view == .side)
        #expect([PositionJoint.knee, .hip].contains(m.primary))
        #expect(m.faults.contains(.torsoLean))
        #expect(!m.faults.contains(.kneesIn), "knees caving can't be seen from the side")
    }

    @Test func timedHoldsAndCustomExercisesAreNotChecked() {
        #expect(!FormModel.supports(Exercise.get("plank")))
        #expect(FormModel.supports(Exercise.get("back-squat")))
    }

    @Test func cleanSetCountsEveryRepAtFullScore() throws {
        let m = try model()
        let a = run(m, FormDemo.frames(m, reps: 5))
        #expect(a.reps.count == 5)
        #expect(a.reps.allSatisfy { $0.faults.isEmpty }, "\(a.reps.map(\.faults))")
        #expect(a.reps.allSatisfy { $0.score == 100 })
        #expect(a.reps.allSatisfy { $0.match >= 90 }, "\(a.reps.map(\.match))")
        let r = a.report()
        #expect(r.score == 100)
        #expect(r.fixes.isEmpty)
        #expect(r.worst == nil)
        #expect(a.live.cue?.text == "Good rep")
    }

    @Test func shortRepsAndLeaningAreCaught() throws {
        let m = try model()
        let a = run(m, FormDemo.frames(m, reps: 6, shallow: [3], lean: [5, 6]))
        #expect(a.reps.count == 6)
        #expect(a.reps[2].faults.contains(.shallow))
        #expect(a.reps[2].depth < FormModel.Limit.fullRange)
        #expect(a.reps[4].faults.contains(.torsoLean))
        #expect(a.reps[5].faults.contains(.torsoLean))
        #expect((a.reps[5].torsoExtra ?? 0) > FormModel.Limit.torsoLean)
        #expect(a.reps[0].faults.isEmpty)
        let r = a.report()
        #expect(r.fixes.first?.fault == .torsoLean)
        #expect(r.fixes.first?.reps == [5, 6])
        #expect(r.fadeFrom == 5)
        #expect([1, 2, 4].contains(r.best ?? 0))
        #expect(r.worst != nil)
        #expect(!r.worstReplay.isEmpty)
        #expect(m.cue(.shallow).text == "Go deeper")
    }

    @Test func stayingHalfWayIsNotARepFinished() throws {
        let m = try model()
        var a = FormAnalyzer(model: m)
        var t = 0.0
        // Rep 1 to the bottom and back up only to a quarter of the way, then rep 2.
        // Poses are drawn by position; find the one whose counted angle is a quarter of the way.
        let a0 = try #require(m.start.angle(m.primary)), a1 = try #require(m.peak.angle(m.primary))
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            let v = ((FormDemo.pose(m, progress: mid).angle(m.primary) ?? a0) - a0) / (a1 - a0)
            if v < 0.25 { lo = mid } else { hi = mid }
        }
        let quarter = lo
        let down = Array(stride(from: 0.0, through: 1, by: 0.05)), halfUp = Array(stride(from: 1.0, through: quarter, by: -0.04))
        let hold = Array(repeating: quarter, count: 12), up = Array(stride(from: 1.0, through: 0, by: -0.05))
        // Rep 2 starts from where rep 1 stopped, never back at the start.
        let downAgain = Array(stride(from: quarter, through: 1, by: 0.05))
        for p in down + halfUp + hold + downAgain + up + Array(repeating: 0.0, count: 8) {
            a.add(FormDemo.pose(m, progress: p), at: t)
            t += 0.1
        }
        #expect(a.reps.count == 2)
        #expect(a.reps[0].faults.contains(.noLockout))
    }

    @Test func frontViewSeesKneesCaving() throws {
        guard let e = Exercise.catalog.first(where: { FormModel(exercise: $0).map { $0.view == .front && $0.faults.contains(.kneesIn) } == true })
        else { return }
        let m = try model(e.id)
        let a = run(m, FormDemo.frames(m, reps: 3, kneesIn: [2]))
        #expect(a.reps.count == 3)
        #expect(a.reps[1].faults.contains(.kneesIn))
        #expect(!a.reps[0].faults.contains(.kneesIn))
    }

    @Test func outOfViewAsksToStepBack() throws {
        let m = try model()
        var a = FormAnalyzer(model: m)
        a.add(FormDemo.pose(m, progress: 0), at: 0)
        #expect(a.live.visible)
        a.add(nil, at: 0.5)
        #expect(a.live.visible)
        a.add(nil, at: 1.6)
        #expect(!a.live.visible)
        #expect(a.live.cue?.tone == .info)
    }

    @Test func ghostStandsOnTheMembersFeet() throws {
        let m = try model()
        var a = FormAnalyzer(model: m)
        let pose = FormDemo.pose(m, progress: 0)
        let live = a.add(pose, at: 0)
        let ghost = try #require(live.ghost)
        let feet = try #require(pose.ankles), ghostFeet = try #require(ghost.ankles)
        #expect(abs(feet.x - ghostFeet.x) < 0.01 && abs(feet.y - ghostFeet.y) < 0.01)
        let len = try #require(pose.length), ghostLen = try #require(ghost.length)
        #expect(abs(len - ghostLen) < 0.02)
    }

    @Test func reportKeepsItsRepsThroughJSON() throws {
        let m = try model()
        let a = run(m, FormDemo.frames(m, reps: 3, shallow: [2]))
        let r = a.report(date: Date(timeIntervalSince1970: 1_800_000_000))
        let back = try JSONDecoder().decode(FormReport.self, from: JSONEncoder().encode(r))
        #expect(back.reps == r.reps)
        #expect(back.worstReplay.count == r.worstReplay.count)
        #expect(back.score == r.score)
        #expect(back.replays.isEmpty, "only the worst rep's frames are saved")
        #expect(FormReport.repsText([6, 7]) == "reps 6–7")
        #expect(FormReport.repsText([2, 5]) == "reps 2, 5")
        #expect(FormReport.repsText([4]) == "rep 4")
    }

    @Test func scoreTakesOffEachFaultOnce() {
        var r = FormRep(number: 1, score: 100, match: 90, depth: 1, seconds: 2, faults: [])
        r.add(.torsoLean)
        r.add(.torsoLean)
        r.add(.tooFast)
        #expect(r.score == 100 - FormFault.torsoLean.penalty - FormFault.tooFast.penalty)
    }
}
