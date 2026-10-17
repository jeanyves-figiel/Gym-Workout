import Foundation

/// Where equipment sits in the member's own gym (#274): named zones, each with its items and, when the member drew a
/// rough floor plan, a block on it. Supersets and circuits only pair exercises from one zone (or zones next to each
/// other on the plan), so the member doesn't cross the gym mid-group. nil on the profile = grouping as before.
public struct GymLayout: Codable, Hashable, Sendable {
    public struct Zone: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String
        /// Palette index for the zone's colour (app side).
        public var color: Int
        public var items: [Equipment]
        /// Block on the floor plan in a unit square (0…1); nil = not drawn.
        public var rect: Rect?

        public init(id: String = UUID().uuidString.lowercased(), name: String, color: Int, items: [Equipment], rect: Rect? = nil) {
            self.id = id
            self.name = name
            self.color = color
            self.items = items
            self.rect = rect
        }
    }

    public struct Rect: Codable, Hashable, Sendable {
        public var x: Double
        public var y: Double
        public var w: Double
        public var h: Double

        public init(x: Double, y: Double, w: Double, h: Double) {
            self.x = x
            self.y = y
            self.w = w
            self.h = h
        }

        /// Gap between two blocks (0 when they touch or overlap).
        public func gap(to o: Rect) -> Double {
            let dx = max(0, max(o.x - (x + w), x - (o.x + o.w)))
            let dy = max(0, max(o.y - (y + h), y - (o.y + o.h)))
            return (dx * dx + dy * dy).squareRoot()
        }

        public var center: Point { Point(x: x + w / 2, y: y + h / 2) }
    }

    /// Point on the plan (unit square).
    public struct Point: Codable, Hashable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public var zones: [Zone]
    /// Entrance on the plan's outer wall (#406); nil = middle of the bottom wall.
    public var door: Point?
    /// Room width (x) and depth (y) in metres from a LiDAR room scan (#406); nil = a typical gym floor.
    public var sizeM: Point?

    public init(zones: [Zone], door: Point? = nil, sizeM: Point? = nil) {
        self.zones = zones
        self.door = door
        self.sizeM = sizeM
    }

    /// Blocks closer than this on the plan count as next to each other.
    public static let neighbourGap = 0.06

    /// Carried to wherever the member is: never ties an exercise to a zone.
    public static let portable: Set<Equipment> = [.mat, .bands, .jumpRope, .sliders, .abWheel, .massageBall, .foamRoller, .dipBelt]

    /// Usual layout to start from: free weights, machines, functional, cardio, stretch (the member fixes what differs).
    public static var starter: GymLayout {
        let order: [GymZone] = [.freeWeights, .machines, .functional, .cardio, .stretch]
        let names: [GymZone: String] = [.freeWeights: "Free weights", .machines: "Machines", .functional: "Functional",
                                         .cardio: "Cardio", .stretch: "Stretch"]
        return GymLayout(zones: order.enumerated().map { i, z in
            Zone(id: z.rawValue, name: names[z]!, color: i, items: Equipment.allCases.filter { $0.zone == z })
        })
    }

    public var hasPlan: Bool { zones.contains { $0.rect != nil } }

    public func zone(of item: Equipment) -> Zone? { zones.first { $0.items.contains(item) } }

    public func zone(id: String) -> Zone? { zones.first { $0.id == id } }

    /// Zone the exercise is done in: the one holding most of its non-portable equipment; nil = anywhere (bodyweight,
    /// mat, bands…) or not placed.
    public func zone(of exercise: Exercise) -> Zone? {
        let fixed = exercise.equipment.filter { !Self.portable.contains($0) }
        var best: (zone: Zone, n: Int)?
        for e in fixed {
            guard let z = zone(of: e) else { continue }
            let n = fixed.filter { z.items.contains($0) }.count
            if best == nil || n > best!.n { best = (z, n) }
        }
        return best?.zone
    }

    /// Same zone, or blocks next to each other on the floor plan.
    public func near(_ a: Zone, _ b: Zone) -> Bool {
        guard a.id != b.id else { return true }
        guard let ra = a.rect, let rb = b.rect else { return false }
        return ra.gap(to: rb) <= Self.neighbourGap
    }

    /// Two exercises can share a superset / circuit: either can be done anywhere, or their zones are near.
    public func near(_ a: Exercise, _ b: Exercise) -> Bool {
        guard let za = zone(of: a), let zb = zone(of: b) else { return true }
        return near(za, zb)
    }

    /// Moves `item` into the zone `id` (out of any other).
    public mutating func move(_ item: Equipment, to id: String) {
        for i in zones.indices { zones[i].items.removeAll { $0 == item } }
        if let i = zones.firstIndex(where: { $0.id == id }) { zones[i].items.append(item) }
    }

    /// Painting id that clears a picture's zone (#289).
    public static let noZone = "-"

    /// Takes `item` out of every zone: it then fits any zone in a workout (#289).
    public mutating func unassign(_ item: Equipment) {
        for i in zones.indices { zones[i].items.removeAll { $0 == item } }
    }

    /// Removes a zone; its items go back to the zone they'd be in on the usual layout, else the first zone.
    public mutating func remove(_ id: String) {
        guard zones.count > 1, let i = zones.firstIndex(where: { $0.id == id }) else { return }
        let items = zones.remove(at: i).items
        for e in items {
            let usual = Self.starter.zone(of: e)?.id
            let target = zones.first { $0.id == usual } ?? zones[0]
            move(e, to: target.id)
        }
    }

    /// Next unused palette index.
    public var nextColor: Int {
        let used = Set(zones.map(\.color))
        return (0...).first { !used.contains($0) }!
    }

    /// Chunks `members` (in order) into groups of up to `size`, each member near every other in its group: the
    /// first member left opens a group, the next members near all of it join. Without a layout this is plain chunking.
    static func chunk<T>(_ members: [T], size: Int, near: (T, T) -> Bool) -> [[T]] {
        var left = members
        var out: [[T]] = []
        while !left.isEmpty {
            var g = [left.removeFirst()]
            while g.count < size, let j = left.firstIndex(where: { m in g.allSatisfy { near(m, $0) } }) {
                g.append(left.remove(at: j))
            }
            out.append(g)
        }
        return out
    }
}

extension Optional where Wrapped == GymLayout {
    /// Exercises near each other; no layout = always.
    func near(_ a: String, _ b: String) -> Bool {
        guard let layout = self, let ea = Exercise.find(a), let eb = Exercise.find(b) else { return true }
        return layout.near(ea, eb)
    }
}
