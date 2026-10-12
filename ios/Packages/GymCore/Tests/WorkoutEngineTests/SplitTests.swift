import Foundation
import Testing
@testable import WorkoutEngine

/// Split styles, per-day picks and focus muscles (#200).
@Suite struct SplitTests {
    private func profile(_ g: Goal = .build, sessions: Int = 4) -> Profile {
        var p = Profile(experience: .intermediate, climbingDaysPerWeek: 0)
        p.applyGoal(g)
        p.sessionsPerWeek = sessions
        return p
    }

    private func strengthItems(_ s: Session) -> [PlannedExercise] {
        s.blocks.filter { $0.kind == .strength }.flatMap(\.items)
    }

    @Test func autoKeepsTheGoalWeekExactly() {
        for g in Goal.allCases {
            let p = profile(g, sessions: g.recommendedSessions)
            var q = p
            q.applySplit(.auto)
            q.focusMuscles = []
            #expect(Generator.generateWeek(p, seed: 7) == Generator.generateWeek(q, seed: 7), "\(g)")
        }
    }

    @Test func everyStyleFillsEveryWeekSize() {
        for style in SplitStyle.allCases where style != .auto {
            for n in 2...6 {
                var p = profile(sessions: n)
                p.applySplit(style)
                let plan = Generator.generateWeek(p, seed: 3)
                #expect(plan.sessions.map(\.focus) == style.foci(n), "\(style) \(n)")
                for s in plan.sessions where s.focus != .conditioning {
                    #expect(strengthItems(s).count >= 2, "\(style) \(n) \(s.focus)")
                }
            }
        }
    }

    @Test func bodyPartDaysTrainTheirArea() {
        var p = profile(sessions: 5)
        p.applySplit(.bodyPart)
        let plan = Generator.generateWeek(p, seed: 11)
        let chest = plan.sessions.first { $0.focus == .chestTri }!
        #expect(strengthItems(chest).first?.slot == .hPush)
        let back = plan.sessions.first { $0.focus == .backBi }!
        #expect(strengthItems(back).allSatisfy { ![.squat, .hinge, .hPush].contains($0.slot) })
        #expect(plan.sessions.map(\.displayTitle).contains("Chest & triceps"))
    }

    @Test func perDayPicksStayOnTheirDays() {
        var p = profile(sessions: 4)
        p.gymWeekdays = [1, 2, 4, 6]
        p.variety = .rotate
        p.setDay(0, to: .chestTri)
        p.setDay(1, to: .backBi)
        p.setDay(2, to: .legs)
        p.setDay(3, to: .shouldersArms)
        #expect(p.customSplit)
        for week in 1...3 {
            let plan = Generator.generateWeek(p, week: week, seed: 2)
            #expect(plan.sessions.map(\.focus) == [.chestTri, .backBi, .legs, .shouldersArms], "week \(week)")
            #expect(plan.sessions.map(\.weekday) == [1, 2, 4, 6])
        }
        let preview = Generator.weekPreview(p)
        #expect(preview.map(\.focus) == [.chestTri, .backBi, .legs, .shouldersArms])
        #expect(preview.map(\.weekday) == [1, 2, 4, 6])
        // A new goal resets per-day picks (the week size changes).
        p.applyGoal(.strength)
        #expect(!p.customSplit && p.splitDays == nil)
        // Picking a style drops them too.
        p.setDay(0, to: .posterior)
        p.applySplit(.ppl)
        #expect(p.splitDays == nil && p.weekFoci == SplitStyle.ppl.foci(p.sessionsPerWeek))
    }

    @Test func focusMusclesGetMoreSetsAndComeFirst() {
        let base = profile(sessions: 4)
        var p = base
        p.focusMuscles = [.back, .arms]
        let a = Generator.generateWeek(base, seed: 9), b = Generator.generateWeek(p, seed: 9)
        func sets(_ plan: WeekPlan, _ groups: Set<MuscleGroup>) -> Int {
            plan.sessions.flatMap(strengthItems).filter { !$0.slot.muscleGroups.isDisjoint(with: groups) }
                .reduce(0) { $0 + $1.prescription.sets }
        }
        #expect(sets(b, [.back, .arms]) > sets(a, [.back, .arms]))
        let upper = b.sessions.first { $0.focus == .upper }!
        let items = strengthItems(upper).dropFirst().filter { $0.supersetWith == nil }
        #expect(items.first.map { !$0.slot.muscleGroups.isDisjoint(with: [.back, .arms]) } == true)
        #expect(strengthItems(upper).contains { $0.prescription.note?.contains("Focus muscle") == true })
        // Every group at once is allowed.
        p.focusMuscles = MuscleGroup.allCases
        #expect(Generator.generateWeek(p, seed: 9).sessions.count == 4)
    }

    @Test func historyStoresAnOlderSessionType() throws {
        var p = profile(sessions: 5)
        p.applySplit(.bodyPart)
        let s = Generator.generateWeek(p, seed: 1).sessions[0]
        #expect(s.focus == .chestTri)
        let r = WorkoutRecord.build(session: s, week: 1, deload: false, setsDone: [:], weights: [:],
                                    startedAt: Date(), endedAt: Date(), bodyMassKg: nil)
        #expect(r.focus == .push && r.title == "Chest & triceps")
        let unknown = try JSONDecoder().decode([Focus].self, from: Data(#"["legs","from-the-future"]"#.utf8))
        #expect(unknown == [.legs, .fullUpper])
    }

    @Test func profileRoundTripsAndOlderProfilesDecode() throws {
        var p = profile()
        p.applySplit(.arnold)
        p.focusMuscles = [.hips, .shoulders]
        let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p))
        #expect(back.splitStyle == .arnold && back.focusGroups == [.hips, .shoulders])
        let old = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(Profile()))
        #expect(old.splitStyle == .auto && old.splitDays == nil && old.focusGroups.isEmpty)
    }

    @Test func quickSessionCoversEveryDayType() {
        let p = profile()
        for f in Generator.dayFoci {
            #expect(Generator.quickSession(p, focus: f, week: 1, seed: 3)?.focus == f, "\(f)")
        }
    }
}
