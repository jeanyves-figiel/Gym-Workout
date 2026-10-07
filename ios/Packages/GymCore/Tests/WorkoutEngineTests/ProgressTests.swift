import Foundation
import Testing
@testable import WorkoutEngine

private let utc = Progression.calendar(TimeZone(identifier: "UTC")!)
private let monday = ISO8601DateFormatter().date(from: "2026-09-07T10:00:00Z")! // a Monday

private func record(_ s: Session, at date: Date, week: Int = 1, deload: Bool = false, all: Bool = true, kg: Double? = 60) -> WorkoutRecord {
    var done: [String: Int] = [:]
    var weights: [String: Double] = [:]
    for b in s.blocks { for it in b.items { done[it.uid] = all ? it.prescription.sets : (b.kind == .cooldown ? 0 : 1) } }
    if let kg { for b in s.blocks where b.kind == .strength { for it in b.items { weights[it.exerciseId] = kg } } }
    return WorkoutRecord.build(session: s, week: week, deload: deload, setsDone: done, weights: weights,
                               startedAt: date, endedAt: date.addingTimeInterval(3600), bodyMassKg: 70)
}

@Suite struct RecordTests {
    let plan = Generator.generateWeek(Profile(sessionsPerWeek: 3, climbingDaysPerWeek: 2), seed: 5)

    @Test func buildsRecordWithVolumeMusclesAndEnergy() {
        let r = record(plan.sessions[0], at: monday)
        #expect(r.durationSec == 3600)
        #expect(r.totalSets > 0)
        #expect(r.volumeKg > 0)
        #expect(!r.muscleHeat.isEmpty)
        #expect(r.muscleHeat.values.max() == 1)
        #expect((r.kcal ?? 0) > 200 && (r.kcal ?? 0) < 900)
        #expect(r.categories.contains(.stretch))
    }

    @Test func repsEstimateParsesRanges() {
        func p(_ s: String) -> Double? { Prescription(sets: 3, reps: s, restSec: 60).repsEstimate }
        #expect(p("5–8") == 6.5)
        #expect(p("12–15 / side") == 13.5)
        #expect(p("5") == 5)
        #expect(p("30–45 s") == nil)
        #expect(p("4 min") == nil)
        #expect(p("45 s / side") == nil)
    }

    @Test func recordRoundTripsJSON() throws {
        let r = record(plan.sessions[1], at: monday)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        #expect(try dec.decode(WorkoutRecord.self, from: enc.encode(r)) == r)
    }
}

@Suite struct StatsTests {
    let plan = Generator.generateWeek(Profile(sessionsPerWeek: 3), seed: 9)

    @Test func streaksAndBuckets() {
        // 3 weeks × 3 sessions, then a week with 1 session (this week).
        var recs: [WorkoutRecord] = []
        for w in 0..<3 { for d in 0..<3 {
            recs.append(record(plan.sessions[d], at: monday.addingTimeInterval(Double(w * 7 + d * 2) * 86_400)))
        } }
        let now = monday.addingTimeInterval(21 * 86_400 + 3600)
        recs.append(record(plan.sessions[0], at: now.addingTimeInterval(-60)))
        let s = Progression.stats(records: recs, weights: [], targetPerWeek: 3, now: now, calendar: utc)
        #expect(s.totalWorkouts == 10)
        #expect(s.thisWeek == 1)
        #expect(s.currentStreakWeeks == 3)
        #expect(s.bestStreakWeeks == 3)
        #expect(s.weeks.count == 12)
        #expect(s.weeks.last?.workouts == 1)
        #expect(s.days.values.reduce(0, +) == 10)
        #expect(!s.muscleBalance.isEmpty)
    }

    @Test func personalRecordsAndPRCount() {
        let w = [
            WeightEntry(exerciseId: "back-squat", date: monday, kg: 80),
            WeightEntry(exerciseId: "back-squat", date: monday.addingTimeInterval(86_400), kg: 85),
            WeightEntry(exerciseId: "back-squat", date: monday.addingTimeInterval(2 * 86_400), kg: 82.5),
            WeightEntry(exerciseId: "pull-up", date: monday, kg: 10),
        ]
        let s = Progression.stats(records: [], weights: w, targetPerWeek: 3, now: monday, calendar: utc)
        #expect(s.personalRecords.first { $0.exerciseId == "back-squat" }?.kg == 85)
        #expect(Progression.prCount(w).last?.1 == 1)
    }

    @Test func oneRepMaxTrend() {
        let r1 = record(plan.sessions[0], at: monday, kg: 60)
        let r2 = record(plan.sessions[0], at: monday.addingTimeInterval(7 * 86_400), kg: 70)
        let main = r1.exercises.first { $0.category == .strength && $0.estimatedOneRepMax != nil }!.exerciseId
        let trend = Progression.oneRepMaxTrend(main, records: [r1, r2], calendar: utc)
        #expect(trend.count == 2)
        #expect(trend[1].1 > trend[0].1)
    }
}

@Suite struct AchievementTests {
    let plan = Generator.generateWeek(Profile(sessionsPerWeek: 3), seed: 3)

    @Test func emptyHistoryLocksEverything() {
        let b = Achievements.evaluate(records: [], weights: [], targetPerWeek: 3, calendar: utc)
        #expect(b.count >= 20)
        #expect(b.allSatisfy { !$0.unlocked && $0.progress == 0 })
        #expect(Set(b.map(\.id)).count == b.count)
    }

    @Test func unlocksMilestonesWithDates() {
        var recs: [WorkoutRecord] = []
        for w in 0..<4 { for d in 0..<3 {
            recs.append(record(plan.sessions[d], at: monday.addingTimeInterval(Double(w * 7 + d * 2) * 86_400), week: w + 1, deload: w == 3))
        } }
        let weights = [WeightEntry(exerciseId: "back-squat", date: monday, kg: 80),
                       WeightEntry(exerciseId: "back-squat", date: monday.addingTimeInterval(86_400 * 8), kg: 90)]
        let b = Dictionary(uniqueKeysWithValues: Achievements.evaluate(records: recs, weights: weights, targetPerWeek: 3, calendar: utc).map { ($0.id, $0) })
        #expect(b["first"]?.unlockedAt == recs[0].startedAt)
        #expect(b["w10"]?.unlocked == true)
        #expect(b["w25"]?.unlocked == false)
        #expect(b["w25"]!.progress > 0.4)
        #expect(b["s4"]?.unlocked == true)
        #expect(b["s8"]?.unlocked == false)
        #expect(b["deload"]?.unlocked == true)
        #expect(b["cycle"]?.unlocked == true)
        #expect(b["pr1"]?.unlocked == true)
        #expect(b["supple"]?.unlocked == true)
        #expect(b["complete"]?.unlocked == true)
        #expect(b["v10"]?.unlocked == true)
    }

    @Test func partialSessionsDoNotCountForSupple() {
        let recs = (0..<12).map { i in record(plan.sessions[i % 3], at: monday.addingTimeInterval(Double(i) * 86_400), all: false) }
        let b = Achievements.evaluate(records: recs, weights: [], targetPerWeek: 3, calendar: utc).first { $0.id == "supple" }!
        #expect(!b.unlocked)
    }
}
