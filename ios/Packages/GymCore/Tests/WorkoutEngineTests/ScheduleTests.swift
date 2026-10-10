import Foundation
import Testing
@testable import WorkoutEngine

private func climber(_ sessions: Int, climbing: [Int]?, gym: [Int]? = nil, goal: Goal = .balanced) -> Profile {
    Profile(goal: goal, sessionsPerWeek: sessions, experience: .intermediate, climbingDaysPerWeek: 2,
            climbingWeekdays: climbing, gymWeekdays: gym)
}

@Suite struct WeekdayTests {
    @Test func wrapsAroundTheWeek() {
        #expect(WeekSchedule.next(7) == 1)
        #expect(WeekSchedule.next(3) == 4)
        #expect(WeekSchedule.previous(1) == 7)
        #expect(WeekSchedule.previous(5) == 4)
        #expect(WeekSchedule.shortName(1) == "Mon")
        #expect(WeekSchedule.name(7) == "Sunday")
        #expect(WeekSchedule.initial(4) == "T")
    }

    @Test func convertsFromCalendarWeekday() {
        // Calendar: 1 = Sunday, 2 = Monday … 7 = Saturday.
        #expect(WeekSchedule.fromCalendar(1) == 7)
        #expect(WeekSchedule.fromCalendar(2) == 1)
        #expect(WeekSchedule.fromCalendar(7) == 6)
    }

    @Test func normalizesPickedDays() {
        #expect(WeekSchedule.normalized([5, 1, 5, 0, 9, 3]) == [1, 3, 5])
        #expect(WeekSchedule.normalized(nil).isEmpty)
    }

    @Test func climbingDaysPerWeekFollowsPickedWeekdays() {
        var p = Profile(climbingDaysPerWeek: 0, climbingWeekdays: [3, 1, 3, 9])
        #expect(p.climbingDays == [1, 3])
        p.syncClimbingDays()
        #expect(p.climbingDaysPerWeek == 2)
        var q = Profile(climbingDaysPerWeek: 3)
        q.syncClimbingDays()
        #expect(q.climbingDaysPerWeek == 3) // nothing picked → untouched
    }

    @Test func combinatorics() {
        #expect(WeekSchedule.combinations(WeekSchedule.weekdays, 3).count == 35)
        #expect(WeekSchedule.combinations(WeekSchedule.weekdays, 3).first == [1, 2, 3])
        #expect(WeekSchedule.distinctPermutations([.push, .pull, .legs, .push, .pull, .legs]).count == 90)
        #expect(WeekSchedule.distinctPermutations([.upper, .lower, .upper, .lower]).count == 6)
    }
}

@Suite struct ClimbingScheduleTests {
    @Test func noWeekdaysKeepsThePlainPlan() {
        let p = Profile(goal: .climbing, sessionsPerWeek: 4, climbingDaysPerWeek: 3)
        #expect(WeekSchedule.assign(Rules.splits[4]!, climbing: [], gym: []) == nil)
        let plan = Generator.generateWeek(p, seed: 4)
        #expect(plan.sessions.allSatisfy { $0.weekday == nil })
        #expect(plan.sessions.map(\.focus) == Rules.splits[4]!)
        #expect(plan.sessions[0].dayLabel == "Day 1")
    }

    @Test(arguments: 2...6)
    func layoutIsAValidWeek(sessions: Int) {
        let plan = Generator.generateWeek(climber(sessions, climbing: [2, 4]), seed: 1)
        let days = plan.sessions.compactMap(\.weekday)
        #expect(days.count == sessions)
        #expect(days == days.sorted())
        #expect(Set(days).count == sessions)
        #expect(plan.sessions.map(\.index) == Array(0..<sessions))
        #expect(plan.sessions.map(\.focus.rawValue).sorted() == Rules.splits[sessions]!.map(\.rawValue).sorted())
    }

    @Test(arguments: 2...4)
    func avoidsClimbingDaysWhenThereIsRoom(sessions: Int) {
        for climbing in [[2, 4], [6, 7], [3], [2, 5]] {
            let plan = Generator.generateWeek(climber(sessions, climbing: climbing), seed: 3)
            for s in plan.sessions { #expect(!climbing.contains(s.weekday!), "\(climbing) \(sessions)") }
        }
    }

    @Test func pushDayGoesBeforeClimbing() {
        // Push/pull/legs: the day before climbing should be a push (antagonist) day, never pull or legs.
        for climbing in [[2, 4], [6, 7], [2, 5]] {
            let plan = Generator.generateWeek(climber(6, climbing: climbing), seed: 5)
            for s in plan.sessions where climbing.contains(WeekSchedule.next(s.weekday!)) {
                #expect(s.focus == .push, "\(climbing): \(s.focus) on \(s.weekday!)")
            }
        }
    }

    @Test func dayBeforeClimbingSkipsExplosiveWork() {
        let climbing = [2, 4]
        let plan = Generator.generateWeek(climber(4, climbing: climbing), seed: 6)
        let pre = plan.sessions.filter { climbing.contains(WeekSchedule.next($0.weekday!)) }
        #expect(!pre.isEmpty)
        for s in pre {
            #expect(!s.blocks.contains { $0.kind == .power })
            #expect(s.blocks.first { $0.kind == .strength }!.note!.contains("Climbing tomorrow"))
            #expect(WeekSchedule.note(weekday: s.weekday!, climbing: climbing)!.contains("tomorrow"))
        }
    }

    @Test func respectsPreferredGymDays() {
        let gym = [1, 3, 5]
        let plan = Generator.generateWeek(climber(3, climbing: [2, 4], gym: gym), seed: 7)
        #expect(plan.sessions.map(\.weekday) == gym.map { Optional($0) })
        // Gym days alone (no climbing) also lay the week out.
        let noClimb = Generator.generateWeek(climber(3, climbing: nil, gym: gym), seed: 7)
        #expect(noClimb.sessions.map(\.weekday) == gym.map { Optional($0) })
        #expect(noClimb.sessions[0].dayLabel == "Monday")
    }

    @Test func tooFewGymDaysAreTopped() {
        let plan = Generator.generateWeek(climber(4, climbing: [2, 4], gym: [1]), seed: 8)
        #expect(plan.sessions.count == 4)
        #expect(plan.sessions.contains { $0.weekday == 1 })
    }

    @Test func scheduledPlanIsDeterministicAndCodable() throws {
        let p = climber(5, climbing: [2, 4, 6], gym: [1, 2, 3, 5, 7], goal: .climbing)
        let plan = Generator.generateWeek(p, week: 2, seed: 9)
        #expect(plan == Generator.generateWeek(p, week: 2, seed: 9))
        let data = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(WeekPlan.self, from: data) == plan)
    }

    @Test func profileWithoutNewFieldsStillDecodes() throws {
        let old = Profile(goal: .climbing, sessionsPerWeek: 4, climbingDaysPerWeek: 2)
        let json = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        #expect(!json.contains("climbingWeekdays"))
        #expect(!json.contains("gymWeekdays"))
        #expect(try JSONDecoder().decode(Profile.self, from: Data(json.utf8)) == old)

        let new = Profile(climbingWeekdays: [2, 4], gymWeekdays: [1, 3])
        #expect(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(new)) == new)
    }
}
