import Foundation

// Ski / snowboard lift vs run (#1129). Raw GPS altitude wobbles 10–20 m, so the old "climbed 25 m → lift" rule flipped
// on bumps and missed slow lifts. This reads altitude (the barometer when the Watch has one, else GPS) as a trend:
// the vertical speed fitted over the last 30 s. A lift is a steady climb held 25 s; riding is a descent held 8 s that
// left the lift top; standing still (queue, strap-in, break) is a pause that counts for neither. Switches are dated
// back to when the new trend began, so ride and lift times stay right. Pure maths: tested with `swift test`.

public final class SlopeDetector {
    public enum Phase: String, Sendable { case ride, lift, still }

    public enum Event: Equatable, Sendable {
        /// A run ended (its lift began): metres dropped from its top to its low point.
        case run(drop: Double, start: Date, end: Date)
        /// Phase changed, effective at `at` (dated back to when the new trend began).
        case phase(Phase, at: Date)
    }

    public private(set) var phase: Phase = .ride
    /// Seconds riding and on lifts (still counts for neither).
    public private(set) var rideSeconds: TimeInterval = 0
    public private(set) var liftSeconds: TimeInterval = 0
    public private(set) var runs = 0
    /// Lift rides so far, start and end (end nil while on one), for Health segments and the iPhone's day bar.
    public private(set) var lifts: [(start: Date, end: Date?)] = []
    /// Fitted vertical speed, m/s (+ up); nil until 18 s of samples.
    public private(set) var verticalSpeed: Double?

    /// Tuning: climb rate and gain for a lift, descent rate for riding, flat for still.
    public var liftRate = 0.35
    public var liftGain = 8.0
    public var rideRate = -0.4
    public var stillRate = 0.12
    public var stillKmh = 4.0
    /// A run needs this drop to count.
    public var minDrop = 30.0

    private var samples: [(t: Date, alt: Double)] = []
    private var last: Date?
    private var kmh: Double?
    private var candidate: Phase?
    private var candidateSince: Date?
    private var runTop: Double?
    private var runLow: Double?
    private var runStart: Date?
    private var liftTop: Double = 0

    public init() {}

    /// Latest horizontal speed (GPS), km/h. Optional: Saver mode has one fix a minute.
    public func speed(_ kmh: Double) { self.kmh = kmh }

    /// A time gap (pause, GPS lost) longer than this counts for neither phase.
    public static let maxGap: TimeInterval = 120

    /// One altitude sample, metres (any zero: the barometer gives relative altitude). Returns what changed.
    @discardableResult
    public func add(_ alt: Double, at t: Date) -> [Event] {
        if let last {
            let dt = t.timeIntervalSince(last)
            guard dt >= 0 else { return [] }
            if dt < Self.maxGap { count(dt, phase) }
        }
        last = t
        samples.append((t, alt))
        samples.removeAll { t.timeIntervalSince($0.t) > 60 }
        if runTop == nil { runTop = alt; runLow = alt; runStart = t }
        if phase == .lift {
            liftTop = max(liftTop, alt)
        } else if let top = runTop, let low = runLow {
            if alt < low { runLow = alt }
            // Still at the top (or walking up to it): the run starts higher.
            if alt > top && low == top { runTop = alt; runLow = alt; runStart = t }
        }
        verticalSpeed = Self.slope(samples.filter { t.timeIntervalSince($0.t) <= 30 })
        guard let v = verticalSpeed else { return [] }
        let want = wanted(v, alt: alt, at: t)
        guard want != phase else { candidate = nil; return [] }
        if candidate != want { candidate = want; candidateSince = t; return [] }
        guard let since = candidateSince, t.timeIntervalSince(since) >= hold(want) else { return [] }
        return switchTo(want, at: since, now: t, alt: alt)
    }

    /// Closes the session: an unfinished run counts if it dropped enough.
    @discardableResult
    public func finish(at t: Date) -> [Event] {
        if !lifts.isEmpty, lifts[lifts.count - 1].end == nil { lifts[lifts.count - 1].end = t }
        guard phase != .lift, let top = runTop, let low = runLow, top - low >= minDrop, let start = runStart else { return [] }
        runs += 1
        runTop = nil
        return [.run(drop: top - low, start: start, end: t)]
    }

    private func wanted(_ v: Double, alt: Double, at t: Date) -> Phase {
        if phase == .lift {
            if v <= rideRate && alt <= liftTop - 12 { return .ride }
            if abs(v) < stillRate && alt >= liftTop - 3 { return .still }
            return .lift
        }
        let low30 = samples.filter { t.timeIntervalSince($0.t) <= 30 }.map(\.alt).min() ?? alt
        if v >= liftRate && alt - low30 >= liftGain { return .lift }
        if phase == .ride && abs(v) < stillRate && (kmh ?? 0) < stillKmh { return .still }
        if phase == .still && v <= rideRate { return .ride }
        return phase
    }

    /// Seconds a new trend must hold: lifts are long and steady, a ride shows fast.
    private func hold(_ p: Phase) -> TimeInterval {
        switch p {
        case .lift: 25
        case .ride: 8
        case .still: 25
        }
    }

    private func switchTo(_ new: Phase, at since: Date, now: Date, alt: Double) -> [Event] {
        let back = now.timeIntervalSince(since)
        count(-back, phase)
        count(back, new)
        var events: [Event] = []
        if new == .lift {
            if let top = runTop, let low = runLow, top - low >= minDrop, let start = runStart {
                runs += 1
                events.append(.run(drop: top - low, start: start, end: since))
            }
            liftTop = alt
            lifts.append((since, nil))
        }
        if phase == .lift {
            if !lifts.isEmpty { lifts[lifts.count - 1].end = since }
            runTop = alt
            runLow = alt
            runStart = since
        }
        phase = new
        candidate = nil
        events.append(.phase(new, at: since))
        return events
    }

    private func count(_ dt: TimeInterval, _ p: Phase) {
        switch p {
        case .ride: rideSeconds = max(0, rideSeconds + dt)
        case .lift: liftSeconds = max(0, liftSeconds + dt)
        case .still: break
        }
    }

    /// Least-squares slope, metres per second; nil with fewer than 4 samples or under 18 s.
    static func slope(_ pts: [(t: Date, alt: Double)]) -> Double? {
        guard pts.count >= 4, let first = pts.first, let lastP = pts.last, lastP.t.timeIntervalSince(first.t) >= 18 else { return nil }
        let xs = pts.map { $0.t.timeIntervalSince(first.t) }
        let n = Double(pts.count)
        let mx = xs.reduce(0, +) / n
        let my = pts.map(\.alt).reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (x, p) in zip(xs, pts) {
            num += (x - mx) * (p.alt - my)
            den += (x - mx) * (x - mx)
        }
        return den > 0 ? num / den : nil
    }
}
