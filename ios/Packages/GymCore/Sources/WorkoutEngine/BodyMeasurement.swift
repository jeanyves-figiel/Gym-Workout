import Foundation

/// Where a tape measure goes (#185). Arms and legs can be measured per side.
public enum GirthSite: String, Codable, CaseIterable, Sendable, Identifiable {
    case neck, shoulders, chest, waist, hips, upperArm, forearm, thigh, calf

    public var id: String { rawValue }

    public var bilateral: Bool { [.upperArm, .forearm, .thigh, .calf].contains(self) }

    public var label: String {
        switch self {
        case .neck: "Neck"
        case .shoulders: "Shoulders"
        case .chest: "Chest"
        case .waist: "Waist"
        case .hips: "Hips"
        case .upperArm: "Upper arm"
        case .forearm: "Forearm"
        case .thigh: "Thigh"
        case .calf: "Calf"
        }
    }

    /// Where to put the tape, shown in the log sheet.
    public var howTo: String {
        switch self {
        case .neck: "Just below the Adam's apple"
        case .shoulders: "Around both shoulders at the widest point"
        case .chest: "At nipple height, arms relaxed, after a normal breath out"
        case .waist: "At the navel, relaxed, after a normal breath out"
        case .hips: "Widest point of the glutes, feet together"
        case .upperArm: "Widest point of the biceps, arm flexed"
        case .forearm: "Widest point, fist clenched, arm straight"
        case .thigh: "Just below the glutes, standing"
        case .calf: "Widest point, standing"
        }
    }

    /// Muscles a bigger girth here mostly reflects (for linking to muscle pages).
    public var muscles: [Muscle] {
        switch self {
        case .neck: [.traps]
        case .shoulders: [.frontDelts, .sideDelts, .rearDelts]
        case .chest: [.chest]
        case .waist, .hips: []
        case .upperArm: [.biceps, .triceps]
        case .forearm: [.forearms]
        case .thigh: [.quads, .hamstrings]
        case .calf: [.calves]
        }
    }
}

public enum LimbSide: String, Codable, CaseIterable, Sendable {
    case left = "L", right = "R"
}

/// One dated measurement entry. Every value is optional: log only what you measured.
/// Girths are keyed by `GirthSite` raw value, plus "L"/"R" for a side ("upperArmL").
public struct BodyMeasurement: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var girthsCm: [String: Double]?
    public var weightKg: Double?
    public var bodyFatPct: Double?

    public init(id: UUID = UUID(), date: Date, girthsCm: [String: Double]? = nil, weightKg: Double? = nil, bodyFatPct: Double? = nil) {
        self.id = id
        self.date = date
        self.girthsCm = girthsCm
        self.weightKg = weightKg
        self.bodyFatPct = bodyFatPct
    }

    public static func key(_ part: GirthSite, _ side: LimbSide? = nil) -> String { part.rawValue + (side?.rawValue ?? "") }

    /// One side, or both sides when measured as one value.
    public func girth(_ part: GirthSite, side: LimbSide?) -> Double? { girthsCm?[Self.key(part, side)] }

    /// The part's value: the single value, else the mean of the sides measured.
    public func girth(_ part: GirthSite) -> Double? {
        if let v = girth(part, side: nil) { return v }
        let sides = LimbSide.allCases.compactMap { girth(part, side: $0) }
        return sides.isEmpty ? nil : sides.reduce(0, +) / Double(sides.count)
    }

    public mutating func setGirth(_ part: GirthSite, side: LimbSide? = nil, _ cm: Double?) {
        var g = girthsCm ?? [:]
        g[Self.key(part, side)] = cm
        girthsCm = g.isEmpty ? nil : g
    }

    /// Fat-free mass from weight and body fat.
    public var leanKg: Double? {
        guard let w = weightKg, let f = bodyFatPct else { return nil }
        return w * (1 - f / 100)
    }

    public var isEmpty: Bool { (girthsCm ?? [:]).isEmpty && weightKg == nil && bodyFatPct == nil }

    /// Number of values logged (a part measured per side counts once).
    public var count: Int {
        GirthSite.allCases.filter { girth($0) != nil }.count + (weightKg == nil ? 0 : 1) + (bodyFatPct == nil ? 0 : 1)
    }

    /// Plausible ranges; anything outside is dropped by the log sheet (and rejected by the server).
    public static let girthRange = 5.0...300.0
    public static let weightRange = 20.0...400.0
    public static let bodyFatRange = 2.0...75.0
}

/// What a progress chart can show.
public enum BodyMetric: Hashable, Sendable, Identifiable {
    case weight, bodyFat, leanMass, girth(GirthSite)

    public static var all: [BodyMetric] { [BodyMetric.weight, .bodyFat, .leanMass] + GirthSite.allCases.map { BodyMetric.girth($0) } }

    public var id: String {
        switch self {
        case .weight: "weight"
        case .bodyFat: "bodyFat"
        case .leanMass: "leanMass"
        case let .girth(p): p.rawValue
        }
    }

    public var label: String {
        switch self {
        case .weight: "Body weight"
        case .bodyFat: "Body fat"
        case .leanMass: "Lean mass"
        case let .girth(p): p.label
        }
    }

    public var unit: String {
        switch self {
        case .weight, .leanMass: "kg"
        case .bodyFat: "%"
        case .girth: "cm"
        }
    }

    public func value(_ m: BodyMeasurement) -> Double? {
        switch self {
        case .weight: m.weightKg
        case .bodyFat: m.bodyFatPct
        case .leanMass: m.leanKg
        case let .girth(p): m.girth(p)
        }
    }
}

public enum BodyMeasurements {
    public struct Point: Hashable, Sendable {
        public var date: Date
        public var value: Double
        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// Values of one metric, oldest first. `extra` (e.g. Apple Health samples) is merged in; an extra point on the
    /// same day as a logged value with the same value (to 0.1) is the copy written to Health, so it is dropped.
    public static func series(_ metric: BodyMetric, in list: [BodyMeasurement], extra: [Point] = [],
                              calendar cal: Calendar = .current) -> [Point] {
        let own = list.compactMap { m in metric.value(m).map { Point(date: m.date, value: $0) } }
        let others = extra.filter { e in
            !own.contains { cal.isDate($0.date, inSameDayAs: e.date) && abs($0.value - e.value) < 0.05 }
        }
        return (own + others).sorted { $0.date < $1.date }
    }

    /// Latest value of a metric, with its date.
    public static func latest(_ metric: BodyMetric, in list: [BodyMeasurement], extra: [Point] = []) -> Point? {
        series(metric, in: list, extra: extra).last
    }

    /// Change from the first to the latest point; nil with fewer than two points.
    public static func change(_ points: [Point]) -> Double? {
        guard points.count > 1, let first = points.first, let last = points.last else { return nil }
        return last.value - first.value
    }
}
