import Foundation
import Testing
@testable import WorkoutEngine

/// Ask your history (#868): questions → number, chart and sentence from the logged workouts.
@Suite struct HistoryAskTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ m: Int, _ d: Int, year: Int = 2026) -> Date {
        cal.date(from: DateComponents(year: year, month: m, day: d, hour: 18))!
    }

    private var now: Date { day(10, 20) }

    private func record(_ date: Date, bench: Double? = nil, squat: Double? = nil) -> WorkoutRecord {
        var ex: [ExerciseRecord] = []
        if let bench { ex.append(ExerciseRecord(uid: "b", exerciseId: "bench-press", category: .strength, setsDone: 4, setsPlanned: 4, reps: 3, weightKg: bench)) }
        if let squat { ex.append(ExerciseRecord(uid: "s", exerciseId: "back-squat", category: .strength, setsDone: 3, setsPlanned: 3, reps: 5, weightKg: squat)) }
        return WorkoutRecord(id: UUID(), startedAt: date, durationSec: 3600, sessionId: "x", week: 1, deload: false, focus: .fullUpper,
                             title: "Day", exercises: ex, kcal: nil, avgHeartRate: nil, maxHeartRate: nil, muscleLoad: [:])
    }

    private var history: [WorkoutRecord] {
        [
            record(day(10, 3, year: 2025), bench: 90),
            record(day(6, 10), bench: 80, squat: 106),
            record(day(8, 12), bench: 85),
            record(day(9, 2), squat: 110), record(day(9, 20), bench: 84),
            record(day(10, 13), bench: 85, squat: 115), record(day(10, 14), squat: 112), record(day(10, 15), bench: 82.5),
        ]
    }

    @Test func bestThisYear() throws {
        let a = try #require(HistoryAsk.answer("Best bench this year?", records: history, now: now, calendar: cal))
        #expect(a.kind == .best)
        #expect(a.title == "Best bench press this year")
        #expect(a.value == "85")
        #expect(a.detail == "13 Oct · 4×3")
        #expect(a.exerciseId == "bench-press")
        #expect(a.bars.last?.label == "Oct")
        #expect(a.caption == "Jun → Oct · +5 kg")
    }

    @Test func bestEverIncludesLastYear() throws {
        let a = try #require(HistoryAsk.answer("What's my heaviest bench press?", records: history, now: now, calendar: cal))
        #expect(a.value == "90")
        #expect(a.title == "Best bench press ever")
    }

    @Test func squattingMoreThanInJune() throws {
        let a = try #require(HistoryAsk.answer("Am I squatting more than in June?", records: history, now: now, calendar: cal))
        #expect(a.kind == .compare)
        #expect(a.exerciseId == "back-squat")
        #expect(a.value == "+9")
        #expect(a.sentence.hasPrefix("Yes, +9 kg"))
        #expect(a.bars.map(\.label) == ["Jun", "Jul", "Aug", "Sep", "Oct"])
    }

    @Test func twoMonthsCompared() throws {
        let a = try #require(HistoryAsk.answer("Squat September vs October", records: history, now: now, calendar: cal))
        #expect(a.value == "+5")
    }

    @Test func workoutsInAMonth() throws {
        let a = try #require(HistoryAsk.answer("How many workouts did I do in October?", records: history, now: now, calendar: cal))
        #expect(a.kind == .count)
        #expect(a.value == "3")
        #expect(a.sentence == "3 workouts in October, 1 more than September. Longest streak 3 days.")
        #expect(a.bars.map(\.label) == ["Jul", "Aug", "Sep", "Oct"])
    }

    @Test func workoutsThisMonthByDefault() throws {
        let a = try #require(HistoryAsk.answer("Workouts this month?", records: history, now: now, calendar: cal))
        #expect(a.value == "3")
        #expect(a.title == "This month")
    }

    @Test func weeklyVolume() throws {
        let a = try #require(HistoryAsk.answer("Weekly volume?", records: history, now: now, calendar: cal))
        #expect(a.kind == .volume)
        #expect(a.bars.count == 6)
        #expect(a.unit == "t")
    }

    @Test func nothingLoggedSaysSo() throws {
        let a = try #require(HistoryAsk.answer("Best bench in March?", records: history, now: now, calendar: cal))
        #expect(a.kind == .none)
        #expect(a.sentence == "No bench press logged in March.")
    }

    @Test func otherQuestionsGoToCoach() {
        #expect(HistoryAsk.answer("How long should I rest?", records: history, now: now, calendar: cal) == nil)
        #expect(HistoryAsk.answer("45 min full body", records: history, now: now, calendar: cal) == nil)
    }

    @Test func stems() {
        #expect(HistoryAsk.stem("squatting") == "squat")
        #expect(HistoryAsk.stem("pressing") == "press")
        #expect(HistoryAsk.stem("deadlifts") == "deadlift")
        #expect(HistoryAsk.stem("benching") == "bench")
    }

    @Test func periodsInOrder() {
        let p = HistoryAsk.periods(in: "June vs last month vs last 6 weeks", now: now, calendar: cal)
        #expect(p.map(\.label) == ["June", "last month", "last 6 weeks"])
        #expect(HistoryAsk.periods(in: "December", now: now, calendar: cal).first?.label == "December 2025")
    }

    @Test func startersUseTheTopLift() {
        let s = HistoryAsk.starters(records: history, now: now, calendar: cal)
        #expect(s.first == "Best bench press this year?")
        #expect(s.contains("Workouts this month?"))
        let tiles = HistoryAsk.starterTiles(records: history, now: now, calendar: cal)
        #expect(tiles.map(\.kind) == [.best, .compare, .count, .volume])
        #expect(tiles.first?.title == "Bench press this year")
    }
}
