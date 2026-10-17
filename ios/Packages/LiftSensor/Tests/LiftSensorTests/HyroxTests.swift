import Foundation
import Testing
@testable import LiftSensor

struct HyroxTests {
    @Test func formats() {
        #expect(HyroxFormat.full.steps.count == 16)
        #expect(HyroxFormat.full.steps.first == .run(1, meters: 1000))
        #expect(HyroxFormat.full.steps.last == .station(.wallBalls))
        #expect(HyroxFormat.half(second: true).steps[1] == .station(.rowing))
        #expect(HyroxFormat.compromised(.sledPush, rounds: 4).steps.count == 8)
    }

    @Test func pacingAddsUpToTheGoal() {
        let steps = HyroxFormat.full.steps
        let p = HyroxPacing(goalSeconds: 75 * 60, steps: steps)
        #expect(abs(p.targets.reduce(0, +) + p.roxzone - 75 * 60) < 0.001)
        // Later runs are planned slower than the first.
        #expect(p.targets[14] > p.targets[0])
        // Wall balls get more time than the farmers carry.
        #expect(p.targets[15] > p.targets[11])
    }

    @Test func divisionLoads() {
        #expect(HyroxDivision(.pro, .men).load(.sledPush) == "202 kg")
        #expect(HyroxDivision(.open, .women).load(.farmersCarry) == "2 × 16 kg")
        #expect(HyroxDivision(.open, .men).load(.skiErg) == nil)
        // Mixed only exists for teams.
        #expect(HyroxDivision(.pro, .mixed).group == .men)
    }

    static let running = HyroxFeatures(cadence: 2.8, intensity: 0.6, period: 0.7, peak: 0.9, rotation: 2)
    static let idle = HyroxFeatures(cadence: 0, intensity: 0.05, period: nil, peak: 0.05, rotation: 0.1)

    static func doing(_ s: HyroxStation) -> HyroxFeatures {
        switch s {
        case .skiErg: HyroxFeatures(cadence: 0, intensity: 0.4, period: 1.5, peak: 0.8, rotation: 1.5)
        case .sledPush: HyroxFeatures(cadence: 1.2, intensity: 0.2, period: nil, peak: 0.2, rotation: 0.3)
        case .sledPull: HyroxFeatures(cadence: 0, intensity: 0.4, period: 1.0, peak: 0.5, rotation: 1.5)
        case .burpeeBroadJumps: HyroxFeatures(cadence: 0.5, intensity: 0.8, period: 4, peak: 2, rotation: 2)
        case .rowing: HyroxFeatures(cadence: 0, intensity: 0.3, period: 2.4, peak: 0.4, rotation: 1)
        case .farmersCarry: HyroxFeatures(cadence: 1.9, intensity: 0.2, period: nil, peak: 0.2, rotation: 0.3)
        case .sandbagLunges: HyroxFeatures(cadence: 0.8, intensity: 0.3, period: 2, peak: 0.4, rotation: 0.8)
        case .wallBalls: HyroxFeatures(cadence: 0, intensity: 0.6, period: 2.5, peak: 1.4, rotation: 1.5)
        }
    }

    @Test func signaturesDoNotMatchRestOrRunning() {
        for s in HyroxStation.allCases {
            #expect(!Self.idle.matches(s))
            #expect(!Self.running.matches(s))
            #expect(Self.doing(s).matches(s))
        }
    }

    /// Every lap: 240 s running, 15 s still, 180 s at the station, 15 s still.
    @Test func recordsAFullRaceByItself() {
        let t0 = Date(timeIntervalSince1970: 0)
        let d = HyroxDetector(steps: HyroxFormat.full.steps, start: t0)
        var timeline: [HyroxFeatures] = []
        for s in HyroxStation.allCases {
            timeline += Array(repeating: Self.running, count: 240) + Array(repeating: Self.idle, count: 15)
            timeline += Array(repeating: Self.doing(s), count: 180) + Array(repeating: Self.idle, count: 15)
        }
        timeline += Array(repeating: Self.idle, count: 30)
        var finished: Date?
        for (i, f) in timeline.enumerated() {
            for e in d.feed(f, at: t0.addingTimeInterval(Double(i))) {
                if case let .finished(t) = e { finished = t }
            }
        }
        #expect(d.splits.count == 16)
        #expect(d.splits.allSatisfy(\.auto))
        #expect(d.splits[0].seconds == 239)
        #expect(d.splits[1].step == .station(.skiErg))
        #expect(d.splits[1].seconds == 179)
        #expect(d.splits[2].start == t0.addingTimeInterval(450))
        #expect(finished == t0.addingTimeInterval(3584))
        let race = HyroxRace(format: .full, division: HyroxDivision(), start: t0, end: finished!, splits: d.splits)
        #expect(race.runSeconds == 8 * 239)
        #expect(race.stationSeconds == 8 * 179)
        #expect(race.roxzone == 240)
    }

    @Test func handMovesOnAndFinishes() {
        let t0 = Date(timeIntervalSince1970: 0)
        let d = HyroxDetector(steps: HyroxFormat.compromised(.wallBalls, rounds: 1).steps, start: t0)
        _ = d.advance(at: t0.addingTimeInterval(300))
        #expect(d.phase == .between)
        _ = d.advance(at: t0.addingTimeInterval(320))
        #expect(d.current == .station(.wallBalls))
        let e = d.finish(at: t0.addingTimeInterval(500))
        #expect(e.last == .finished(t0.addingTimeInterval(500)))
        #expect(d.splits.map(\.auto) == [false, false])
        #expect(d.splits[1].seconds == 180)
    }

    @Test func asksWhenTheRoxzoneDrags() {
        let t0 = Date(timeIntervalSince1970: 0)
        let d = HyroxDetector(steps: HyroxFormat.full.steps, start: t0)
        _ = d.advance(at: t0.addingTimeInterval(240))
        var asked = 0
        for i in 241...400 {
            asked += d.feed(Self.idle, at: t0.addingTimeInterval(Double(i))).filter { $0 == .unsure(1) }.count
        }
        #expect(asked == 1)
    }

    @Test func periodOfASine() {
        let hz = 25.0
        let x = (0..<200).map { sin(2 * Double.pi * Double($0) / hz / 2.0) }
        #expect(abs((HyroxMotion.period(x, hz: hz) ?? 0) - 2.0) < 0.05)
        #expect(HyroxMotion.period(Array(repeating: 0.1, count: 200), hz: hz) == nil)
    }

    @Test func countsWallBalls() {
        var c = HyroxRepCounter(for: .wallBalls)
        var n = 0
        // A throw every 2.5 s for 25 s at 25 Hz.
        for i in 0..<625 {
            let t = Double(i) / 25
            let v = 1.5 * max(0, sin(2 * Double.pi * t / 2.5))
            if c.add(v, at: t) { n += 1 }
        }
        #expect(n == 10)
    }

    @Test func reportFindsTheWeakestStationAndFade() {
        let t0 = Date(timeIntervalSince1970: 0)
        let steps = HyroxFormat.full.steps
        let plan = HyroxPacing(goalSeconds: 75 * 60, steps: steps)
        var t = t0
        var splits: [HyroxSplit] = []
        for (i, s) in steps.enumerated() {
            // Sled push 50 % over plan; runs 2 % slower each.
            let factor = s == .station(.sledPush) ? 1.5 : (s.isRun ? 1 + 0.02 * Double(i / 2) : 1)
            let end = t.addingTimeInterval(plan.targets[i] * factor)
            splits.append(HyroxSplit(step: s, start: t, end: end))
            t = end.addingTimeInterval(20)
        }
        let race = HyroxRace(format: .full, division: HyroxDivision(), start: t0, end: t, goalSeconds: 75 * 60, splits: splits)
        let r = HyroxReport(race)
        #expect(r.weakest == .sledPush)
        #expect((r.rows[2].delta ?? 0) > 0)
        #expect((r.fade ?? 0) > 0.1)
        #expect(r.focus?.hasPrefix("Sled push") == true)
        #expect(HyroxTime.clock(4718) == "1:18:38")
        #expect(HyroxTime.delta(-14) == "−0:14")
    }
}
