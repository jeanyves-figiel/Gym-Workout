import Foundation

// MARK: - Heart-rate zones (#609, designs A + B + C from `apple-tech-radar/t7.png`)

/// Five heart-rate zones, given by the four bpm where zones 2…5 start. Apple's own zones (Health settings, watchOS 27 /
/// iOS 27) replace the standard ones when the member has five; otherwise they come from age and resting heart rate
/// (heart-rate reserve, Karvonen).
public struct HeartZones: Codable, Hashable, Sendable {
    /// bpm where zone 2, 3, 4 and 5 start, rising.
    public var starts: [Int]

    public static let count = 5
    /// Zone 2 minutes a week worth aiming for (aerobic base, WHO 150 min of moderate activity).
    public static let zone2Goal = 150

    public init(starts: [Int]) {
        self.starts = starts
    }

    /// Standard zones: 60 / 70 / 80 / 90 % of heart-rate reserve above resting. Max from age (Tanaka, 208 − 0.7 × age).
    /// Unknown age reads as 35, unknown resting heart rate as 60 bpm.
    public static func standard(age: Int?, restingHR: Double?) -> HeartZones {
        let a = Double(min(max(age ?? 35, 14), 90))
        let rest = min(max(restingHR ?? 60, 35), 100)
        let hrMax = 208 - 0.7 * a
        let reserve = max(hrMax - rest, 40)
        return HeartZones(starts: [0.6, 0.7, 0.8, 0.9].map { Int((rest + reserve * $0).rounded()) })
    }

    /// Apple's zones as lower bounds of zones 2…5 (first zone has none); nil unless there are exactly five, rising.
    public static func apple(lowerBounds: [Double?]) -> HeartZones? {
        guard lowerBounds.count == count else { return nil }
        let starts = lowerBounds.dropFirst().compactMap { $0.map { Int($0.rounded()) } }
        guard starts.count == count - 1, zip(starts, starts.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        return HeartZones(starts: starts)
    }

    public var isValid: Bool { starts.count == Self.count - 1 && zip(starts, starts.dropFirst()).allSatisfy { $0 < $1 } }

    /// Zone 1…5 for a heart rate.
    public func zone(_ bpm: Double) -> Int {
        1 + starts.filter { bpm >= Double($0) }.count
    }

    /// bpm range of a zone; zone 1 has no floor, zone 5 no ceiling.
    public func range(_ zone: Int) -> (low: Int?, high: Int?) {
        let z = min(max(zone, 1), Self.count)
        return (z > 1 ? starts[z - 2] : nil, z < Self.count ? starts[z - 1] - 1 : nil)
    }

    /// "142–155", "< 130", "≥ 170".
    public func label(_ zone: Int) -> String {
        switch range(zone) {
        case let (l?, h?): "\(l)–\(h)"
        case let (nil, h?): "< \(h + 1)"
        case let (l?, nil): "≥ \(l)"
        default: ""
        }
    }

    /// Target lock (design B): in the zone, or how many bpm under or over it.
    public func status(_ bpm: Double, target: Int) -> ZoneStatus {
        let (low, high) = range(target)
        if let low, bpm < Double(low) { return .low(Int((Double(low) - bpm).rounded(.up))) }
        if let high, bpm > Double(high) { return .high(Int((bpm - Double(high)).rounded(.up))) }
        return .inZone
    }

    public static let names = ["Easy", "Zone 2 · base", "Tempo", "Threshold", "Max"]
    /// Tile colours, zone 1…5: blue, teal, lime, orange, pink.
    public static let tints: [(UInt32, UInt32)] = [
        (0x3D59FF, 0x00C7FF), (0x00B86B, 0x3DFFB0), (0x9BD300, 0xCCFF3D), (0xFF7A3D, 0xFFC23D), (0xFF3D8B, 0xFF6B6B),
    ]
}

public enum ZoneStatus: Equatable, Sendable {
    case inZone
    /// bpm under the zone.
    case low(Int)
    /// bpm over the zone.
    case high(Int)
}

/// Time in each zone, filled from heart-rate samples (a workout's, or the week's).
public struct ZoneTime: Codable, Hashable, Sendable {
    /// Seconds in zone 1…5.
    public var seconds: [Double]

    public init(seconds: [Double] = Array(repeating: 0, count: HeartZones.count)) {
        self.seconds = seconds.count == HeartZones.count ? seconds : Array(repeating: 0, count: HeartZones.count)
    }

    /// Each sample counts until the next one, at most `gap` seconds (a gap in the readings counts for nothing more).
    public static func from(samples: [(date: Date, bpm: Double)], zones: HeartZones, gap: TimeInterval = 30) -> ZoneTime {
        var t = ZoneTime()
        let sorted = samples.sorted { $0.date < $1.date }
        for (i, s) in sorted.enumerated() {
            let next = i + 1 < sorted.count ? sorted[i + 1].date.timeIntervalSince(s.date) : 5
            t.seconds[zones.zone(s.bpm) - 1] += min(max(next, 0), gap)
        }
        return t
    }

    public static func + (a: ZoneTime, b: ZoneTime) -> ZoneTime {
        ZoneTime(seconds: zip(a.seconds, b.seconds).map(+))
    }

    public var minutes: [Int] { seconds.map { Int(($0 / 60).rounded()) } }
    public var zone2Minutes: Int { minutes[1] }
    /// Share of the Zone 2 goal, 0…1.
    public var zone2Progress: Double { min(1, Double(zone2Minutes) / Double(HeartZones.zone2Goal)) }
    public var isEmpty: Bool { seconds.allSatisfy { $0 < 30 } }
}
