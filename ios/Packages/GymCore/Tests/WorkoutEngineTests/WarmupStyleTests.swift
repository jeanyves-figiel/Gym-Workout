import Foundation
import Testing
@testable import WorkoutEngine

/// Warm-up and cool-down styles and per-workout moves (#293).
@Suite struct WarmupStyleTests {
    let base = Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0)
    let cardioIds = Set(Exercise.catalog.filter { $0.category == .cardio }.map(\.id))

    private func session(_ p: Profile, focus: Focus = .push, minutes: Int = 45) throws -> Session {
        try #require(Generator.quickSession(p, focus: focus, week: 2, seed: 7, minutes: minutes))
    }

    private func block(_ s: Session, _ k: BlockKind) throws -> Block {
        try #require(s.blocks.first { $0.kind == k })
    }

    @Test func autoStyleLeavesPlansUnchanged() throws {
        var p = base
        p.warmupStyle = .auto
        p.cooldownStyle = .auto
        #expect(Generator.generateWeek(p, week: 2, seed: 4) == Generator.generateWeek(base, week: 2, seed: 4))
        #expect(base.applying(FlowTweaks()) == base)
        #expect(base.applying(nil) == base)
    }

    @Test func pulseWarmupIsMostlyAMachine() throws {
        var p = base
        p.warmupStyle = .pulse
        let wu = try block(session(p), .warmup)
        let first = try #require(wu.items.first)
        #expect(cardioIds.contains(first.exerciseId))
        #expect(first.estSec >= (wu.targetMin - 2) * 60)
        #expect(wu.items.count <= 3)
    }

    @Test func dynamicWarmupHasNoMachine() throws {
        var p = base
        p.warmupStyle = .dynamic
        let wu = try block(session(p), .warmup)
        #expect(!wu.items.isEmpty)
        #expect(wu.items.allSatisfy { !cardioIds.contains($0.exerciseId) })
    }

    @Test func activationWarmupPrefersActivationDrills() throws {
        var p = base
        p.warmupStyle = .activation
        let wu = try block(session(p), .warmup)
        #expect(wu.items.contains { Generator.activationDrills.contains($0.exerciseId) })
    }

    @Test func foamRollCooldownRollsWithARoller() throws {
        var p = base
        p.cooldownStyle = .foamRoll
        let cd = try block(session(p), .cooldown)
        #expect(cd.items.contains { $0.exerciseId.hasPrefix("foam-roll") })
        #expect(cd.items.last?.exerciseId == "breathing")

        p.equipment = p.equipment.filter { $0 != .foamRoller }
        let plain = try block(session(p), .cooldown)
        #expect(!plain.items.contains { $0.exerciseId.hasPrefix("foam-roll") })
        #expect(plain.items.count >= Generator.minStretches + 1)
    }

    @Test func easyCardioCooldownStartsOnAMachine() throws {
        var p = base
        p.cooldownStyle = .easyCardio
        let cd = try block(session(p), .cooldown)
        #expect(cardioIds.contains(try #require(cd.items.first).exerciseId))
    }

    @Test func breatheCooldownBreathesLonger() throws {
        var p = base
        p.cooldownStyle = .breathe
        let cd = try block(session(p), .cooldown)
        #expect(cd.items.last?.exerciseId == "breathing")
        #expect(cd.items.last?.estSec == 180)
    }

    @Test func exactMovesReplaceTheBlock() throws {
        let moves = [BlockPick(exerciseId: "rower", minutes: 3), BlockPick(exerciseId: "cat-cow", minutes: 2)]
        let t = FlowTweaks(cooldownStyle: .stretch, warmupMoves: moves)
        let s = try session(base.applying(t))
        let wu = try block(s, .warmup)
        #expect(wu.items.map(\.exerciseId) == ["rower", "cat-cow"])
        #expect(wu.targetMin == 5)
        #expect(t.movesMinutes(.warmup) == 5)
        #expect(t.movesMinutes(.cooldown) == nil)
    }

    @Test func customWorkoutFlowFollowsTweaks() throws {
        let ex = ["bench-press", "barbell-row"].compactMap(Exercise.find)
        try #require(ex.count == 2)
        var p = base
        p.warmupStyle = .dynamic
        let blocks = Generator.flowBlocks(p, around: ex, minutes: [.warmup: 6, .cooldown: 5], seed: 1)
        let wu = try #require(blocks.first { $0.kind == .warmup })
        #expect(wu.items.allSatisfy { !cardioIds.contains($0.exerciseId) })
    }

    @Test func tweaksRoundTripOnCustomWorkouts() throws {
        var w = CustomWorkout(name: "Push", items: [CustomWorkout.Item(exerciseId: "bench-press", sets: 3, reps: 8, restSec: 90)])
        w.flowTweaks = FlowTweaks(warmupStyle: .pulse, cooldownMoves: [BlockPick(exerciseId: "childs-pose-reach", minutes: 2)])
        let back = try JSONDecoder().decode(CustomWorkout.self, from: JSONEncoder().encode(w))
        #expect(back.flowTweaks == w.flowTweaks)

        let unknown = #"{"id":"\#(w.id.uuidString)","name":"x","items":[],"flowTweaks":{"warmupStyle":"future"}}"#
        let lenient = try JSONDecoder().decode(CustomWorkout.self, from: Data(unknown.utf8))
        #expect(lenient.flowTweaks?.warmupStyle == .auto)
    }
}
