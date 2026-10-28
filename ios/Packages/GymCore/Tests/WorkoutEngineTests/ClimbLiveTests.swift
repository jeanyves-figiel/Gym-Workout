import Foundation
import Testing
@testable import WorkoutEngine

/// Climbing live tally (#829).
@Suite struct ClimbLiveTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func go(_ grade: String, _ result: ClimbResult, _ minute: Double) -> ClimbAttempt {
        ClimbAttempt(grade: grade, result: result, at: t0.addingTimeInterval(minute * 60))
    }

    @Test func countsTopAndPyramid() {
        let a = [go("6A", .flash, 1), go("6B", .fall, 5), go("6B", .send, 9), go("6C", .fall, 14), go("5+", .flash, 18)]
        let t = ClimbTally(a, scale: .font)
        #expect(t.flashes == 2)
        #expect(t.sends == 1)
        #expect(t.falls == 2)
        #expect(t.tops == 3)
        #expect(t.attempts == 5)
        #expect(t.top == "6B")
        #expect(t.pyramid.map(\.grade) == ["6C", "6B", "6A", "5+"])
        #expect(t.pyramid[1] == ClimbTally.Row(grade: "6B", tops: 1, falls: 1))
        #expect(t.summary == "3 sends · 2 flashes · 2 falls")
    }

    @Test func vScaleRanksNumerically() {
        let t = ClimbTally([go("V9", .fall, 1), go("V10", .send, 2), go("V2", .flash, 3)], scale: .v)
        #expect(t.top == "V10")
        #expect(t.pyramid.map(\.grade) == ["V10", "V9", "V2"])
    }

    @Test func emptyAndFallsOnly() {
        #expect(ClimbTally([], scale: .font).summary == nil)
        let t = ClimbTally([go("7A", .fall, 1)], scale: .font)
        #expect(t.top == nil)
        #expect(t.summary == "0 sends · 1 fall")
    }

    @Test func effortAndRest() {
        #expect(ClimbTally.effort(attempts: 0, minutes: 10) == 3)
        #expect(ClimbTally.effort(attempts: 20, minutes: 90) == 9)
        #expect(ClimbTally.effort(attempts: 60, minutes: 180) == 10)
        #expect(ClimbTally.rest([], now: t0) == nil)
        #expect(ClimbTally.rest([go("6A", .send, 1), go("6A", .send, 3)], now: t0.addingTimeInterval(200)) == 20)
    }

    @Test func scalesStartOnTheirList() {
        for s in ClimbScale.allCases { #expect(s.rank(s.start) != nil) }
    }
}
