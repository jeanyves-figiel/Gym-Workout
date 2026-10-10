import Testing
@testable import WorkoutEngine

/// #79: every tap on the Explore body map opened Calves.
@Suite struct BodyMapLayoutTests {
    @Test(arguments: BodyMapLayout.Side.allCases)
    func centreOfEveryEllipseHitsItsOwnMuscle(side: BodyMapLayout.Side) {
        for shape in BodyMapLayout.shapes(side) {
            #expect(BodyMapLayout.muscle(at: shape.midX, shape.midY, side: side) == shape.muscle, "\(side) \(shape.muscle)")
        }
    }

    @Test func tapsResolveToDifferentMuscles() {
        #expect(BodyMapLayout.muscle(at: 81, 95, side: .front) == .chest)
        #expect(BodyMapLayout.muscle(at: 100, 152, side: .front) == .abs)
        #expect(BodyMapLayout.muscle(at: 79, 264, side: .front) == .quads)
        #expect(BodyMapLayout.muscle(at: 78, 357, side: .front) == .calves)
        #expect(BodyMapLayout.muscle(at: 100, 90, side: .back) == .upperBack)
        #expect(BodyMapLayout.muscle(at: 82, 208, side: .back) == .glutes)
        #expect(BodyMapLayout.muscle(at: 120, 270, side: .back) == .hamstrings) // mirrored twin
        let hit = Set(BodyMapLayout.shapes(.front).compactMap { BodyMapLayout.muscle(at: $0.midX, $0.midY, side: .front) })
        #expect(hit.count == BodyMapLayout.muscles(.front).count)
    }

    @Test func outsideMusclesHitsNothing() {
        #expect(BodyMapLayout.muscle(at: 2, 2, side: .front) == nil)
        #expect(BodyMapLayout.muscle(at: 100, 30, side: .back) == nil) // head
    }

    @Test func everyMuscleIsOnTheMap() {
        let shown = Set(BodyMapLayout.muscles(.front) + BodyMapLayout.muscles(.back))
        #expect(shown == Set(Muscle.allCases))
    }
}
