import Foundation
import Testing
@testable import WorkoutEngine

/// Life-stage programmes (#625).
@Suite struct LifeStageTests {
    let profile = Profile(goal: .athletic, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0)
    let now = Date(timeIntervalSince1970: 1_792_454_400)

    @Test func programmesAreSoundAndFindable() {
        for p in Programme.lifeStages {
            #expect(Programme.find(p.id) == p)
            #expect(p.lifeStage != nil)
            #expect(!Programme.all.contains(p))
            #expect(p.weeks >= 4 && p.weeks <= 12, "\(p.id)")
            for s in p.signatures {
                for it in s.items { #expect(Exercise.find(it.exerciseId) != nil, "\(p.id) \(it.exerciseId)") }
            }
        }
        for stage in LifeStage.allCases {
            let check = LifeStageCheckIn(stage: stage, dueDate: now.addingTimeInterval(10 * 7 * 86_400),
                                         birthDate: now.addingTimeInterval(-4 * 7 * 86_400), weeksOff: 10, doctorOK: true)
            for r in stage.rules(check, now: now) {
                #expect(Exercise.find(r.from) != nil, "\(stage) \(r.from)")
                #expect(Exercise.find(r.to) != nil, "\(stage) \(r.to)")
                #expect(r.from != r.to)
            }
        }
    }

    @Test func trimesterFollowsTheDueDate() {
        let week: (Double) -> Date = { now.addingTimeInterval($0 * 7 * 86_400) }
        #expect(LifeStageCheckIn(stage: .pregnancy, dueDate: week(30), doctorOK: true).trimester(now: now) == 1)
        #expect(LifeStageCheckIn(stage: .pregnancy, dueDate: week(20), doctorOK: true).trimester(now: now) == 2)
        #expect(LifeStageCheckIn(stage: .pregnancy, dueDate: week(5), doctorOK: true).trimester(now: now) == 3)
        #expect(LifeStageCheckIn(stage: .postpartum, birthDate: week(-6), doctorOK: true).weeksSinceBirth(now: now) == 6)
    }

    @Test func guardSwapsRiskyMovesAndSaysWhy() {
        let second = LifeStageCheckIn(stage: .pregnancy, dueDate: now.addingTimeInterval(20 * 7 * 86_400), doctorOK: true)
        let rules = LifeStage.pregnancy.rules(second, now: now)
        #expect(rules.contains { $0.from == "bench-press" && $0.why.contains("2nd trimester") })
        #expect(rules.contains { $0.from == "box-jump" })
        // First trimester keeps bench press.
        let first = LifeStageCheckIn(stage: .pregnancy, dueDate: now.addingTimeInterval(32 * 7 * 86_400), doctorOK: true)
        #expect(!LifeStage.pregnancy.rules(first, now: now).contains { $0.from == "bench-press" })

        let plan = Generator.generateWeek(profile, week: 2, seed: 4)
        let out = LifeStage.pregnancy.guarded(plan, second, now: now)
        let froms = Set(rules.map(\.from))
        for s in out.plan.sessions {
            for b in s.blocks {
                for it in b.items { #expect(!froms.contains(it.exerciseId), "\(it.exerciseId) left in") }
                if [.power, .strength].contains(b.kind) {
                    #expect(b.items.allSatisfy { $0.prescription.intensity == LifeStage.talkTest })
                }
            }
        }
        // Uids stay, so logs and edits still match.
        #expect(out.plan.sessions.flatMap { $0.blocks.flatMap(\.items).map(\.uid) } == plan.sessions.flatMap { $0.blocks.flatMap(\.items).map(\.uid) })
        if !out.swaps.isEmpty {
            #expect(out.plan.sessions.flatMap(\.blocks).contains { $0.note?.contains("Swapped for you") == true })
        }
    }
}
