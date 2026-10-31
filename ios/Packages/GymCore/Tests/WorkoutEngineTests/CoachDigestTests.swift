import Foundation
import Testing
@testable import WorkoutEngine

private let utc = Progression.calendar(TimeZone(identifier: "UTC")!)
private let now = ISO8601DateFormatter().date(from: "2026-10-31T10:00:00Z")!

private func record(_ s: Session, daysAgo: Double, kg: Double) -> WorkoutRecord {
    var done: [String: Int] = [:]
    var weights: [String: Double] = [:]
    for b in s.blocks { for it in b.items { done[it.uid] = it.prescription.sets } }
    for b in s.blocks where b.kind == .strength { for it in b.items { weights[it.exerciseId] = kg } }
    let start = now.addingTimeInterval(-daysAgo * 86_400)
    return WorkoutRecord.build(session: s, week: 1, deload: false, setsDone: done, weights: weights,
                               startedAt: start, endedAt: start.addingTimeInterval(3000), bodyMassKg: 70)
}

/// Coach sees the member's own training (#1010).
@Suite struct CoachDigestTests {
    let plan = Generator.generateWeek(Profile(sessionsPerWeek: 3), seed: 3)

    @Test func emptyHistoryGivesNoLines() {
        #expect(CoachDigest.lines(records: [], now: now, calendar: utc).isEmpty)
    }

    @Test func recentWorkoutsLiftTrendsAndWeight() {
        let s = plan.sessions[0]
        let records = [record(s, daysAgo: 30, kg: 50), record(s, daysAgo: 1, kg: 60), record(s, daysAgo: 0, kg: 62.5)]
        let weights = [BodyMeasurements.Point(date: now.addingTimeInterval(-40 * 86_400), value: 67.2),
                       BodyMeasurements.Point(date: now, value: 66)]
        let lines = CoachDigest.lines(records: records, weights: weights, now: now, calendar: utc)
        #expect(lines.first?.hasPrefix("Workouts: 2 in the last 28 days") == true)
        #expect(lines[1].hasPrefix("Sat 31 Oct (today): \(s.displayTitle)"))
        #expect(lines[2].contains("(yesterday)"))
        #expect(lines.contains { $0.contains("est. 1RM") && $0.contains("3 to 6 weeks ago") })
        #expect(lines.last == "Body weight: 66 kg on 31 Oct; 67.2 kg 40 days before (-1.2 kg).")
        #expect(lines.allSatisfy { $0.count <= CoachDigest.lineLimit })
        #expect(lines.count <= CoachDigest.maxLines)
    }

    @Test func weekPlanStates() {
        let days = [CoachDigest.Day(weekday: 6, title: "Legs", done: false), CoachDigest.Day(weekday: 1, title: "Push", done: true),
                    CoachDigest.Day(weekday: 3, title: "Pull", done: false), CoachDigest.Day(weekday: 7, title: "Climb", done: false)]
        #expect(CoachDigest.week(days, today: 6) == "This week (today Sat): Mon Push done, Wed Pull not done, Sat Legs today, Sun Climb planned.")
        #expect(CoachDigest.week([], today: 6) == nil)
    }

    @Test func recoveryLine() {
        #expect(CoachDigest.recovery(sleepHours: 6.83, hrv: 44, hrvUsual: 50, restingHR: 58.4, restingUsual: 55, vo2Max: 44)
            == "Recovery (Apple Health): slept 6.8 h last night; HRV -12 % vs usual; resting HR 58 (usual 55); VO2 max 44.")
        #expect(CoachDigest.recovery(sleepHours: nil, hrv: nil, hrvUsual: nil, restingHR: nil, restingUsual: nil, vo2Max: nil) == nil)
    }

    @Test func mindLine() {
        let ins = [MindCheckIn(date: now.addingTimeInterval(-10 * 86_400), mood: 1),
                   MindCheckIn(date: now.addingTimeInterval(-2 * 86_400), mood: 2),
                   MindCheckIn(date: now.addingTimeInterval(-3600), mood: 4)]
        let line = CoachDigest.mind(ins, now: now)
        #expect(line?.hasPrefix("Mind: 2 check-ins in 7 days, mood 3 of 5 on average") == true)
        #expect(line?.hasSuffix("last check-in 4 of 5.") == true)
        #expect(CoachDigest.mind([], now: now) == nil)
    }

    @Test func roundsNumbers() {
        #expect(CoachDigest.num(66) == "66")
        #expect(CoachDigest.num(32.25) == "32.3")
        #expect(CoachDigest.num(-1.2) == "-1.2")
    }
}
