import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct FamilyTests {
    private let profile = Profile(goal: .balanced, experience: .intermediate, climbingDaysPerWeek: 0)

    @Test func variationLinksPointAtCatalogBases() {
        for (variation, base) in Exercise.variationOf {
            #expect(Exercise.find(variation) != nil, "unknown variation \(variation)")
            #expect(Exercise.find(base) != nil, "unknown base \(base)")
            #expect(Exercise.variationOf[base] == nil, "\(base) is a base and a variation")
            #expect(variation != base)
        }
    }

    @Test func extensionIsLibraryOnly() {
        #expect(Exercise.libraryOnlyIds.count >= 100)
        for id in Exercise.libraryOnlyIds {
            let e = Exercise.get(id)
            #expect(!e.generator, "\(id) must not be generated")
            #expect(!Exercise.travelIds.contains(id))
        }
    }

    @Test func generatedWorkoutsNeverUseTheExtension() {
        for seed in UInt32(1)...10 {
            for g in MuscleGroup.allCases {
                let w = CustomWorkout.generate(MuscleWorkoutOptions(groups: [g], minutes: 60), profile: profile, seed: seed)
                #expect(Exercise.libraryOnlyIds.isDisjoint(with: w.items.map(\.exerciseId)), "\(g) seed \(seed)")
            }
            let p = Profile(goal: .build, sessionsPerWeek: 5, experience: .advanced, climbingDaysPerWeek: 0)
            let ids = Generator.generateWeek(p, seed: seed).sessions.flatMap { $0.blocks.flatMap(\.items) }.map(\.exerciseId)
            #expect(Exercise.libraryOnlyIds.isDisjoint(with: ids))
        }
    }

    @Test func familyStartsWithBase() {
        let curl = Exercise.get("spider-curl")
        #expect(curl.baseId == "db-curl")
        #expect(curl.family.first?.id == "db-curl")
        #expect(curl.family.contains { $0.id == "barbell-curl" })
        #expect(!curl.relatives.contains { $0.id == "spider-curl" })
        #expect(Exercise.get("db-curl").relatives.count == Exercise.variationOf.values.filter { $0 == "db-curl" }.count)
        #expect(Exercise.get("plank").family.map(\.id).first == "plank")
    }

    @Test func foldingHidesVariationsOnlyWhenTheirBaseIsListed() {
        let list = ["db-curl", "spider-curl", "hammer-curl", "rope-hammer-curl", "zottman-curl"].map(Exercise.get)
        let folded = Exercise.folded(list)
        #expect(folded.map(\.exercise.id) == ["db-curl", "hammer-curl"])
        #expect(folded[0].variations.map(\.id) == ["spider-curl", "zottman-curl"])
        #expect(folded[1].variations.map(\.id) == ["rope-hammer-curl"])
        // Base not in the list: the variation stays a row of its own.
        #expect(Exercise.folded([Exercise.get("spider-curl")]).map(\.exercise.id) == ["spider-curl"])
    }

    @Test func foldedCategoryListsAreShorter() {
        for c in WorkoutEngine.Category.allCases {
            let all = Exercise.inCategory(c, custom: CustomExercises())
            let folded = Exercise.folded(all)
            #expect(folded.count + folded.reduce(0) { $0 + $1.variations.count } == all.count, "\(c)")
        }
        #expect(Exercise.folded(Exercise.inCategory(.strength, custom: CustomExercises())).count
            < Exercise.inCategory(.strength, custom: CustomExercises()).count)
    }

    @Test func variationOptionsRespectEquipmentAndLevel() {
        var p = profile
        p.equipment = [.dumbbells, .bench]
        let options = Exercise.get("db-curl").variationOptions(for: p)
        #expect(!options.isEmpty)
        for e in options {
            #expect(e.equipment.allSatisfy { p.equipment.contains($0) }, "\(e.id)")
            #expect(e.level <= p.experience.level)
            #expect(e.familyId == "db-curl")
        }
        #expect(!options.contains { $0.id == "db-curl" })
        #expect(!options.contains { $0.id == "cable-curl" })
    }
}
