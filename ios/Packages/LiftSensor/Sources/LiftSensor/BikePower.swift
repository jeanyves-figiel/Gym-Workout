import Foundation

/// Cycling with sensors (#623): Bluetooth power, cadence and heart-rate packets, FTP-based power zones and the
/// 20′ FTP test. Pure Swift so it is tested on macOS; the Watch feeds it the sensors' notifications.
public enum BikePower {
    // MARK: Zones (Coggan, % of FTP)

    public struct Zone: Equatable, Sendable {
        /// 1…7.
        public let index: Int
        public let name: String
        /// Upper bound in % of FTP; the last zone has none.
        public let upTo: Double?
    }

    public static let zones: [Zone] = [
        Zone(index: 1, name: "Recovery", upTo: 0.55),
        Zone(index: 2, name: "Endurance", upTo: 0.75),
        Zone(index: 3, name: "Tempo", upTo: 0.90),
        Zone(index: 4, name: "Threshold", upTo: 1.05),
        Zone(index: 5, name: "VO2 max", upTo: 1.20),
        Zone(index: 6, name: "Anaerobic", upTo: 1.50),
        Zone(index: 7, name: "Sprint", upTo: nil),
    ]

    /// Zone of `watts` at `ftp`; nil without an FTP.
    public static func zone(watts: Double, ftp: Int?) -> Zone? {
        guard let ftp, ftp > 0 else { return nil }
        let pct = watts / Double(ftp)
        return zones.first { $0.upTo.map { pct <= $0 } ?? true }
    }

    /// Watt range of a zone at `ftp` ("166–205 W").
    public static func range(_ z: Zone, ftp: Int) -> ClosedRange<Int> {
        let lowPct = zones.first { $0.index == z.index - 1 }?.upTo ?? 0
        let low = z.index == 1 ? 0 : Int((Double(ftp) * lowPct).rounded()) + 1
        let high = z.upTo.map { Int((Double(ftp) * $0).rounded()) } ?? Int(Double(ftp) * 2.5)
        return low...max(low, high)
    }

    // MARK: FTP test

    /// The guided test: 15′ warm-up, 20′ all out, 10′ easy.
    public enum TestPhase: String, Sendable, CaseIterable {
        case warmUp, allOut, coolDown, done

        public var seconds: TimeInterval {
            switch self {
            case .warmUp: 15 * 60
            case .allOut: 20 * 60
            case .coolDown: 10 * 60
            case .done: 0
            }
        }

        public var label: String {
            switch self {
            case .warmUp: "Warm-up"
            case .allOut: "20′ all out"
            case .coolDown: "Cool-down"
            case .done: "Done"
            }
        }
    }

    /// Phase `elapsed` seconds into the test, and the seconds left in it.
    public static func testPhase(elapsed: TimeInterval) -> (phase: TestPhase, left: TimeInterval) {
        var t = elapsed
        for p in TestPhase.allCases where p != .done {
            if t < p.seconds { return (p, p.seconds - t) }
            t -= p.seconds
        }
        return (.done, 0)
    }

    /// FTP from the 20′ average: 95 %.
    public static func ftp(twentyMinuteAverage avg: Double) -> Int { Int((avg * 0.95).rounded()) }

    /// Retest every 6 weeks.
    public static func retestDue(lastTest: Date?, now: Date) -> Bool {
        guard let lastTest else { return true }
        return now.timeIntervalSince(lastTest) >= 42 * 86_400
    }

    // MARK: Rolling average

    /// Average of the samples in the last `window` seconds (3″ power).
    public struct Rolling: Sendable {
        public let window: TimeInterval
        private var samples: [(t: TimeInterval, v: Double)] = []

        public init(window: TimeInterval = 3) { self.window = window }

        public mutating func add(_ v: Double, at t: TimeInterval) {
            samples.append((t, v))
            samples.removeAll { $0.t < t - window }
        }

        public var average: Double? { samples.isEmpty ? nil : samples.map(\.v).reduce(0, +) / Double(samples.count) }
    }

    // MARK: Bluetooth packets (GATT, little endian)

    public struct CrankReading: Equatable, Sendable {
        /// Cumulative crank revolutions (wraps at 65 536).
        public var revs: UInt16
        /// Last crank event time in 1/1024 s (wraps at 64 s).
        public var time: UInt16

        public init(revs: UInt16, time: UInt16) {
            self.revs = revs
            self.time = time
        }
    }

    /// Cycling Power Measurement (0x2A63): instantaneous watts and crank data when present.
    public static func parsePower(_ d: [UInt8]) -> (watts: Int, crank: CrankReading?)? {
        guard d.count >= 4 else { return nil }
        let flags = UInt16(d[0]) | UInt16(d[1]) << 8
        let watts = Int(Int16(bitPattern: UInt16(d[2]) | UInt16(d[3]) << 8))
        var i = 4
        if flags & 0x01 != 0 { i += 1 } // pedal power balance
        if flags & 0x04 != 0 { i += 2 } // accumulated torque
        if flags & 0x10 != 0 { i += 6 } // wheel revolutions + time
        var crank: CrankReading?
        if flags & 0x20 != 0, d.count >= i + 4 {
            crank = CrankReading(revs: UInt16(d[i]) | UInt16(d[i + 1]) << 8, time: UInt16(d[i + 2]) | UInt16(d[i + 3]) << 8)
        }
        return (watts, crank)
    }

    /// CSC Measurement (0x2A5B): crank data when present.
    public static func parseCadence(_ d: [UInt8]) -> CrankReading? {
        guard let flags = d.first else { return nil }
        var i = 1
        if flags & 0x01 != 0 { i += 6 }
        guard flags & 0x02 != 0, d.count >= i + 4 else { return nil }
        return CrankReading(revs: UInt16(d[i]) | UInt16(d[i + 1]) << 8, time: UInt16(d[i + 2]) | UInt16(d[i + 3]) << 8)
    }

    /// Heart Rate Measurement (0x2A37).
    public static func parseHeartRate(_ d: [UInt8]) -> Int? {
        guard let flags = d.first, d.count >= 2 else { return nil }
        if flags & 0x01 != 0 {
            guard d.count >= 3 else { return nil }
            return Int(UInt16(d[1]) | UInt16(d[2]) << 8)
        }
        return Int(d[1])
    }

    /// Cadence in rpm between two crank readings; nil when the crank event did not move (no new revolution).
    public static func cadence(from a: CrankReading, to b: CrankReading) -> Double? {
        let revs = b.revs &- a.revs
        let ticks = b.time &- a.time
        guard revs > 0, ticks > 0 else { return nil }
        let rpm = Double(revs) / (Double(ticks) / 1024) * 60
        return rpm < 250 ? rpm : nil
    }
}
