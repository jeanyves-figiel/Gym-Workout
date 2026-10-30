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

    /// Where to put the tape, shown in the log sheet. Short enough for two lines on a card (#823); the ? sheet has
    /// the full steps.
    public var howTo: String {
        switch self {
        case .neck: "Just below the Adam's apple"
        case .shoulders: "Widest point of both shoulders"
        case .chest: "Nipple height, after breathing out"
        case .waist: "At the navel, after breathing out"
        case .hips: "Widest point of the glutes"
        case .upperArm: "Widest point of the flexed biceps"
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
    /// Server version this copy was pulled or saved as, sent back as `baseUpdatedAt` so an edit never overwrites a
    /// newer copy from another device. Nil until the server has it.
    public var updatedAt: String?

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

/// How to take one measurement (#220): steps and a tip for the log sheet's how-to page and guided mode.
public struct MeasureGuide: Sendable, Equatable {
    public let steps: [String]
    public let tip: String
}

public extension BodyMetric {
    /// Same advice for every tape measurement, appended to each girth's own tip.
    static let tapeTip = "Snug, not tight, on bare skin. Same time of day each time, ideally in the morning before training."

    var guide: MeasureGuide {
        switch self {
        case .weight:
            MeasureGuide(steps: ["Weigh in the morning, after the toilet, before eating or drinking.",
                                 "Same scale on a hard, flat floor, in light clothes or none.",
                                 "Stand still with your weight even on both feet, then read."],
                         tip: "Day-to-day swings of 1–2 kg are mostly water. Watch the weekly trend.")
        case .bodyFat:
            MeasureGuide(steps: ["Smart scale: barefoot, dry feet, in the morning before drinking.",
                                 "Calipers: same sites and same person each time; average 3 pinches per site.",
                                 "A DEXA or BodPod scan is the most accurate: log it on the day of the scan."],
                         tip: "Methods can disagree by several %. Stick to one and follow the trend.")
        case .leanMass:
            MeasureGuide(steps: ["Worked out from body weight and body fat logged on the same day."],
                         tip: "Log weight and body fat together to see it.")
        case let .girth(p):
            MeasureGuide(steps: p.steps, tip: p.tip.map { $0 + " " + Self.tapeTip } ?? Self.tapeTip)
        }
    }
}

extension GirthSite {
    var steps: [String] {
        switch self {
        case .neck:
            ["Stand tall, look straight ahead, shoulders relaxed.",
             "Tape just below the larynx (Adam's apple), sloping slightly down to the front.",
             "Read without pressing into the skin."]
        case .shoulders:
            ["Stand tall, arms relaxed at your sides.",
             "Tape round both shoulders at the widest point, level all the way round.",
             "Read after a normal breath out."]
        case .chest:
            ["Stand tall, arms relaxed at your sides.",
             "Tape round the chest at nipple height, under the armpits, level across the back.",
             "Read after a normal breath out."]
        case .waist:
            ["Stand tall, feet together, belly relaxed.",
             "Tape round the navel, level all the way round.",
             "Read after a normal breath out."]
        case .hips:
            ["Stand with feet together, glutes relaxed.",
             "Tape round the widest point of the glutes, level all the way round.",
             "Check it's level in a mirror from the side, then read."]
        case .upperArm:
            ["Raise the arm to the side, bend the elbow and flex the biceps.",
             "Tape round the peak of the biceps, at a right angle to the arm.",
             "Read, then do the other arm if you log both."]
        case .forearm:
            ["Hold the arm straight out in front, palm up, fist clenched.",
             "Tape round the widest point, a few cm below the elbow.",
             "Read without squeezing."]
        case .thigh:
            ["Stand with feet hip-width apart, weight on both legs.",
             "Tape round the thigh just below the glutes, level all the way round.",
             "Read without squeezing."]
        case .calf:
            ["Stand with feet hip-width apart, weight on both legs.",
             "Tape round the widest point of the calf.",
             "Read without squeezing."]
        }
    }

    var tip: String? {
        switch self {
        case .shoulders, .chest: "A mirror or a helper keeps the tape level across the back."
        case .upperArm: "Always the same arm position and the same flex."
        default: nil
        }
    }
}

public extension BodyMapLayout {
    /// Where the tape sits on the front figure (#220): a horizontal span in the 200 × 410 design space.
    struct TapeBand: Sendable, Equatable {
        public let y, minX, maxX: Double
        public var width: Double { maxX - minX }
    }

    /// Tape position for a girth site. Limbs default to the member's right (viewer's left on the front view).
    static func tapeBand(_ site: GirthSite, side: LimbSide? = nil, figure: Figure = .male) -> TapeBand? {
        func limb(_ muscle: Muscle, dy: Double, y fixedY: Double? = nil) -> (y: Double, x: Double)? {
            let twins = shapes(.front, figure: figure).filter { $0.muscle == muscle }
            guard let s = twins.first(where: { side == .left ? $0.midX > width / 2 : $0.midX < width / 2 }) else { return nil }
            return (y: fixedY ?? s.midY + dy, x: s.midX)
        }
        let anchor: (y: Double, x: Double)? = switch site {
        case .neck: (58, width / 2)
        case .shoulders: (84, width / 2)
        case .chest: (114, width / 2)
        case .waist: (170, width / 2)
        case .hips: (215, width / 2)
        case .upperArm: limb(.biceps, dy: 0)
        case .forearm: limb(.forearms, dy: -8)
        case .thigh: limb(.quads, dy: 0, y: 252)
        case .calf: limb(.calves, dy: -15)
        }
        guard let anchor else { return nil }
        // Even-odd scanline across the silhouette; keep the run that contains the anchor.
        for poly in outline(.front, figure: figure) {
            var xs: [Double] = []
            for i in poly.indices {
                let p = poly[i], q = poly[(i + 1) % poly.count]
                if (p.y > anchor.y) != (q.y > anchor.y) { xs.append(p.x + (anchor.y - p.y) * (q.x - p.x) / (q.y - p.y)) }
            }
            xs.sort()
            for i in stride(from: 0, to: xs.count - 1, by: 2) where xs[i] <= anchor.x && anchor.x <= xs[i + 1] {
                return TapeBand(y: anchor.y, minX: xs[i], maxX: xs[i + 1])
            }
        }
        return nil
    }
}
