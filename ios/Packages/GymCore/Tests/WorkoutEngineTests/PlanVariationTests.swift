import Foundation
import Testing
@testable import WorkoutEngine

private let profile = Profile(goal: .balanced, sessionsPerWeek: 4, experience: .intermediate, climbingDaysPerWeek: 0)
private let plan = Generator.generateWeek(profile, week: 2, seed: 21)

private func items(_ p: WeekPlan, _ session: Int) -> [(Block, Int, PlannedExercise)] {
    p.sessions[session].blocks.flatMap { b in b.items.enumerated().map { (b, $0.offset, $0.element) } }
}

@Suite struct PlanVariationTests {
    @Test func onlyRequestedDaysAndPartsChange() {
        let day = plan.sessions[1].id
        let swaps = plan.varied(VaryRequest(sessions: [day], parts: [.accessories], seed: 1), profile: profile)
        #expect(!swaps.isEmpty)
        let varied = plan.applying(PlanVariation(week: plan.week, seed: plan.seed, swaps: swaps))
        for s in plan.sessions.indices where s != 1 { #expect(varied.sessions[s] == plan.sessions[s]) }
        for ((b, i, before), (_, _, after)) in zip(items(plan, 1), items(varied, 1)) where before.exerciseId != after.exerciseId {
            #expect(b.varyPart(at: i) == .accessories)
            // Same movement → same muscle focus; same unit and sides.
            let o = Exercise.get(before.exerciseId), n = Exercise.get(after.exerciseId)
            #expect(o.pattern == n.pattern)
            #expect(o.unit == n.unit && o.unilateral == n.unilateral)
            #expect(before.prescription.sets == after.prescription.sets)
        }
    }

    @Test func mainLiftsStayUnlessAsked() {
        let all = Set(plan.sessions.map(\.id))
        let mains = { (p: WeekPlan) in p.sessions.map { $0.blocks.first { $0.kind == .strength }?.items.first?.exerciseId } }
        let keep = plan.applying(PlanVariation(week: 2, seed: 21, swaps: plan.varied(VaryRequest(sessions: all, seed: 3), profile: profile)))
        #expect(mains(keep) == mains(plan))
        let swapped = plan.applying(PlanVariation(week: 2, seed: 21,
                                                  swaps: plan.varied(VaryRequest(sessions: all, parts: [.mainLifts], seed: 3), profile: profile)))
        #expect(mains(swapped) != mains(plan))
        for m in mains(swapped).compactMap({ $0 }) { #expect(Exercise.get(m).main) }
    }

    @Test func keptExercisesStayAndNoDuplicatesInADay() {
        let all = Set(plan.sessions.map(\.id))
        let keep = Set(items(plan, 0).map(\.2.uid))
        let swaps = plan.varied(VaryRequest(sessions: all, parts: Set(VaryPart.allCases), keep: keep, seed: 9), profile: profile)
        #expect(swaps.keys.allSatisfy { !keep.contains($0) })
        let varied = plan.applying(PlanVariation(week: 2, seed: 21, swaps: swaps))
        for s in varied.sessions {
            let ids = s.blocks.filter { $0.kind != .cooldown }.flatMap { $0.items.map(\.exerciseId) }
            #expect(ids.count == Set(ids).count, "\(s.id)")
        }
    }

    @Test func deterministicAndShuffleChanges() {
        let r = VaryRequest(sessions: [plan.sessions[2].id], seed: 5)
        #expect(plan.varied(r, profile: profile) == plan.varied(r, profile: profile))
        var other = r
        other.seed = 6
        #expect(plan.varied(r, profile: profile) != plan.varied(other, profile: profile))
    }

    @Test func reshuffleBuildsOnCurrentSwaps() {
        let day = plan.sessions[0].id
        let first = plan.varied(VaryRequest(sessions: [day], seed: 1), profile: profile)
        let second = plan.varied(VaryRequest(sessions: [plan.sessions[1].id], seed: 2), profile: profile, current: first)
        for (k, v) in first { #expect(second[k] == v) }
    }

    @Test func variationForAnotherPlanIsIgnored() {
        let swaps = plan.varied(VaryRequest(sessions: [plan.sessions[0].id], seed: 1), profile: profile)
        #expect(plan.applying(PlanVariation(week: 3, seed: 21, swaps: swaps)) == plan)
        #expect(plan.applying(PlanVariation(week: 2, seed: 22, swaps: swaps)) == plan)
    }

    @Test func codableRoundTrip() throws {
        let v = PlanVariation(week: 2, seed: 21, swaps: ["w2s1-st-1": "db-row"])
        #expect(try JSONDecoder().decode(PlanVariation.self, from: JSONEncoder().encode(v)) == v)
    }
}
