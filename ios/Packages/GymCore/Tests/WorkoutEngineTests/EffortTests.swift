import Testing
@testable import WorkoutEngine

@Suite struct EffortTests {
    @Test func rirPrefillsTheScore() {
        #expect(Effort.fromRIR([]) == nil)
        #expect(Effort.fromRIR([0, 0]) == 10)
        #expect(Effort.fromRIR([1, 2, 3]) == 8)
        #expect(Effort.fromRIR([3]) == 7)
        #expect(Effort.fromRIR([12]) == 1)
    }

    @Test func bandsFollowApple() {
        #expect(Effort.word(2) == "easy")
        #expect(Effort.word(5) == "moderate")
        #expect(Effort.word(7) == "hard")
        #expect(Effort.word(10) == "all out")
    }
}
