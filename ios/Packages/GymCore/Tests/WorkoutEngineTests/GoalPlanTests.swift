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
}
