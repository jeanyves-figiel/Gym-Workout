import Foundation
import Testing
@testable import WorkoutEngine

/// Heart-rate zones (#609) and run programmes (#618).
@Suite struct RunPlanTests {
    let cal = Progression.calendar(TimeZone(identifier: "Europe/Zurich")!)

    private func date(_ s: String) -> Date {
        let p = s.split(separator: "-").compactMap { Int($0) }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))!
    }

    @Test func standardZonesRiseFromRestingHeartRate() {
        let z = HeartZones.standard(age: 40, restingHR: 60)
        #expect(z.isValid)
        // Max 180, reserve 120: 132 / 144 / 156 / 168.
        #expect(z.starts == [132, 144, 156, 168])
        #expect(z.zone(100) == 1 && z.zone(132) == 2 && z.zone(150) == 3 && z.zone(200) == 5)
        #expect(z.label(2) == "132–143" && z.label(1) == "< 132" && z.label(5) == "≥ 168")
        #expect(z.status(150, target: 2) == .high(7))
        #expect(z.status(120, target: 2) == .low(12))
        #expect(z.status(140, target: 2) == .inZone)
    }

    @Test func appleZonesNeedFiveRising() {
        #expect(HeartZones.apple(lowerBounds: [nil, 120, 135, 150, 165]) == HeartZones(starts: [120, 135, 150, 165]))
        #expect(HeartZones.apple(lowerBounds: [nil, 120, 135]) == nil)
        #expect(HeartZones.apple(lowerBounds: [nil, 150, 135, 150, 165]) == nil)
    }

    @Test func zoneTimeCountsUntilNextSampleCapped() {
        let z = HeartZones(starts: [120, 135, 150, 165])
        let t0 = Date(timeIntervalSince1970: 0)
        let samples = (0..<60).map { (date: t0.addingTimeInterval(Double($0) * 10), bpm: 125.0) }
            + [(date: t0.addingTimeInterval(3_600), bpm: 170.0)]
        let t = ZoneTime.from(samples: samples, zones: z)
        // 59 gaps of 10 s + one capped at 30 s in zone 2; the last sample counts 5 s in zone 5.
        #expect(t.seconds[1] == 620 && t.seconds[4] == 5)
        #expect(t.zone2Minutes == 10)
    }

    @Test func raceWeeksFollowPhases() {
        let goal = RunGoal(distance: .k10, raceDate: "2027-03-14", targetSeconds: 49 * 60 + 30)
        #expect(goal.racePace == 297)
        #expect(RunPlanner.phase(goal, weekStart: date("2027-03-08"), cal) == .race)
        #expect(RunPlanner.phase(goal, weekStart: date("2027-03-01"), cal) == .taper)
        #expect(RunPlanner.phase(goal, weekStart: date("2027-02-15"), cal) == .peak)
        #expect(RunPlanner.phase(goal, weekStart: date("2027-01-25"), cal) == .build)
        #expect(RunPlanner.phase(goal, weekStart: date("2026-11-02"), cal) == .base)
        #expect(RunPlanner.phase(goal, weekStart: date("2027-03-15"), cal) == nil)
        #expect(goal.daysLeft(now: date("2027-03-10"), cal) == 4)
    }

    @Test func longRunSaturdayNeverAfterLegs() {
        let goal = RunGoal(distance: .k10, raceDate: "2027-03-14")
        // Legs on Friday: the long run moves off Saturday.
        let lifting: [(weekday: Int, focus: Focus)] = [(1, .upper), (3, .pull), (5, .legs)]
        let week = RunPlanner.week(goal, weekStart: date("2027-01-25"), lifting: lifting, cal)
        #expect(week.count == 3)
        let long = week.first { $0.workout.kind == .long }!
        #expect(long.weekday != 6 && long.weekday != 5)
        for d in week where d.workout.kind.hard || d.workout.kind == .long { #expect(d.weekday != 6 && d.weekday != 5) }
        #expect(Set(week.map(\.weekday)).count == week.count)
        #expect(week.allSatisfy { $0.workout.id.hasPrefix("run-2027-01-") || $0.workout.id.hasPrefix("run-2027-02-") })
        // No legs day: Saturday it is.
        let free = RunPlanner.week(goal, weekStart: date("2027-01-25"), lifting: [(1, .upper), (3, .pull)], cal)
        #expect(free.first { $0.workout.kind == .long }?.weekday == 6)
    }

    @Test func intervalsHaveRepsAndPaces() {
        let goal = RunGoal(distance: .k5, raceDate: "2027-03-14", targetSeconds: 25 * 60)
        let week = RunPlanner.week(goal, weekStart: date("2027-02-15"), lifting: [], cal)
        let iv = week.first { $0.workout.kind == .intervals }!.workout
        #expect(iv.reps == 8)
        #expect(iv.steps.first?.kind == .warmup && iv.steps.last?.kind == .cooldown)
        #expect(iv.steps.filter { $0.kind == .work }.allSatisfy { $0.meters == 400 && $0.pace == 291 && $0.of == 8 })
        #expect(iv.minutes > 20)
    }

    @Test func raceWeekHasTheRaceOnItsDay() {
        let goal = RunGoal(distance: .half, raceDate: "2027-03-14", raceName: "Zürich Half")
        let week = RunPlanner.week(goal, weekStart: date("2027-03-08"), lifting: [], cal)
        let race = week.first { $0.workout.kind == .race }
        #expect(race?.weekday == 7 && race?.workout.title == "Zürich Half")
        #expect(race?.workout.id == "run-2027-03-14")
    }

    @Test func hybridAddsTwoZone2AndOneIntervalDay() {
        let goal = RunGoal(mode: .hybrid)
        let week = RunPlanner.week(goal, weekStart: date("2027-01-25"), lifting: [(1, .upper), (3, .legs), (5, .push)], cal)
        #expect(week.count == 3)
        #expect(week.filter { $0.workout.zone == 2 }.count == 2)
        #expect(week.filter { $0.workout.kind == .intervals }.count == 1)
        #expect(Set(week.map(\.workout.sport)) == [.roadBike, .run, .rowing])
        #expect(!week.contains { $0.weekday == 3 })
    }
}
