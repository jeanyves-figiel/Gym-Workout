import Foundation
import Testing
@testable import WorkoutEngine

private func climber(_ sessions: Int, climbing: [Int], before: ClimbNeighbour? = nil, after: ClimbNeighbour? = nil,
                     sameDay: ClimbSameDay? = nil) -> Profile {
    Profile(goal: .balanced, sessionsPerWeek: sessions, experience: .intermediate, climbingDaysPerWeek: 2,
            climbingWeekdays: climbing, climbBefore: before, climbAfter: after, climbSameDay: sameDay)
}

/// Choices for the gym days around climbing (#47).
@Suite struct ClimbPrefsTests {
    @Test func defaultsMatchOriginalBehaviour() {
        for sessions in 2...6 {
            let unset = Generator.generateWeek(climber(sessions, climbing: [2, 4]), seed: 11)
            let explicit = Generator.generateWeek(climber(sessions, climbing: [2, 4], before: .light, after: .light, sameDay: .avoid), seed: 11)
            #expect(unset == explicit)
        }
        #expect(Profile().climbPrefs == ClimbPrefs())
    }

    @Test func strongDayBeforeKeepsPushingHard() {
        let climbing = [2, 4]
        let plan = Generator.generateWeek(climber(4, climbing: climbing, before: .strong), seed: 6)
        let pre = plan.sessions.filter { climbing.contains(WeekSchedule.next($0.weekday!)) }
        #expect(!pre.isEmpty)
        for s in pre {
            #expect(s.blocks.first { $0.kind == .strength }!.note!.contains("push hard"))
            #expect(WeekSchedule.note(weekday: s.weekday!, climbing: climbing, prefs: ClimbPrefs(before: .strong))!.contains("push hard"))
        }
    }

    @Test func noAdjustmentLeavesSessionsUntouched() {
        let climbing = [2, 4]
        let plan = Generator.generateWeek(climber(4, climbing: climbing, before: .any, after: .any), seed: 6)
        for s in plan.sessions {
            let note = s.blocks.first { $0.kind == .strength }?.note ?? ""
            #expect(!note.contains("Climbing tomorrow"))
        }
        #expect(WeekSchedule.note(weekday: 1, climbing: climbing, prefs: ClimbPrefs(before: .any)) == "Climbing tomorrow")
    }

    @Test func restKeepsDaysAroundClimbingFree() {
        // Climbing Tue + Thu: Mon, Wed, Fri touch a climbing day, so two sessions go to the weekend.
        let plan = Generator.generateWeek(climber(2, climbing: [2, 4], before: .rest, after: .rest), seed: 3)
        #expect(Set(plan.sessions.compactMap(\.weekday)) == [6, 7])
    }

    @Test func sameDayAllowedCostsLess() {
        let avoid = WeekSchedule.score(days: [2], order: [.push], climbing: [2], gym: [], prefs: ClimbPrefs())
        let allow = WeekSchedule.score(days: [2], order: [.push], climbing: [2], gym: [], prefs: ClimbPrefs(sameDay: .allow))
        #expect(allow < avoid)
        #expect(WeekSchedule.note(weekday: 2, climbing: [2], prefs: ClimbPrefs(sameDay: .allow))!.contains("gym first"))
    }

    @Test func prefsRoundTripAndOldProfilesDecode() throws {
        let p = climber(3, climbing: [2, 4], before: .strong, after: .rest, sameDay: .allow)
        var q = p
        q.climbDayAddon = true
        #expect(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(q)) == q)
        let json = String(decoding: try JSONEncoder().encode(Profile()), as: UTF8.self)
        #expect(!json.contains("climbBefore"))
    }

    @Test func climbingDayAddonResolves() {
        let t = WorkoutTemplate.climbAddon
        for it in t.items { #expect(Exercise.find(it.exerciseId) != nil, "\(it.exerciseId)") }
        #expect(!WorkoutTemplate.all.contains(t))
        #expect(WorkoutTemplate.find(sessionId: t.sessionId) == t)
        // No pulling or heavy grip: it stacks with a climbing session.
        #expect(t.items.allSatisfy { !Exercise.get($0.exerciseId).gripHeavy })
        #expect(t.session.estMin <= 35)
    }
}
