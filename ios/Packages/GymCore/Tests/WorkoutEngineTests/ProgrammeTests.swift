import Foundation
import Testing
@testable import WorkoutEngine

/// Training programmes (#255): phases, signature workouts, running weeks, pause.
@Suite struct ProgrammeTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)!
    }

    private func member(climbing: Int = 0) -> Profile {
        Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: climbing)
    }

    @Test func catalogIsSoundAndUsesRealExercises() {
        #expect(Programme.all.count >= 3)
        #expect(Set(Programme.all.map(\.id)).count == Programme.all.count)
        for p in Programme.all {
            #expect(p.weeks >= 4 && p.weeks <= 12, "\(p.id)")
            #expect(p.phases.last?.kind == .test || p.phases.last?.kind == .ease, "\(p.id)")
            for id in p.lifts { #expect(Exercise.find(id) != nil, "\(p.id) lift \(id)") }
            for s in p.signatures {
                for it in s.items { #expect(Exercise.find(it.exerciseId) != nil, "\(p.id) \(s.id) \(it.exerciseId)") }
            }
            #expect(Programme.find(p.id) == p)
        }
    }

    @Test func phasesMapOntoTheGeneratorCycle() {
        let p = Programme.strengthFoundation
        #expect(p.weeks == 8)
        #expect((1...8).map { p.phase(week: $0).kind } == [.base, .base, .base, .build, .build, .peak, .ease, .test])
        #expect((1...8).map { p.cycleWeek(week: $0) } == [1, 1, 1, 2, 2, 3, 4, 4])
        #expect(p.phaseStarts.map(\.week) == [1, 4, 6, 7, 8])
        // Out of range clamps.
        #expect(p.phase(week: 0).kind == .base)
        #expect(p.phase(week: 99).kind == .test)
    }

    @Test func programmeSetsGoalSplitMethodAndKeepsTheRest() {
        var mine = member(climbing: 2)
        mine.maxSessionMinutes = 50
        mine.split = .ppl
        mine.splitDays = [.push, .pull, .legs]
        let p = Programme.muscleBuilder.profile(from: mine, starting: true)
        #expect(p.goal == .build && p.split == .upperLower && p.method == .volume && p.splitDays == nil)
        #expect(p.sessionsPerWeek == 4)
        #expect(p.maxSessionMinutes == 50 && p.climbingDaysPerWeek == 2 && p.equipment == mine.equipment)
        #expect(Programme.muscleBuilder.isApplied(to: p))
        // Later edits keep the member's session count.
        var edited = p
        edited.sessionsPerWeek = 5
        edited.goal = .endurance
        let enforced = Programme.muscleBuilder.profile(from: edited)
        #expect(enforced.goal == .build && enforced.sessionsPerWeek == 5)
    }

    @Test func signaturesReplaceAMatchingDayAndKeepItsFlow() {
        let prog = Programme.strengthFoundation
        let profile = prog.profile(from: member(), starting: true)
        for week in 1...prog.weeks {
            let plan = Generator.generateWeek(profile, week: prog.cycleWeek(week: week), seed: Programme.seed(9, week: week))
            let inserts = prog.signatureInserts(week: week, plan: plan, profile: profile)
            if prog.phase(week: week).kind == .test {
                #expect(inserts.isEmpty)
                continue
            }
            #expect(inserts.count == 2, "week \(week)")
            #expect(Set(inserts.compactMap(\.replacing)).count == inserts.count)
            let applied = plan.applying(inserts)
            #expect(applied.sessions.count == plan.sessions.count)
            for ins in inserts {
                let s = applied.sessions[ins.replacing!]
                #expect(s.isPlanInsert && s.title == ins.workout.name)
                let generated = plan.sessions[ins.replacing!]
                #expect(s.weekday == generated.weekday)
                // Warm-up stays, strength block is the signature.
                #expect(s.blocks.contains { $0.kind == .warmup } == generated.blocks.contains { $0.kind == .warmup })
                let strength = s.blocks.filter { $0.kind == .strength }.flatMap(\.items)
                #expect(!strength.isEmpty)
                #expect(Set(s.blocks.flatMap(\.items).map(\.uid)).count == s.blocks.flatMap(\.items).count)
            }
        }
        // Heavier, fewer reps as the phases go.
        let squat: (Int) -> String? = { week in
            let plan = Generator.generateWeek(profile, week: prog.cycleWeek(week: week), seed: 1)
            return prog.signatureInserts(week: week, plan: plan, profile: profile).first?.generated?
                .blocks.first { $0.kind == .strength }?.items.first?.prescription.reps
        }
        #expect(squat(1) == "5" && squat(4) == "3" && squat(6) == "2")
    }

    @Test func signatureInsertIdsAreStablePerWeek() {
        let a = Programme.insertId(programme: "x", signature: "y", week: 2)
        #expect(a == Programme.insertId(programme: "x", signature: "y", week: 2))
        #expect(a != Programme.insertId(programme: "x", signature: "y", week: 3))
        #expect(Programme.seed(5, week: 1) == 5)
        #expect(Programme.seed(5, week: 2) != Programme.seed(5, week: 3))
    }

    @Test func missingEquipmentSwapsOrDropsExercises() {
        let prog = Programme.strengthFoundation
        var profile = prog.profile(from: member(), starting: true)
        profile.equipment = [.dumbbells, .bench]
        let plan = Generator.generateWeek(profile, week: 1, seed: 4)
        for ins in prog.signatureInserts(week: 1, plan: plan, profile: profile) {
            for it in ins.generated!.blocks.filter({ $0.kind == .strength }).flatMap(\.items) {
                #expect(Selector.isAvailable(Exercise.get(it.exerciseId), Set(profile.equipment)), "\(it.exerciseId)")
            }
        }
    }

    @Test func runningWeeksPauseAndFinish() {
        let saved = ActiveProgramme.SavedPlan(profile: member(), seed: 1, week: 2)
        // Started on a Wednesday: week 1 is that week.
        var a = ActiveProgramme(programmeId: "climbers-power", start: day("2026-10-14"), seed: 3, saved: saved)
        #expect(a.week(on: day("2026-10-12"), calendar: cal) == 1)
        #expect(a.week(on: day("2026-10-18"), calendar: cal) == 1)
        #expect(a.week(on: day("2026-10-19"), calendar: cal) == 2)
        #expect(!a.finished(on: day("2026-11-22"), calendar: cal))
        #expect(a.finished(on: day("2026-11-23"), calendar: cal))
        // Paused in week 2 for two weeks: resumes at week 2.
        a.pausedAt = day("2026-10-21")
        #expect(a.week(on: day("2026-11-05"), calendar: cal) == 2)
        #expect(!a.finished(on: day("2027-01-01"), calendar: cal))
        let r = a.resumed(on: day("2026-11-04"), calendar: cal)
        #expect(!r.paused && r.pausedWeeks == 2)
        #expect(r.week(on: day("2026-11-04"), calendar: cal) == 2)
        #expect(r.week(on: day("2026-11-09"), calendar: cal) == 3)
        let back = try! JSONDecoder().decode(ActiveProgramme.self, from: JSONEncoder().encode(r))
        #expect(back == r)
    }

    @Test func liftsCompareBeforeAndSinceTheStart() {
        let start = day("2026-10-12")
        let logs = [
            SetLog(date: day("2026-10-01"), exerciseId: "back-squat", kg: 100, reps: 5),
            SetLog(date: day("2026-06-01"), exerciseId: "back-squat", kg: 200, reps: 5),
            SetLog(date: day("2026-10-20"), exerciseId: "back-squat", kg: 105, reps: 5),
        ]
        let out = ProgrammeLift.compare(["back-squat", "bench-press"], logs: logs, attempts: [], start: start)
        #expect(out.count == 2)
        #expect(out[0].before! < out[0].now!)
        #expect(out[0].change! > 0)
        #expect(out[1].before == nil && out[1].now == nil && out[1].change == nil)
    }
}
