import Foundation
import Testing
@testable import LiftSensor

/// WOD timers (#622), swim sets and plans (#624), punch and swing counting (#611).
struct WodTimerTests {
    @Test func tabataPhases() {
        let t = WodTimer.tabata
        #expect(t.totalSeconds == 240)
        #expect(t.state(at: 0).phase?.kind == .prep)
        #expect(t.state(at: 0).remaining == 10)
        #expect(t.state(at: 10).phase == WodTimer.Phase(kind: .work, round: 1, start: 10, seconds: 20))
        #expect(t.state(at: 239.5).phase?.round == 8)
        #expect(t.state(at: 239.5).remaining == 1)
        #expect(t.state(at: 240).finished)
        #expect(t.summary == "8 × 20″ / 10″")
    }

    @Test func cuesAreRungOnce() {
        let t = WodTimer.tabata
        #expect(t.cues(from: 6, to: 10) == [.tick, .tick, .tick, .bell])
        #expect(t.cues(from: 29, to: 30) == [.rest])
        #expect(t.cues(from: 239, to: 240) == [.done])
        // Same stretch asked twice in two halves: nothing doubled.
        #expect(t.cues(from: 6, to: 8) + t.cues(from: 8, to: 10) == t.cues(from: 6, to: 10))
        // Boxing claps 10 s before the bell; Tabata's 20 s rounds don't.
        #expect(WodTimer.boxing.cues(from: 179, to: 180) == [.clap])
        #expect(!t.cues(from: 0, to: 240).contains(.clap))
    }

    @Test func kinds() {
        #expect(WodTimer.boxing.summary == "6 × 3′ / 1′")
        #expect(WodTimer.emom.summary == "Every min × 10")
        #expect(WodTimer.amrap.summary == "12′ as many rounds")
        #expect(WodTimer(name: "x", kind: .amrap, work: 600, rounds: 5).rounds == 1)
        // For time counts up.
        #expect(WodTimer.forTime.display(at: 70) == 60)
        #expect(WodTimer.amrap.display(at: 70) == 12 * 60 - 60)
        #expect(WodTimer.clock(754) == "12:34")
        #expect(WodTimer.short(90) == "1′30″")
    }
}

struct SwimTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d))! }

    @Test func sendOffClock() {
        let w = SwimWorkout(name: "t", sets: [SwimSet(reps: 1, meters: 300, stroke: .easy, sendOff: 420),
                                              SwimSet(reps: 4, meters: 100, stroke: .free, sendOff: 120)])
        #expect(w.sets[1].full == "4×100 free @ 2:00")
        #expect(w.summary == "300 m easy · 4×100 free")
        #expect(w.clock(at: 0) == SwimWorkout.Clock(set: 0, rep: 1, nextIn: 420, finished: false))
        #expect(w.clock(at: 430) == SwimWorkout.Clock(set: 1, rep: 1, nextIn: 110, finished: false))
        #expect(w.clock(at: 670) == SwimWorkout.Clock(set: 1, rep: 3, nextIn: 110, finished: false))
        #expect(w.clock(at: 900).finished)
        #expect(w.sendOffs(from: 0, to: 900) == 5)
        #expect(w.sendOffs(from: 0, to: 419) == 0)
    }

    @Test func planGrowsAndEndsWithTheTest() {
        let p = SwimPlan(goal: .oneK, weeks: 8, perWeek: 2, start: day(19), days: [3, 5])
        let first = p.workout(week: 1, index: 0)
        #expect(first.totalMeters == 600)
        #expect(first.sets[1].title == "3×100 free")
        #expect(p.workout(week: 7, index: 0).totalMeters > first.totalMeters)
        #expect(p.workout(week: 8, index: 1).sets.last?.meters == 1000)
        // Tuesday and Thursday of week 1; nothing on Wednesday; next from Wednesday is Thursday.
        #expect(p.workout(on: day(20), calendar: cal)?.id == first.id)
        #expect(p.workout(on: day(22), calendar: cal)?.id == p.workout(week: 1, index: 1).id)
        #expect(p.workout(on: day(21), calendar: cal) == nil)
        #expect(p.next(from: day(21), calendar: cal)?.day == day(22))
        #expect(p.week(on: day(18), calendar: cal) == nil)
    }

    @Test func swimDaysAvoidLifting() {
        #expect(SwimPlan.days(perWeek: 2, lifting: [2, 4, 6]) == [3, 5])
        #expect(SwimPlan.days(perWeek: 3, lifting: [2, 4, 6]) == [3, 5, 7])
        #expect(SwimPlan.days(perWeek: 2, lifting: [3, 5, 7]) == [2, 4])
        #expect(SwimPlan.days(perWeek: 3, lifting: [1, 2, 3, 4, 5, 6]).count == 3)
    }

    @Test func gymDayBlock() {
        let b = SwimWorkout.block(minutes: 15, place: .finisher, pace: 150)
        #expect(b.summary == "300 m easy · 4×50 free")
        #expect(b.seconds <= 15 * 60)
    }
}

struct ImpactTests {
    private func still(_ n: Int) -> [Vec3] { Array(repeating: Vec3(0, 0, 1), count: n) }
    private func hit(_ n: Int = 4) -> [Vec3] { Array(repeating: Vec3(0, 0, 7), count: n) }

    @Test func punchesCountedOnce() {
        var c = PunchCounter(hz: 100)
        for a in still(50) + hit() + still(50) + hit() + still(5) + hit() + still(50) { c.append(a) }
        // Second and third hits are 0.09 s apart: one punch.
        #expect(c.count == 2)
        #expect(PunchCounter.power(12) == 1)
    }

    @Test func swingsByShot() {
        var c = SwingCounter(hz: 200)
        func swing(_ r: Vec3, _ g: Vec3) {
            for _ in 0..<100 { c.append(rotation: .zero, gravity: Vec3(0, -1, 0)) }
            for _ in 0..<10 { c.append(rotation: r, gravity: g) }
            for _ in 0..<100 { c.append(rotation: .zero, gravity: Vec3(0, -1, 0)) }
        }
        swing(Vec3(0, 0, 20), Vec3(0, -1, 0))
        swing(Vec3(0, 0, -15), Vec3(0, -1, 0))
        swing(Vec3(0, 0, 12), Vec3(-1, 0, 0))
        #expect(c.counts[.forehand] == 1)
        #expect(c.counts[.backhand] == 1)
        #expect(c.counts[.smash] == 1)
        #expect(abs(c.top - 86.4) < 0.01)
    }
}
