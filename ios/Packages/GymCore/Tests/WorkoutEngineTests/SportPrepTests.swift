import Foundation
import Testing
@testable import WorkoutEngine

/// Sport prep on sport days (#523).
@Suite struct SportPrepTests {
    @Test func everySportButClimbingHasPrep() {
        for s in Sport.allCases {
            if s == .climbing {
                #expect(SportPrep.before(s) == nil && SportPrep.after(s) == nil)
            } else {
                #expect(SportPrep.before(s) != nil && SportPrep.after(s) != nil, "\(s)")
            }
        }
    }

    @Test func prepResolvesToShortPlayableSessions() {
        let all = SportPrep.templates
        #expect(all.count == SportPrep.Family.allCases.count * 2)
        #expect(Set(all.map(\.sessionId)).count == all.count)
        for t in all {
            #expect(WorkoutTemplate.find(sessionId: t.sessionId) == t)
            #expect(!WorkoutTemplate.all.contains(t))
            for it in t.items { #expect(Exercise.find(it.exerciseId) != nil, "\(t.id): \(it.exerciseId)") }
            #expect(t.session.estMin >= 2 && t.session.estMin <= 15, "\(t.id) \(t.session.estMin) min")
        }
        // Before: warm-up only and no kit (done at the slope, trail or court); after: cool-down only.
        for f in SportPrep.Family.allCases {
            let pair = SportPrep.pairs[f]!
            #expect(pair.before.session.blocks.map(\.kind) == [.warmup], "\(f)")
            #expect(pair.after.session.blocks.map(\.kind) == [.cooldown], "\(f)")
            #expect(pair.before.items.allSatisfy { Exercise.get($0.exerciseId).equipment.isEmpty }, "\(f)")
        }
    }
}
