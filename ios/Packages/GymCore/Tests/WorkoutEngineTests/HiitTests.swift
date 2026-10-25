import Foundation
import Testing
@testable import WorkoutEngine

/// HIIT sessions (#693).
@Suite struct HiitTests {
    @Test func everyBuiltWorkoutFitsItsLengthAndResolves() throws {
        for f in HiitFormat.allCases {
            for m in HiitSpec.lengths {
                for kit in Hiit.Kit.allCases {
                    for low in [false, true] {
                        let spec = HiitSpec(format: f, minutes: m, kit: kit, lowImpact: low)
                        #expect(HiitSpec(sessionId: spec.sessionId) == spec)
                        let w = Hiit.build(spec, gym: Gym.puls5.equipment)
                        #expect(abs(w.minutes - m) <= 2, "\(spec.sessionId): \(w.minutes)′")
                        #expect(w.blocks.allSatisfy { $0.format == f })
                        for b in w.blocks {
                            #expect(!b.moves.isEmpty)
                            for mv in b.moves {
                                let e = try #require(Exercise.find(mv.exerciseId), "\(mv.exerciseId)")
                                if low { #expect(!Hiit.pool.contains { $0.id == mv.exerciseId && $0.jumps }, "\(mv.exerciseId) jumps") }
                                if kit == .body { #expect(e.equipment.allSatisfy { $0 == .mat }, "\(mv.exerciseId) needs kit") }
                            }
                        }
                        for id in w.warmup + w.cooldown { #expect(Exercise.find(id) != nil, "\(id)") }
                        let s = try #require(Hiit.session(sessionId: spec.sessionId, gym: Gym.puls5.equipment))
                        #expect(s.hiit == w && s.focus == .conditioning && s.isExample)
                    }
                }
            }
        }
        #expect(HiitSpec(sessionId: "example-hiit-nope") == nil)
        #expect(HiitSpec(sessionId: "w1s2") == nil)
    }

    @Test func stepsWalkTheBlocks() throws {
        let w = Hiit.build(HiitSpec(format: .tabata, minutes: 10, kit: .body))
        let steps = w.steps
        #expect(steps.first?.kind == .prep)
        // Contiguous, no gaps.
        for (a, b) in zip(steps, steps.dropFirst()) { #expect(a.end == b.start) }
        let work = steps.filter { $0.kind == .work }
        #expect(work.count == 8 && work.allSatisfy { $0.seconds == 20 })
        #expect(steps.filter { $0.kind == .rest }.count == 7)
        // Two moves in turn.
        #expect(work[0].exerciseId == w.blocks[0].moves[0].exerciseId && work[1].exerciseId == w.blocks[0].moves[1].exerciseId)
        #expect(work[2].moveIndex == 0)
        // A rest shows the next move.
        let rest = try #require(steps.first { $0.kind == .rest })
        #expect(rest.exerciseId == work[1].exerciseId)
        #expect(w.step(at: 0)?.kind == .prep)
        #expect(w.step(at: Double(w.totalSeconds)) == nil)

        let amrap = Hiit.build(HiitSpec(format: .amrap, minutes: 15, kit: .kettlebell))
        let open = try #require(amrap.steps.first { $0.kind == .work })
        #expect(open.open && open.moves.count == 3 && open.seconds == amrap.blocks[0].work)

        let pyramid = Hiit.build(HiitSpec(format: .pyramid, minutes: 10, kit: .body))
        #expect(pyramid.steps.filter { $0.kind == .work }.map(\.seconds) == [20, 40, 60, 40, 20])
    }

    @Test func sessionItemsMatchBlocks() {
        let w = Hiit.build(HiitSpec(format: .emom, minutes: 15, kit: .dumbbells))
        let s = w.session(id: "x")
        #expect(s.blocks.map(\.kind) == [.warmup, .cardio, .cooldown])
        let main = s.blocks[1].items
        #expect(main.count == w.blocks[0].moves.count)
        #expect(main.map(\.group) == ["A1", "A2"])
        // EMOM alternates: sets split between the moves.
        #expect(main.reduce(0) { $0 + $1.prescription.sets } == w.blocks[0].rounds)
        #expect(abs(s.estMin - 15) <= 2)
        #expect(s.displayTitle == w.name)
    }

    @Test func planAddsHiitDaysOnFreeDays() throws {
        var p = Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0)
        p.gymWeekdays = [1, 3, 5]
        let before = Generator.generateWeek(p, week: 1, seed: 42)
        p.hiit = HiitPlan(days: 2)
        let plan = Generator.generateWeek(p, week: 1, seed: 42)
        let hiit = plan.sessions.filter { $0.hiit != nil }
        #expect(hiit.count == 2)
        #expect(plan.sessions.count == before.sessions.count + 2)
        let lifting = Set(before.sessions.compactMap(\.weekday))
        for s in hiit {
            let wd = try #require(s.weekday)
            #expect(!lifting.contains(wd))
            #expect(s.focus == .conditioning)
            #expect(abs(s.estMin - Hiit.plannedMinutes(p, deload: false)) <= 2, "\(s.estMin)")
        }
        // Not on back-to-back days.
        let days = hiit.compactMap(\.weekday).sorted()
        #expect(WeekSchedule.next(days[0]) != days[1])
        // Lifting days unchanged.
        #expect(plan.sessions.filter { $0.hiit == nil } == before.sessions)
        // Ids unique.
        #expect(Set(plan.sessions.map(\.id)).count == plan.sessions.count)
        // Formats rotate week to week; the deload week is easy.
        let w2 = Generator.generateWeek(p, week: 2, seed: 42).sessions.first { $0.hiit != nil }
        #expect(w2?.hiit?.name != hiit[0].hiit?.name)
        let deload = Generator.generateWeek(p, week: 4, seed: 42).sessions.first { $0.hiit != nil }
        #expect(deload?.hiit?.name == "Easy intervals")
    }

    @Test func offOrNoFreeDayKeepsThePlan() {
        var p = Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0)
        p.gymWeekdays = [1, 3, 5]
        let base = Generator.generateWeek(p, week: 1, seed: 7)
        p.hiit = HiitPlan(days: 0)
        #expect(Generator.generateWeek(p, week: 1, seed: 7) == base)
        p.hiit = nil
        #expect(Generator.generateWeek(p, week: 1, seed: 7) == base)
        // Every day taken: no HIIT day.
        p.gymWeekdays = [1, 2, 3, 4, 5, 6, 7]
        p.sessionsPerWeek = 6
        p.climbingWeekdays = [7]
        p.climbingDaysPerWeek = 1
        p.hiit = HiitPlan(days: 3)
        let full = Generator.generateWeek(p, week: 1, seed: 7)
        #expect(full.sessions.filter { $0.hiit != nil }.count <= 1)
    }

    @Test func finisherReplacesCardio() {
        var p = Profile(goal: .endurance, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0)
        let base = Generator.generateWeek(p, week: 1, seed: 3)
        p.hiit = HiitPlan(days: 0, finisher: true)
        let plan = Generator.generateWeek(p, week: 1, seed: 3)
        #expect(plan.sessions.count == base.sessions.count)
        for (a, b) in zip(base.sessions, plan.sessions) where a.focus != .conditioning && a.blocks.contains(where: { $0.kind == .cardio }) {
            let fin = b.blocks.first { $0.kind == .cardio }!
            #expect(fin.title.hasPrefix("Finisher"))
            #expect(fin.items.map(\.group) == ["F1", "F2"])
            #expect(fin.items.reduce(0) { $0 + $1.prescription.sets } == 8)
            // The rest of the session is untouched.
            #expect(a.blocks.filter { $0.kind != .cardio } == b.blocks.filter { $0.kind != .cardio })
        }
        #expect(!plan.sessions.contains { $0.hiit != nil })
    }

    @Test func easedHasFewerIntervals() {
        let w = Hiit.planned(week: 1, n: 0, minutes: 30, equipment: Gym.puls5.equipment, lowImpact: false, seed: 1)
        let e = w.eased()
        #expect(e.totalSeconds < w.totalSeconds)
        let s = w.session(id: "w1s4", index: 3)
        var placed = s
        placed.weekday = 2
        let eased = placed.easedForReadiness()
        #expect(eased.id == "w1s4" && eased.weekday == 2 && eased.hiit == e)
    }

    @Test func planInsertKeepsTheTiming() {
        let s = Hiit.build(HiitSpec(format: .tabata, minutes: 15)).session(id: HiitSpec(format: .tabata, minutes: 15).sessionId)
        let ins = PlanInsert(week: 1, weekday: 3, workout: CustomWorkout(name: s.title), generated: s)
        let placed = ins.session(index: 4, weekday: 3)
        #expect(placed.hiit == s.hiit)
        #expect(placed.blocks[1].items.map(\.group) == s.blocks[1].items.map(\.group))
        let decoded = try? JSONDecoder().decode(Session.self, from: JSONEncoder().encode(placed))
        #expect(decoded?.hiit == s.hiit)
    }

    // #757: picked days, a fixed format and a length.
    @Test func pickedDaysFormatAndLength() throws {
        var p = Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0)
        p.gymWeekdays = [1, 3, 5]
        p.hiit = HiitPlan(days: 1, weekdays: [6], format: .tabata, minutes: 20)
        let plan = Generator.generateWeek(p, week: 1, seed: 42)
        let hiit = plan.sessions.filter { $0.hiit != nil }
        #expect(hiit.count == 1)
        #expect(hiit.first?.weekday == 6)
        #expect(hiit.first?.hiit?.blocks.allSatisfy { $0.format == .tabata } == true)
        #expect(abs((hiit.first?.estMin ?? 0) - 20) <= 2)
        // A picked lifting day stays the lift's: Coach picks a free day instead.
        p.hiit = HiitPlan(days: 1, weekdays: [3])
        let moved = Generator.generateWeek(p, week: 1, seed: 42).sessions.filter { $0.hiit != nil }
        #expect(moved.count == 1)
        #expect(moved.first?.weekday != 3)
        // Two days, one picked: the other is a Coach pick.
        p.hiit = HiitPlan(days: 2, weekdays: [7])
        let two = Generator.generateWeek(p, week: 1, seed: 42).sessions.compactMap { $0.hiit != nil ? $0.weekday : nil }
        #expect(two.count == 2 && two.contains(7))
    }

    @Test func planDecodesWithoutNewFieldsAndTogglesDays() throws {
        let old = try JSONDecoder().decode(HiitPlan.self, from: Data(#"{"days":2,"finisher":true,"lowImpact":false}"#.utf8))
        #expect(old == HiitPlan(days: 2, finisher: true))
        var h = HiitPlan(days: 1)
        h.toggle(2)
        #expect(h.weekdays == [2])
        h.toggle(4)
        #expect(h.weekdays == [4] && h.days == 1)
        h.setDays(2)
        h.toggle(6)
        #expect(h.weekdays == [4, 6])
        h.setDays(1)
        #expect(h.weekdays == [6])
        let round = try JSONDecoder().decode(HiitPlan.self, from: JSONEncoder().encode(HiitPlan(days: 1, weekdays: [3], format: .emom, minutes: 15)))
        #expect(round.format == .emom && round.minutes == 15 && round.weekdays == [3])
    }
}
