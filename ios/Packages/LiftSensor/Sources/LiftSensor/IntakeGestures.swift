import Foundation

/// Invisible Monkey (#1087): sips and bites from the Watch's wrist motion, so water and meals log themselves.
///
/// Input is the raw accelerometer the Watch keeps in the background (`CMSensorRecorder`, ~50 Hz, in g, gravity
/// included). A low-pass filter gives the gravity direction; its share along the forearm (the Watch's x axis) is the
/// forearm's elevation. Bringing a cup or a fork to the mouth raises the hand above the elbow for a moment and brings
/// it back down:
/// - sip: the hand goes high (cup tilted, ≥ 55°) and stays 1–8 s;
/// - bite: shorter and lower (35–75°, 0.4–4 s), and comes in runs; a run of bites is a meal window.
///
/// Heuristic thresholds, tuned on synthetic traces; each member's Keep / Bin answers on the phone teach the rest.
/// Pure Swift, tested with `swift test` like the lift sensor.
public enum IntakeGestures {
    /// One accelerometer reading: seconds since any fixed start, and acceleration in g in the Watch's frame.
    public struct Sample: Equatable, Sendable {
        public var t: TimeInterval
        public var a: Vec3
        public init(t: TimeInterval, a: Vec3) {
            self.t = t
            self.a = a
        }
    }

    public enum Kind: String, Codable, Sendable { case sip, bite }

    /// One hand-to-mouth movement.
    public struct Gesture: Equatable, Sendable {
        public var kind: Kind
        /// Start, seconds on the samples' clock.
        public var start: TimeInterval
        /// Seconds the hand stayed up.
        public var duration: TimeInterval
        /// Highest forearm elevation, degrees above level.
        public var peak: Double
        /// 0–1: how much it looks like the real thing.
        public var confidence: Double
    }

    /// A run of bites: someone eating.
    public struct MealWindow: Equatable, Sendable {
        public var start: TimeInterval
        public var end: TimeInterval
        public var bites: Int
        public var confidence: Double
    }

    /// Which way the Watch's x axis points when the hand is above the elbow: −1 on the left wrist with the crown on
    /// the right (the default), +1 when only one of the two is flipped, −1 again when both are.
    public static func handSign(leftWrist: Bool, crownRight: Bool) -> Double { leftWrist == crownRight ? -1 : 1 }

    // Thresholds.
    static let raised = 35.0
    static let sipPeak = 55.0
    static let sipMin = 1.0
    static let sipMax = 8.0
    static let biteMin = 0.4
    static let biteMax = 4.0
    /// Hand must come from below this before rising (arm on a desk or hanging), so a hand already up doesn't count.
    static let fromBelow = 20.0
    /// A dip under `raised` shorter than this doesn't end the movement.
    static let gap = 0.3
    /// Bites closer than this belong to the same meal.
    static let mealGap: TimeInterval = 4 * 60
    static let mealBites = 6
    static let mealSpan: TimeInterval = 3 * 60

    /// Forearm elevation in degrees (−90 hand down … +90 hand up) for each sample, from low-passed gravity.
    public static func elevations(_ samples: [Sample], handSign: Double, alpha: Double = 0.1) -> [Double] {
        var g = samples.first?.a ?? .zero
        return samples.map { s in
            g = Vec3(g.x + alpha * (s.a.x - g.x), g.y + alpha * (s.a.y - g.y), g.z + alpha * (s.a.z - g.z))
            let u = g.unit
            let up = max(-1, min(1, handSign * u.x))
            return asin(up) * 180 / .pi
        }
    }

    /// Hand-to-mouth movements in the samples (time-ordered).
    public static func detect(_ samples: [Sample], handSign: Double) -> [Gesture] {
        guard samples.count > 10 else { return [] }
        let el = elevations(samples, handSign: handSign)
        var out: [Gesture] = []
        var i = 0
        while i < samples.count {
            guard el[i] >= raised else { i += 1; continue }
            // A raised span, bridging short dips.
            let start = i
            var end = i
            var j = i
            while j < samples.count {
                if el[j] >= raised {
                    end = j
                } else if samples[j].t - samples[end].t > gap {
                    break
                }
                j += 1
            }
            i = end + 1
            let t0 = samples[start].t
            let duration = samples[end].t - t0
            // Where the hand came from: lowest elevation in the second before the rise.
            var before = el[start]
            var k = start
            while k > 0, t0 - samples[k - 1].t <= 1.5 {
                k -= 1
                before = min(before, el[k])
            }
            // A span that runs into the start of the data can't be judged.
            guard start > 0, before <= fromBelow else { continue }
            let peak = el[start...end].max() ?? 0
            // Shake while up: a cup to the lips is held still, a lift or a wave is not.
            let mags = samples[start...end].map(\.a.length)
            let mean = mags.reduce(0, +) / Double(mags.count)
            let shake = (mags.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(mags.count)).squareRoot()
            if let g = classify(duration: duration, peak: peak, shake: shake) {
                out.append(Gesture(kind: g.0, start: t0, duration: duration, peak: peak, confidence: g.1))
            }
        }
        return out
    }

    static func classify(duration: TimeInterval, peak: Double, shake: Double) -> (Kind, Double)? {
        // Strong shake while up: lifting, waving, combing hair.
        guard shake < 0.35 else { return nil }
        let still = shake < 0.12 ? 0.1 : 0
        if peak >= sipPeak, duration >= sipMin, duration <= sipMax {
            var c = 0.6 + still
            if peak >= 70 { c += 0.1 }
            if duration >= 1.5, duration <= 5 { c += 0.1 }
            return (.sip, min(0.95, c))
        }
        if peak <= 80, duration >= biteMin, duration <= biteMax {
            return (.bite, min(0.8, 0.5 + still + (duration <= 2.5 ? 0.1 : 0)))
        }
        return nil
    }

    /// Runs of bites (sips in between don't break a run) that look like a meal.
    public static func meals(_ gestures: [Gesture]) -> [MealWindow] {
        let bites = gestures.filter { $0.kind == .bite }.sorted { $0.start < $1.start }
        var out: [MealWindow] = []
        var run: [Gesture] = []
        func close() {
            defer { run = [] }
            guard run.count >= mealBites, let a = run.first, let b = run.last else { return }
            let end = b.start + b.duration
            guard end - a.start >= mealSpan else { return }
            let mean = run.map(\.confidence).reduce(0, +) / Double(run.count)
            out.append(MealWindow(start: a.start, end: end, bites: run.count, confidence: min(0.9, mean * 0.6 + Double(run.count) * 0.02)))
        }
        for b in bites {
            if let last = run.last, b.start - (last.start + last.duration) > mealGap { close() }
            run.append(b)
        }
        close()
        return out
    }
}
