import Foundation

/// Load–velocity maths (#383): estimated 1RM from sets at different loads, and speed zones.
public enum LoadVelocity {
    public struct Point: Equatable, Sendable {
        public var kg: Double
        /// Mean speed of the fastest rep at this load, m/s.
        public var velocity: Double

        public init(kg: Double, velocity: Double) {
            self.kg = kg
            self.velocity = velocity
        }
    }

    /// Load where the fitted line reaches the lift's minimum velocity. Needs two loads at least 5 % apart
    /// and a line where heavier is slower; never below the heaviest load lifted.
    public static func estimatedOneRepMax(_ points: [Point], minimumVelocity: Double) -> Double? {
        let p = points.filter { $0.kg > 0 && $0.velocity > 0 }
        guard p.count >= 2, let lo = p.map(\.kg).min(), let hi = p.map(\.kg).max(), hi >= lo * 1.05 else { return nil }
        let n = Double(p.count)
        let mx = p.map(\.kg).reduce(0, +) / n
        let my = p.map(\.velocity).reduce(0, +) / n
        var sxy = 0.0
        var sxx = 0.0
        for q in p {
            sxy += (q.kg - mx) * (q.velocity - my)
            sxx += (q.kg - mx) * (q.kg - mx)
        }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        guard slope < 0 else { return nil }
        let kg = mx + (minimumVelocity - my) / slope
        guard kg.isFinite else { return nil }
        // An extrapolation more than twice the heaviest load is noise.
        return min(max(kg, hi), hi * 2)
    }
}

/// What a rep's speed trains, from the usual velocity-based training bands.
public enum SpeedZone: Int, CaseIterable, Sendable {
    case maxStrength, strength, power, speed, explosive

    public static func of(_ v: Double) -> SpeedZone {
        switch v {
        case ..<0.5: .maxStrength
        case ..<0.75: .strength
        case ..<1.0: .power
        case ..<1.3: .speed
        default: .explosive
        }
    }

    public var title: String {
        switch self {
        case .maxStrength: "Max strength"
        case .strength: "Strength"
        case .power: "Power"
        case .speed: "Speed"
        case .explosive: "Explosive"
        }
    }

    /// 0…1 position of a speed on a 0.15–1.3 m/s bar.
    public static func position(_ v: Double) -> Double { min(1, max(0, (v - 0.15) / 1.15)) }
}
