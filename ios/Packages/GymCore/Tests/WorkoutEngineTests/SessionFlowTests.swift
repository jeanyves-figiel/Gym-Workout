import Foundation
import Testing
@testable import WorkoutEngine

private func profile(_ goal: Goal = .balanced, flow: SessionFlow? = nil, sessions: Int = 3) -> Profile {
    Profile(goal: goal, sessionsPerWeek: sessions, experience: .intermediate, climbingDaysPerWeek: 0, sessionFlow: flow)
}

private func kinds(_ s: Session) -> [BlockKind] { s.blocks.map(\.kind) }

@Suite struct SessionFlowTests {
    @Test func automaticFlowLeavesPlansUnchanged() {
        for goal in Goal.allCases {
            let plain = Generator.generateWeek(profile(goal), seed: 11)
            #expect(Generator.generateWeek(profile(goal, flow: SessionFlow()), seed: 11) == plain)
        }
    }

    @Test func blockSwitchedOffIsGoneAndTimeStays() {
        let flow = SessionFlow(off: [.warmup, .cooldown, .mobility])
        let p = profile(.balanced, flow: flow)
        for s in Generator.generateWeek(p, seed: 3).sessions {
            #expect(!kinds(s).contains(.warmup))
            #expect(!kinds(s).contains(.cooldown))
            #expect(!kinds(s).contains(.mobility))
            let split = Generator.flowMinutes(p, focus: s.focus, minutes: s.targetMin, flow: flow)
            #expect(split.reduce(0) { $0 + $1.minutes } == s.targetMin)
            #expect(split.allSatisfy { ![.warmup, .cooldown, .mobility].contains($0.kind) })
        }
    }

    @Test func freedTimeGoesToWorkBlocks() {
        let p = profile(.balanced)
        let auto = Generator.flowMinutes(p, focus: .fullLower, minutes: 60, flow: nil)
        let off = Generator.flowMinutes(p, focus: .fullLower, minutes: 60, flow: SessionFlow(off: [.cooldown]))
        let strength = { (x: [(kind: BlockKind, minutes: Int)]) in x.first { $0.kind == .strength }?.minutes ?? 0 }
        #expect(strength(off) > strength(auto))
        #expect(off.first { $0.kind == .warmup }?.minutes == auto.first { $0.kind == .warmup }?.minutes)
    }

    @Test func blockSwitchedOnGetsItsMinimum() {
        let p = profile(.strength)
        let auto = Generator.autoFlowMinutes(p, focus: .upper, minutes: 60)
        let flow = SessionFlow().setting(.cardio, true, autoMinutes: auto)
        let split = Generator.flowMinutes(p, focus: .upper, minutes: 60, flow: flow)
        #expect((split.first { $0.kind == .cardio }?.minutes ?? 0) >= SessionFlow.minimum(.cardio))
        #expect(split.reduce(0) { $0 + $1.minutes } == 60)
        let s = Generator.generateWeek(profile(.strength, flow: flow), seed: 2).sessions[0]
        #expect(kinds(s).contains(.cardio))
    }

    @Test func draggedSharesSetTheSplit() {
        let flow = SessionFlow(shares: [.warmup: 10, .strength: 40, .cooldown: 10])
        let split = Generator.flowMinutes(profile(), focus: .upper, minutes: 60, flow: flow)
        #expect(split.map(\.kind) == [.warmup, .strength, .cooldown])
        #expect(split.map(\.minutes) == [10, 40, 10])
        let longer = Generator.flowMinutes(profile(), focus: .upper, minutes: 90, flow: flow)
        #expect(longer.map(\.minutes) == [15, 60, 15])
    }

    @Test func switchingOffWithSharesRedistributes() {
        let flow = SessionFlow(shares: [.warmup: 8, .strength: 40, .mobility: 6, .cooldown: 6])
        let off = flow.setting(.mobility, false)
        #expect(off.shares?[.mobility] == nil)
        #expect(off.shares?[.strength] == 46)
        #expect(off.off.contains(.mobility))
    }

    @Test func lastWorkBlockStays() {
        let flow = SessionFlow(off: [.power, .mobility, .cardio])
        #expect(flow.setting(.strength, false) == flow)
        #expect(SessionFlow(off: Set(SessionFlow.workBlocks)).sanitized.contains(.strength))
    }

    @Test func perWorkoutFlowChangesOnlyThatWorkout() {
        var p = profile(.balanced)
        let plain = Generator.generateWeek(p, seed: 9)
        p.sessionStyles = ["w1s1": SessionStyle(flow: SessionFlow(off: [.cooldown]))]
        let plan = Generator.generateWeek(p, seed: 9)
        #expect(!kinds(plan.sessions[0]).contains(.cooldown))
        #expect(kinds(plain.sessions[0]).contains(.cooldown))
        #expect(Array(plan.sessions.dropFirst()) == Array(plain.sessions.dropFirst()))
    }

    @Test func conditioningKeepsItsSplitUnderPlanShares() {
        let flow = SessionFlow(shares: [.warmup: 10, .strength: 40, .cooldown: 10])
        let p = profile(.endurance, flow: flow, sessions: 4)
        let auto = Generator.flowMinutes(p, focus: .conditioning, minutes: 50, flow: SessionFlow())
        let plan = Generator.generateWeek(p, seed: 4)
        if let c = plan.sessions.first(where: { $0.focus == .conditioning }) {
            #expect(c.blocks.contains { $0.kind == .cardio } == auto.contains { $0.kind == .cardio })
        }
    }

    @Test func presetsAreDistinctAndFullIsAutomatic() {
        #expect(SessionFlow.Preset.full.flow.isAuto)
        #expect(Set(SessionFlow.Preset.allCases.map(\.flow)).count == SessionFlow.Preset.allCases.count)
        #expect(SessionFlow.Preset.liftFocus.flow.preset == .liftFocus)
    }

    @Test func flowRoundTripsAndOlderProfilesDecode() throws {
        let flow = SessionFlow(off: [.power], on: [.cardio], shares: [.warmup: 8, .strength: 40, .cardio: 10])
        let back = try JSONDecoder().decode(SessionFlow.self, from: JSONEncoder().encode(flow))
        #expect(back == flow)
        let json = #"{"goal":"build","sessionsPerWeek":4,"experience":"beginner","climbingDaysPerWeek":0,"equipment":["dumbbells"]}"#
        #expect(try JSONDecoder().decode(Profile.self, from: Data(json.utf8)).sessionFlow == nil)
        let odd = #"{"off":["warmup","teleport"],"on":[],"shares":{"strength":40,"teleport":5}}"#
        let lenient = try JSONDecoder().decode(SessionFlow.self, from: Data(odd.utf8))
        #expect(lenient.off == [.warmup])
        #expect(lenient.shares == [.strength: 40])
    }

    @Test func customWorkoutPlaysFlowAroundItsExercises() throws {
        let p = Profile(goal: .balanced, experience: .intermediate, climbingDaysPerWeek: 0)
        var w = CustomWorkout(name: "Legs", items: [.init(exerciseId: "back-squat", sets: 4, reps: 6)])
        w.flow = Generator.flowBlocks(p, around: [Exercise.get("back-squat")], minutes: [.warmup: 6, .cooldown: 5, .mobility: 6], seed: 1)
        #expect(w.flow.map(\.kind) == [.warmup, .mobility, .cooldown])
        let s = w.session
        #expect(kinds(s) == [.warmup, .strength, .mobility, .cooldown])
        #expect(s.blocks.flatMap(\.items).allSatisfy { $0.uid.hasPrefix(w.sessionId) })
        #expect(Set(s.blocks.flatMap(\.items).map(\.uid)).count == s.blocks.flatMap(\.items).count)
        let back = try JSONDecoder().decode(CustomWorkout.self, from: JSONEncoder().encode(w))
        #expect(back.flow == w.flow)
        #expect(w.duplicated().flow == w.flow)
        // No flow: the same single block as before.
        #expect(kinds(CustomWorkout(name: "x", items: w.items).session) == [.strength])
    }

    @Test func flowBlocksNeedExercises() {
        #expect(Generator.flowBlocks(Profile(), around: [], minutes: [.warmup: 6], seed: 1).isEmpty)
    }

    // MARK: My picks (#204)

    private func picked(_ picks: BlockPicks, kind: BlockKind = .warmup, equipment: [Equipment]? = nil) -> Profile {
        var p = profile(.balanced)
        if let equipment { p.equipment = equipment }
        p.setPicks(picks, for: kind)
        return p
    }

    @Test func noPicksLeavePlansUnchanged() {
        var p = profile(.balanced)
        p.setPicks(BlockPicks(), for: .warmup)
        #expect(p.blockPicks == nil)
        #expect(Generator.generateWeek(p, seed: 8) == Generator.generateWeek(profile(.balanced), seed: 8))
    }

    @Test func pinnedWarmupGoesFirstEveryWorkout() {
        let p = picked(BlockPicks(items: [BlockPick(exerciseId: "treadmill-run", minutes: 7)]))
        for s in Generator.generateWeek(p, seed: 8).sessions {
            let wu = s.blocks.first { $0.kind == .warmup }
            #expect(wu?.items.first?.exerciseId == "treadmill-run")
            #expect(wu?.items.first?.prescription.reps == "7 min")
            #expect(wu?.items.filter { $0.exerciseId == "treadmill-run" }.count == 1)
        }
    }

    @Test func onlyMyPicksKeepsJustThem() {
        let p = picked(BlockPicks(items: [BlockPick(exerciseId: "treadmill-run", minutes: 7)], only: true))
        let wu = Generator.generateWeek(p, seed: 8).sessions[0].blocks.first { $0.kind == .warmup }
        #expect(wu?.items.map(\.exerciseId) == ["treadmill-run"])
        #expect(wu?.targetMin == 7)
    }

    @Test func picksTheGymLacksAreSkipped() {
        let p = picked(BlockPicks(items: [BlockPick(exerciseId: "treadmill-run", minutes: 7)], only: true),
                       equipment: [.dumbbells, .bench, .mat])
        let wu = Generator.generateWeek(p, seed: 8).sessions[0].blocks.first { $0.kind == .warmup }
        #expect(wu?.items.contains { $0.exerciseId == "treadmill-run" } == false)
        #expect(wu?.items.isEmpty == false)
    }

    @Test func cooldownPicksAndOwnWorkouts() {
        let picks = BlockPicks(items: [BlockPick(exerciseId: "pigeon", minutes: 2)])
        let p = picked(picks, kind: .cooldown)
        let cd = Generator.generateWeek(p, seed: 8).sessions[0].blocks.first { $0.kind == .cooldown }
        #expect(cd?.items.first?.exerciseId == "pigeon")
        let around = [Exercise.get("back-squat")]
        let custom = Generator.flowBlocks(p, around: around, minutes: [.cooldown: 6], seed: 1)
        #expect(custom.first?.items.first?.exerciseId == "pigeon")
        var off = picks
        off.inCustom = false
        let q = picked(off, kind: .cooldown)
        let plain = Generator.flowBlocks(q, around: around, minutes: [.cooldown: 6], seed: 1)
        #expect(plain.first?.items.first?.exerciseId != "pigeon" || plain.first?.items.first?.prescription.note != "Your pick")
    }

    @Test func picksRoundTrip() throws {
        let p = picked(BlockPicks(items: [BlockPick(exerciseId: "treadmill-run", minutes: 7)], only: true))
        let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p))
        #expect(back.picks(.warmup) == p.picks(.warmup))
    }
}
