import Foundation

// Hyrox auto-recording (#426): the race order is fixed, so the Watch only has to tell running from the next
// station's movement. Each second it gets the step cadence (pedometer) and features of the last seconds of wrist
// motion; runs end at the last running second, stations start at their first matching second, and the gaps are
// the Roxzone. Thresholds are first guesses: they need tuning on a real Watch.

/// One second of what the Watch feels.
public struct HyroxFeatures: Equatable, Sendable {
    /// Steps per second (running ≈ 2.6–3.2, walking ≈ 1.6–2.0).
    public var cadence: Double
    /// Spread of the wrist's acceleration, g.
    public var intensity: Double
    /// Main rhythm of the vertical wrist movement, seconds; nil when there is none.
    public var period: Double?
    /// Biggest upward push in the window, g.
    public var peak: Double
    /// Mean wrist rotation, rad/s.
    public var rotation: Double

    public init(cadence: Double, intensity: Double, period: Double?, peak: Double, rotation: Double) {
        self.cadence = cadence
        self.intensity = intensity
        self.period = period
        self.peak = peak
        self.rotation = rotation
    }

    public var running: Bool { cadence >= 2.3 && intensity >= 0.3 }

    private func period(_ lo: Double, _ hi: Double) -> Bool { period.map { $0 >= lo && $0 <= hi } ?? false }

    /// Looks like `station` (its own movement signature).
    public func matches(_ station: HyroxStation) -> Bool {
        switch station {
        case .skiErg: cadence < 0.8 && intensity >= 0.25 && peak >= 0.6 && period(0.9, 2.5)
        case .sledPush: cadence >= 0.5 && cadence < 2.1 && intensity < 0.4 && rotation < 1.0
        case .sledPull: cadence < 1.0 && intensity >= 0.25 && period(0.5, 1.6)
        case .burpeeBroadJumps: peak >= 1.5 && period(2.5, 7)
        case .rowing: cadence < 0.5 && intensity >= 0.2 && period(1.6, 3.2)
        case .farmersCarry: cadence >= 1.4 && cadence < 2.6 && rotation < 0.8 && intensity < 0.45
        case .sandbagLunges: cadence >= 0.3 && cadence < 1.3 && period(1.2, 3.2)
        case .wallBalls: cadence < 0.8 && peak >= 1.0 && period(1.8, 4.0)
        }
    }
}

/// Turns seconds of features into splits, step by step through the race order. Moving on by hand (double tap,
/// Action button, LAP) always works and wins over detection.
public final class HyroxDetector {
    public enum Event: Equatable, Sendable {
        /// A step began (`index` into `steps`), at the given time.
        case started(Int, Date)
        /// A step ended.
        case ended(Int, Date)
        /// Unsure for a while: ask the member to confirm the next step (buzz + prompt).
        case unsure(Int)
        case finished(Date)
    }

    public enum Phase: Equatable, Sendable {
        /// Doing `steps[index]`.
        case active
        /// Between `steps[index - 1]` and `steps[index]` (Roxzone).
        case between
        case done
    }

    public let steps: [HyroxStep]
    public private(set) var index = 0
    public private(set) var phase: Phase = .active
    public private(set) var splits: [HyroxSplit] = []
    public private(set) var stepStart: Date
    /// Reps counted in the current step.
    public private(set) var reps = 0

    /// A run must last this long before a stop can end it (sims and Roxzone jogs are shorter).
    public var minRunSeconds: Double = 90
    /// Seconds without running that end a run.
    public var runStopSeconds: Double = 8
    /// Seconds a station's signature must hold to start it.
    public var matchSeconds: Double = 3
    /// Seconds of running that end a station.
    public var runStartSeconds: Double = 4
    /// Seconds without any match that end the last station.
    public var finishSeconds: Double = 12
    /// Seconds in the Roxzone before asking.
    public var askAfter: Double = 75

    private var lastRun: Date?
    private var runSince: Date?
    private var matchSince: Date?
    private var lastMatch: Date?
    private var betweenSince: Date?
    private var asked = false
    private var auto = true

    /// Starts on the first step (a run) at `start`.
    public init(steps: [HyroxStep], start: Date) {
        self.steps = steps
        stepStart = start
        lastRun = start
    }

    public var current: HyroxStep? { index < steps.count ? steps[index] : nil }

    /// Feeds one second of features; returns what changed.
    public func feed(_ f: HyroxFeatures, at t: Date) -> [Event] {
        guard phase != .done, let step = current else { return [] }
        var out: [Event] = []
        // A fast farmers carry is not a run: the station's own signature wins.
        let matching = step.station.map(f.matches) ?? false
        if f.running, !(phase == .active && matching) {
            runSince = runSince ?? t
            lastRun = t
        } else {
            runSince = nil
        }
        switch (phase, step) {
        case (.active, .run):
            if let last = lastRun, t.timeIntervalSince(last) >= runStopSeconds, last.timeIntervalSince(stepStart) >= minRunSeconds {
                out += close(at: last)
            }
        case (.between, .station):
            if matching {
                matchSince = matchSince ?? t
                if let since = matchSince, t.timeIntervalSince(since) >= matchSeconds - 1 {
                    out += open(at: since)
                    lastMatch = t
                }
            } else {
                matchSince = nil
                out += ask(t)
            }
        case (.active, .station):
            if matching { lastMatch = t }
            let end = lastMatch ?? stepStart
            if index == steps.count - 1 {
                if t.timeIntervalSince(end) >= finishSeconds { out += close(at: end) }
            } else if let since = runSince, t.timeIntervalSince(since) >= runStartSeconds - 1 {
                // Running again: the station ended at its last matching second, the next run began with the running.
                out += close(at: end)
                out += open(at: since)
            }
        case (.between, .run):
            if let since = runSince, t.timeIntervalSince(since) >= runStartSeconds - 1 {
                out += open(at: since)
            } else {
                out += ask(t)
            }
        default:
            break
        }
        return out
    }

    /// A counted rep (stroke, jump, throw) in the current station.
    public func rep() {
        if phase == .active, current?.station?.counts == true { reps += 1 }
    }

    /// Moving on by hand: ends the current step (or starts the next one from the Roxzone).
    public func advance(at t: Date) -> [Event] {
        guard phase != .done else { return [] }
        auto = false
        let out = phase == .active ? close(at: t) : open(at: t)
        auto = true
        return out
    }

    /// Ends the race now (the last step closes at `t`).
    public func finish(at t: Date) -> [Event] {
        guard phase != .done else { return [] }
        if phase == .active {
            auto = false
            defer { auto = true }
            return close(at: t, last: true)
        }
        phase = .done
        return [.finished(t)]
    }

    private func open(at t: Date) -> [Event] {
        phase = .active
        stepStart = t
        reps = 0
        matchSince = nil
        lastMatch = nil
        betweenSince = nil
        asked = false
        return [.started(index, t)]
    }

    private func close(at t: Date, last: Bool = false) -> [Event] {
        guard let step = current else { return [] }
        let end = max(t, stepStart)
        splits.append(HyroxSplit(step: step, start: stepStart, end: end, reps: step.station?.counts == true ? reps : nil, auto: auto))
        index += 1
        if last || index >= steps.count {
            phase = .done
            return [.ended(index - 1, end), .finished(end)]
        }
        phase = .between
        betweenSince = end
        lastRun = nil
        return [.ended(index - 1, end)]
    }

    private func ask(_ t: Date) -> [Event] {
        guard !asked, let since = betweenSince, t.timeIntervalSince(since) >= askAfter else { return [] }
        asked = true
        return [.unsure(index)]
    }
}

/// Features from a few seconds of wrist motion (≈ 25 Hz), plus the pedometer cadence.
public enum HyroxMotion {
    public static func features(_ samples: [MotionSample], hz: Double, cadence: Double) -> HyroxFeatures {
        guard samples.count > 4 else { return HyroxFeatures(cadence: cadence, intensity: 0, period: nil, peak: 0, rotation: 0) }
        let mags = samples.map(\.userAcceleration.length)
        let mean = mags.reduce(0, +) / Double(mags.count)
        let sd = (mags.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(mags.count)).squareRoot()
        let v = samples.map(\.verticalUp)
        let rot = samples.reduce(0) { $0 + $1.rotationRate } / Double(samples.count)
        return HyroxFeatures(cadence: cadence, intensity: sd, period: period(v, hz: hz), peak: v.max() ?? 0, rotation: rot)
    }

    /// Main rhythm of `x` in seconds (autocorrelation peak between 0.4 s and half the window), nil when weak.
    public static func period(_ x: [Double], hz: Double, minCorrelation: Double = 0.3) -> Double? {
        let n = x.count
        let mean = x.reduce(0, +) / Double(max(n, 1))
        let c = x.map { $0 - mean }
        let energy = c.reduce(0) { $0 + $1 * $1 }
        guard energy > 1e-6 else { return nil }
        let lo = max(1, Int(0.4 * hz)), hi = n / 2
        guard hi > lo else { return nil }
        var best = (lag: 0, r: minCorrelation)
        var prev = 1.0
        var falling = true
        for lag in lo...hi {
            var s = 0.0
            for i in 0..<(n - lag) { s += c[i] * c[i + lag] }
            let r = s / energy * Double(n) / Double(n - lag)
            // First local maximum above the bar after the correlation has dipped.
            if falling, r > prev { falling = false }
            if !falling, r > best.r { best = (lag, r) }
            if !falling, best.lag > 0, r < best.r * 0.8 { break }
            prev = r
        }
        return best.lag > 0 ? Double(best.lag) / hz : nil
    }
}

/// Counts strokes, jumps and throws: an upward push over `threshold` g, at least `gap` seconds after the last.
public struct HyroxRepCounter: Sendable {
    public var threshold: Double
    public var gap: Double
    private var lastPeak: Double = -.infinity
    private var above = false

    public init(for station: HyroxStation) {
        switch station {
        case .burpeeBroadJumps: (threshold, gap) = (1.4, 2.0)
        case .wallBalls: (threshold, gap) = (0.9, 1.5)
        case .skiErg: (threshold, gap) = (0.6, 0.8)
        default: (threshold, gap) = (0.5, 1.4)
        }
    }

    /// Feeds one vertical value at `t` seconds; true when a rep is counted.
    public mutating func add(_ v: Double, at t: Double) -> Bool {
        if v >= threshold, !above {
            above = true
            if t - lastPeak >= gap {
                lastPeak = t
                return true
            }
        } else if v < threshold * 0.5 {
            above = false
        }
        return false
    }
}
