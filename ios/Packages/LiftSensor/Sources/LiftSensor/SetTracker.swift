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
    /// Config at the normal counting level; `config` is this at the current strictness (#410).
    private var baseConfig: SetAnalyzer.Config
    public private(set) var strictness: Double
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

    /// `strictness`: counting level (#410), -2 relaxed … 0 normal … +2 strict; see `Strictness`.
    public init(profile: LiftProfile, lossLimit: Double?, config: SetAnalyzer.Config = SetAnalyzer.Config(), strictness: Double = 0) {
        self.profile = profile
        self.lossLimit = lossLimit
        var c = config
        c.minRange = min(c.minRange, profile.minRange)
        baseConfig = c
        self.strictness = strictness
        self.config = Strictness.apply(strictness, to: c)
    }

    /// Recounts the set at another counting level (practice mode, #410).
    public func setStrictness(_ level: Double) -> Update {
        strictness = level
        config = Strictness.apply(level, to: baseConfig)
        reps = compute(closed: false)
        return update(lossReached: false, ended: false)
    }

    /// Smoothed acceleration along the measured axis (g) for the last `seconds`, one value every `step` samples,
    /// and the sample index of the first value (to place reps on it).
    public func trace(seconds: Double = 6, every step: Int = 5) -> (values: [Double], start: Int) {
        let n = Int(seconds * config.sampleRate)
        let series = axisSeries()
        let start = max(0, series.count - n)
        let smooth = SetAnalyzer.smooth(Array(series[start...]), half: 4)
        return (stride(from: 0, to: smooth.count, by: max(1, step)).map { smooth[$0] }, start)
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
        let all = SetAnalyzer.reps(phases, concentricSign: sign, sampleRate: config.sampleRate)
        return SetAnalyzer.consistent(all, share: config.minRangeShare)
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
