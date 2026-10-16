import Foundation
import Testing
@testable import LiftSensor

/// Deterministic noise for synthetic sets.
struct Rng {
    var s: UInt64

    mutating func next() -> Double {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Double(s >> 11) / Double(UInt64(1) << 53)
    }

    mutating func gauss() -> Double {
        let u1 = max(next(), 1e-12)
        let u2 = next()
        return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }
}

/// A set of smooth reps (cosine speed profile) as vertical acceleration in g at 100 Hz, plus each rep's true
/// mean lifting speed. `startUp`: lift first (deadlift, curl); else lower first (squat, bench).
func synthSet(reps: Int = 8, conc: Double = 0.8, ecc: Double = 1.6, rom: Double = 0.45, pause: Double = 0.4,
              fatigue: Double = 0.04, noise: Double = 0.03, bias: Double = 0.01, startUp: Bool = false,
              pre: Double = 2, post: Double = 7, seed: UInt64 = 1) -> (accel: [Double], truth: [Double]) {
    var rng = Rng(s: seed)
    let hz = 100.0
    var out: [Double] = []
    var truth: [Double] = []
    func move(_ dur: Double, _ d: Double) {
        let n = Int(dur * hz)
        for i in 0..<n {
            let s = Double(i) / Double(n)
            let a = d * Double.pi * Double.pi / (2 * dur * dur) * cos(Double.pi * s)
            out.append(a / 9.80665 + rng.gauss() * noise + bias)
        }
    }
    func still(_ dur: Double) {
        for _ in 0..<Int(dur * hz) { out.append(rng.gauss() * noise * 0.3 + bias) }
    }
    still(pre)
    for r in 0..<reps {
        let c = conc * (1 + fatigue * Double(r))
        if startUp {
            move(c, rom)
            truth.append(rom / c)
            move(ecc, -rom)
        } else {
            move(ecc, -rom)
            still(0.05)
            move(c, rom)
            truth.append(rom / c)
        }
        still(pause)
    }
    still(post)
    return (out, truth)
}

func lifting(_ accel: [Double]) -> [LiftRep] {
    SetAnalyzer.reps(SetAnalyzer.phases(accel, closed: true), concentricSign: 1)
}

struct SetCase: Sendable, CustomTestStringConvertible {
    var name: String
    var startUp = false
    var conc = 0.8
    var ecc = 1.6
    var rom = 0.45
    var pause = 0.4
    var noise = 0.03
    var bias = 0.01

    var testDescription: String { name }
}

@Suite struct AnalyzerTests {
    @Test(arguments: [
        SetCase(name: "squat / bench"),
        SetCase(name: "deadlift / curl", startUp: true),
        SetCase(name: "fast", conc: 0.5, ecc: 1.0, rom: 0.6, pause: 0.1),
        SetCase(name: "touch and go with bias", startUp: true, pause: 0, bias: 0.02),
    ])
    func countsRepsAndSpeed(_ c: SetCase) {
        let s = synthSet(conc: c.conc, ecc: c.ecc, rom: c.rom, pause: c.pause, noise: c.noise, bias: c.bias, startUp: c.startUp)
        let reps = lifting(s.accel)
        #expect(reps.count == 8)
        guard reps.count == 8 else { return }
        for (r, t) in zip(reps, s.truth) {
            #expect(abs(r.meanVelocity - t) / t < 0.25, "speed \(r.meanVelocity) vs \(t)")
        }
        let meanRange = reps.map(\.range).reduce(0, +) / 8
        #expect(abs(meanRange - c.rom) / c.rom < 0.2)
    }

    @Test func slowGrindingReps() {
        let s = synthSet(conc: 1.5, ecc: 2.5, rom: 0.3, noise: 0.015, seed: 2)
        #expect(lifting(s.accel).count == 8)
    }

    @Test func noisyWristStillCounts() {
        let s = synthSet(noise: 0.04, bias: 0.02)
        #expect(lifting(s.accel).count == 8)
    }

    @Test func smallWobbleIsNotARep() {
        let s = synthSet(reps: 6, conc: 0.6, ecc: 0.6, rom: 0.03, pause: 0.3)
        #expect(lifting(s.accel).isEmpty)
    }

    @Test func stillnessHasNoReps() {
        let s = synthSet(reps: 0, pre: 5, post: 5)
        #expect(lifting(s.accel).isEmpty)
    }

    @Test func tempoHasLoweringTime() {
        let s = synthSet(conc: 0.8, ecc: 1.6)
        let reps = lifting(s.accel)
        let ecc = reps.compactMap(\.eccentricSec)
        #expect(ecc.count >= 6)
        if let e = ecc.first { #expect(e > 1.0 && e < 2.0) }
    }
}

@Suite struct TrackerTests {
    func feed(_ accel: [Double], into t: SetTracker, horizontal: Bool = false) -> [SetTracker.Update] {
        var updates: [SetTracker.Update] = []
        for a in accel {
            let s = horizontal
                ? MotionSample(userAcceleration: Vec3(a, 0, 0), gravity: Vec3(0, 0, -1))
                : MotionSample(userAcceleration: Vec3(0, 0, a), gravity: Vec3(0, 0, -1))
            if let u = t.append(s) { updates.append(u) }
        }
        return updates
    }

    @Test func endsSetAndCuesVelocityLoss() {
        let s = synthSet(fatigue: 0.06)
        let t = SetTracker(profile: LiftProfile(direction: .up, family: .squat), lossLimit: 0.2)
        let updates = feed(s.accel, into: t)
        #expect(updates.filter(\.ended).count == 1)
        #expect(updates.filter(\.lossReached).count == 1)
        #expect(updates.last?.reps.count == 8)
        // Rep count only grows while the set runs.
        let counts = updates.map(\.reps.count)
        #expect(counts.last == counts.max())
    }

    @Test func undoWaitsForMoreReps() {
        let s = synthSet(reps: 3, post: 6)
        let t = SetTracker(profile: LiftProfile(direction: .up, family: .bench), lossLimit: nil)
        let first = feed(s.accel, into: t).contains { $0.ended }
        #expect(first)
        t.resume()
        let more = synthSet(reps: 2, pre: 0.5, post: 6, seed: 7)
        let updates = feed(more.accel, into: t)
        let endedAgain = updates.contains { $0.ended }
        #expect(endedAgain)
        #expect(t.finish().count == 5)
    }

    @Test func pulldownCountsDownwardPulls() {
        let s = synthSet(startUp: true)
        let t = SetTracker(profile: LiftProfile(direction: .down, family: .row), lossLimit: nil)
        // A pulldown seen from the wrist: lifting part goes down.
        _ = feed(s.accel.map { -$0 }, into: t)
        #expect(t.finish().count == 8)
    }

    @Test func sidewaysMachineUsesMainAxis() {
        let s = synthSet(startUp: true)
        let t = SetTracker(profile: LiftProfile(direction: .axis, family: .row), lossLimit: nil)
        _ = feed(s.accel, into: t, horizontal: true)
        let reps = t.finish()
        #expect(reps.count == 8)
        if let r = reps.first, let truth = s.truth.first { #expect(abs(r.meanVelocity - truth) / truth < 0.25) }
    }
}

@Suite struct ProfileTests {
    @Test func wristLifts() {
        #expect(LiftProfile.for(name: "Barbell Back Squat") == LiftProfile(direction: .up, family: .squat))
        #expect(LiftProfile.for(name: "Bench Press") == LiftProfile(direction: .up, family: .bench))
        #expect(LiftProfile.for(name: "Conventional Deadlift") == LiftProfile(direction: .up, family: .hinge))
        #expect(LiftProfile.for(name: "Lat Pulldown")?.direction == .down)
        #expect(LiftProfile.for(name: "Seated Cable Row")?.direction == .axis)
        #expect(LiftProfile.for(name: "Dumbbell Curl") == LiftProfile(direction: .up, family: .arm))
    }

    @Test func machineLiftsAreNotTracked() {
        for n in ["Leg Press", "Leg Extension", "Seated Leg Curl", "Standing Calf Raise", "Barbell Hip Thrust", "Pull-Up", "Dips", "Plank"] {
            #expect(LiftProfile.for(name: n) == nil, "\(n)")
        }
    }
}

@Suite struct LoadVelocityTests {
    @Test func oneRepMaxFromTwoLoads() {
        // 0.8 m/s at 60 kg, 0.5 m/s at 90 kg → 0.01 m/s per kg → 0.3 m/s (squat) at 110 kg.
        let e = LoadVelocity.estimatedOneRepMax([.init(kg: 60, velocity: 0.8), .init(kg: 90, velocity: 0.5)], minimumVelocity: 0.3)
        #expect(e.map { abs($0 - 110) < 0.01 } == true)
    }

    @Test func needsDifferentLoads() {
        #expect(LoadVelocity.estimatedOneRepMax([.init(kg: 80, velocity: 0.6), .init(kg: 80, velocity: 0.5)], minimumVelocity: 0.3) == nil)
    }

    @Test func zones() {
        #expect(SpeedZone.of(0.4) == .maxStrength)
        #expect(SpeedZone.of(0.9) == .power)
        let loss = LiftStats.velocityLoss([
            LiftRep(meanVelocity: 0.8, peakVelocity: 1, range: 0.4, concentricSec: 0.5, eccentricSec: nil, endIndex: 0),
            LiftRep(meanVelocity: 0.6, peakVelocity: 1, range: 0.4, concentricSec: 0.6, eccentricSec: nil, endIndex: 0),
        ])
        #expect(abs(loss - 0.25) < 1e-9)
    }
}

@Suite struct MachineTests {
    @Test func spots() {
        #expect(MachineSpot.for(name: "Leg Extension")?.place == "the shin pad")
        #expect(MachineSpot.for(name: "Seated Calf Raise")?.place == "the knee pad")
        #expect(MachineSpot.for(name: "Leg Press")?.family == .squat)
        #expect(MachineSpot.for(name: "Plank") == nil)
        #expect(MachineSpot.for(name: "Bench Press") == nil)
    }

    @Test func fixedAxisCountsPushes() {
        let s = synthSet(startUp: true)
        let t = SetTracker(profile: LiftProfile(direction: .axis, family: .other), lossLimit: nil)
        t.fixAxis(Vec3(-1, 0, 0))
        for a in s.accel {
            _ = t.append(MotionSample(userAcceleration: Vec3(-a, 0, 0), gravity: Vec3(0, 0, -1)))
        }
        #expect(t.finish().count == 8)
    }
}
