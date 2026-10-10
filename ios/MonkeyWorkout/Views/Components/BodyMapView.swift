import SwiftUI
import WorkoutEngine

typealias BodySide = BodyMapLayout.Side

private let W = CGFloat(BodyMapLayout.width)
private let H = CGFloat(BodyMapLayout.height)

/// Stylised anatomical map. Fill = heat (0…1); tap a muscle to drill in.
/// Taps are resolved in design space by `BodyMapLayout.muscle(at:_:side:)` (one gesture for the whole map),
/// so each ellipse opens its own muscle.
struct BodyMapView: View {
    let side: BodySide
    var heat: [Muscle: Double] = [:]
    var selected: Muscle?
    var showLabel = true
    var onTap: ((Muscle) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / W, geo.size.height / H)
            ZStack(alignment: .topLeading) {
                silhouette(s)
                ForEach(Array(shapes.enumerated()), id: \.offset) { _, shape in
                    muscle(shape, s: s)
                }
            }
            .frame(width: W * s, height: H * s)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap in
                guard let onTap, s > 0,
                      let m = BodyMapLayout.muscle(at: Double(tap.location.x / s), Double(tap.location.y / s), side: side)
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

    private var shapes: [BodyMapLayout.Shape] { BodyMapLayout.shapes(side) }

    private var accessibilitySummary: String {
        let worked = BodyMapLayout.muscles(side).filter { (heat[$0] ?? 0) > 0 }
        return "\(side.rawValue) body map" + (worked.isEmpty ? "" : ": " + worked.map(\.name).joined(separator: ", "))
    }

    @ViewBuilder
    private func muscle(_ shape: BodyMapLayout.Shape, s: CGFloat) -> some View {
        let h = heat[shape.muscle] ?? 0
        let isSel = selected == shape.muscle
        let fill: Color = h > 0 ? Theme.heat(h) : Color.white.opacity(0.10)
        Ellipse()
            .fill(fill.opacity(h > 0 ? 0.35 + 0.65 * h : 1))
            .overlay(Ellipse().strokeBorder(isSel ? Color.white : Color.white.opacity(0.12), lineWidth: isSel ? 2 : 0.5))
            .shadow(color: h > 0.5 ? fill.opacity(0.7) : .clear, radius: 6 * s)
            .frame(width: CGFloat(shape.w) * s, height: CGFloat(shape.h) * s)
            .rotationEffect(.degrees(shape.angle))
            .position(x: CGFloat(shape.midX) * s, y: CGFloat(shape.midY) * s)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func silhouette(_ s: CGFloat) -> some View {
        let base = Color.white.opacity(0.05)
        Group {
            Circle().fill(base).frame(width: 44 * s, height: 44 * s).position(x: 100 * s, y: 32 * s)
            RoundedRectangle(cornerRadius: 6 * s).fill(base).frame(width: 20 * s, height: 16 * s).position(x: 100 * s, y: 60 * s)
            RoundedRectangle(cornerRadius: 28 * s).fill(base).frame(width: 88 * s, height: 132 * s).position(x: 100 * s, y: 132 * s)
            RoundedRectangle(cornerRadius: 20 * s).fill(base).frame(width: 74 * s, height: 44 * s).position(x: 100 * s, y: 204 * s)
            ForEach([CGFloat(1), -1], id: \.self) { d in
                Capsule().fill(base).frame(width: 24 * s, height: 96 * s).rotationEffect(.degrees(Double(8 * d)))
                    .position(x: (100 - 56 * d) * s, y: 120 * s)
                Capsule().fill(base).frame(width: 20 * s, height: 84 * s).rotationEffect(.degrees(Double(8 * d)))
                    .position(x: (100 - 66 * d) * s, y: 194 * s)
                Capsule().fill(base).frame(width: 34 * s, height: 112 * s)
                    .position(x: (100 - 19 * d) * s, y: 268 * s)
                Capsule().fill(base).frame(width: 26 * s, height: 86 * s)
                    .position(x: (100 - 20 * d) * s, y: 358 * s)
            }
        }
    }
}

/// Front + back side by side.
struct BodyMapPair: View {
    var heat: [Muscle: Double]
    var selected: Muscle?
    var onTap: ((Muscle) -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            BodyMapView(side: .front, heat: heat, selected: selected, onTap: onTap)
            BodyMapView(side: .back, heat: heat, selected: selected, onTap: onTap)
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
