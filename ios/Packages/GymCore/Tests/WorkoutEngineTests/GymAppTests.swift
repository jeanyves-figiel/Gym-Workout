import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct GymAppTests {
    private let profile = Profile(goal: .build, sessionsPerWeek: 4, experience: .advanced, climbingDaysPerWeek: 0)

    private func ids(_ p: WeekPlan) -> [String] { p.sessions.flatMap { $0.blocks.flatMap(\.items) }.map(\.exerciseId) }

    @Test func additionsAreLibraryOnlyWithEquipmentInTheCatalog() {
        #expect(Exercise.gymAppCatalog.count >= 70)
        for e in Exercise.gymAppCatalog {
            #expect(Exercise.libraryOnlyIds.contains(e.id), "\(e.id)")
            #expect(!e.generator, "\(e.id)")
        }
        let used = Set(Exercise.catalog.flatMap(\.equipment))
        for eq in [Equipment.rowMachine, .backExtensionMachine, .squatMachine, .beltSquat, .gluteMachine, .multiHip,
                   .pulloverMachine, .sandbag, .sliders, .balanceTrainer, .massageBall, .stallBars, .lateralRaiseMachine] {
            #expect(used.contains(eq), "\(eq) has no exercise")
            #expect(GymArea.allCases.contains { $0.items.contains(eq) } || GymArea.floor.contains(eq), "\(eq) has no area")
        }
    }

    @Test func calisthenicsFoldUnderTheirBase() {
        #expect(Exercise.get("tuck-front-lever").baseId == "front-lever")
        #expect(Exercise.get("archer-pull-up").baseId == "pull-up")
        #expect(Exercise.get("one-arm-push-up").baseId == "push-up")
        #expect(Exercise.get("machine-row").baseId == "seated-cable-row")
        #expect(Exercise.get("db-floor-pullover").baseId == "machine-pullover")
    }

    @Test func rotationIsOffByDefault() {
        #expect(!Profile().rotatesVariations)
        for week in 1...Generator.mesocycleWeeks {
            let plan = Generator.generateWeek(profile, week: week, seed: 7)
            #expect(plan.rotatingVariations(for: profile) == plan)
        }
    }

    @Test func rotationSwapsAccessoriesForFamilyMembersFromWeekTwo() {
        var p = profile
        p.rotateVariations = true
        let week1 = Generator.generateWeek(p, week: 1, seed: 7)
        #expect(week1.rotatingVariations(for: p) == week1)
        var changed = 0
        for week in 2...Generator.mesocycleWeeks {
            let plan = Generator.generateWeek(p, week: week, seed: 7)
            let rotated = plan.rotatingVariations(for: p)
            #expect(rotated == plan.rotatingVariations(for: p), "deterministic")
            for (a, b) in zip(ids(plan), ids(rotated)) where a != b {
                changed += 1
                let from = Exercise.get(a), to = Exercise.get(b)
                #expect(!from.main, "\(a) is a main lift")
                #expect(from.familyId == to.familyId, "\(a) → \(b)")
                #expect(to.level <= p.experience.level)
                #expect(Selector.isAvailable(to, Set(p.equipment)))
            }
        }
        #expect(changed > 0)
    }

    @Test func keptSwapsAndSameVarietyAreLeftAlone() {
        var p = profile
        p.rotateVariations = true
        let plan = Generator.generateWeek(p, week: 3, seed: 7)
        let swaps = plan.sessions.flatMap { s in
            s.blocks.flatMap(\.items).map { ExerciseSwap(weekday: s.weekday, sessionIndex: s.index, from: $0.exerciseId, to: $0.exerciseId) }
        }
        #expect(plan.rotatingVariations(for: p, swaps: swaps) == plan)
        p.variety = .same
        #expect(!p.rotatesVariations)
        #expect(plan.rotatingVariations(for: p) == plan)
    }
}
