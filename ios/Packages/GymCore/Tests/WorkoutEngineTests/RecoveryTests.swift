import Foundation
import Testing
@testable import WorkoutEngine

/// Mobility & recovery days (#619).
@Suite struct RecoveryTests {
    @Test func routinesResolveToShortMatSessions() {
        let all = Recovery.templates
        #expect(all.count == Recovery.Area.allCases.count)
        #expect(Set(all.map(\.sessionId)).count == all.count)
        for t in all {
            #expect(WorkoutTemplate.find(sessionId: t.sessionId) == t)
            #expect(!WorkoutTemplate.all.contains(t))
            for it in t.items {
                let e = Exercise.find(it.exerciseId)
                #expect(e != nil, "\(t.id): \(it.exerciseId)")
                #expect(e?.equipment.allSatisfy { $0 == .mat } ?? false, "\(t.id): \(it.exerciseId) needs kit")
            }
            #expect(t.session.estMin >= 8 && t.session.estMin <= 18, "\(t.id) \(t.session.estMin) min")
            #expect(t.session.blocks.map(\.kind) == [.mobility, .cooldown], "\(t.id)")
        }
    }

    @Test func areaFollowsTheWeeksLoad() {
        #expect(Recovery.area([:]) == .full)
        #expect(Recovery.area([.quads: 10, .hamstrings: 6, .calves: 2, .chest: 3]) == .legs)
        #expect(Recovery.area([.glutes: 8, .lowerBack: 4, .lats: 3, .quads: 2]) == .hipsBack)
        #expect(Recovery.area([.chest: 6, .frontDelts: 4, .triceps: 4, .quads: 2]) == .upper)
        // Even spread: nothing above 40 %.
        #expect(Recovery.area([.quads: 4, .chest: 2, .frontDelts: 2, .lats: 2, .glutes: 2]) == .full)
    }

    @Test func hardDaysAreTheDaysThatAreaLed() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let mon = Date(timeIntervalSince1970: 1_792_454_400) // 00:00 UTC
        let day: (Int) -> Date = { mon.addingTimeInterval(Double($0) * 86_400 + 18 * 3600) }
        let records: [(start: Date, load: [Muscle: Double])] = [
            (day(2), [.quads: 8, .hamstrings: 4]),
            (day(0), [.quads: 9, .glutes: 2]),
            (day(1), [.chest: 8, .triceps: 4]),
        ]
        let days = Recovery.hardDays(records, area: .legs, calendar: cal)
        #expect(days == [cal.startOfDay(for: day(0)), cal.startOfDay(for: day(2))])
        #expect(Recovery.hardDays(records, area: .full, calendar: cal).isEmpty)
    }

    @Test func finisherOnlyWhenNoCoolDown() throws {
        let strong = try #require(WorkoutTemplate.all.first { t in
            let s = t.session
            return !s.blocks.contains { $0.kind == .cooldown } && s.blocks.contains { $0.kind == .strength }
        })
        let s = strong.session
        let f = Recovery.withFinisher(s)
        let cd = try #require(f.blocks.last)
        #expect(cd.kind == .cooldown)
        #expect(cd.items.count == Recovery.finisherCount)
        #expect(Set(cd.items.map(\.uid)).count == cd.items.count)
        #expect(cd.items.allSatisfy { Exercise.get($0.exerciseId).category == .stretch })
        #expect(cd.estMin >= 4 && cd.estMin <= 6)
        #expect(f.estMin > s.estMin)
        #expect(Recovery.withFinisher(f) == f)
        // Mobility routines and sport prep stay as they are.
        for t in Recovery.templates + SportPrep.templates { #expect(Recovery.withFinisher(t.session) == t.session) }
    }
}
