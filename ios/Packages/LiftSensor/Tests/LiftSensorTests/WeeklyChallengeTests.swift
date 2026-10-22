import Foundation
import Testing
@testable import LiftSensor

/// Weekly challenge room (#626 C).
@Suite struct WeeklyChallengeTests {
    private let utc = TimeZone(identifier: "UTC")!
    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    @Test func weekKeyMatchesTheServer() {
        // Same cases as backend/test/live.test.ts.
        #expect(WeeklyChallenge.key(for: date("2026-10-22T10:00:00Z"), timeZone: utc) == "2026-W43")
        #expect(WeeklyChallenge.key(for: date("2027-01-01T00:00:00Z"), timeZone: utc) == "2026-W53")
        #expect(WeeklyChallenge.key(for: date("2025-12-29T00:00:00Z"), timeZone: utc) == "2026-W01")
    }

    @Test func oneAmrapPerWeekRotating() {
        let a = WeeklyChallenge.wod(for: "2026-W43")
        #expect(a.kind == .amrap && a.work == 12 * 60 && a.moves.count == 3)
        #expect(a == WeeklyChallenge.wod(for: "2026-W43"))
        #expect(a.name != WeeklyChallenge.wod(for: "2026-W44").name)
        #expect(WeeklyChallenge.score(rounds: 8, reps: 12) > WeeklyChallenge.score(rounds: 7, reps: 999))
    }
}
