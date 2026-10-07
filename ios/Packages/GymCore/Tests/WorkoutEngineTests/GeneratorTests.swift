import Foundation
import Testing
@testable import WorkoutEngine

private let base = Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0)
private func allItems(_ p: WeekPlan) -> [PlannedExercise] { p.sessions.flatMap { $0.blocks.flatMap(\.items) } }

@Suite struct CatalogTests {
    @Test func uniqueIds() {
        #expect(Set(Exercise.catalog.map(\.id)).count == Exercise.catalog.count)
        #expect(Exercise.catalog.count >= 150)
    }
}

@Suite struct SessionLengthTests {
    @Test func shorterPerSessionButMoreWeeklyAsFrequencyRises() {
        let mins = (2...6).map { n in Generator.sessionMinutes(withSessions(base, n)) }
        for i in 1..<mins.count { #expect(mins[i] <= mins[i - 1]) }
        let weekly = mins.enumerated().map { $0.element * ($0.offset + 2) }
        for i in 1..<weekly.count { #expect(weekly[i] > weekly[i - 1]) }
    }

    @Test func dependsOnGoal() {
        var s = base; s.goal = .strength
        var c = base; c.goal = .climbing
        #expect(Generator.sessionMinutes(s) > Generator.sessionMinutes(c))
    }

    @Test func respectsCapAndRoundsTo5() {
        var p = base; p.maxSessionMinutes = 45
        #expect(Generator.sessionMinutes(p) <= 45)
        #expect(Generator.sessionMinutes(base) % 5 == 0)
    }
}

@Suite struct WeekTests {
    @Test func deterministic() {
        #expect(Generator.generateWeek(base, seed: 42) == Generator.generateWeek(base, seed: 42))
        #expect(Generator.generateWeek(base, seed: 42) != Generator.generateWeek(base, seed: 43))
    }

    @Test(arguments: Goal.allCases)
    func fitsTargetTime(goal: Goal) {
        for n in 2...6 {
            var p = withSessions(base, n); p.goal = goal
            let plan = Generator.generateWeek(p, seed: 1)
            #expect(plan.sessions.count == n)
            for s in plan.sessions {
                #expect(Double(abs(s.estMin - s.targetMin)) <= max(8, Double(s.targetMin) * 0.15), "\(goal) \(n) \(s.focus)")
            }
        }
    }

    @Test func blockOrder() {
        let order = BlockKind.allCases
        for s in Generator.generateWeek(base, seed: 3).sessions {
            let kinds = s.blocks.map(\.kind)
            #expect(kinds.first == .warmup)
            #expect(kinds.contains(.strength))
            #expect(kinds.last == .cooldown)
            let idx = kinds.map { order.firstIndex(of: $0)! }
            #expect(idx == idx.sorted())
        }
    }

    @Test func balancedHasEveryComponent() {
        for s in Generator.generateWeek(base, seed: 5).sessions {
            let kinds = Set(s.blocks.map(\.kind))
            #expect(kinds.isSuperset(of: [.power, .mobility, .cardio]))
        }
    }

    @Test func onlyAvailableEquipment() {
        let eq: [Equipment] = [.dumbbells, .bench, .cable, .mat, .bike, .bands]
        var p = base; p.equipment = eq
        for it in allItems(Generator.generateWeek(p, seed: 9)) {
            #expect(Exercise.get(it.exerciseId).equipment.allSatisfy { eq.contains($0) })
        }
    }

    @Test func respectsExperience() {
        var p = base; p.experience = .beginner
        for it in allItems(Generator.generateWeek(p, seed: 11)) { #expect(Exercise.get(it.exerciseId).level == 1) }
    }

    @Test func deloadReducesVolume() {
        let w2 = Generator.generateWeek(base, week: 2, seed: 2)
        let w4 = Generator.generateWeek(base, week: 4, seed: 2)
        #expect(w4.deload)
        #expect(w4.sessionMinutes < w2.sessionMinutes)
        func mainSets(_ p: WeekPlan) -> Int { p.sessions[0].blocks.first { $0.kind == .strength }!.items[0].prescription.sets }
        #expect(mainSets(w4) < mainSets(w2))
        for s in w4.sessions { for b in s.blocks where b.kind == .cardio { #expect(b.title.contains("Zone 2")) } }
    }

    @Test func climberPrehabAndGripSparing() {
        let p = Profile(goal: .climbing, sessionsPerWeek: 4, experience: .intermediate, climbingDaysPerWeek: 3)
        let plan = Generator.generateWeek(p, seed: 4)
        for s in plan.sessions where s.focus == .upper {
            #expect(s.blocks.first { $0.kind == .strength }!.items.map(\.slot).contains(.shoulderHealth))
        }
        #expect(allItems(plan).contains { Exercise.get($0.exerciseId).pattern == .forearmAntagonist })
        let strength = plan.sessions.flatMap { $0.blocks.filter { $0.kind == .strength }.flatMap(\.items) }
        #expect(strength.filter { Exercise.get($0.exerciseId).gripHeavy }.count <= 1)
    }

    @Test func cooldownTargetsMostLoadedMuscle() {
        for s in Generator.generateWeek(withSessions(base, 4), seed: 8).sessions {
            let cd = s.blocks.first { $0.kind == .cooldown }!
            let load = Generator.muscleLoad(s.blocks)
            let top = load.max { $0.value < $1.value }!.key
            #expect(cd.items.flatMap { Exercise.get($0.exerciseId).primary }.contains(top))
            #expect(cd.items.last?.exerciseId == "breathing")
        }
    }

    @Test func variesAcrossWeek() {
        let plan = Generator.generateWeek(withSessions(base, 4), seed: 12)
        let mains = plan.sessions.map { $0.blocks.first { $0.kind == .strength }!.items[0].exerciseId }
        #expect(mains[0] != mains[2])
        #expect(mains[1] != mains[3])
    }

    @Test func supersetsReferenceHostInSameBlock() {
        let plan = Generator.generateWeek(Profile(goal: .climbing, sessionsPerWeek: 3, climbingDaysPerWeek: 2), seed: 21)
        for s in plan.sessions {
            let st = s.blocks.first { $0.kind == .strength }!
            for it in st.items {
                if let host = it.supersetWith { #expect(st.items.contains { $0.uid == host }) }
            }
        }
    }

    @Test func swapAlternativesSharePattern() {
        let alts = Exercise.get("back-squat").alternatives(for: Profile(experience: .advanced))
        #expect(alts.count > 2)
        #expect(alts.allSatisfy { $0.pattern == .squat })
    }

    @Test func planIsCodableRoundTrip() throws {
        let plan = Generator.generateWeek(base, seed: 7)
        let data = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(WeekPlan.self, from: data) == plan)
    }
}

private func withSessions(_ p: Profile, _ n: Int) -> Profile {
    var q = p
    q.sessionsPerWeek = n
    return q
}
