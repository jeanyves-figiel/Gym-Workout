import Foundation
import Testing
@testable import WorkoutEngine

/// Finish screen charts + lift report (#801).
@Suite struct WorkoutReportTests {
    private func record(_ day: Int, bench: Double, reps: Double = 8, dips: Int = 3, focus: Focus = .fullUpper) -> WorkoutRecord {
        WorkoutRecord(
            id: UUID(), startedAt: Date(timeIntervalSince1970: Double(day) * 86_400), durationSec: 48 * 60, sessionId: "push",
            week: 1, deload: false, focus: focus, title: "Push day",
            exercises: [
                ExerciseRecord(uid: "w", exerciseId: "bench-press", category: .warmup, setsDone: 1, setsPlanned: 1, reps: 10, weightKg: 20),
                ExerciseRecord(uid: "a", exerciseId: "bench-press", category: .strength, setsDone: 4, setsPlanned: 4, reps: reps, weightKg: bench),
                ExerciseRecord(uid: "b", exerciseId: "db-bench", category: .strength, setsDone: dips, setsPlanned: 3, reps: 10, weightKg: 24),
            ],
            kcal: nil, avgHeartRate: nil, maxHeartRate: nil, muscleLoad: [:])
    }

    @Test func everyLiftComparesWithLastTime() throws {
        let history = [record(1, bench: 75), record(4, bench: 77.5), record(6, bench: 80, dips: 2, focus: .lower)]
        let now = record(8, bench: 80, dips: 2)
        let r = WorkoutReport.build(now, history: history + [now])
        #expect(r.lifts.map(\.uid) == ["a", "b"])
        let bench = try #require(r.lifts.first)
        #expect(bench.change == .same)
        #expect(bench.topKg.map(\.value) == [75, 77.5, 80, 80])
        #expect(bench.topKg.last?.today == true)
        #expect(!bench.newBest)
        #expect(bench.line == "4 × 8 · 80 kg")
        let db = try #require(r.lifts.last)
        #expect(db.change == .same)
        #expect(db.line == "2 of 3 sets × 10 · 24 kg")

        let heavier = WorkoutReport.build(record(8, bench: 82.5, dips: 2), history: history)
        #expect(heavier.lifts[0].change == .heavier(2.5))
        #expect(heavier.lifts[0].change.label == "+2.5 kg")
        #expect(heavier.lifts[0].newBest)
        #expect(WorkoutReport.build(record(8, bench: 80, reps: 9, dips: 2), history: history).lifts[0].change == .moreReps(1))
        #expect(WorkoutReport.build(record(8, bench: 80, dips: 3), history: history).lifts[1].change == .moreSets(1))
        #expect(WorkoutReport.build(now, history: []).lifts[0].change == .new)
    }

    @Test func volumeChartKeepsTheSameFocus() throws {
        let history = (1...10).map { record($0, bench: 70 + Double($0), focus: $0 == 5 ? .lower : .fullUpper) }
        let now = record(12, bench: 85)
        let r = WorkoutReport.build(now, history: history, points: 8)
        #expect(r.volume.count == 8)
        #expect(r.volume.last?.today == true)
        #expect(r.volume.dropLast().allSatisfy { !$0.today })
        let avg = try #require(r.volumeVsAverage)
        #expect(avg > 0)
        #expect(WorkoutReport.build(now, history: []).volumeVsAverage == nil)
        #expect(r.charted.first?.exerciseId == "bench-press")
    }

    @Test func todaysSetsComeFromThisWorkoutsLogs() {
        let now = record(8, bench: 80)
        let t = now.startedAt
        let logs = [
            SetLog(date: t.addingTimeInterval(60), exerciseId: "bench-press", sessionId: "push", setIndex: 0, kg: 80, reps: 8),
            SetLog(date: t.addingTimeInterval(200), exerciseId: "bench-press", sessionId: "push", setIndex: 1, kg: 80, reps: 7),
            SetLog(date: t.addingTimeInterval(300), exerciseId: "bench-press", sessionId: "push", setIndex: 1, kg: 80, reps: 8),
            SetLog(date: t.addingTimeInterval(-86_400), exerciseId: "bench-press", sessionId: "push", setIndex: 2, kg: 75, reps: 8),
        ]
        let sets = WorkoutReport.build(now, history: [], logs: logs).lifts[0].sets
        #expect(sets.map(\.reps) == [8, 8])
    }

    /// A run closed and resumed later (#817): its first sets, before the record's start, still belong to it, but
    /// never sets of an earlier workout of the same session.
    @Test func setsWindowCoversAResumedRun() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var now = record(8, bench: 80)
        now.startedAt = now.startedAt.addingTimeInterval(12 * 3600)
        let day = utc.startOfDay(for: now.startedAt)
        #expect(WorkoutReport.setsFrom(now, history: [], calendar: utc) == day)
        var morning = record(8, bench: 80)
        morning.startedAt = day.addingTimeInterval(7 * 3600)
        #expect(WorkoutReport.setsFrom(now, history: [morning, now], calendar: utc) == morning.endedAt)
        #expect(WorkoutReport.setsFrom(morning, history: [morning, now], calendar: utc) == day)
    }
}
