import Foundation

/// 3D key positions of a catalog exercise for the position guide (#402): start, middle and end, lifted from the
/// same key poses the animation is drawn from (ios/Tools/illustrations/positions.py → ExercisePositions.json.z).
/// The figure faces +x, y is up, the floor is y = 0; units are px of the 400×300 drawing (~190 tall standing).
public struct ExercisePosition: Sendable, Hashable {
    public enum View: String, Sendable { case side = "s", front = "f", back = "b" }

    /// One of the three key positions: joints and the equipment around the figure.
    public struct Key: Sendable, Hashable {
        public let joints: [String: SIMD3<Double>]
        public let props: [Prop]

        public init(joints: [String: SIMD3<Double>], props: [Prop]) {
            self.joints = joints
            self.props = props
        }

        public subscript(_ name: String) -> SIMD3<Double>? { joints[name] }
    }

    public enum Prop: Sendable, Hashable {
        /// Upholstered pad along a→b, `normal` = thickness direction (x, y), `halfWidth` across (0 = front view).
        case pad(a: SIMD3<Double>, b: SIMD3<Double>, normal: SIMD2<Double>, halfWidth: Double)
        /// Box between two corners (stack, plyo box, mat).
        case box(lo: SIMD3<Double>, hi: SIMD3<Double>, mat: Bool)
        /// Bar, tube or frame between a and b.
        case rod(a: SIMD3<Double>, b: SIMD3<Double>, radius: Double)
        /// Weight plate; axis across the body (z) unless `alongX`.
        case disc(center: SIMD3<Double>, radius: Double, alongX: Bool)
        /// Dumbbell, kettlebell or ball held or resting at `center`.
        case weight(kind: String, center: SIMD3<Double>, radius: Double)
    }

    /// The view the animation is drawn in (the guide opens on it).
    public let view: View
    /// Start, middle and end.
    public let keys: [Key]

    /// The key position furthest from the start (the bottom of a squat, the top of a pull-up): the guide
    /// opens on it.
    public var mainKey: Int {
        guard let start = keys.first else { return 0 }
        func dist(_ k: Key) -> Double {
            k.joints.reduce(0) { sum, j in
                guard let s = start.joints[j.key] else { return sum }
                let d = j.value - s
                return sum + (d * d).sum().squareRoot()
            }
        }
        return keys.indices.dropFirst().max { dist(keys[$0]) < dist(keys[$1]) } ?? 0
    }
}

/// Joint geometry of a key position: angles and what the guide measures.
public enum PositionJoint: String, CaseIterable, Sendable {
    case knee, hip, elbow, shoulder, ankle

    public var label: String { rawValue.capitalized }

    /// Bone ends and the joint for one side ("N" near, "F" far): (a, joint, b).
    public func points(_ side: String) -> (String, String, String) {
        switch self {
        case .knee: ("hip" + side, "knee" + side, "ankle" + side)
        case .hip: ("shoulder" + side, "hip" + side, "knee" + side)
        case .elbow: ("shoulder" + side, "elbow" + side, "wrist" + side)
        case .shoulder: ("hip" + side, "shoulder" + side, "elbow" + side)
        case .ankle: ("knee" + side, "ankle" + side, "toe" + side)
        }
    }
}

extension ExercisePosition.Key {
    /// Angle at `joint` on `side` in degrees (180 = straight).
    public func angle(_ joint: PositionJoint, side: String = "N") -> Double? {
        let (a, j, b) = joint.points(side)
        guard let pa = joints[a], let pj = joints[j], let pb = joints[b] else { return nil }
        let u = pa - pj, v = pb - pj
        let nu = (u * u).sum().squareRoot(), nv = (v * v).sum().squareRoot()
        guard nu > 0, nv > 0 else { return nil }
        return acos(max(-1, min(1, (u * v).sum() / nu / nv))) * 180 / .pi
    }
}

/// One angle the guide shows on a key position: the arc, its value and the range that counts as right.
public struct PositionCheck: Sendable, Hashable {
    public let joint: PositionJoint
    public let side: String
    public let degrees: Int
    public let range: ClosedRange<Int>

    /// "Knee 85°"
    public var label: String { "\(joint.label) \(degrees)°" }
    /// "80–100°"
    public var rangeText: String { "\(range.lowerBound)–\(range.upperBound)°" }
}

extension ExercisePosition {
    /// Range around the drawn angle that still counts as the right position.
    public static let tolerance = 10

    /// The (up to) two joints that move the most over the exercise, measured on key `index`: what to check
    /// in that position. Ranges are the drawn angle ± `tolerance`.
    public func checks(at index: Int) -> [PositionCheck] {
        guard keys.indices.contains(index) else { return [] }
        let key = keys[index]
        let moved: [(PositionJoint, String, Double)] = PositionJoint.allCases.flatMap { j in
            ["N", "F"].compactMap { side -> (PositionJoint, String, Double)? in
                let values = keys.compactMap { $0.angle(j, side: side) }
                guard let lo = values.min(), let hi = values.max() else { return nil }
                return (j, side, hi - lo)
            }
        }
        var picked: [PositionCheck] = []
        for (j, side, range) in moved.sorted(by: { $0.2 > $1.2 }) where range >= 15 {
            guard !picked.contains(where: { $0.joint == j }), let a = key.angle(j, side: side) else { continue }
            let d = Int(a.rounded())
            picked.append(PositionCheck(joint: j, side: side, degrees: d,
                                        range: max(0, d - Self.tolerance)...min(180, d + Self.tolerance)))
            if picked.count == 2 { break }
        }
        return picked
    }

    /// Joint a body part's checkpoint pin sits on.
    public static func joint(for part: BodyPart) -> String {
        switch part {
        case .head: "head"
        case .shoulders: "shoulderN"
        case .elbows: "elbowN"
        case .hands: "handN"
        case .back: "spine"
        case .core: "core"
        case .hips: "hipN"
        case .knees: "kneeN"
        case .feet: "toeN"
        }
    }
}

extension ExercisePosition.Key {
    /// Joint position, including the derived points "spine" (upper back) and "core" (belly).
    public func point(_ name: String) -> SIMD3<Double>? {
        if let p = joints[name] { return p }
        guard let hip = joints["hip"], let sh = joints["shoulder"] else { return nil }
        switch name {
        case "spine": return hip + (sh - hip) * 0.65
        case "core": return hip + (sh - hip) * 0.3
        default: return nil
        }
    }
}

// MARK: - Common mistake ghost

/// A typical error drawn as a red ghost over the right position: picked from the exercise's own "Avoid" list
/// (Technique.mistakes) by what the text describes, and applied to the joints.
public struct PositionMistake: Sendable, Hashable {
    public enum Kind: String, Sendable, CaseIterable {
        case kneesIn, roundedBack, archedBack, hipsSag, hipsHigh, elbowsFlared, shrug, headForward, halfRange
    }

    public let kind: Kind
    /// The exercise's own wording of the mistake.
    public let text: String

    /// First mistake of the list the guide can draw. Keywords per kind, checked in order.
    public static func pick(_ mistakes: [String]) -> PositionMistake? {
        let rules: [(Kind, [String])] = [
            (.kneesIn, ["knees cav", "knee cav", "knees in", "knees collaps", "knee collaps", "knees fall in",
                        "knee falls in", "knee drifting in", "knees drifting in", "valgus"]),
            (.roundedBack, ["round", "hunch", "flexing the spine", "slump"]),
            (.hipsSag, ["sag", "hips drop", "hip drop", "dropping the hips", "banana"]),
            (.archedBack, ["arch", "overarch", "hyperext", "leaning back", "lean back", "rib cage flar", "ribs flar"]),
            (.hipsHigh, ["hips too high", "hips high", "piking", "pike"]),
            (.elbowsFlared, ["flare", "elbows out", "elbows wide"]),
            (.shrug, ["shrug", "shoulders up", "shoulders to ears", "shoulders to the ears"]),
            (.headForward, ["neck", "chin jut", "head forward", "craning", "looking up"]),
            (.halfRange, ["half rep", "partial", "short range", "not deep", "too shallow", "cutting the range",
                          "half range"]),
        ]
        for m in mistakes {
            let l = m.lowercased()
            for (kind, words) in rules where words.contains(where: l.contains) {
                return PositionMistake(kind: kind, text: m)
            }
        }
        return nil
    }

    /// The key position with this mistake applied (for the red ghost). Nil when it would not show on the figure.
    public func apply(to key: ExercisePosition.Key, view: ExercisePosition.View, start: ExercisePosition.Key)
        -> ExercisePosition.Key? {
        var j = key.joints
        func move(_ names: [String], by d: SIMD3<Double>) {
            for n in names { j[n] = j[n].map { $0 + d } }
        }
        let upper = ["shoulder", "shoulderN", "shoulderF", "neck", "head", "elbowN", "elbowF", "wristN", "wristF",
                     "handN", "handF"]
        guard let hip = j["hip"], let sh = j["shoulder"] else { return nil }
        let torso = sh - hip
        let len = (torso * torso).sum().squareRoot()
        guard len > 0 else { return nil }
        let up = torso / len
        // the figure's front: +x turned into the torso's plane
        var front = SIMD3<Double>(up.y, -up.x, 0)
        if (front * SIMD3(1, 0, 0)).sum() < 0 && abs(up.y) > 0.5 { front = -front }
        switch kind {
        case .kneesIn:
            for s in ["N", "F"] {
                guard let k = j["knee" + s] else { continue }
                j["knee" + s] = SIMD3(k.x, k.y, k.z * 0.15)
            }
        case .roundedBack:
            // shoulders and head roll forward and down around the hip
            let shift = front * len * 0.22 - up * len * 0.1
            move(upper, by: shift)
            move(["neck", "head"], by: front * len * 0.08)
        case .archedBack:
            move(upper, by: -front * len * 0.18)
        case .hipsSag:
            let down = SIMD3<Double>(0, -len * 0.22, 0)
            move(["hip", "hipN", "hipF"], by: down)
            move(["shoulder", "shoulderN", "shoulderF", "neck", "head"], by: down * 0.35)
            move(["kneeN", "kneeF"], by: down * 0.5)
        case .hipsHigh:
            let lift = SIMD3<Double>(0, len * 0.25, 0)
            move(["hip", "hipN", "hipF"], by: lift)
            move(["kneeN", "kneeF"], by: lift * 0.5)
        case .elbowsFlared:
            for s in ["N", "F"] {
                guard let e = j["elbow" + s], let shp = j["shoulder" + s] else { continue }
                let out: Double = shp.z >= 0 ? 1 : -1
                j["elbow" + s] = SIMD3(e.x - (e.x - shp.x) * 0.5, e.y, e.z + out * 26)
            }
            guard view == .side || view == .front || view == .back else { return nil }
        case .shrug:
            move(["shoulder", "shoulderN", "shoulderF", "elbowN", "elbowF", "wristN", "wristF", "handN", "handF"],
                 by: up * 9)
            move(["neck", "head"], by: up * 3)
        case .headForward:
            move(["head"], by: front * 12 + up * -2)
            move(["neck"], by: front * 5)
        case .halfRange:
            // stops halfway: every joint between the start and this position
            for (n, p) in j {
                guard let s = start.joints[n] else { continue }
                j[n] = s + (p - s) * 0.5
            }
        }
        return ExercisePosition.Key(joints: j, props: [])
    }
}

// MARK: - Loading

extension ExercisePosition {
    private static let table: [String: ExercisePosition] = load()

    /// Key positions of the exercise, nil for custom exercises (no drawn poses).
    public static func of(_ exerciseId: String) -> ExercisePosition? { table[exerciseId] }

    public static var ids: Set<String> { Set(table.keys) }

    private static func load() -> [String: ExercisePosition] {
        guard let url = Bundle.module.url(forResource: "ExercisePositions.json", withExtension: "z"),
              let packed = try? Data(contentsOf: url),
              let data = try? (packed as NSData).decompressed(using: .zlib) as Data,
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else { return [:] }
        var out: [String: ExercisePosition] = [:]
        for (id, e) in raw {
            guard let v = (e["v"] as? String).flatMap(View.init(rawValue:)),
                  let ks = e["k"] as? [[String: Any]] else { continue }
            let keys = ks.map { k -> Key in
                var joints: [String: SIMD3<Double>] = [:]
                for (n, p) in k["j"] as? [String: [Double]] ?? [:] { joints[n] = vec(p) }
                let props = (k["p"] as? [[String: Any]] ?? []).compactMap(prop)
                return Key(joints: joints, props: props)
            }
            out[id] = ExercisePosition(view: v, keys: keys)
        }
        return out
    }

    private static func vec(_ p: Any?) -> SIMD3<Double> {
        guard let a = p as? [Double], a.count == 3 else { return .zero }
        return SIMD3(a[0], a[1], a[2])
    }

    private static func prop(_ d: [String: Any]) -> Prop? {
        let r = d["r"] as? Double ?? 0
        switch d["k"] as? String {
        case "pad":
            let n = d["n"] as? [Double] ?? [0, 1]
            return .pad(a: vec(d["a"]), b: vec(d["b"]), normal: SIMD2(n[0], n[1]), halfWidth: d["w"] as? Double ?? 0)
        case "block": return .box(lo: vec(d["lo"]), hi: vec(d["hi"]), mat: false)
        case "mat": return .box(lo: vec(d["lo"]), hi: vec(d["hi"]), mat: true)
        case "rod": return .rod(a: vec(d["a"]), b: vec(d["b"]), radius: r)
        case "disc": return .disc(center: vec(d["c"]), radius: r, alongX: d["ax"] as? String == "x")
        case let kind?: return .weight(kind: kind, center: vec(d["c"]), radius: r)
        default: return nil
        }
    }
}

extension Exercise {
    /// 3D start / middle / end positions for the position guide (catalog exercises).
    public var position: ExercisePosition? { ExercisePosition.of(id) }
}
