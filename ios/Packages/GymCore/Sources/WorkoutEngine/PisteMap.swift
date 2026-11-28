import Foundation

/// A ski resort's pistes and lifts from OpenStreetMap (#1132), as `GET /v1/me/pistes` serves them. The ski session map
/// draws them under the day's track; runs are matched to the piste they followed and lift rides to the lift they took.
public struct PisteMap: Codable, Equatable, Sendable {
    public struct Line: Codable, Equatable, Sendable {
        public var name: String?
        public var ref: String?
        /// Pistes: novice, easy, intermediate, advanced, expert, freeride, extreme.
        public var difficulty: String?
        /// Lifts: gondola, chair_lift, drag_lift, t-bar, cable_car, …
        public var kind: String?
        /// lat, lon, lat, lon, …
        public var pts: [Double]

        public init(name: String? = nil, ref: String? = nil, difficulty: String? = nil, kind: String? = nil, pts: [Double]) {
            self.name = name
            self.ref = ref
            self.difficulty = difficulty
            self.kind = kind
            self.pts = pts
        }

        public var coordinates: [(lat: Double, lon: Double)] {
            stride(from: 0, to: pts.count - 1, by: 2).map { (pts[$0], pts[$0 + 1]) }
        }

        /// European piste colour: blue (novice, easy), red, black (advanced, expert), orange off-piste. Hiking paths
        /// (#1133) as Swiss signs: T1 yellow, T2–T3 red (white-red-white), T4–T6 blue (white-blue-white). MTB: S0–S1
        /// green, S2 blue, S3 red, S4–S6 black.
        public var colour: Colour {
            switch difficulty {
            case "novice", "easy", "T4", "T5", "T6", "S2": .blue
            case "intermediate", "T2", "T3", "S3": .red
            case "advanced", "expert", "S4", "S5", "S6": .black
            case "freeride", "extreme": .orange
            case "T1": .yellow
            case "S0", "S1": .green
            default: .unknown
            }
        }

        /// A graded trail (#1133): "T3", "S2".
        var grade: String? { difficulty.flatMap { $0.count == 2 && ($0.hasPrefix("T") || $0.hasPrefix("S")) ? $0 : nil } }

        /// "Red 12 Standard", "Gondola Alpha", "Chair lift".
        public var label: String {
            if kind != nil {
                let k = kind.map(Self.liftKind) ?? "Lift"
                return name.map { $0.localizedCaseInsensitiveContains(k) ? $0 : "\(k) \($0)" } ?? k
            }
            if let grade { return name.map { "\(grade) · \($0)" } ?? grade }
            let head = [colour == .unknown ? "Piste" : colour.rawValue.capitalized, ref].compactMap { $0 }.joined(separator: " ")
            return name.map { "\(head) · \($0)" } ?? head
        }

        static func liftKind(_ k: String) -> String {
            switch k {
            case "gondola", "mixed_lift": "Gondola"
            case "cable_car": "Cable car"
            case "chair_lift": "Chair"
            case "drag_lift", "t-bar", "j-bar", "platter", "rope_tow": "Drag lift"
            case "magic_carpet": "Carpet"
            default: "Lift"
            }
        }
    }

    public enum Colour: String, Sendable { case blue, red, black, orange, yellow, green, unknown }

    public var pistes: [Line]
    public var lifts: [Line]
    public var attribution: String

    public init(pistes: [Line], lifts: [Line], attribution: String = "© OpenStreetMap contributors") {
        self.pistes = pistes
        self.lifts = lifts
        self.attribution = attribution
    }

    /// The server's JSON (lifts carry `kind`, pistes `difficulty`).
    public static func decode(_ data: Data) throws -> PisteMap { try JSONDecoder().decode(PisteMap.self, from: data) }

    /// Box around a track with a 500 m margin: south, west, north, east.
    public static func box(_ track: SportTrack) -> (s: Double, w: Double, n: Double, e: Double)? {
        guard let s = track.points.map(\.lat).min(), let n = track.points.map(\.lat).max(),
              let w = track.points.map(\.lon).min(), let e = track.points.map(\.lon).max() else { return nil }
        let dLat = 0.0045, dLon = 0.0045 / max(0.2, cos((s + n) / 2 * .pi / 180))
        return (s - dLat, w - dLon, n + dLat, e + dLon)
    }

    /// The piste a run followed: the one most of its points lie within `near` metres of (at least half of them).
    public func piste(for run: SportTrack.Run, in track: SportTrack, near: Double = 40) -> Line? {
        best(pistes, points: Array(track.points[run.from...run.to]), near: near, share: 0.5)
    }

    /// The lift taken between `from` and `to` (a lift ride's points): the closest line to both its ends.
    public func lift(from a: SportTrack.Point, to b: SportTrack.Point, near: Double = 80) -> Line? {
        lifts.map { l in (l, Self.distance(a, to: l) + Self.distance(b, to: l)) }
            .filter { $0.1 <= 2 * near }
            .min { $0.1 < $1.1 }?.0
    }

    private func best(_ lines: [Line], points: [SportTrack.Point], near: Double, share: Double) -> Line? {
        guard !points.isEmpty else { return nil }
        // Up to about 60 points is plenty and keeps a long day quick.
        let sample = stride(from: 0, to: points.count, by: max(1, points.count / 60)).map { points[$0] }
        var top: (Line, Double)?
        for l in lines {
            let hits = Double(sample.filter { Self.distance($0, to: l) <= near }.count) / Double(sample.count)
            if hits >= share, hits > (top?.1 ?? 0) { top = (l, hits) }
        }
        return top?.0
    }

    /// Trails a hike, ride or XC ski day used (#1133): metres on each (by label), longest first, at least 200 m each.
    public func usage(_ track: SportTrack, near: Double = 30) -> [(line: Line, meters: Double)] {
        guard track.points.count > 1 else { return [] }
        var metres: [String: (Line, Double)] = [:]
        let dist = track.distances
        for i in 1..<track.points.count {
            let p = track.points[i]
            guard let (l, d) = pistes.map({ ($0, Self.distance(p, to: $0)) }).min(by: { $0.1 < $1.1 }), d <= near else { continue }
            metres[l.label, default: (l, 0)].1 += dist[i] - dist[i - 1]
        }
        return metres.values.filter { $0.1 >= 200 }.sorted { $0.1 > $1.1 }.map { ($0.0, $0.1) }
    }

    /// Metres from a point to a polyline (flat-earth, fine within a resort).
    static func distance(_ p: SportTrack.Point, to line: Line) -> Double {
        let c = line.coordinates
        guard let first = c.first else { return .infinity }
        let k = cos(p.lat * .pi / 180)
        let m = 111_320.0
        func xy(_ lat: Double, _ lon: Double) -> (Double, Double) { ((lon - p.lon) * k * m, (lat - p.lat) * m) }
        guard c.count > 1 else { let (x, y) = xy(first.lat, first.lon); return (x * x + y * y).squareRoot() }
        var best = Double.infinity
        for i in 0..<(c.count - 1) {
            let (ax, ay) = xy(c[i].lat, c[i].lon), (bx, by) = xy(c[i + 1].lat, c[i + 1].lon)
            let dx = bx - ax, dy = by - ay
            let len = dx * dx + dy * dy
            let t = len > 0 ? max(0, min(1, -(ax * dx + ay * dy) / len)) : 0
            let x = ax + t * dx, y = ay + t * dy
            best = min(best, (x * x + y * y).squareRoot())
        }
        return best
    }
}
