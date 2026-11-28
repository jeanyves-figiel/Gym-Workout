import Foundation
import Testing
@testable import LiftSensor

/// Ski / snowboard lift vs run (#1129) on a simulated day: strap in, run with a bump, break on the slope, cat track,
/// lift queue, chairlift with a dip. One altitude sample a second with barometer-like noise.
struct SlopeDetectorTests {
    /// Deterministic noise in −1…1.
    struct Noise {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 33) / Double(1 << 30) - 1
        }
    }

    struct Day {
        var t = Date(timeIntervalSince1970: 1_800_000_000)
        var alt = 2000.0
        var noise: Noise
        var noiseMetres: Double
        var samples: [(Date, Double, Double)] = []

        init(seed: UInt64, noiseMetres: Double) {
            noise = Noise(state: seed)
            self.noiseMetres = noiseMetres
        }

        mutating func seg(_ seconds: Int, _ vs: Double, kmh: Double) {
            for _ in 0..<seconds {
                t = t.addingTimeInterval(1)
                alt += vs + noise.next() * 0.2
                samples.append((t, alt + noise.next() * noiseMetres, max(0, kmh + noise.next())))
            }
        }

        /// One lap: 438 m run (bump, break, cat track), 3 min queue, 270 s chair with a dip.
        mutating func lap() {
            seg(60, 0, kmh: 1)
            seg(90, -1.8, kmh: 35); seg(15, 0.5, kmh: 10); seg(60, -2.2, kmh: 45)
            seg(120, 0, kmh: 0.5)
            seg(100, -1.5, kmh: 30); seg(20, -0.1, kmh: 8)
            seg(180, 0, kmh: 0.5)
            seg(100, 1.4, kmh: 15); seg(20, -0.4, kmh: 15); seg(150, 1.4, kmh: 15)
        }
    }

    private func run(seed: UInt64, noise: Double, laps: Int = 3) -> (SlopeDetector, [SlopeDetector.Event]) {
        var day = Day(seed: seed, noiseMetres: noise)
        for _ in 0..<laps { day.lap() }
        let d = SlopeDetector()
        var events: [SlopeDetector.Event] = []
        for (t, a, k) in day.samples {
            d.speed(k)
            events += d.add(a, at: t)
        }
        return (d, events)
    }

    @Test(arguments: [1, 2, 3] as [UInt64]) func barometerDay(seed: UInt64) {
        let (d, events) = run(seed: seed, noise: 0.4)
        #expect(d.runs == 3)
        #expect(d.lifts.count == 3)
        // Truth: 285 s riding and 270 s on the chair per lap.
        #expect(abs(d.rideSeconds - 855) < 90)
        #expect(abs(d.liftSeconds - 810) < 60)
        let drops = events.compactMap { if case let .run(drop, _, _) = $0 { drop } else { nil } }
        #expect(drops.allSatisfy { abs($0 - 438) < 25 })
        // The dip on the chair and the bump on the run never flip the phase.
        let lifts = events.filter { if case .phase(.lift, _) = $0 { true } else { false } }
        #expect(lifts.count == 3)
    }

    @Test func noisyGPSAltitudeStillCountsRuns() {
        let (d, _) = run(seed: 7, noise: 6)
        #expect(d.runs == 3)
        #expect(d.lifts.count == 3)
        #expect(abs(d.liftSeconds - 810) < 150)
    }

    @Test func standingStillIsNeither() {
        let d = SlopeDetector()
        let t0 = Date(timeIntervalSince1970: 0)
        for i in 0..<600 { d.speed(0.3); d.add(1500 + (i % 2 == 0 ? 0.3 : -0.3), at: t0.addingTimeInterval(Double(i))) }
        #expect(d.phase == .still)
        #expect(d.runs == 0)
        #expect(d.liftSeconds == 0)
        #expect(d.rideSeconds < 60)
    }

    @Test func lastRunCountsAtFinish() {
        var day = Day(seed: 4, noiseMetres: 0.4)
        day.lap()
        day.seg(60, 0, kmh: 1)
        day.seg(200, -1.8, kmh: 40)
        let d = SlopeDetector()
        for (t, a, k) in day.samples { d.speed(k); d.add(a, at: t) }
        #expect(d.runs == 1)
        let end = d.finish(at: day.t)
        #expect(d.runs == 2)
        #expect(end.count == 1)
        #expect(d.lifts.allSatisfy { $0.end != nil })
    }

    @Test func slopeFit() {
        let t0 = Date(timeIntervalSince1970: 0)
        let pts = (0..<30).map { (t: t0.addingTimeInterval(Double($0)), alt: 100 + 1.5 * Double($0)) }
        #expect(abs((SlopeDetector.slope(pts) ?? 0) - 1.5) < 1e-9)
        #expect(SlopeDetector.slope(Array(pts.prefix(10))) == nil)
    }
}
