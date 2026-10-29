import Testing
@testable import WorkoutEngine

@Suite struct ExploreMachineTests {
    @Test func usingGroupsByCategoryAndTrainsTheRightMuscles() {
        let legPress = Exercise.using(.legPress, custom: .init())
        #expect(legPress.allSatisfy { $0.equipment.contains(.legPress) })
        let grouped = Exercise.using(.legPress, byCategory: .init())
        #expect(grouped.reduce(0) { $0 + $1.1.count } == legPress.count)
        #expect(Exercise.muscles(using: .legPress, custom: .init()).prefix(3).contains(.quads))
        #expect(Exercise.muscles(using: .latPulldown, custom: .init()).prefix(2).contains(.lats))

    }

    @Test func tricepsMachineHeatsTricepsOverChest() {
        let load = Exercise.muscleLoad(using: .tricepsMachine, custom: .init())
        #expect(load.first?.muscle == .triceps)
        #expect(load.first?.load == 1)
        let chest = load.first { $0.muscle == .chest }?.load ?? 0
        #expect(chest < 0.5)
    }

    @Test func filterKeysRoundTrip() {
        for f in MachineFilter.chips { #expect(MachineFilter(key: f.key) == f) }
        #expect(MachineFilter(key: "nonsense") == .all)
    }

    @Test func filtersNarrowMuscleLists() {
        let all = Exercise.working(.chest, custom: .init()).flatMap(\.1)
        let cables = Exercise.working(.chest, filter: .area(.cables), gym: nil, custom: .init()).flatMap(\.1)
        #expect(!cables.isEmpty && cables.count < all.count)
        #expect(cables.allSatisfy { $0.exercise.equipment.contains(.cable) || $0.exercise.equipment.contains(.latPulldown)
            || $0.exercise.equipment.contains(.seatedRow) })
        let body = Exercise.working(.chest, filter: .bodyweight, gym: nil, custom: .init()).flatMap(\.1)
        #expect(body.contains { $0.exercise.id == "push-up" })
        // My gym: only dumbbells + bench → no barbell or cable chest work.
        let gym = Exercise.working(.chest, filter: .gym, gym: [.dumbbells, .bench], custom: .init()).flatMap(\.1)
        #expect(!gym.isEmpty)
        #expect(gym.allSatisfy { $0.exercise.equipment.allSatisfy { [.dumbbells, .bench, .mat, .foamRoller].contains($0) } })
        // Not set up: nothing hidden.
        #expect(Exercise.working(.chest, filter: .gym, gym: nil, custom: .init()).flatMap(\.1).count == all.count)
    }
}
