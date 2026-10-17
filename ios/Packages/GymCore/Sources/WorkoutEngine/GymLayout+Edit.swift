import Foundation

// Gym map editing (#422, design A + C swap): blocks never overlap. A block that moves or grows pushes the ones it
// lands on aside (and they push theirs), the entrance stays clear, and dropping a block on another swaps them.

extension GymLayout.Rect {
    static let eps = 0.001

    /// Shares area with `o` (touching edges don't count).
    public func overlaps(_ o: GymLayout.Rect) -> Bool {
        x < o.x + o.w - Self.eps && o.x < x + w - Self.eps && y < o.y + o.h - Self.eps && o.y < y + h - Self.eps
    }

    public var centre: GymLayout.Point { GymLayout.Point(x: x + w / 2, y: y + h / 2) }

    public func contains(_ p: GymLayout.Point) -> Bool { p.x >= x && p.x <= x + w && p.y >= y && p.y <= y + h }

    /// Moved the shortest way out of `obstacle`, staying inside the plan when it can.
    func pushed(outOf obstacle: GymLayout.Rect) -> GymLayout.Rect {
        let moves: [(dx: Double, dy: Double)] = [
            (obstacle.x - (x + w), 0), (obstacle.x + obstacle.w - x, 0),
            (0, obstacle.y - (y + h)), (0, obstacle.y + obstacle.h - y),
        ]
        let inside = { (m: (dx: Double, dy: Double)) in
            x + m.dx >= -Self.eps && x + w + m.dx <= 1 + Self.eps && y + m.dy >= -Self.eps && y + h + m.dy <= 1 + Self.eps
        }
        let size = { (m: (dx: Double, dy: Double)) in abs(m.dx) + abs(m.dy) }
        let best = moves.filter(inside).min { size($0) < size($1) } ?? moves.min { size($0) < size($1) }!
        var r = self
        r.x = min(max(0, x + best.dx), 1 - w)
        r.y = min(max(0, y + best.dy), 1 - h)
        return r
    }
}

extension GymLayout {
    /// Floor kept clear in front of the entrance.
    public var doorClearance: Rect {
        let d = entrance
        let long = 0.2, deep = 0.08
        if d.y <= 0.001 || d.y >= 0.999 {
            return Rect(x: min(max(0, d.x - long / 2), 1 - long), y: d.y <= 0.001 ? 0 : 1 - deep, w: long, h: deep)
        }
        return Rect(x: d.x <= 0.001 ? 0 : 1 - deep, y: min(max(0, d.y - long / 2), 1 - long), w: deep, h: long)
    }

    /// After block `id` moved or was resized: it leaves the entrance clear, and every block it now overlaps is
    /// pushed aside (in turn pushing the ones it lands on). Bounded, so a crowded plan can't loop.
    public mutating func settle(_ id: String) {
        var queue = [id]
        var steps = 0
        while !queue.isEmpty, steps < 60 {
            steps += 1
            let current = queue.removeFirst()
            guard let i = zones.firstIndex(where: { $0.id == current }), var r = zones[i].rect else { continue }
            if r.overlaps(doorClearance) {
                r = r.pushed(outOf: doorClearance)
                zones[i].rect = r
            }
            for j in zones.indices where j != i {
                guard let o = zones[j].rect, o.overlaps(r) else { continue }
                zones[j].rect = o.pushed(outOf: r)
                queue.append(zones[j].id)
            }
        }
    }

    /// Two blocks trade places (each keeps the other's spot and size).
    public mutating func swapPlaces(_ a: String, _ b: String) {
        guard let i = zones.firstIndex(where: { $0.id == a }), let j = zones.firstIndex(where: { $0.id == b }), i != j else { return }
        let ri = zones[i].rect
        zones[i].rect = zones[j].rect
        zones[j].rect = ri
    }

    /// Block under a plan point, other than `except`.
    public func zone(at p: Point, except: String? = nil) -> Zone? {
        zones.first { $0.id != except && ($0.rect?.contains(p) ?? false) }
    }
}
