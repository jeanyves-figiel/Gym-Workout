import Foundation
import Testing
@testable import WorkoutEngine

/// Sport season blocks, add-on and Coach suggestion (#620).
@Suite struct SeasonBlockTests {
    let profile = Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0)

    @Test func everySeasonSportOpensAProgramme() {
        for s in SeasonSport.allCases {
            let p = Programme.find(s.programmeId)
            #expect(p != nil, "\(s)")
        }
        for p in Programme.seasonBlocks {
            #expect(p.isSeason)
            #expect(!Programme.all.contains(p))
            #expect(p.weeks == 8)
            for id in p.lifts { #expect(Exercise.find(id) != nil, "\(p.id) lift \(id)") }
            for sig in p.signatures {
                for it in sig.items { #expect(Exercise.find(it.exerciseId) != nil, "\(p.id) \(sig.id) \(it.exerciseId)") }
            }
            // Fits a season start: shorter and longer than the standard 8 weeks.
            #expect(p.resized(to: 5).weeks == 5)
            #expect(p.resized(to: 12).weeks == 12)
        }
        #expect(SeasonSport.of(.tennis) == .padel)
        #expect(SeasonSport.of(.golf) == nil)
    }

    @Test func seasonWeeksAreClamped() {
        let cal = Progression.calendar()
        let now = Date(timeIntervalSince1970: 1_792_454_400)
        let far = cal.date(byAdding: .weekOfYear, value: 30, to: now)!
        let near = cal.date(byAdding: .day, value: 8, to: now)!
        let eight = cal.date(byAdding: .weekOfYear, value: 8, to: now)!
        #expect(Programme.seasonWeeks(until: far, now: now, calendar: cal) == Programme.seasonMaxWeeks)
        #expect(Programme.seasonWeeks(until: near, now: now, calendar: cal) == Programme.seasonMinWeeks)
        #expect(Programme.seasonWeeks(until: eight, now: now, calendar: cal) == 8)
    }

    @Test func addOnGoesIntoTheFirstStrengthSessions() {
        let plan = Generator.generateWeek(profile, week: 2, seed: 3)
        #expect(SportAddOn.apply(plan, nil) == plan)
        let out = SportAddOn.apply(plan, SportAddOnPref(sport: .climb, perWeek: 2))
        let withIt = out.sessions.filter { s in s.blocks.flatMap(\.items).contains { $0.uid.hasSuffix("-ao0") } }
        #expect(withIt.count == 2)
        for s in withIt {
            let before = plan.sessions.first { $0.id == s.id }!
            #expect(s.estMin == before.estMin + SportAddOn.minutes)
            #expect(Set(s.blocks.map(\.kind)).count == s.blocks.count, "one block per kind")
            #expect(s.blocks.contains { $0.kind == .mobility && $0.title.contains("Climb add-on") })
            let uids = s.blocks.flatMap(\.items).map(\.uid)
            #expect(Set(uids).count == uids.count)
        }
        for s in SeasonSport.allCases {
            for it in SportAddOn.items(s, sessionId: "x") { #expect(Exercise.find(it.exerciseId) != nil, "\(s) \(it.exerciseId)") }
        }
        #expect(SportAddOnPref(sport: .run, perWeek: 9).perWeek == 3)
    }

    @Test func coachSuggestsAfterThreeSessionsInTwoWeeks() {
        let now = Date(timeIntervalSince1970: 1_792_454_400)
        let day: (Double) -> Date = { now.addingTimeInterval(-$0 * 86_400) }
        #expect(SportAddOn.suggestion([(.padel, day(1)), (.tennis, day(5))], now: now) == nil)
        let s = SportAddOn.suggestion([(.padel, day(1)), (.tennis, day(5)), (.padel, day(9)), (.run, day(2)), (.padel, day(20))], now: now)
        #expect(s?.sport == .padel && s?.count == 3)
    }
}
