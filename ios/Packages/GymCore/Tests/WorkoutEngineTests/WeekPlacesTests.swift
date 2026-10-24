import Foundation
import Testing
@testable import WorkoutEngine

/// Week places (#684) and hybrid synergy (#685).
@Suite struct WeekPlacesTests {
    let cal = Progression.calendar(TimeZone(identifier: "Europe/Zurich")!)
    let home = DayKit(gymId: "custom:home", name: "Home", equipment: [.dumbbells, .bench, .mat])

    private func profile() -> Profile {
        var p = Profile(sessionsPerWeek: 3, climbingDaysPerWeek: 0, gymWeekdays: [1, 3, 5])
        p.climbingWeekdays = []
        return p
    }

    private func equipmentUsed(_ s: Session) -> Set<Equipment> {
        Set(s.blocks.filter { $0.kind == .strength }.flatMap(\.items).flatMap { Exercise.find($0.exerciseId)?.equipment ?? [] })
    }

    @Test func noPlacesKeepsThePlanByteIdentical() {
        let p = profile()
        var q = p
        q.dayPlaces = ["1": "gym"]
        #expect(Generator.generateWeek(p, week: 2, seed: 9) == Generator.generateWeek(q, week: 2, seed: 9))
    }

    @Test func dayAtAnotherGymUsesItsEquipment() {
        var p = profile()
        p.dayKits = ["1": home]
        let plan = Generator.generateWeek(p, week: 1, seed: 3)
        let monday = plan.sessions.first { $0.weekday == 1 }!
        #expect(monday.place == "Home")
        #expect(equipmentUsed(monday).isSubset(of: Set(home.equipment)))
        let base = Generator.generateWeek(profile(), week: 1, seed: 3)
        // Other days are the plan's own gym, unchanged.
        for s in plan.sessions where s.weekday != 1 {
            #expect(s.place == nil)
            #expect(s.blocks == base.sessions.first { $0.id == s.id }!.blocks)
        }
    }

    @Test func oneOffPlaceOverridesItsDayOnlyInItsWeek() {
        var p = profile()
        p.dayKits = ["1": home, "3": home]
        let monday = Progression.weekStart(cal.date(from: DateComponents(year: 2027, month: 1, day: 25))!, cal)
        let gym = DayKit(gymId: "map:1,2", name: "Puls 5", equipment: Gym.puls5.equipment)
        // Wednesday 27 Jan at the gym, Monday back to the plan's gym; a day of another week changes nothing.
        let dated = ["2027-01-27": "map:1,2", "2027-01-25": "own", "2027-02-03": "map:1,2"]
        let q = p.placing(dated, weekStart: monday, cal) { $0 == gym.gymId ? gym : nil }
        #expect(q.kit(onWeekday: 3) == gym)
        #expect(q.kit(onWeekday: 1) == nil)
        #expect(p.placing([:], weekStart: monday, cal) { _ in gym } == p)
        let plan = Generator.generateWeek(q, week: 1, seed: 3)
        #expect(plan.sessions.first { $0.weekday == 3 }?.place == "Puls 5")
        #expect(plan.sessions.first { $0.weekday == 1 }?.place == nil)
    }

    @Test func settingAPlaceMakesItAGymDay() {
        var p = profile()
        p.setPlace("custom:home", onWeekday: 2)
        p.setPlace("gym", onWeekday: 4)
        #expect(p.gymWeekdays == [2, 4])
        #expect(p.place(onWeekday: 2) == "custom:home")
        p.setPlace(nil, onWeekday: 2)
        #expect(p.gymWeekdays == [4])
    }

    @Test func movedSessionTakesTheGymOfItsNewDay() {
        var p = profile()
        p.dayKits = ["2": home]
        let monday = Progression.weekStart(cal.date(from: DateComponents(year: 2027, month: 1, day: 25))!, cal)
        let plan = Generator.generateWeek(p, week: 1, seed: 3)
        let first = plan.sessions.first { $0.weekday == 1 }!
        let week = PlanCalendar.adapt(p, week: 1, seed: 3, weekStart: monday, away: [], base: plan, fixed: [first.id: 2], calendar: cal)
        let moved = week.plan.sessions.first { $0.id == first.id }!
        #expect(moved.weekday == 2 && moved.place == "Home")
        #expect(equipmentUsed(moved).isSubset(of: Set(home.equipment)))
    }

    @Test func hybridRunReplacesCardioAndTrimsLegsBeforeHardRuns() {
        // Four lifting days and four runs: at least one day has both.
        var p = profile()
        p.sessionsPerWeek = 4
        p.gymWeekdays = [1, 2, 4, 6]
        p.runGoal = RunGoal(mode: .hybrid, perWeek: 4)
        let plan = Generator.generateWeek(p, week: 1, seed: 5)
        let monday = Progression.weekStart(Date(), Progression.calendar())
        let runs = Dictionary(RunPlanner.week(p.runGoal!, weekStart: monday,
                                              lifting: plan.sessions.compactMap { s in s.weekday.map { ($0, s.focus) } },
                                              Progression.calendar(), step: RunPlanner.step(plan)).map { ($0.weekday, $0.workout) },
                              uniquingKeysWith: { a, _ in a })
        #expect(plan.sessions.contains { s in s.weekday.map { runs[$0] != nil } ?? false })
        for s in plan.sessions {
            guard let wd = s.weekday, runs[wd] != nil else { continue }
            #expect(!s.blocks.contains { $0.kind == .cardio })
            #expect(s.synergy?.contains("Lift first") == true)
        }
        // Blending twice changes nothing.
        #expect(RunPlanner.blend(plan, p, weekStart: monday, Progression.calendar()) == plan)
    }

    @Test func hybridSessionsGrowThroughTheBlock() {
        let goal = RunGoal(mode: .hybrid, perWeek: 4)
        let start = cal.date(from: DateComponents(year: 2027, month: 1, day: 25))!
        let mins = (-1...2).map { step in RunPlanner.week(goal, weekStart: start, lifting: [], cal, step: step).map(\.workout.minutes).reduce(0, +) }
        #expect(mins == mins.sorted() && Set(mins).count == 4)
        #expect(RunPlanner.week(goal, weekStart: start, lifting: [], cal) == RunPlanner.week(goal, weekStart: start, lifting: [], cal, step: 0))
    }
}
