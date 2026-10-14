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
        #expect(Programme.all.count >= 5)
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

    /// Leaving a programme brings back the member's goal, split and method, not the gym list they had then.
    @Test func restoringKeepsGymEditedDuringTheProgramme() throws {
        var own = member()
        own.split = .upperLower
        own.method = .block
        own.equipment = Array(Gym.puls5.equipment.prefix(48))
        let saved = ActiveProgramme.SavedPlan(profile: own, seed: 1, week: 2)
        let prog = try #require(Programme.all.first)
        var now = prog.profile(from: own, starting: true)
        now.equipment = Gym.puls5.equipment
        now.gymWeekdays = [1, 3, 5]
        let back = saved.restoring(onto: now)
        #expect(back.equipment == Gym.puls5.equipment)
        #expect(back.gymWeekdays == [1, 3, 5])
        #expect(back.goal == own.goal && back.split == own.split && back.method == own.method)
        #expect(back.focusMuscles == own.focusMuscles && back.sessionsPerWeek == own.sessionsPerWeek)
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

    @Test func lengthsStretchBaseAndBuildOnly() {
        let sf = Programme.strengthFoundation
        #expect(sf.lengths.map(\.weeks) == [6, 8, 10, 12])
        #expect(sf.lengths.filter(\.standard).map(\.weeks) == [8])
        let ten = sf.resized(to: 10)
        #expect(ten.weeks == 10)
        #expect(ten.phases.map(\.weeks) == [4, 3, 1, 1, 1])
        #expect(sf.resized(to: 6).phases.map(\.weeks) == [2, 1, 1, 1, 1])
        #expect(sf.resized(to: 12).phases.map(\.weeks) == [5, 4, 1, 1, 1])
        #expect(sf.resized(to: 8) == sf)
        // Too short to keep a week of Base and Build: standard.
        #expect(sf.resized(to: 4) == sf)
        #expect(ten.phase(week: 10).kind == .test && ten.phase(week: 4).kind == .base && ten.phase(week: 5).kind == .build)
        for p in Programme.all {
            #expect(p.lengths.count >= 3, "\(p.id)")
            for l in p.lengths {
                let r = p.resized(to: l.weeks)
                #expect(r.weeks == l.weeks && r.phases == l.phases, "\(p.id) \(l.weeks)")
                #expect(r.phases.allSatisfy { $0.weeks >= 1 })
                #expect(r.phases.map(\.kind) == p.phases.map(\.kind))
            }
        }
        #expect(Programme.muscleBuilder.lengths.map(\.weeks) == [4, 6, 8, 10])
    }

    @Test func memberLengthIsKeptAndDecodesFromOlderProfiles() throws {
        let saved = ActiveProgramme.SavedPlan(profile: member(), seed: 1, week: 1)
        let a = ActiveProgramme(programmeId: "strength-foundation", start: day("2026-10-12"), seed: 3, saved: saved, length: 12)
        #expect(a.programme?.weeks == 12)
        #expect(!a.finished(on: day("2026-12-28"), calendar: cal))
        #expect(a.finished(on: day("2027-01-04"), calendar: cal))
        let back = try JSONDecoder().decode(ActiveProgramme.self, from: JSONEncoder().encode(a))
        #expect(back.length == 12)
        // Saved before #268: no length, standard programme.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as! [String: Any]
        json.removeValue(forKey: "length")
        let old = try JSONDecoder().decode(ActiveProgramme.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.length == nil && old.programme?.weeks == 8)
        let r = ProgrammeRecord(programmeId: "muscle-builder", start: day("2026-10-12"), end: day("2026-12-12"), finished: true,
                                weeks: 8, length: 8)
        #expect(r.programme?.weeks == 8)
    }

    @Test func previewWeeksCarryTheSignatures() {
        let prog = Programme.strengthFoundation.resized(to: 10)
        for week in 1...prog.weeks {
            let plan = prog.previewWeek(week, member: member(), seed: 1, starting: true)
            #expect(plan.sessions.count == prog.sessionsPerWeek, "week \(week)")
            let sigs = plan.sessions.filter(\.isPlanInsert).count
            #expect(prog.phase(week: week).kind == .test ? sigs == 0 : sigs == 2, "week \(week)")
        }
        // Every programme pins at least one signature in week 1.
        for p in Programme.all {
            let plan = p.previewWeek(1, member: member(climbing: p.climbing ? 2 : 0), seed: 1, starting: true)
            #expect(plan.sessions.contains { $0.isPlanInsert }, "\(p.id)")
        }
        // Same seed, same preview.
        #expect(prog.previewWeek(3, member: member(), seed: 5, starting: true) == prog.previewWeek(3, member: member(), seed: 5, starting: true))
    }

    @Test func memberProgrammePhasesFitTheLength() {
        for weeks in 4...12 {
            for test in [true, false] {
                let ph = Programme.phases(weeks: weeks, test: test)
                #expect(ph.reduce(0) { $0 + $1.weeks } == weeks, "\(weeks) \(test)")
                #expect(ph.allSatisfy { $0.weeks >= 1 })
                #expect(ph.last?.kind == (test ? .test : .ease))
                #expect(ph.first?.kind == .base)
            }
        }
        #expect(Programme.phases(weeks: 8, test: true).map(\.weeks) == [3, 2, 1, 1, 1])
    }

    @Test func workoutBecomesASignatureWithProgression() {
        let sig = ProgrammeSignature.from(
            id: "sig-1", name: "My legs", focus: nil,
            items: [("arm-circles", 1, 15, 0), ("back-squat", 4, 8, 150), ("back-squat", 3, 5, 90), ("plank", 3, 30, 60)],
            progression: true)
        #expect(sig.items.map(\.exerciseId) == ["back-squat", "plank"])
        #expect(sig.items[0].dose(.base) == .init(4, "8"))
        #expect(sig.items[0].dose(.build) == .init(4, "6"))
        #expect(sig.items[0].dose(.peak) == .init(4, "4"))
        #expect(sig.items[0].dose(.ease) == .init(3, "8"))
        #expect(sig.items[1].dose(.base).reps == "30 s")
        #expect(sig.replaces.first == .legs)
        #expect(Set(sig.replaces) == Set(Focus.allCases))
        let flat = ProgrammeSignature.from(id: "s", name: "x", focus: .push, items: [("bench-press", 3, 8, 90)], progression: false)
        #expect(flat.items[0].dose(.peak) == .init(3, "8") && flat.replaces.first == .push)
    }

    @Test func memberProgrammeRunsFromItsSnapshot() throws {
        var mine = Programme.strengthFoundation.copy()
        #expect(mine.mine && mine.basedOn == "strength-foundation" && mine.name == "My strength foundation")
        #expect(Programme.find(mine.id) == nil)
        mine.phases = Programme.phases(weeks: 10, test: true)
        let saved = ActiveProgramme.SavedPlan(profile: member(), seed: 1, week: 1)
        let a = ActiveProgramme(programmeId: mine.id, start: day("2026-10-12"), seed: 3, saved: saved, custom: mine)
        #expect(a.programme == mine && a.programme?.weeks == 10)
        #expect(mine.lengths.contains { $0.standard && $0.weeks == 10 })
        let back = try JSONDecoder().decode(ActiveProgramme.self, from: JSONEncoder().encode(a))
        #expect(back == a)
        var shorter = a
        shorter.length = mine.lengths.first!.weeks
        #expect(shorter.programme!.weeks < 10)
        let plan = mine.previewWeek(1, member: member(), seed: 1, starting: true)
        #expect(plan.sessions.contains { $0.isPlanInsert })
    }
}
