import SwiftUI
import WorkoutEngine

typealias BodySide = BodyMapLayout.Side

private let W = CGFloat(BodyMapLayout.width)
private let H = CGFloat(BodyMapLayout.height)

/// Anatomical map (#110): smoothed vector silhouette + muscle shapes for the chosen body figure.
/// Fill = heat (0…1); tap a muscle to drill in. Taps are resolved in design space by
/// `BodyMapLayout.muscle(at:_:side:figure:)` (one gesture for the whole map).
struct BodyMapView: View {
    let side: BodySide
    var heat: [Muscle: Double] = [:]
    var selected: Muscle?
    var showLabel = true
    /// Drawn on a vivid gradient (figure picker): darker silhouette so it reads on colour.
    var onColor = false
    var onTap: ((Muscle) -> Void)?
    /// Explicit figure (picker previews); nil = the user's choice from the environment.
    var figure: BodyFigure?
    @Environment(\.bodyFigure) private var chosenFigure

    private var fig: BodyFigure { figure ?? chosenFigure }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / W, geo.size.height / H)
            Canvas { ctx, _ in draw(&ctx, s: s) }
                .frame(width: W * s, height: H * s)
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { tap in
                    guard let onTap, s > 0,
                          let m = BodyMapLayout.muscle(at: Double(tap.location.x / s), Double(tap.location.y / s), side: side, figure: fig)
                    else { return }
                    onTap(m)
                }, including: onTap == nil ? .subviews : .all)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(W / H, contentMode: .fit)
        .overlay(alignment: .bottom) {
            if showLabel { Text(side.rawValue.uppercased()).eyebrow().offset(y: 16) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityActions {
            if let onTap {
                ForEach(BodyMapLayout.muscles(side), id: \.self) { m in
                    Button(m.name) { onTap(m) }
                }
            }
        }
    }

    private var accessibilitySummary: String {
        let worked = BodyMapLayout.muscles(side).filter { (heat[$0] ?? 0) > 0 }
        return "\(side.rawValue) body map" + (worked.isEmpty ? "" : ": " + worked.map(\.name).joined(separator: ", "))
    }

    private func draw(_ ctx: inout GraphicsContext, s: CGFloat) {
        let shapes = BodyMapLayout.shapes(side, figure: fig)
        let skinTop = onColor ? Color.black.opacity(0.30) : Color.white.opacity(0.10)
        let skinBottom = onColor ? Color.black.opacity(0.18) : Color.white.opacity(0.04)
        for poly in BodyMapLayout.outline(side, figure: fig) {
            let path = Self.smooth(poly, s: s)
            ctx.fill(path, with: .linearGradient(Gradient(colors: [skinTop, skinBottom]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: H * s)))
            ctx.stroke(path, with: .color(.white.opacity(onColor ? 0.25 : 0.14)), lineWidth: max(0.5, 0.8 * s))
        }
        // Glow under the hottest muscles.
        let hot = shapes.filter { (heat[$0.muscle] ?? 0) > 0.5 }
        if !hot.isEmpty {
            ctx.drawLayer { glow in
                glow.addFilter(.blur(radius: 4 * s))
                for shape in hot {
                    glow.fill(Self.smooth(shape.points, s: s), with: .color(Theme.heat(heat[shape.muscle] ?? 0).opacity(0.6)))
                }
            }
        }
        for shape in shapes {
            let h = heat[shape.muscle] ?? 0
            let path = Self.smooth(shape.points, s: s)
            if h > 0 {
                let c = Theme.heat(h)
                ctx.fill(path, with: .color(c.opacity(0.6 + 0.4 * h)))
            } else {
                ctx.fill(path, with: .color(.white.opacity(onColor ? 0.14 : 0.07)))
            }
            if selected == shape.muscle {
                ctx.stroke(path, with: .color(.white), lineWidth: max(1, 1.6 * s))
            } else {
                ctx.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: max(0.4, 0.7 * s))
            }
        }
        for line in BodyMapLayout.details(side, figure: fig) {
            var p = Path()
            p.addLines(line.map { CGPoint(x: $0.x * s, y: $0.y * s) })
            ctx.stroke(p, with: .color(.black.opacity(0.3)), style: StrokeStyle(lineWidth: max(0.4, 0.8 * s), lineCap: .round))
        }
    }

    /// Closed Catmull-Rom spline through the polygon (same as ios/Tools/bodymap/generate.py's preview).
    static func smooth(_ pts: [BodyMapLayout.Point], s: CGFloat) -> Path {
        var path = Path()
        let n = pts.count
        guard n > 2 else { return path }
        func p(_ i: Int) -> CGPoint { let q = pts[(i % n + n) % n]; return CGPoint(x: q.x * s, y: q.y * s) }
        path.move(to: p(0))
        for i in 0..<n {
            let p0 = p(i - 1), p1 = p(i), p2 = p(i + 1), p3 = p(i + 2)
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.closeSubpath()
        return path
    }
}

typealias BodyFigure = BodyMapLayout.Figure

private struct BodyFigureKey: EnvironmentKey {
    static let defaultValue: BodyFigure = .male
}

extension EnvironmentValues {
    /// Figure drawn on every body map; set once at the root from the user's choice (#110).
    var bodyFigure: BodyFigure {
        get { self[BodyFigureKey.self] }
        set { self[BodyFigureKey.self] = newValue }
    }
}

/// Front + back side by side.
struct BodyMapPair: View {
    var heat: [Muscle: Double]
    var selected: Muscle?
    var figure: BodyFigure?
    var onTap: ((Muscle) -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            BodyMapView(side: .front, heat: heat, selected: selected, onTap: onTap, figure: figure)
            BodyMapView(side: .back, heat: heat, selected: selected, onTap: onTap, figure: figure)
        }
        .padding(.bottom, 18)
    }
}

/// Heat legend: cool → hot.
struct HeatLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("ASSIST").eyebrow()
            LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 0.25).map { Theme.heat($0) }, startPoint: .leading, endPoint: .trailing)
                .frame(height: 6)
                .clipShape(Capsule())
            Text("MAIN").eyebrow()
        }
    }
}

extension Exercise {
    /// Heat for an exercise's own body map: primary 1, secondary 0.45.
    var heat: [Muscle: Double] { muscleWeights.mapValues { $0 >= 1 ? 1 : 0.45 } }
}
