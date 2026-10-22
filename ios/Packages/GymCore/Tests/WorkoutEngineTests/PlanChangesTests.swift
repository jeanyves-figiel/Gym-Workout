import Foundation
import Testing
@testable import WorkoutEngine

private let cal: Calendar = {
    var c = Calendar(identifier: .iso8601)
    c.timeZone = TimeZone(identifier: "Europe/Zurich")!
    return c
}()

/// Monday 12 Oct 2026.
private let monday = PlanCalendar.date("2026-10-12", cal)!

@Suite struct PlanChangesTests {
    let climber = Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 2,
                          climbingWeekdays: [2, 5], gymWeekdays: nil)

    private var plan: WeekPlan { Generator.generateWeek(climber, week: 1, seed: 3) }

    @Test func movingOntoASessionSwapsDays() throws {
        let a = plan.sessions[0], b = plan.sessions[1]
        let days = PlanCalendar.moving(a.id, to: try #require(b.weekday), in: plan, done: [])
        #expect(days == [a.id: b.weekday!, b.id: a.weekday!])
        let moved = plan.pinning(days)
        #expect(moved.sessions[0].weekday == b.weekday && moved.sessions[1].weekday == a.weekday)
        #expect(moved.sessions.map(\.id) == plan.sessions.map(\.id))
    }

    @Test func movingToAFreeDayMovesOnlyThatSession() throws {
        let used = Set(plan.sessions.compactMap(\.weekday))
        let free = try #require(WeekSchedule.weekdays.first { !used.contains($0) })
        let a = plan.sessions[2]
        #expect(PlanCalendar.moving(a.id, to: free, in: plan, done: []) == [a.id: free])
    }

    @Test func doneSessionsNeitherMoveNorSwap() throws {
        let a = plan.sessions[0], b = plan.sessions[1]
        #expect(PlanCalendar.moving(a.id, to: b.weekday!, in: plan, done: [a.id]).isEmpty)
        #expect(PlanCalendar.moving(a.id, to: b.weekday!, in: plan, done: [b.id]) == [a.id: b.weekday!])
        #expect(PlanCalendar.moving("nope", to: 3, in: plan, done: []).isEmpty)
        #expect(PlanCalendar.moving(a.id, to: a.weekday!, in: plan, done: []).isEmpty)
    }

    @Test func adaptKeepsMovesInAnUntouchedWeek() throws {
        let used = Set(plan.sessions.compactMap(\.weekday))
        let free = try #require(WeekSchedule.weekdays.first { !used.contains($0) })
        let a = plan.sessions[0]
        let w = PlanCalendar.adapt(climber, week: 1, seed: 3, weekStart: monday, away: [], base: plan, fixed: [a.id: free], calendar: cal)
        #expect(w.plan.sessions.first { $0.id == a.id }?.weekday == free)
        #expect(w.plan.sessions.count == plan.sessions.count)
        #expect(w.adapted)
        // Unknown ids (another week's moves) change nothing.
        let same = PlanCalendar.adapt(climber, week: 1, seed: 3, weekStart: monday, away: [], base: plan, fixed: ["w9s9": 1], calendar: cal)
        #expect(same.plan == plan && !same.adapted)
    }

    @Test func movedSessionKeepsItsDayWhenOtherDaysAreOff() throws {
        let a = plan.sessions[0]
        let target = 7
        let others = plan.sessions.dropFirst().compactMap(\.weekday).filter { $0 != target }
        let keys = PlanCalendar.dayKeys(weekStart: monday, cal)
        let away = others.map { AwayPeriod(kind: .off, start: keys[$0 - 1], end: keys[$0 - 1]) }
        let w = PlanCalendar.adapt(climber, week: 1, seed: 3, weekStart: monday, away: away, base: plan, fixed: [a.id: target], calendar: cal)
        #expect(w.plan.sessions.first { $0.id == a.id }?.weekday == target)
        #expect(w.plan.sessions.allSatisfy { s in s.weekday.map { w.off[$0] == nil } ?? false })
        #expect(Set(w.plan.sessions.compactMap(\.weekday)).count == w.plan.sessions.count)
    }

    @Test func moveOntoADayOffIsPlannedElsewhere() throws {
        let a = plan.sessions[0]
        let key = PlanCalendar.dayKeys(weekStart: monday, cal)[6]
        let w = PlanCalendar.adapt(climber, week: 1, seed: 3, weekStart: monday, away: [AwayPeriod(kind: .off, start: key, end: key)],
                                   base: plan, fixed: [a.id: 7], calendar: cal)
        let day = try #require(w.plan.sessions.first { $0.id == a.id }?.weekday)
        #expect(day != 7)
    }

    @Test func weeksApplyMovesToTheCurrentWeekOnly() {
        let now = cal.date(byAdding: .hour, value: 10, to: monday)!
        let a = plan.sessions[0]
        let weeks = PlanCalendar.weeks(climber, seed: 3, currentWeek: 1, current: plan, done: [], away: [], now: now, count: 2,
                                       fixed: [a.id: 7], calendar: cal)
        #expect(weeks[0].plan.sessions.first { $0.id == a.id }?.weekday == 7)
        #expect(weeks[1].plan.sessions.first { $0.id == "w2s1" }?.weekday == Generator.generateWeek(climber, week: 2, seed: 3).sessions[0].weekday)
    }

    @Test(arguments: Generator.quickFoci)
    func quickSessionHasTheFocus(_ focus: Focus) throws {
        let s = try #require(Generator.quickSession(climber, focus: focus, week: 2, seed: 5))
        #expect(s.focus == focus)
        #expect(s.weekday == nil)
        #expect(s.estMin > 0)
        #expect(!s.blocks.flatMap(\.items).isEmpty)
    }

    @Test(arguments: Generator.quickDurations)
    func quickSessionFitsTheDuration(_ minutes: Int) throws {
        for focus in Generator.quickFoci {
            let s = try #require(Generator.quickSession(climber, focus: focus, week: 2, seed: 5, minutes: minutes))
            #expect(s.focus == focus && s.targetMin == minutes)
            #expect(!s.blocks.flatMap(\.items).isEmpty)
            #expect(Double(s.estMin) <= Double(minutes) * 1.3 + 6, "\(focus) \(minutes) min → \(s.estMin)")
        }
    }

    @Test func quickSessionWithoutMinutesIsUnchanged() throws {
        let a = try #require(Generator.quickSession(climber, focus: .push, week: 2, seed: 5))
        let b = try #require(Generator.quickSession(climber, focus: .push, week: 2, seed: 5, minutes: nil))
        #expect(a == b)
        let short = try #require(Generator.quickSession(climber, focus: .push, week: 2, seed: 5, minutes: 15))
        #expect(short.estMin < a.estMin)
    }

    @Test func quickWorkoutTargetsTheMuscles() {
        let w = Generator.quickWorkout(climber, groups: [.chest, .arms], minutes: 20, seed: 7)
        #expect(!w.items.isEmpty)
        #expect(w.items.allSatisfy { i in i.exercise.map { $0.primary.contains { Set<MuscleGroup>([.chest, .arms]).contains($0.group) } } ?? false })
        #expect(w.session.estMin <= 30)
        #expect(Generator.quickWorkout(climber, groups: [], minutes: 20, seed: 7).items.isEmpty)
    }

    /// "Upper body" and "Lower body" quick extras (#590) stay on their half: the upper one had hinges and lunges.
    @Test func quickUpperAndLowerStayOnTheirHalf() throws {
        let legs: Set<MuscleGroup> = [.hips, .legs]
        func main(_ f: Focus) throws -> [Exercise] {
            let s = try #require(Generator.quickSession(climber, focus: f, week: 2, seed: 5))
            return s.blocks.filter { $0.kind == .strength }.flatMap(\.items).map { Exercise.get($0.exerciseId) }
        }
        let upper = try main(.upper)
        #expect(!upper.isEmpty)
        for e in upper { #expect(!e.primary.contains { legs.contains($0.group) }, "\(e.id)") }
        #expect(try main(.lower).contains { $0.primary.contains { legs.contains($0.group) } })
    }

    @Test func focusPresetsHaveMuscles() {
        for f in Generator.quickFoci where f != .conditioning { #expect(!f.muscleGroups.isEmpty) }
        #expect(Focus.conditioning.muscleGroups.isEmpty)
    }

    @Test func quickExtraIsAPlanSessionWithItsOwnIds() throws {
        let g = try #require(Generator.quickSession(climber, focus: .pull, week: 1, seed: 1))
        let ins = PlanInsert(week: 1, weekday: 6, workout: CustomWorkout(name: "Extra pull"), generated: g)
        let p = plan.applying([ins])
        let s = try #require(p.sessions.last)
        #expect(p.sessions.count == plan.sessions.count + 1)
        #expect(s.isPlanInsert && s.planInsertId == ins.id)
        #expect(s.focus == .pull && s.weekday == 6 && s.displayTitle == "Extra pull")
        #expect(s.blocks.flatMap(\.items).map(\.exerciseId) == g.blocks.flatMap(\.items).map(\.exerciseId))
        let uids = s.blocks.flatMap(\.items).map(\.uid)
        #expect(Set(uids).count == uids.count && uids.allSatisfy { $0.hasPrefix(s.id) })
        #expect(try JSONDecoder().decode(PlanInsert.self, from: JSONEncoder().encode(ins)) == ins)
    }

    @Test func movesRoundTrip() throws {
        let m = [SessionMove(weekOf: "2026-10-12", sessionId: "w1s2", weekday: 9)]
        #expect(m[0].weekday == 7)
        #expect(try JSONDecoder().decode([SessionMove].self, from: JSONEncoder().encode(m)) == m)
    }
}
