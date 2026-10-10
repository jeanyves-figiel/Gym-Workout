import Foundation
import Testing
@testable import WorkoutEngine

private func profile(_ v: PlanVariety?, sessions: Int = 4) -> Profile {
    Profile(goal: .balanced, sessionsPerWeek: sessions, experience: .intermediate, climbingDaysPerWeek: 0, variety: v)
}

private func ids(_ s: Session) -> [String] { s.blocks.flatMap { $0.items.map(\.exerciseId) } }
private func mainLift(_ s: Session) -> String? { s.blocks.first { $0.kind == .strength }?.items.first?.exerciseId }
private func week(_ p: Profile, _ w: Int, seed: UInt32 = 11) -> WeekPlan { Generator.generateWeek(p, week: w, seed: seed) }

@Suite struct VarietyTests {
    @Test func olderProfilesDefaultToFresh() throws {
        let json = #"{"goal":"balanced","sessionsPerWeek":3,"experience":"intermediate","climbingDaysPerWeek":0,"equipment":[]}"#
        let p = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        #expect(p.variety == nil)
        #expect(p.planVariety == .fresh)
    }

    @Test(arguments: [2, 3, 4, 5, 6])
    func sameRepeatsEveryExercise(sessions: Int) {
        let p = profile(.same, sessions: sessions)
        let w1 = week(p, 1), w2 = week(p, 2), w3 = week(p, 3)
        #expect(w1.sessions.map(ids) == w2.sessions.map(ids))
        #expect(w1.sessions.map(\.focus) == w3.sessions.map(\.focus))
        #expect(w1.sessions.map(mainLift) == w3.sessions.map(mainLift))
    }

    @Test(arguments: [2, 3, 4, 5, 6])
    func freshKeepsMainLiftsButVariesAccessories(sessions: Int) {
        let p = profile(.fresh, sessions: sessions)
        let weeks = (1...3).map { week(p, $0) }
        for w in weeks.dropFirst() {
            #expect(w.sessions.map(mainLift) == weeks[0].sessions.map(mainLift))
        }
        #expect(Set(weeks.map { $0.sessions.map(ids) }).count > 1)
    }

    @Test(arguments: [2, 3, 4, 5, 6])
    func rotateShiftsDayFocusAndLead(sessions: Int) {
        let p = profile(.rotate, sessions: sessions)
        let w1 = week(p, 1), w2 = week(p, 2)
        // Same sessions in the week (volume per muscle group unchanged), new emphasis.
        #expect(w1.sessions.map(\.focus.rawValue).sorted() == w2.sessions.map(\.focus.rawValue).sorted())
        #expect(w1.sessions.map(mainLift) != w2.sessions.map(mainLift))
    }

    @Test func rotatingLeadKeepsPatterns() {
        let slots = Rules.strengthSlots(.fullLower, variant: 0)
        for step in 0..<4 {
            let r = Rules.rotatingLead(slots, .fullLower, step: step)
            #expect(r.sorted { $0.rawValue < $1.rawValue } == slots.sorted { $0.rawValue < $1.rawValue })
        }
        #expect(Rules.rotatingLead(slots, .fullLower, step: 1).first == .hinge)
        #expect(Rules.rotatedSplit([.upper, .lower, .conditioning], week: 2) == [.lower, .conditioning, .upper])
    }

    @Test func newSeedStillReshuffles() {
        let p = profile(.same)
        #expect(week(p, 1, seed: 1).sessions.map(ids) != week(p, 1, seed: 2).sessions.map(ids))
    }
}
