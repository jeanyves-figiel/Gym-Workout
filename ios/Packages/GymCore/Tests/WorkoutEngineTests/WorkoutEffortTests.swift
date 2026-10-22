import Testing
@testable import WorkoutEngine

@Suite struct WorkoutEffortTests {
    @Test func rirPrefillsTheScore() {
        #expect(WorkoutEffort.fromRIR([]) == nil)
        #expect(WorkoutEffort.fromRIR([0, 0]) == 10)
        #expect(WorkoutEffort.fromRIR([1, 2, 3]) == 8)
        #expect(WorkoutEffort.fromRIR([3]) == 7)
        #expect(WorkoutEffort.fromRIR([12]) == 1)
    }

    @Test func bandsFollowApple() {
        #expect(WorkoutEffort.word(2) == "easy")
        #expect(WorkoutEffort.word(5) == "moderate")
        #expect(WorkoutEffort.word(7) == "hard")
        #expect(WorkoutEffort.word(10) == "all out")
    }
}
