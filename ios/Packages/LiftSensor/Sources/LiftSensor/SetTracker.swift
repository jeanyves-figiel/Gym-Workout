import Foundation

/// Live tracking of one set from device motion (#383): feed samples, read reps, speed and velocity loss.
/// Not thread-safe: call from one queue.
public final class SetTracker {
    public struct Update: Equatable, Sendable {
        public var reps: [LiftRep]
        /// Fastest rep's mean speed so far, m/s.
        public var best: Double?
        /// 0…1 drop of the last rep against the fastest.
        public var velocityLoss: Double
        /// The velocity-loss limit was just reached (once per set).
        public var lossReached: Bool
        /// No new rep for `endSeconds` after at least one: the bar is racked (once until `resume`).
        public var ended: Bool
    }

    public let profile: LiftProfile
    public var config: SetAnalyzer.Config
    /// Velocity loss (0…1) that triggers the stop cue; nil = no cue.
    public var lossLimit: Double?
    /// Quiet time after the last rep that ends the set.
    public var endSeconds: Double = 4.5
    /// Longest set kept (s); older samples are not added.
    public var maxSeconds: Double = 150

    private var samples: [MotionSample] = []
    private var axis: Vec3?
    /// Machine mode: axis learned from a test rep, pointing in the push direction.
    private var fixedAxis: Vec3?
    public private(set) var reps: [LiftRep] = []
    private var lossSent = false
    private var endSent = false
    /// Sample index from which the end timer counts (last rep end, or an undo).
    private var quietFrom: Int?
    private var sinceAnalysis = 0

    public init(profile: LiftProfile, lossLimit: Double?, config: SetAnalyzer.Config = SetAnalyzer.Config()) {
        self.profile = profile
        self.lossLimit = lossLimit
        var c = config
        c.minRange = min(c.minRange, profile.minRange)
        self.config = c
    }

    public var sampleCount: Int { samples.count }

    /// Adds a sample; every `every` samples it re-analyses the set and returns an update when something changed.
    public func append(_ s: MotionSample, every: Int = 10) -> Update? {
        guard Double(samples.count) < maxSeconds * config.sampleRate else { return checkEnd() }
        samples.append(s)
        sinceAnalysis += 1
        guard sinceAnalysis >= every else { return nil }
        sinceAnalysis = 0
        return analyse()
    }

    /// Uses a known axis (machine mode test rep) whose positive direction is the lifting part.
    public func fixAxis(_ axis: Vec3) {
        fixedAxis = axis.unit
    }

    /// The member said the set isn't over (Undo): wait for more reps before ending again.
    public func resume() {
        endSent = false
        quietFrom = samples.count
    }

    /// Final reps, treating the set as over.
    public func finish() -> [LiftRep] {
        reps = compute(closed: true)
        return reps
    }

    /// Acceleration along the measured axis, g.
    public func axisSeries() -> [Double] {
        switch profile.direction {
        case .up: return samples.map(\.verticalUp)
        case .down: return samples.map { -$0.verticalUp }
        case .axis:
            let ua = samples.map(\.userAcceleration)
            if let fixedAxis { return ua.map { $0.dot(fixedAxis) } }
            if let a = SetAnalyzer.principalAxis(ua, previous: axis) { axis = a }
            guard let axis else { return [Double](repeating: 0, count: samples.count) }
            return ua.map { $0.dot(axis) }
        }
    }

    private func compute(closed: Bool) -> [LiftRep] {
        let phases = SetAnalyzer.phases(axisSeries(), rotation: samples.map(\.rotationRate), config: config, closed: closed)
        let sign = SetAnalyzer.concentricSign(phases, given: profile.direction == .axis && fixedAxis == nil ? nil : 1)
        return SetAnalyzer.reps(phases, concentricSign: sign, sampleRate: config.sampleRate)
    }

    private func analyse() -> Update? {
        let before = reps
        reps = compute(closed: false)
        if reps.count > before.count, let last = reps.last { quietFrom = max(quietFrom ?? 0, last.endIndex) }
        let changed = reps != before
        if let end = checkEnd() { return end }
        return changed ? update(lossReached: lossCheck(), ended: false) : nil
    }

    private func checkEnd() -> Update? {
        guard !endSent, !reps.isEmpty, let from = quietFrom,
              Double(samples.count - 1 - from) / config.sampleRate >= endSeconds else { return nil }
        endSent = true
        return update(lossReached: lossCheck(), ended: true)
    }

    private func lossCheck() -> Bool {
        guard let lossLimit, !lossSent, reps.count >= 2, LiftStats.velocityLoss(reps) >= lossLimit else { return false }
        lossSent = true
        return true
    }

    private func update(lossReached: Bool, ended: Bool) -> Update {
        Update(reps: reps, best: reps.map(\.meanVelocity).max(), velocityLoss: LiftStats.velocityLoss(reps),
               lossReached: lossReached, ended: ended)
    }
}

/// Numbers shown for a set (#383).
public enum LiftStats {
    /// Drop of the last rep's mean speed against the fastest rep (0…1).
    public static func velocityLoss(_ reps: [LiftRep]) -> Double {
        guard let best = reps.map(\.meanVelocity).max(), best > 0, let last = reps.last else { return 0 }
        return max(0, 1 - last.meanVelocity / best)
    }

    /// Mean power of the lifting parts, W (load × g × mean speed).
    public static func power(kg: Double, reps: [LiftRep]) -> Double? {
        guard kg > 0, !reps.isEmpty else { return nil }
        let v = reps.map(\.meanVelocity).reduce(0, +) / Double(reps.count)
        return kg * 9.80665 * v
    }
}
