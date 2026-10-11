import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct SwapTests {
    private let profile = Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0)

    private func firstStrength(_ s: Session) -> PlannedExercise {
        s.blocks.first { $0.kind == .strength }!.items[0]
    }

    @Test func keptSwapAppliesOnItsDayOnly() throws {
        let plan = Generator.generateWeek(profile, seed: 42)
        let day = plan.sessions[0]
        let item = firstStrength(day)
        let to = try #require(Exercise.get(item.exerciseId).swapOptions(for: profile).first)
        let rule = ExerciseSwap(weekday: day.weekday, sessionIndex: day.index, from: item.exerciseId, to: to.id)

        let swapped = plan.applying(swaps: [rule])
        #expect(swapped.sessions[0].blocks.flatMap(\.items).first { $0.uid == item.uid }?.exerciseId == to.id)
        // Other days keep their picks.
        for i in plan.sessions.indices.dropFirst() { #expect(swapped.sessions[i] == plan.sessions[i]) }
    }

    @Test func unknownTargetIsIgnored() {
        let plan = Generator.generateWeek(profile, seed: 42)
        let item = firstStrength(plan.sessions[0])
        let rule = ExerciseSwap(weekday: plan.sessions[0].weekday, sessionIndex: 0, from: item.exerciseId, to: "user-gone")
        #expect(plan.applying(swaps: [rule]) == plan)
    }

    @Test func weekdayRulesMatchByWeekday() {
        var s = Generator.generateWeek(profile, seed: 1).sessions[0]
        s.weekday = 3
        #expect(ExerciseSwap(weekday: 3, sessionIndex: 5, from: "a", to: "b").matches(s))
        #expect(!ExerciseSwap(weekday: 4, sessionIndex: s.index, from: "a", to: "b").matches(s))
        s.weekday = nil
        #expect(ExerciseSwap(weekday: nil, sessionIndex: s.index, from: "a", to: "b").matches(s))
        #expect(!ExerciseSwap(weekday: 3, sessionIndex: s.index, from: "a", to: "b").matches(s))
    }

    @Test func optionsShareMusclesAndFitEquipment() {
        let bench = Exercise.get("bench-press")
        let options = bench.swapOptions(for: profile)
        #expect(!options.isEmpty)
        #expect(!options.contains { $0.id == bench.id })
        #expect(Set(options.map(\.id)).count == options.count)
        let gear = Set(profile.equipment)
        for e in options {
            #expect(e.primary.contains { bench.primary.contains($0) } || e.pattern == bench.pattern)
            #expect(WorkoutEngine.Selector.isAvailable(e, gear))
        }
    }

    @Test func codableRoundTrip() throws {
        let r = ExerciseSwap(weekday: nil, sessionIndex: 2, from: "squat", to: "leg-press")
        #expect(try JSONDecoder().decode(ExerciseSwap.self, from: JSONEncoder().encode(r)) == r)
    }
}
