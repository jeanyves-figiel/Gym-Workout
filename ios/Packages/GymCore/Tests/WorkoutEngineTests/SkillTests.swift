import Foundation
import Testing
@testable import WorkoutEngine

/// Calisthenics skill tree (#621).
@Suite struct SkillTests {
    @Test func treeUsesRealBodyweightExercises() {
        for b in Skills.Branch.allCases {
            let nodes = Skills.nodes(b)
            #expect(nodes.count >= 4, "\(b)")
            #expect(nodes.map(\.level) == Array(1...nodes.count))
            for n in nodes {
                #expect(Exercise.find(n.exerciseId) != nil, "\(n.exerciseId)")
                #expect(n.target > 0)
                let t = Skills.practice(n)
                #expect(WorkoutTemplate.find(sessionId: t.sessionId) == t)
                #expect(Skills.isPractice(t.sessionId))
                #expect(t.session.estMin <= 15, "\(t.id) \(t.session.estMin) min")
            }
        }
        #expect(Set(Skills.tree.values.flatMap { $0 }.map(\.exerciseId)).count == Skills.tree.values.flatMap { $0 }.count)
    }

    @Test func testsUnlockInOrder() {
        var p = SkillProgress()
        let pull = Skills.nodes(.pull)
        #expect(p.unlocked(.pull) == 1)
        // Passing level 3 before level 2 opens nothing.
        let early = p.record(pull[2], result: 99)
        #expect(early == nil)
        #expect(p.unlocked(.pull) == 1)
        let short = p.record(pull[0], result: pull[0].target - 1)
        #expect(short == nil)
        let opened = p.record(pull[0], result: pull[0].target)
        #expect(opened == pull[1])
        // Level 2 passed: level 3 was passed already, so level 4 opens.
        let jump = p.record(pull[1], result: pull[1].target)
        #expect(jump == pull[3])
        // Best is kept.
        p.record(pull[0], result: 1)
        #expect(p.best?[pull[0].exerciseId] == pull[0].target)
    }

    @Test func skillOfTheMonthLastsItsMonth() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let oct = cal.date(from: DateComponents(year: 2026, month: 10, day: 22))!
        let nov = cal.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let p = SkillProgress(focus: "pull-up", focusMonth: Skills.monthKey(oct, cal))
        #expect(p.focusNode(now: oct, calendar: cal)?.exerciseId == "pull-up")
        #expect(p.focusNode(now: nov, calendar: cal) == nil)
        // October 2026: 4 Mondays, 4 Wednesdays, 5 Fridays.
        #expect(Skills.practiceGoal(month: "2026-10", calendar: cal) == 13)
    }
}
