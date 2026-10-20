import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct WatchOnlyRecordTests {
    @Test func keepsWhatTheWatchSent() {
        let start = Date(timeIntervalSince1970: 1_791_367_200)
        let r = WorkoutRecord.watchOnly(
            sessionId: "w2s1", title: "Upper A", week: 2, deload: false, startedAt: start,
            endedAt: start.addingTimeInterval(2_700), kcal: 310, avgHeartRate: 128, maxHeartRate: 165)
        #expect(r.sessionId == "w2s1" && r.title == "Upper A" && r.week == 2)
        #expect(r.durationSec == 2_700 && r.endedAt == start.addingTimeInterval(2_700))
        #expect(r.kcal == 310 && r.avgHeartRate == 128 && r.maxHeartRate == 165)
        #expect(r.exercises.isEmpty && r.muscleLoad.isEmpty && r.totalSets == 0)
    }

    @Test func untitledAndBackwardsClockStillRecord() {
        let start = Date(timeIntervalSince1970: 1_791_367_200)
        let r = WorkoutRecord.watchOnly(
            sessionId: "x", title: nil, week: 1, deload: true, startedAt: start, endedAt: start.addingTimeInterval(-5),
            kcal: nil, avgHeartRate: nil, maxHeartRate: nil)
        #expect(r.title == "Apple Watch workout")
        #expect(r.durationSec == 0)
    }
}
