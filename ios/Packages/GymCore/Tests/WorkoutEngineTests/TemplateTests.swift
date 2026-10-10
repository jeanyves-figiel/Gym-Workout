import Testing
@testable import WorkoutEngine

@Suite struct TemplateTests {
    @Test func examplesResolveToCatalogExercises() {
        #expect(WorkoutTemplate.all.count == 2)
        for t in WorkoutTemplate.all {
            #expect(!t.items.isEmpty)
            for it in t.items { #expect(Exercise.find(it.exerciseId) != nil, "\(t.id): \(it.exerciseId)") }
            let s = t.session
            #expect(s.isExample)
            #expect(s.displayTitle == t.name)
            #expect(WorkoutTemplate.find(sessionId: s.id) == t)
            #expect(s.blocks.flatMap(\.items).allSatisfy { $0.prescription.sets == 3 && $0.prescription.reps == "10" })
            #expect(Set(s.blocks.flatMap(\.items).map(\.uid)).count == t.items.count)
            #expect(s.estMin > 0)
        }
        #expect(WorkoutTemplate.armsShoulder.items.count == 10)
    }

    @Test func exampleOnlyExercisesNeverGenerated() {
        let exampleOnly = Set(Exercise.catalog.filter { !$0.generator }.map(\.id))
        #expect(!exampleOnly.isEmpty)
        let p = Profile(goal: .build, sessionsPerWeek: 5, experience: .advanced, climbingDaysPerWeek: 0)
        for seed in UInt32(1)...20 {
            for w in 1...4 {
                let ids = Generator.generateWeek(p, week: w, seed: seed).sessions.flatMap { $0.blocks.flatMap(\.items) }.map(\.exerciseId)
                #expect(exampleOnly.isDisjoint(with: ids))
            }
        }
    }

    @Test func generatedSessionsKeepFocusTitle() {
        let s = Generator.generateWeek(Profile(), seed: 1).sessions[0]
        #expect(!s.isExample)
        #expect(s.displayTitle == s.focus.label)
    }
}
