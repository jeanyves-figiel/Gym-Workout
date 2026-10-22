import Foundation

// High-rate motion (#611, design B + C from `apple-tech-radar/t9.png`): punches and racket / club swings counted from
// the Watch's batched sensors (accelerometer up to 800 Hz, device motion 200 Hz, `CMBatchedSensorManager`).
// Pure maths so it is tested on macOS; thresholds are first guesses and need a real-Watch check.

/// One impact peak: a run above `threshold` closes when the signal falls under half of it; a new peak inside
/// `refractory` seconds of the last one is the same movement.
struct PeakFinder: Sendable {
    let hz: Double
    let threshold: Double
    let refractory: Double
    private var index = 0
    private var lastPeak = -1_000_000
    private var open: (value: Double, index: Int)?

    init(hz: Double, threshold: Double, refractory: Double) {
        self.hz = hz
        self.threshold = threshold
        self.refractory = refractory
    }

    /// The peak value and its sample index when a peak closes on this sample.
    mutating func append(_ v: Double) -> (value: Double, index: Int)? {
        defer { index += 1 }
        if v >= threshold {
            if open == nil || v > open!.value { open = (v, index) }
            return nil
        }
        guard let peak = open, v < threshold / 2 else { return nil }
        open = nil
        guard Double(peak.index - lastPeak) / hz >= refractory else { return nil }
        lastPeak = peak.index
        return peak
    }
}

/// Boxing (C): punches per round from total acceleration (g, gravity included, as the accelerometer gives it).
public struct PunchCounter: Sendable {
    private var finder: PeakFinder
    public private(set) var count = 0
    /// Peak of each punch, in g above gravity.
    public private(set) var peaks: [Double] = []

    /// Punches peak well above 3 g at the wrist; shadow-boxing drift stays under it.
    public init(hz: Double, threshold: Double = 3.0, refractory: Double = 0.22) {
        finder = PeakFinder(hz: hz, threshold: threshold, refractory: refractory)
    }

    /// Feeds one accelerometer reading; true when it closed a punch.
    @discardableResult
    public mutating func append(_ acceleration: Vec3) -> Bool {
        guard let peak = finder.append(max(0, acceleration.length - 1)) else { return false }
        count += 1
        peaks.append(peak.value)
        return true
    }

    /// 0…1 power of a punch from its peak (3 g light … 12 g hard).
    public static func power(_ peak: Double) -> Double { min(1, max(0, (peak - 3) / 9)) }
}

/// Racket and club swings (B): forehand, backhand and smash counts with the fastest swing.
public struct SwingCounter: Sendable {
    public enum Shot: String, CaseIterable, Sendable {
        case forehand, backhand, smash

        public var short: String {
            switch self {
            case .forehand: "FH"
            case .backhand: "BH"
            case .smash: "SMASH"
            }
        }
    }

    private var finder: PeakFinder
    /// Lever from shoulder to racket head (m): turns the wrist's spin into head speed.
    private let lever: Double
    /// Watch on the non-racket wrist mirrors forehand and backhand.
    private let mirrored: Bool
    private var gravityAtPeak: [Int: Vec3] = [:]
    private var spinAtPeak: [Int: Vec3] = [:]
    private var index = 0
    public private(set) var counts: [Shot: Int] = [:]
    /// km/h of the fastest swing.
    public private(set) var top: Double = 0
    public private(set) var last: (shot: Shot, kmh: Double)?

    public var total: Int { counts.values.reduce(0, +) }

    /// `lever`: padel / tennis about 1.2 m, golf 1.6 m. Swings spin the wrist past 8 rad/s; footwork stays under it.
    public init(hz: Double, lever: Double = 1.2, mirrored: Bool = false, threshold: Double = 8, refractory: Double = 0.7) {
        finder = PeakFinder(hz: hz, threshold: threshold, refractory: refractory)
        self.lever = lever
        self.mirrored = mirrored
    }

    /// Feeds one device-motion reading (rotation rate in rad/s, gravity in g); the shot when a swing closed.
    @discardableResult
    public mutating func append(rotation: Vec3, gravity: Vec3) -> Shot? {
        let i = index
        index += 1
        // Keep the readings of the run that is open, to classify it at its peak; forget them once the wrist is still.
        let spin = rotation.length
        if spin >= 4 {
            gravityAtPeak[i] = gravity
            spinAtPeak[i] = rotation
        }
        let closed = finder.append(spin)
        defer {
            if spin < 2 {
                gravityAtPeak.removeAll(keepingCapacity: true)
                spinAtPeak.removeAll(keepingCapacity: true)
            }
        }
        guard let peak = closed, let g = gravityAtPeak[peak.index], let r = spinAtPeak[peak.index] else { return nil }
        let shot = Self.classify(rotation: r, gravity: g, mirrored: mirrored)
        let kmh = peak.value * lever * 3.6
        counts[shot, default: 0] += 1
        top = max(top, kmh)
        last = (shot, kmh)
        return shot
    }

    /// Hand above the wrist (the Watch's x axis points up, gravity along −x) is an overhead smash; otherwise the
    /// sign of the spin around the screen's axis tells forehand from backhand.
    static func classify(rotation: Vec3, gravity: Vec3, mirrored: Bool) -> Shot {
        if gravity.x < -0.5 { return .smash }
        let forehand = rotation.z >= 0
        return forehand != mirrored ? .forehand : .backhand
    }
}
