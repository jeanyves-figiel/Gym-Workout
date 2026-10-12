import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct GoalPlanTests {
    @Test func recommendedSessionsSitInRangeAndHaveASplit() {
        for g in Goal.allCases {
            #expect(g.sessionRange.contains(g.recommendedSessions))
            #expect(Rules.splits[g.recommendedSessions] != nil)
            let s = g.mixShares
            #expect(abs(s.power + s.strength + s.mobility + s.cardio - 1) < 1e-9)
        }
    }

    @Test func pickingAGoalAppliesItsWeekAndKeepsClimbing() {
        var p = Profile(goal: .balanced, sessionsPerWeek: 6, climbingDaysPerWeek: 2, climbingWeekdays: [2, 4])
        p.applyGoal(.build)
        #expect(p.sessionsPerWeek == 4)
        #expect(p.climbingDaysPerWeek == 2)
        #expect(p.climbingDays == [2, 4])
        var q = Profile(climbingDaysPerWeek: 0)
        #expect(!q.climbs)
        q.applyGoal(.climbing)
        #expect(q.sessionsPerWeek == 2)
        #expect(q.climbs && q.climbingDaysPerWeek == 2)
    }

    @Test func climbsToggle() {
        var p = Profile(goal: .build, climbingDaysPerWeek: 3, climbingWeekdays: [1, 3, 5])
        #expect(p.climbs)
        p.climbs = false
        #expect(p.climbingDaysPerWeek == 0 && p.climbingDays.isEmpty && !Generator.isClimber(p))
        p.climbs = true
        #expect(p.climbingDaysPerWeek == 2 && Generator.isClimber(p))
    }

    @Test func recommendedMinutesMatchGenerator() {
        let p = Profile(experience: .advanced)
        var q = p
        q.applyGoal(.endurance)
        #expect(p.recommendedMinutes(for: .endurance) == Generator.sessionMinutes(q))
    }

    @Test func profileGymIsOptionalAndRoundTrips() throws {
        let old = try JSONEncoder().encode(Profile())
        var json = try JSONSerialization.jsonObject(with: old) as! [String: Any]
        json.removeValue(forKey: "gym")
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.gym == nil)

        let ref = GymRef(id: "mk-1", name: "Test Gym", address: "Somewhere 1", latitude: 47.38, longitude: 8.52)
        let p = Profile(gym: ref)
        let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p))
        #expect(back.gym == ref)
        #expect(Gym.puls5.ref.scoped?.id == Gym.puls5.id)
        #expect(ref.scoped == nil)
    }

    // MARK: Goal change re-plans the week (#194)

    private func week(_ g: Goal, sessions: Int? = nil, seed: UInt32 = 5) -> WeekPlan {
        var p = Profile(experience: .intermediate, climbingDaysPerWeek: 0)
        p.applyGoal(g)
        if let sessions { p.sessionsPerWeek = sessions }
        return Generator.generateWeek(p, seed: seed)
    }

    private func strengthIds(_ plan: WeekPlan) -> [String] {
        plan.sessions.flatMap { $0.blocks.filter { $0.kind == .strength }.flatMap(\.items) }.map(\.exerciseId)
    }

    @Test func balancedAndClimbingKeepTheDefaultSplit() {
        for n in 2...6 {
            #expect(Rules.split(.balanced, n) == Rules.splits[n])
            #expect(Rules.split(.climbing, n) == Rules.splits[n])
            for g in Goal.allCases { #expect(Rules.split(g, n).count == n, "\(g) \(n)") }
        }
    }

    @Test func goalsShapeTheirWeek() {
        #expect(week(.build, sessions: 3).sessions.map(\.focus) == [.push, .pull, .legs])
        #expect(week(.endurance).sessions.filter { $0.focus == .conditioning }.count == 2)
        #expect(week(.athletic).sessions.filter { $0.focus == .fullPower }.count >= 1)
        #expect(!week(.strength, sessions: 5).sessions.contains { $0.focus == .conditioning })
    }

    @Test func everyGoalChangeChangesTheWeek() {
        let plans = Goal.allCases.map { ($0, week($0)) }
        for (a, pa) in plans {
            for (b, pb) in plans where a != b {
                let sameShape = pa.sessions.map(\.focus) == pb.sessions.map(\.focus)
                let sameExercises = strengthIds(pa) == strengthIds(pb)
                #expect(!(sameShape && sameExercises), "\(a) → \(b) left the week as it was")
            }
        }
    }

    @Test func goalBiasPicksItsKindOfExercise() throws {
        // Same 4-day upper / lower split, different accessories.
        let balanced = Set(strengthIds(week(.balanced, sessions: 4)))
        let build = Set(strengthIds(week(.build, sessions: 4)))
        #expect(balanced != build)
        let strength = Exercise.catalog.filter { $0.category == .strength && $0.generator }
        let barbell = try #require(strength.first { $0.equipment.contains(.barbell) })
        let machine = try #require(strength.first { $0.equipment == [.legPress] || $0.equipment == [.cable] })
        let light = try #require(strength.first { $0.equipment == [.dumbbells] || $0.equipment.isEmpty })
        #expect(Selector.goalBias(.strength, barbell, main: true) > Selector.goalBias(.strength, machine, main: true))
        #expect(Selector.goalBias(.build, machine, main: false) > Selector.goalBias(.build, light, main: false))
        #expect(Selector.goalBias(.build, machine, main: true) == 0)
        #expect(Selector.goalBias(.endurance, light, main: false) > Selector.goalBias(.endurance, barbell, main: false))
        for e in [barbell, machine, light] {
            #expect(Selector.goalBias(.balanced, e, main: true) == 0 && Selector.goalBias(.climbing, e, main: false) == 0)
        }
    }

    @Test func quickSessionWorksForFociTheGoalWeekLacks() {
        var p = Profile(climbingDaysPerWeek: 0)
        p.applyGoal(.endurance)
        for f in Generator.quickFoci {
            #expect(Generator.quickSession(p, focus: f, week: 1, seed: 3)?.focus == f, "\(f)")
            #expect(Generator.quickSession(p, focus: f, week: 1, seed: 3, minutes: 20)?.focus == f, "\(f) 20 min")
        }
    }

    @Test func keepingLeavesDoneSessionsAsTheyWere() {
        let old = week(.balanced, sessions: 4)
        let new = week(.strength, sessions: 3)
        let kept = new.keeping(["w1s2", "w1s4"], from: old)
        #expect(kept.sessions.count == 4)
        #expect(kept.sessions.map(\.id) == ["w1s1", "w1s2", "w1s3", "w1s4"])
        #expect(kept.sessions[1] == old.sessions[1])
        #expect(kept.sessions[3] == old.sessions[3])
        #expect(kept.sessions[0] == new.sessions[0])
        #expect(new.keeping([], from: old) == new)
        #expect(new.keeping(["w1s1"], from: nil) == new)
        var otherWeek = old
        otherWeek.week = 2
        #expect(new.keeping(["w1s2"], from: otherWeek) == new)
    }
}
