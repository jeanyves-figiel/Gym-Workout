import SwiftUI
import WorkoutEngine

// Gym Map (#406, design A + B): the floor plan reads as a real plan (floor tiles, outer walls, entrance), every
// session shows its route through the gym, and the player shows the walk to the next zone.

/// Plan floor: tiles, thick outer walls and the entrance as a gap with a door swing.
struct GymFloor: View {
    var door: GymLayout.Point?
    var wall: CGFloat = 5
    var tile: CGFloat = 16

    static let floorColor = Color(red: 0.08, green: 0.10, blue: 0.18)
    static let tileColor = Color(red: 0.14, green: 0.17, blue: 0.28)
    static let wallColor = Color(red: 0.91, green: 0.93, blue: 1)

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.floorColor))
            var grid = Path()
            var x: CGFloat = 0
            while x <= size.width { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)); x += tile }
            var y: CGFloat = 0
            while y <= size.height { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)); y += tile }
            ctx.stroke(grid, with: .color(Self.tileColor), lineWidth: 0.7)

            let d = Self.doorGeometry(door, size: size, inset: wall / 2)
            let r = CGRect(origin: .zero, size: size).insetBy(dx: wall / 2, dy: wall / 2)
            // Walls round the outside, leaving the door gap.
            var walls = Path()
            walls.addRect(r)
            ctx.stroke(walls, with: .color(Self.wallColor), style: StrokeStyle(lineWidth: wall, lineJoin: .round))
            ctx.stroke(Path { p in p.move(to: d.a); p.addLine(to: d.b) }, with: .color(Self.floorColor), lineWidth: wall + 2)
            // Door leaf + swing.
            var swing = Path()
            swing.move(to: d.a)
            swing.addLine(to: d.leaf)
            swing.addArc(center: d.a, radius: d.width, startAngle: d.leafAngle, endAngle: d.wallAngle, clockwise: d.clockwise)
            ctx.stroke(swing, with: .color(Self.wallColor.opacity(0.6)), lineWidth: 1.2)
        }
        .accessibilityHidden(true)
    }

    struct DoorGeometry {
        var a: CGPoint, b: CGPoint, leaf: CGPoint
        var width: CGFloat
        var wallAngle: Angle, leafAngle: Angle
        var clockwise: Bool
    }

    /// Door gap on the wall nearest the entrance point, opening inwards.
    static func doorGeometry(_ door: GymLayout.Point?, size: CGSize, inset: CGFloat) -> DoorGeometry {
        let p = door ?? GymLayout.Point(x: 0.5, y: 1)
        let w = min(size.width, size.height) * 0.16
        let edge = GymLayout.Point.nearestWall(p)
        switch edge {
        case .bottom, .top:
            let y = edge == .bottom ? size.height - inset : inset
            let cx = min(max(CGFloat(p.x) * size.width, w / 2 + inset), size.width - w / 2 - inset)
            let a = CGPoint(x: cx - w / 2, y: y), b = CGPoint(x: cx + w / 2, y: y)
            let inward: CGFloat = edge == .bottom ? -1 : 1
            return DoorGeometry(a: a, b: b, leaf: CGPoint(x: a.x, y: y + inward * w), width: w,
                                wallAngle: .degrees(0), leafAngle: .degrees(edge == .bottom ? -90 : 90), clockwise: edge != .bottom)
        case .left, .right:
            let x = edge == .right ? size.width - inset : inset
            let cy = min(max(CGFloat(p.y) * size.height, w / 2 + inset), size.height - w / 2 - inset)
            let a = CGPoint(x: x, y: cy - w / 2), b = CGPoint(x: x, y: cy + w / 2)
            let inward: CGFloat = edge == .right ? -1 : 1
            return DoorGeometry(a: a, b: b, leaf: CGPoint(x: x + inward * w, y: a.y), width: w,
                                wallAngle: .degrees(90), leafAngle: .degrees(edge == .right ? 180 : 0), clockwise: edge == .right)
        }
    }
}

extension GymLayout.Point {
    enum Wall { case top, bottom, left, right }

    /// Outer wall closest to the point.
    static func nearestWall(_ p: GymLayout.Point) -> Wall {
        let d: [(Wall, Double)] = [(.top, p.y), (.bottom, 1 - p.y), (.left, p.x), (.right, 1 - p.x)]
        return d.min { $0.1 < $1.1 }!.0
    }

    /// Snapped onto the nearest outer wall.
    var onWall: GymLayout.Point {
        let c = { (v: Double) in min(max(v, 0.08), 0.92) }
        switch Self.nearestWall(self) {
        case .top: return .init(x: c(x), y: 0)
        case .bottom: return .init(x: c(x), y: 1)
        case .left: return .init(x: 0, y: c(y))
        case .right: return .init(x: 1, y: c(y))
        }
    }
}

/// Small read-only plan: zone blocks, an optional numbered route from the entrance, or a walk from one zone to the
/// next (the rest dimmed).
struct GymMiniMap: View {
    let layout: GymLayout
    /// Zone ids in route order: drawn as a dashed lime path with numbered stops.
    var route: [String] = []
    /// Walk highlight: from (white dot) → to (lime dot).
    var from: String?
    var to: String?
    var labels = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let small = size.width < 120
            ZStack(alignment: .topLeading) {
                GymFloor(door: layout.door, wall: small ? 2 : 3, tile: small ? 6 : 10)
                ForEach(layout.zones) { z in
                    if let r = z.rect {
                        let lit = to == nil || z.id == to || z.id == from
                        RoundedRectangle(cornerRadius: small ? 2 : 5, style: .continuous)
                            .fill(z.gradient)
                            .opacity(lit ? 0.95 : 0.3)
                            .overlay(alignment: .topLeading) {
                                if labels {
                                    Text(z.name).font(Theme.label(9)).lineLimit(1).minimumScaleFactor(0.6)
                                        .foregroundStyle(.white).padding(3)
                                }
                            }
                            .frame(width: max(2, CGFloat(r.w) * size.width - 4), height: max(2, CGFloat(r.h) * size.height - 4))
                            .offset(x: CGFloat(r.x) * size.width + 2, y: CGFloat(r.y) * size.height + 2)
                    }
                }
                path(size, small: small)
            }
        }
        .aspectRatio(0.8, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    private func centre(_ id: String, _ size: CGSize) -> CGPoint? {
        guard let c = layout.zone(id: id)?.rect?.center else { return nil }
        return CGPoint(x: CGFloat(c.x) * size.width, y: CGFloat(c.y) * size.height)
    }

    @ViewBuilder private func path(_ size: CGSize, small: Bool) -> some View {
        if let to, let b = centre(to, size) {
            let a = from.flatMap { centre($0, size) }
            ZStack(alignment: .topLeading) {
                if let a {
                    Path { p in
                        p.move(to: a)
                        p.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2, y: min(a.y, b.y) - size.height * 0.12))
                    }
                    .stroke(Theme.lime, style: StrokeStyle(lineWidth: small ? 2 : 3, lineCap: .round, dash: [4, 3]))
                    Circle().fill(.white).frame(width: small ? 7 : 10).position(a)
                }
                Circle().fill(Theme.lime).frame(width: small ? 9 : 13).position(b)
            }
        } else if !route.isEmpty {
            let e = layout.entrance
            let points = [CGPoint(x: CGFloat(e.x) * size.width, y: CGFloat(e.y) * size.height)] + route.compactMap { centre($0, size) }
            ZStack(alignment: .topLeading) {
                Path { p in p.addLines(points) }
                    .stroke(Theme.lime, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [6, 5]))
                ForEach(Array(points.dropFirst().enumerated()), id: \.offset) { i, pt in
                    Text("\(i + 1)").font(Theme.label(11)).foregroundStyle(Theme.ink)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Theme.lime))
                        .position(pt)
                }
            }
        }
    }
}

/// Session page (A): the walk this session takes through the member's gym, stop by stop.
struct GymRouteCard: View {
    let layout: GymLayout
    let route: GymRoute
    /// First stop's zone is usually busy around now (B: learned from "Taken?" taps).
    var busyFirst = false
    var onPlan: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your route today").font(Theme.label(11)).tracking(1.4).textCase(.uppercase).opacity(0.85)
                    Text("\(route.stops.count) \(route.stops.count == 1 ? "stop" : "stops") · \(route.walks) \(route.walks == 1 ? "walk" : "walks")")
                        .font(Theme.display(24))
                }
                Spacer()
                if let m = route.metres {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("≈\(m) m").font(Theme.display(26)).monospacedDigit()
                        Text("walking").font(Theme.label(11)).opacity(0.85)
                    }
                }
            }
            if layout.hasPlan {
                Button { onPlan?() } label: {
                    GymMiniMap(layout: layout, route: route.stops.map(\.zone.id), labels: true)
                        .frame(maxHeight: 190)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(onPlan == nil)
                .accessibilityLabel("Floor plan with your route")
            }
            VStack(spacing: 6) {
                ForEach(Array(route.stops.enumerated()), id: \.offset) { i, s in
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(Theme.label(13)).foregroundStyle(Theme.ink)
                            .frame(width: 24, height: 24).background(Circle().fill(Theme.lime))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.zone.name).font(Theme.label(14))
                            Text(names(s)).font(.caption.weight(.semibold)).opacity(0.85).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Circle().fill(s.zone.gradient).frame(width: 12, height: 12)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.22)))
                }
            }
            if busyFirst, let first = route.stops.first {
                Label("\(first.zone.name) is usually busy around now. In the player, Taken? swaps to a free zone.",
                      systemImage: "person.3.fill")
                    .font(.caption.weight(.bold))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.3)))
            }
        }
        .gradientCard(LinearGradient(colors: [Color(hex: 0x2F6BFF), Color(hex: 0x8A4DFF)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.route")
    }

    private func names(_ s: GymRoute.Stop) -> String {
        var seen = Set<String>()
        return s.exerciseIds.filter { seen.insert($0).inserted }.compactMap { Exercise.find($0)?.name }.joined(separator: " · ")
    }
}

/// Player beat when the member leaves a zone for good (#406).
struct ZoneClearedBanner: View {
    let zone: GymLayout.Zone
    var next: GymLayout.Zone?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 18, weight: .heavy))
            VStack(alignment: .leading, spacing: 0) {
                Text("\(zone.name) cleared").font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.7)
                if let next { Text("Walk to \(next.name)").font(Theme.label(11)).opacity(0.9) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(zone.gradient))
        .foregroundStyle(.white)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}
