import Testing
@testable import WorkoutEngine

@Suite struct SplitLoadTests {
    @Test func weightStackMachinesShowTheToggle() {
        #expect(Exercise.get("seated-leg-curl").splitLoadMachine)
        #expect(Exercise.get("chest-press-machine").splitLoadMachine)
        #expect(!Exercise.get("hack-squat").splitLoadMachine)
        #expect(!Exercise.get("cable-fly").splitLoadMachine)
        #expect(!Exercise.get("db-bench").splitLoadMachine)
    }

    @Test func otherLoadedMovesOfferTheChipCardioAndHoldsNothing() {
        #expect(Exercise.get("hack-squat").splitLoadPossible)
        #expect(Exercise.get("cable-fly").splitLoadPossible)
        #expect(Exercise.get("db-bench").splitLoadPossible)
        #expect(!Exercise.get("elliptical").splitLoadMachine)
        #expect(!Exercise.get("elliptical").splitLoadPossible)
        #expect(!Exercise.get("plank").splitLoadPossible)
    }
}
