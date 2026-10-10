import Foundation

/// Geometry of the stylised body map, in a 200 × 410 design space, plus hit-testing.
/// Kept here (not in the view) so taps can be resolved and tested without SwiftUI.
public enum BodyMapLayout {
    public enum Side: String, CaseIterable, Sendable, Identifiable {
        case front, back
        public var id: String { rawValue }
    }

    public static let width: Double = 200
    public static let height: Double = 410

    /// One drawn muscle ellipse: bounding box (before rotation) and rotation in degrees.
    public struct Shape: Sendable, Equatable {
        public let muscle: Muscle
        public let x, y, w, h: Double
        public let angle: Double

        public var midX: Double { x + w / 2 }
        public var midY: Double { y + h / 2 }

        /// Normalised distance from the centre: ≤ 1 inside the (rotated) ellipse.
        public func distance(x px: Double, y py: Double) -> Double {
            let dx = px - midX, dy = py - midY
            let a = -angle * .pi / 180
            let lx = dx * cos(a) - dy * sin(a)
            let ly = dx * sin(a) + dy * cos(a)
            let rx = w / 2, ry = h / 2
            return (lx * lx) / (rx * rx) + (ly * ly) / (ry * ry)
        }
    }

    private struct Region: Sendable {
        let muscle: Muscle
        let x, y, w, h: Double
        var mirrored = true
        var angle: Double = 0
    }

    private static let front: [Region] = [
        Region(muscle: .sideDelts, x: 34, y: 74, w: 14, h: 28, angle: 12),
        Region(muscle: .frontDelts, x: 44, y: 68, w: 22, h: 26, angle: 20),
        Region(muscle: .chest, x: 63, y: 78, w: 36, h: 34),
        Region(muscle: .biceps, x: 36, y: 100, w: 17, h: 46, angle: 8),
        Region(muscle: .forearms, x: 26, y: 162, w: 16, h: 62, angle: 8),
        Region(muscle: .obliques, x: 64, y: 122, w: 18, h: 56),
        Region(muscle: .abs, x: 86, y: 116, w: 28, h: 72, mirrored: false),
        Region(muscle: .hipFlexors, x: 74, y: 192, w: 18, h: 24, angle: -20),
        Region(muscle: .quads, x: 66, y: 220, w: 26, h: 88, angle: 4),
        Region(muscle: .adductors, x: 89, y: 222, w: 10, h: 54),
        Region(muscle: .calves, x: 70, y: 330, w: 16, h: 54),
    ]

    private static let back: [Region] = [
        Region(muscle: .sideDelts, x: 34, y: 74, w: 14, h: 28, angle: 12),
        Region(muscle: .rearDelts, x: 44, y: 70, w: 22, h: 24, angle: 20),
        Region(muscle: .upperBack, x: 72, y: 66, w: 56, h: 48, mirrored: false),
        Region(muscle: .rotatorCuff, x: 64, y: 92, w: 20, h: 20),
        Region(muscle: .lats, x: 62, y: 112, w: 28, h: 60, angle: -8),
        Region(muscle: .triceps, x: 36, y: 100, w: 17, h: 48, angle: 8),
        Region(muscle: .forearms, x: 26, y: 162, w: 16, h: 62, angle: 8),
        Region(muscle: .lowerBack, x: 84, y: 158, w: 32, h: 32, mirrored: false),
        Region(muscle: .glutes, x: 66, y: 190, w: 33, h: 36),
        Region(muscle: .hamstrings, x: 67, y: 232, w: 26, h: 76, angle: 3),
        Region(muscle: .adductors, x: 91, y: 232, w: 9, h: 40),
        Region(muscle: .calves, x: 68, y: 320, w: 25, h: 62),
    ]

    /// Every ellipse drawn for a side, mirrored twins included, in draw order.
    public static func shapes(_ side: Side) -> [Shape] {
        (side == .front ? front : back).flatMap { r -> [Shape] in
            let s = Shape(muscle: r.muscle, x: r.x, y: r.y, w: r.w, h: r.h, angle: r.angle)
            guard r.mirrored else { return [s] }
            return [s, Shape(muscle: r.muscle, x: width - r.x - r.w, y: r.y, w: r.w, h: r.h, angle: -r.angle)]
        }
    }

    /// Muscles shown on a side, in draw order, without duplicates.
    public static func muscles(_ side: Side) -> [Muscle] {
        var seen = Set<Muscle>()
        return shapes(side).map(\.muscle).filter { seen.insert($0).inserted }
    }

    /// Muscle under a point in design space; where ellipses overlap, the one whose centre is closest
    /// (relative to its size) wins. Nil outside every muscle.
    public static func muscle(at x: Double, _ y: Double, side: Side) -> Muscle? {
        shapes(side)
            .map { ($0.muscle, $0.distance(x: x, y: y)) }
            .filter { $0.1 <= 1 }
            .min { $0.1 < $1.1 }?.0
    }
}
