import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct PlanFollowTests {
    /// A generated week with its sessions laid out on Mon, Wed, Fri, Sat (as many as it has).
    private var plan: WeekPlan {
        var p = Generator.generateWeek(Profile(), week: 1, seed: 7)
        let days = [1, 3, 5, 6]
        for i in p.sessions.indices { p.sessions[i].weekday = days[i % days.count] }
        return p
    }

    @Test func wholeKeepsEverything() {
        #expect(PlanFollow.whole.applying(to: plan, keep: [], today: 3) == plan)
    }

    @Test func someDaysKeepsPickedDaysAndDone() throws {
        let p = plan
        try #require(p.sessions.count >= 2)
        let f = PlanFollow(scope: .someDays, days: [3])
        let out = f.applying(to: p, keep: [p.sessions[0].id], today: 3)
        for s in out.sessions { #expect(s.weekday == 3 || s.id == p.sessions[0].id) }
        #expect(out.sessions.contains { $0.id == p.sessions[0].id })
    }

    @Test func oneAtATimePutsNextOnToday() throws {
        let p = plan
        try #require(p.sessions.count >= 2)
        let f = PlanFollow(scope: .oneAtATime)
        let out = f.applying(to: p, keep: [p.sessions[0].id], today: 4)
        #expect(out.sessions.count == 2)
        #expect(out.sessions[1].id == p.sessions[1].id)
        #expect(out.sessions[1].weekday == 4)
    }

    @Test func ownWorkoutsPlansNothing() {
        let out = PlanFollow(scope: .ownWorkouts).applying(to: plan, keep: [], today: 1)
        #expect(out.sessions.isEmpty)
    }

    @Test func cutsShortenNotStarted() throws {
        let p = plan
        let s = try #require(p.sessions.first { $0.hiit == nil && $0.blocks.contains { $0.kind == .warmup } })
        let lifts = WorkoutCut.lifts.apply(s)
        #expect(lifts.blocks.allSatisfy { $0.kind == .strength || $0.kind == .power })
        #expect(lifts.estMin <= s.estMin)
        let quick = WorkoutCut.quick.apply(s)
        #expect(quick.estMin <= s.estMin)
        // Done sessions are never cut.
        let out = PlanFollow(cut: .lifts).applying(to: p, keep: [s.id], today: 1)
        #expect(out.sessions.first { $0.id == s.id } == s)
    }

    @Test func tolerantDecoding() throws {
        let json = #"{"scope":"later","days":[9,2,1],"cut":"tiny"}"#.data(using: .utf8)!
        let f = try JSONDecoder().decode(PlanFollow.self, from: json)
        #expect(f == PlanFollow(scope: .whole, days: [1, 2], cut: .full))
        #expect(PlanFollow(scope: .someDays, days: [4, 1], cut: .lifts).summary { "D\($0)" } == "Some days · D1 D4 · Lifts only")
    }
}
