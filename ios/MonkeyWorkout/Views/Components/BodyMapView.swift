import SwiftUI
import WorkoutEngine

enum BodySide: String, CaseIterable, Identifiable {
    case front, back
    var id: String { rawValue }
}

/// One drawable muscle region in a 200 × 410 design space; `mirrored` draws the symmetric twin.
private struct Region {
    let muscle: Muscle
    let rect: CGRect
    var mirrored = true
    var angle: Double = 0
}

private let W: CGFloat = 200
private let H: CGFloat = 410

private func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }

private let frontRegions: [Region] = [
    Region(muscle: .sideDelts, rect: r(34, 74, 14, 28), angle: 12),
    Region(muscle: .frontDelts, rect: r(44, 68, 22, 26), angle: 20),
    Region(muscle: .chest, rect: r(63, 78, 36, 34)),
    Region(muscle: .biceps, rect: r(36, 100, 17, 46), angle: 8),
    Region(muscle: .forearms, rect: r(26, 162, 16, 62), angle: 8),
    Region(muscle: .obliques, rect: r(64, 122, 18, 56)),
    Region(muscle: .abs, rect: r(86, 116, 28, 72), mirrored: false),
    Region(muscle: .hipFlexors, rect: r(74, 192, 18, 24), angle: -20),
    Region(muscle: .quads, rect: r(66, 220, 26, 88), angle: 4),
    Region(muscle: .adductors, rect: r(89, 222, 10, 54)),
    Region(muscle: .calves, rect: r(70, 330, 16, 54)),
]

private let backRegions: [Region] = [
    Region(muscle: .sideDelts, rect: r(34, 74, 14, 28), angle: 12),
    Region(muscle: .rearDelts, rect: r(44, 70, 22, 24), angle: 20),
    Region(muscle: .upperBack, rect: r(72, 66, 56, 48), mirrored: false),
    Region(muscle: .rotatorCuff, rect: r(64, 92, 20, 20)),
    Region(muscle: .lats, rect: r(62, 112, 28, 60), angle: -8),
    Region(muscle: .triceps, rect: r(36, 100, 17, 48), angle: 8),
    Region(muscle: .forearms, rect: r(26, 162, 16, 62), angle: 8),
    Region(muscle: .lowerBack, rect: r(84, 158, 32, 32), mirrored: false),
    Region(muscle: .glutes, rect: r(66, 190, 33, 36)),
    Region(muscle: .hamstrings, rect: r(67, 232, 26, 76), angle: 3),
    Region(muscle: .adductors, rect: r(91, 232, 9, 40)),
    Region(muscle: .calves, rect: r(68, 320, 25, 62)),
]

/// Stylised anatomical map. Fill = heat (0…1); tap a muscle to drill in.
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
                ForEach(Array(regions.enumerated()), id: \.offset) { _, region in
                    muscle(region, rect: region.rect, s: s)
                    if region.mirrored {
                        muscle(region, rect: CGRect(x: W - region.rect.maxX, y: region.rect.minY, width: region.rect.width, height: region.rect.height), s: s, flip: true)
                    }
                }
            }
            .frame(width: W * s, height: H * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(W / H, contentMode: .fit)
        .overlay(alignment: .bottom) {
            if showLabel { Text(side.rawValue.uppercased()).eyebrow().offset(y: 16) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var regions: [Region] { side == .front ? frontRegions : backRegions }

    private var accessibilitySummary: String {
        let worked = regions.map(\.muscle).filter { (heat[$0] ?? 0) > 0 }
        return "\(side.rawValue) body map" + (worked.isEmpty ? "" : ": " + worked.map(\.name).joined(separator: ", "))
    }

    @ViewBuilder
    private func muscle(_ region: Region, rect: CGRect, s: CGFloat, flip: Bool = false) -> some View {
        let h = heat[region.muscle] ?? 0
        let isSel = selected == region.muscle
        let fill: Color = h > 0 ? Theme.heat(h) : Color.white.opacity(0.10)
        Ellipse()
            .fill(fill.opacity(h > 0 ? 0.35 + 0.65 * h : 1))
            .overlay(Ellipse().strokeBorder(isSel ? Color.white : Color.white.opacity(0.12), lineWidth: isSel ? 2 : 0.5))
            .shadow(color: h > 0.5 ? fill.opacity(0.7) : .clear, radius: 6 * s)
            .frame(width: rect.width * s, height: rect.height * s)
            .rotationEffect(.degrees(flip ? -region.angle : region.angle))
            .position(x: rect.midX * s, y: rect.midY * s)
            .contentShape(Ellipse())
            .onTapGesture { onTap?(region.muscle) }
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
