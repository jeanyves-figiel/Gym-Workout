import Testing
@testable import WorkoutEngine

/// Hands-free player commands (#412).
@Suite struct VoiceCommandTests {
    @Test func setDoneWithEffort() {
        #expect(VoiceCommand.parse("Done") == .done(rir: nil))
        #expect(VoiceCommand.parse("Hey Coach, log it") == .done(rir: nil))
        #expect(VoiceCommand.parse("done, two left") == .done(rir: 2))
        #expect(VoiceCommand.parse("Set done, easy") == .done(rir: 4))
        #expect(VoiceCommand.parse("failed") == .done(rir: 0))
    }

    @Test func weightAndReps() {
        #expect(VoiceCommand.parse("80 kg") == .kg(80))
        #expect(VoiceCommand.parse("weight 62.5") == .kg(62.5))
        #expect(VoiceCommand.parse("too heavy, drop 5 kg") == .kgBy(-5))
        #expect(VoiceCommand.parse("add 2.5 kilos") == .kgBy(2.5))
        #expect(VoiceCommand.parse("minus five") == .kgBy(-5))
        #expect(VoiceCommand.parse("8 reps") == .reps(8))
        #expect(VoiceCommand.parse("did ten") == .reps(10))
        #expect(VoiceCommand.parse("lighter") == .kgStep(-1))
        #expect(VoiceCommand.parse("heavier") == .kgStep(1))
    }

    @Test func restAndNavigation() {
        #expect(VoiceCommand.parse("skip rest") == .skipRest)
        #expect(VoiceCommand.parse("Let's go") == .skipRest)
        #expect(VoiceCommand.parse("more rest") == .addRest)
        #expect(VoiceCommand.parse("next exercise") == .next)
        #expect(VoiceCommand.parse("go back") == .previous)
    }

    @Test func questionsGoToTheCoach() {
        #expect(VoiceCommand.parse("Should I skip rest?") == .ask("Should I skip rest?"))
        #expect(VoiceCommand.parse("my shoulder clicks on this one") == .ask("my shoulder clicks on this one"))
        #expect(VoiceCommand.parse("how deep should I squat") == .ask("how deep should I squat"))
        #expect(VoiceCommand.parse("   ") == nil)
    }

    @Test func exerciseNamedByCoach() {
        let none = CustomExercises()
        #expect(Exercise.named("dumbbell Bench Press", custom: none)?.id == "db-bench")
        #expect(Exercise.named("DB bench press", custom: none)?.id == "db-bench")
        #expect(Exercise.named("bench press", custom: none)?.id == "bench-press")
        #expect(Exercise.named("moon walk press", custom: none) == nil)
    }
}
