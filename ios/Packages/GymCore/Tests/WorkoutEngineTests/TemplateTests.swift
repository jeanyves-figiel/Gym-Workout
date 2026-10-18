import Testing
@testable import WorkoutEngine

@Suite struct TemplateTests {
    @Test func examplesResolveToCatalogExercises() {
        #expect(WorkoutTemplate.all.count == 13)
        #expect(Set(WorkoutTemplate.all.map(\.id)).count == WorkoutTemplate.all.count)
        #expect(Set(WorkoutTemplate.all.map(\.name)).count == WorkoutTemplate.all.count)
        for t in WorkoutTemplate.all {
            #expect(!t.items.isEmpty)
            for it in t.items { #expect(Exercise.find(it.exerciseId) != nil, "\(t.id): \(it.exerciseId)") }
            let s = t.session
            #expect(s.isExample)
            #expect(s.displayTitle == t.name)
            #expect(WorkoutTemplate.find(sessionId: s.id) == t)
            #expect(Set(s.blocks.flatMap(\.items).map(\.uid)).count == t.items.count)
            #expect(Set(s.blocks.map(\.kind)).count == s.blocks.count)
            #expect(s.estMin > 0)
        }
        for t in [WorkoutTemplate.lowerbody, .armsShoulder] {
            #expect(t.session.blocks.count == 1)
            #expect(t.session.blocks.flatMap(\.items).allSatisfy { $0.prescription.sets == 3 && $0.prescription.reps == "10" })
        }
        #expect(WorkoutTemplate.armsShoulder.items.count == 10)
        #expect(WorkoutTemplate.lowerbody.items.count == 10)
        // Trainer's Chest & Back plan: 3 × 10, pull-ups 3 × 12, one strength block.
        let cb = WorkoutTemplate.chestBack
        #expect(cb.items.count == 10)
        #expect(cb.session.blocks.count == 1)
        #expect(cb.session.blocks[0].items.map(\.prescription.reps) == ["10", "10", "10", "10", "12", "10", "10", "10", "10", "10"])
    }

    /// #252: ten library workouts, each goal covered, warm-up before and cool-down after the main block, sensible length.
    @Test func libraryWorkoutsHaveDistinctFocus() {
        #expect(WorkoutTemplate.library.count == 10)
        #expect(Set(WorkoutTemplate.library.map(\.goal)) == Set(WorkoutTemplate.Goal.allCases))
        for t in WorkoutTemplate.library {
            let s = t.session
            #expect((15...75).contains(s.estMin), "\(t.id): \(s.estMin) min")
            let kinds = s.blocks.map(\.kind)
            #expect(kinds.contains(t.main), "\(t.id)")
            if t.main != .mobility {
                #expect(kinds.first == .warmup, "\(t.id)")
                #expect(kinds.last == .cooldown, "\(t.id)")
            }
            // Timed moves read as seconds or minutes, never as reps.
            for p in s.blocks.flatMap(\.items) {
                let e = Exercise.get(p.exerciseId)
                if e.category == .cardio { #expect(p.prescription.reps.hasSuffix("min"), "\(t.id): \(e.id)") }
                if e.unit == .sec, e.category != .cardio { #expect(p.prescription.reps.hasSuffix("s"), "\(t.id): \(e.id)") }
            }
            // Circuit members share the round's rest.
            let grouped = Dictionary(grouping: s.blocks.flatMap(\.items).filter { $0.group != nil }) { $0.group!.prefix(1) }
            for (_, members) in grouped {
                #expect(members.count > 1, "\(t.id)")
                #expect(Set(members.map(\.prescription.restSec)).count == 1, "\(t.id)")
            }
        }
    }

    @Test func libraryWorkoutCopyKeepsFlowAndCircuits() {
        let t = WorkoutTemplate.pushPower
        let c = CustomWorkout(duplicating: t)
        #expect(c.items.count == t.items.filter { t.blockKind($0) == .strength }.count)
        #expect(c.flow.map(\.kind) == [.warmup, .cooldown])
        #expect(c.items.contains { $0.group == "A" })
        #expect(c.session.blocks.count == 3)
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
