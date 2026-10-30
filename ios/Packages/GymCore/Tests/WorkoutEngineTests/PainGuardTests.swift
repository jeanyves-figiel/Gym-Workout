import Foundation
import Testing
@testable import WorkoutEngine

/// Train around pain (#870).
@Suite struct PainGuardTests {
    let profile = Profile(goal: .athletic, sessionsPerWeek: 4, experience: .intermediate, climbingDaysPerWeek: 0)

    @Test func everyAreaAndLevelLeavesNoRiskyMoveAndKeepsUids() {
        let plan = Generator.generateWeek(profile, week: 2, seed: 4)
        let uids = Set(plan.sessions.flatMap { $0.blocks.flatMap(\.items).map(\.uid) })
        for area in PainArea.allCases {
            for level in PainLevel.allCases {
                let guardIt = PainProtect(area: area, side: .right, level: level)
                let out = guardIt.guarded(plan, profile: profile)
                for s in out.plan.sessions {
                    #expect(!s.blocks.contains { $0.items.isEmpty }, "\(area) \(level) empty block")
                    for it in s.blocks.flatMap(\.items) {
                        if let e = Exercise.find(it.exerciseId) { #expect(!guardIt.risky(e), "\(area) \(level) \(it.exerciseId)") }
                        #expect(uids.contains(it.uid))
                    }
                }
                for c in out.changes {
                    #expect(Exercise.find(c.from) != nil)
                    if let to = c.to { #expect(Exercise.find(to) != nil && to != c.from) }
                }
                #expect(out.swapped.isSubset(of: uids))
            }
        }
    }

    @Test func eachLevelSwapsAtLeastAsMuch() {
        for area in PainArea.allCases {
            let counts = PainLevel.allCases.map { l in Exercise.catalog.filter { PainProtect(area: area, level: l).risky($0) }.count }
            #expect(counts == counts.sorted(), "\(area) \(counts)")
            #expect(counts[0] > 0, "\(area) mild swaps nothing")
        }
    }

    @Test func kneeSwapsSquatsAndJumpsNotPresses() {
        let knee = PainProtect(area: .knee, side: .right, level: .loaded)
        #expect(knee.risky(Exercise.get("back-squat")))
        #expect(knee.risky(Exercise.get("walking-lunge")))
        #expect(knee.risky(Exercise.get("box-jump")))
        #expect(!knee.risky(Exercise.get("leg-press")))
        #expect(!knee.risky(Exercise.get("bench-press")))
        #expect(PainProtect(area: .knee, level: .sharp).risky(Exercise.get("leg-press")))
        #expect(!PainProtect(area: .knee, level: .mild).risky(Exercise.get("back-squat")))
    }

    @Test func spotDayAndAdvice() {
        let since = Date(timeIntervalSince1970: 1_792_454_400)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let p = PainProtect(area: .knee, side: .right, level: .loaded, since: since)
        #expect(p.spot == "right knee")
        #expect(PainProtect(area: .lowerBack, side: .left, level: .mild).spot == "lower back")
        #expect(p.day(now: since, calendar: cal) == 1)
        #expect(p.day(now: since.addingTimeInterval(3 * 86_400), calendar: cal) == 4)
        #expect(!p.longRunning(now: since.addingTimeInterval(13 * 86_400), calendar: cal))
        #expect(p.longRunning(now: since.addingTimeInterval(14 * 86_400), calendar: cal))
        #expect(PainArea.knee.friendly == "Knee-friendly plan")
    }

    @Test func storedProtectDecodes() throws {
        let p = PainProtect(area: .shoulder, side: .left, level: .sharp, since: Date(timeIntervalSince1970: 0), seeDoctor: true)
        let back = try JSONDecoder().decode(PainProtect.self, from: JSONEncoder().encode(p))
        #expect(back == p)
    }
}
