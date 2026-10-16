import Foundation

/// One up or down movement found in a set.
public struct LiftPhase: Equatable, Sendable {
    /// +1 along the measured axis, -1 against it.
    public var sign: Int
    /// Sample indexes of the moving part (trimmed of the slow ends).
    public var start: Int
    public var end: Int
    public var duration: Double
    /// Distance travelled, m.
    public var range: Double
    /// Mean and peak speed, m/s.
    public var meanVelocity: Double
    public var peakVelocity: Double
}

/// One rep: its lifting (concentric) part and, when found, the lowering part next to it.
public struct LiftRep: Codable, Equatable, Sendable {
    /// Mean speed of the lifting part, m/s (the number velocity-based training uses).
    public var meanVelocity: Double
    public var peakVelocity: Double
    /// Range of motion, m.
    public var range: Double
    public var concentricSec: Double
    public var eccentricSec: Double?
    /// Sample index where the lifting part ended.
    public var endIndex: Int

    public init(meanVelocity: Double, peakVelocity: Double, range: Double, concentricSec: Double, eccentricSec: Double?, endIndex: Int) {
        self.meanVelocity = meanVelocity
        self.peakVelocity = peakVelocity
        self.range = range
        self.concentricSec = concentricSec
        self.eccentricSec = eccentricSec
        self.endIndex = endIndex
    }
}

/// Finds reps in one set's acceleration along the movement axis (#383).
///
/// Method: smooth; find still stretches (accel close to zero for 0.6 s) and take the sensor bias from them;
/// integrate acceleration to speed between still stretches, removing the remaining linear drift so speed is
/// zero at both ends; split at speed sign changes; remove drift again per movement (speed is zero at each
/// turnaround) and trim the slow ends. A movement counts when it travels at least the minimum range.
public enum SetAnalyzer {
    public struct Config: Equatable, Sendable {
        public var sampleRate = 100.0
        public var minRange = 0.08
        public var minDuration = 0.2
        public var maxDuration = 6.0
        /// Smoothed |accel| below this (g) for `stillSeconds` counts as still.
        public var stillAccel = 0.012
        public var stillSeconds = 0.6
        /// Rotation (rad/s) above this is never still (only when rotation is known).
        public var stillRotation = 0.35
        /// Speed (m/s) a movement must pass before a turnaround is looked for.
        public var turnVelocity = 0.04
        /// Slower mean speeds are drift, not reps (grinding reps stay above ~0.1 m/s).
        public var minMeanVelocity = 0.08

        public init() {}
    }

    static let g = 9.80665

    /// Movements in `accel` (g along the axis, one value per sample). `rotation` is optional, same length.
    /// `closed`: the set is over, so a movement still going at the end is finished as well.
    public static func phases(_ accel: [Double], rotation: [Double]? = nil, config c: Config = Config(), closed: Bool = false) -> [LiftPhase] {
        let n = accel.count
        guard n > 2 else { return [] }
        let dt = 1 / c.sampleRate
        let a = smooth(accel.map { $0 * g }, half: 5)
        let wide = smooth(accel, half: 10)
        let stillRun = max(2, Int(c.stillSeconds * c.sampleRate))

        // Still stretches.
        var still = [Bool](repeating: false, count: n)
        var run = 0
        for i in 0..<n {
            let quiet = abs(wide[i]) < c.stillAccel && (rotation.map { i < $0.count ? $0[i] < c.stillRotation : true } ?? true)
            run = quiet ? run + 1 : 0
            if run == stillRun {
                for j in (i - run + 1)...i { still[j] = true }
            } else if run > stillRun {
                still[i] = true
            }
        }
        var biasSum = 0.0
        var biasCount = 0
        for i in 0..<n where still[i] {
            biasSum += a[i]
            biasCount += 1
        }
        let bias = biasCount > 0 ? biasSum / Double(biasCount) : a.reduce(0, +) / Double(n)

        var out: [LiftPhase] = []
        var i = 0
        while i < n {
            if still[i] {
                i += 1
                continue
            }
            var j = i
            while j < n && !still[j] { j += 1 }
            let endsStill = j < n || closed
            // Speed over the moving stretch.
            var v = [Double](repeating: 0, count: j - i)
            var acc = 0.0
            for k in i..<j {
                acc += (a[k] - bias) * dt
                v[k - i] = acc
            }
            if endsStill, let last = v.last, v.count > 1 {
                let m = Double(v.count)
                for k in v.indices { v[k] -= last * Double(k + 1) / m }
            }
            // Turnarounds.
            var cuts = [0]
            var armed = 0
            for k in v.indices where abs(v[k]) > c.turnVelocity {
                let s = v[k] > 0 ? 1 : -1
                if armed != 0 && s != armed {
                    var kk = k
                    while kk > 0 && v[kk - 1] * Double(s) > 0 { kk -= 1 }
                    if kk > cuts.last! { cuts.append(kk) }
                }
                armed = s
            }
            if endsStill { cuts.append(v.count) }
            for (c0, c1) in zip(cuts, cuts.dropFirst()) where c1 - c0 >= 2 {
                if let p = phase(Array(v[c0..<c1]), offset: i + c0, dt: dt, config: c) { out.append(p) }
            }
            i = j
        }
        return out
    }

    private static func phase(_ raw: [Double], offset: Int, dt: Double, config c: Config) -> LiftPhase? {
        let m = raw.count
        let v0 = raw[0]
        let v1 = raw[m - 1]
        var v = raw
        for k in 0..<m { v[k] -= v0 + (v1 - v0) * Double(k) / Double(m - 1) }
        var total = 0.0
        var peak = 0.0
        for x in v {
            total += x * dt
            peak = max(peak, abs(x))
        }
        let sign = total >= 0 ? 1 : -1
        let floor = max(0.02, 0.1 * peak)
        guard let first = v.firstIndex(where: { $0 * Double(sign) >= floor }),
              let last = v.lastIndex(where: { $0 * Double(sign) >= floor }) else { return nil }
        var range = 0.0
        for k in first...last { range += v[k] * dt }
        range = abs(range)
        let duration = Double(last - first + 1) * dt
        guard range >= c.minRange, duration >= c.minDuration, duration <= c.maxDuration, range / duration >= c.minMeanVelocity else { return nil }
        return LiftPhase(sign: sign, start: offset + first, end: offset + last, duration: duration, range: range,
                         meanVelocity: range / duration, peakVelocity: peak)
    }

    /// Lifting direction along the axis: given, or (axis mode) the faster direction once both are seen,
    /// else the direction of the first movement (machines and cables start by lifting).
    public static func concentricSign(_ phases: [LiftPhase], given: Int?) -> Int {
        if let given { return given }
        let pos = phases.filter { $0.sign > 0 }
        let neg = phases.filter { $0.sign < 0 }
        if pos.count >= 2, neg.count >= 2 {
            let p = pos.map(\.duration).reduce(0, +) / Double(pos.count)
            let q = neg.map(\.duration).reduce(0, +) / Double(neg.count)
            return p <= q ? 1 : -1
        }
        return phases.first?.sign ?? 1
    }

    /// Reps from movements: each lifting movement is a rep, with the lowering movement right before or after it.
    public static func reps(_ phases: [LiftPhase], concentricSign sign: Int, sampleRate: Double = 100) -> [LiftRep] {
        var out: [LiftRep] = []
        for (k, p) in phases.enumerated() where p.sign == sign {
            let near = 1.5 * sampleRate
            var ecc: Double?
            if k > 0, phases[k - 1].sign != sign, Double(p.start - phases[k - 1].end) < near {
                ecc = phases[k - 1].duration
            } else if k + 1 < phases.count, phases[k + 1].sign != sign, Double(phases[k + 1].start - p.end) < near {
                ecc = phases[k + 1].duration
            }
            out.append(LiftRep(meanVelocity: p.meanVelocity, peakVelocity: p.peakVelocity, range: p.range,
                               concentricSec: p.duration, eccentricSec: ecc, endIndex: p.end))
        }
        return out
    }

    /// Centred moving average with prefix sums.
    static func smooth(_ x: [Double], half: Int) -> [Double] {
        let n = x.count
        var prefix = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + x[i] }
        return (0..<n).map { i in
            let lo = max(0, i - half)
            let hi = min(n, i + half + 1)
            return (prefix[hi] - prefix[lo]) / Double(hi - lo)
        }
    }

    /// Main axis of a cloud of vectors (power iteration on the covariance), sign kept close to `previous`.
    public static func principalAxis(_ vectors: [Vec3], previous: Vec3? = nil) -> Vec3? {
        let moving = vectors.filter { $0.length > 0.05 }
        guard moving.count >= 20 else { return nil }
        var c = [[Double]](repeating: [0, 0, 0], count: 3)
        for v in moving {
            let a = [v.x, v.y, v.z]
            for r in 0..<3 { for s in 0..<3 { c[r][s] += a[r] * a[s] } }
        }
        var e = previous ?? Vec3(0.577, 0.577, 0.577)
        for _ in 0..<30 {
            let a = [e.x, e.y, e.z]
            let m = (0..<3).map { r in c[r][0] * a[0] + c[r][1] * a[1] + c[r][2] * a[2] }
            let next = Vec3(m[0], m[1], m[2]).unit
            if next == .zero { return nil }
            e = next
        }
        if let previous, e.dot(previous) < 0 { e = e * -1 }
        return e
    }
}
