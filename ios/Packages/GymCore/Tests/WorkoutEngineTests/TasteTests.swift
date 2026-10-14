import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct TasteTests {
    private let profile = Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0)
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func items(_ p: WeekPlan) -> [PlannedExercise] { p.sessions.flatMap { $0.blocks.flatMap(\.items) } }

    @Test func swapsAwayBuildADislike() {
        var t = MemberTaste()
        t.learn(swap: "a", to: "b", kept: false, at: t0)
        #expect(t.affinity("a", at: t0) == -0.75)
        #expect(t.affinity("b", at: t0) == 0.3)
        #expect(t.affinity("a", at: t0) > MemberTaste.dislikeThreshold)
        t.learn(swap: "a", to: "c", kept: false, at: t0)
        #expect(t.affinity("a", at: t0) <= MemberTaste.dislikeThreshold)
        #expect(t.disliked(at: t0).first == "a")
        #expect(Set(t.liked(at: t0)) == ["b", "c"])
    }

    @Test func affinityIsCapped() {
        var t = MemberTaste()
        for _ in 0..<10 { t.learn(swap: "a", to: "b", kept: true, at: t0) }
        #expect(t.affinity("a", at: t0) == -3)
        #expect(t.affinity("b", at: t0) == 0.9)
    }

    @Test func signalsFade() {
        var t = MemberTaste()
        t.record("a", .removed, at: t0)
        t.record("a", .removed, at: t0)
        let later = t0.addingTimeInterval(MemberTaste.halfLifeDays * 86_400)
        #expect(t.affinity("a", at: t0) == -1.5)
        #expect(t.affinity("a", at: later) == -0.75)
    }

    @Test func undoingAnEditCancelsIt() throws {
        let s = Generator.generateWeek(profile, seed: 42).sessions[0]
        var edited = s.blocks
        let item = try #require(edited.first { $0.kind == .strength }?.items.last)
        edited.remove(item.uid)
        var t = MemberTaste()
        t.learn(edit: s.blocks, edited, at: t0)
        #expect(t.affinity(item.exerciseId, at: t0) == -0.75)
        t.learn(edit: edited, s.blocks, at: t0)
        #expect(t.affinity(item.exerciseId, at: t0) == 0)
    }

    @Test func finishedWorkoutSkipsOnlyWhatWasPassedOver() {
        func rec(_ id: String, _ done: Int) -> ExerciseRecord {
            ExerciseRecord(uid: id, exerciseId: id, category: .strength, setsDone: done, setsPlanned: 3)
        }
        let w = WorkoutRecord(
            id: UUID(), startedAt: t0, durationSec: 1800, sessionId: "w1s1", week: 1, deload: false, focus: .upper,
            title: "Upper", exercises: [rec("a", 3), rec("b", 0), rec("c", 2), rec("d", 0)],
            kcal: nil, avgHeartRate: nil, maxHeartRate: nil, muscleLoad: [:])
        var t = MemberTaste()
        t.learn(from: w)
        #expect(t.affinity("a", at: w.endedAt) > 0)
        #expect(t.affinity("b", at: w.endedAt) < 0)
        // Partly done, or not reached because the workout stopped early: no signal.
        #expect(t.exercises["c"] == nil)
        #expect(t.exercises["d"] == nil)
    }

    @Test func nothingLearnedKeepsPlansIdentical() {
        var empty = profile
        empty.learnedTaste = [:]
        var unknown = profile
        unknown.learnedTaste = ["not-an-exercise": -3]
        for seed: UInt32 in [1, 42, 99] {
            let plain = Generator.generateWeek(profile, seed: seed)
            #expect(Generator.generateWeek(empty, seed: seed) == plain)
            #expect(Generator.generateWeek(unknown, seed: seed) == plain)
        }
    }

    @Test func dislikedAccessoryLeavesThePlan() throws {
        let plan = Generator.generateWeek(profile, seed: 42)
        let accessory = try #require(items(plan).first { it in
            let e = Exercise.get(it.exerciseId)
            return e.category == .strength && !e.main && e.alternatives(for: profile).count >= 3
        })
        var p = profile
        p.learnedTaste = [accessory.exerciseId: -3]
        let after = Generator.generateWeek(p, seed: 42)
        #expect(!items(after).contains { $0.exerciseId == accessory.exerciseId })
    }

    @Test func variationAvoidsDislikes() throws {
        let plan = Generator.generateWeek(profile, seed: 42)
        let request = VaryRequest(sessions: Set(plan.sessions.map(\.id)), parts: Set(VaryPart.allCases), keep: [], seed: 5)
        let plain = plan.varied(request, profile: profile)
        let picked = try #require(plain.values.first)
        var p = profile
        p.learnedTaste = [picked: -3]
        // Only items with no other option keep it.
        let count = { (swaps: [String: String]) in swaps.values.filter { $0 == picked }.count }
        #expect(count(plan.varied(request, profile: p)) < count(plain))
    }
}
