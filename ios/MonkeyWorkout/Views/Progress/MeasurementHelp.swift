import SwiftUI
import WorkoutEngine

/// Help for each measurement (#220): a body figure with the tape where it goes, steps and a tip.
/// Shown from the ? on each Log measurements card (how-to sheet) and in the guided "Measure with me" mode.

/// Front body figure (the member's chosen figure) with a glowing tape band at the girth site;
/// body weight and body fat stand the figure on a scale.
struct MeasureFigure: View {
    let metric: BodyMetric
    var side: LimbSide?
    @Environment(\.bodyFigure) private var figure

    private static let tape = Theme.lime

    var body: some View {
        Canvas { ctx, size in
            let w = BodyMapLayout.width, h = BodyMapLayout.height + 14
            let s = min(size.width / w, size.height / h)
            ctx.translateBy(x: (size.width - w * s) / 2, y: (size.height - h * s) / 2)
            func rect(_ x: Double, _ y: Double, _ rw: Double, _ rh: Double) -> CGRect {
                CGRect(x: x * s, y: y * s, width: rw * s, height: rh * s)
            }

            let onScale: Bool = switch metric {
            case .weight, .bodyFat, .leanMass: true
            case .girth: false
            }
            if onScale {
                ctx.fill(Path(roundedRect: rect(52, 402, 96, 11), cornerRadius: 4 * s), with: .color(Self.tape))
                ctx.fill(Path(roundedRect: rect(90, 405.5, 20, 4), cornerRadius: 1.5 * s), with: .color(Theme.ink.opacity(0.6)))
            }

            for poly in BodyMapLayout.outline(.front, figure: figure) {
                ctx.fill(BodyMapView.smooth(poly, s: s), with: .color(.white.opacity(0.94)))
            }
            for line in BodyMapLayout.details(.front, figure: figure) where line.count > 1 {
                var p = Path()
                p.addLines(line.map { CGPoint(x: $0.x * s, y: $0.y * s) })
                ctx.stroke(p, with: .color(.black.opacity(0.12)), lineWidth: max(0.5, 0.8 * s))
            }

            switch metric {
            case let .girth(site):
                guard let band = BodyMapLayout.tapeBand(site, side: side, figure: figure) else { return }
                let rh = max(6, band.width * 0.18)
                let ring = Path(ellipseIn: rect(band.minX - 3, band.y - rh / 2, band.width + 6, rh))
                ctx.drawLayer { glow in
                    glow.addFilter(.blur(radius: 3 * s))
                    glow.stroke(ring, with: .color(Self.tape), lineWidth: 5 * s)
                }
                ctx.stroke(ring, with: .color(Self.tape), lineWidth: max(1.5, 3 * s))
            case .bodyFat:
                // Calipers pinching the skin at the side of the waist.
                guard let waist = BodyMapLayout.tapeBand(.waist, figure: figure) else { return }
                let x = waist.maxX + 2, y = waist.y
                var pinch = Path()
                pinch.move(to: CGPoint(x: (x + 16) * s, y: (y - 9) * s))
                pinch.addLine(to: CGPoint(x: x * s, y: (y - 2) * s))
                pinch.move(to: CGPoint(x: (x + 16) * s, y: (y + 9) * s))
                pinch.addLine(to: CGPoint(x: x * s, y: (y + 2) * s))
                ctx.drawLayer { glow in
                    glow.addFilter(.blur(radius: 3 * s))
                    glow.stroke(pinch, with: .color(Self.tape), lineWidth: 5 * s)
                }
                ctx.stroke(pinch, with: .color(Self.tape), style: StrokeStyle(lineWidth: max(1.5, 3 * s), lineCap: .round))
            case .weight, .leanMass:
                break
            }
        }
        .accessibilityHidden(true)
    }
}

/// Numbered steps with lime number tiles.
struct MeasureSteps: View {
    let steps: [String]
    var font: Font = .subheadline.weight(.medium)

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)")
                        .font(Theme.label(13))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.lime))
                    Text(step).font(font).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// One measurement's help page (option A): figure, steps, tip.
struct MeasurementHowToSheet: View {
    let metric: BodyMetric
    var side: LimbSide?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("How to measure").eyebrow()
                        Text(MeasureGuideView.title(metric, side)).font(Theme.display(30))
                    }
                    MeasureFigure(metric: metric, side: side)
                        .padding(14)
                        .frame(height: 290)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(metric.category.gradient))
                    MeasureSteps(steps: metric.guide.steps)
                    Label(metric.guide.tip, systemImage: "lightbulb.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 14)
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .readableWidth()
            .themedForm()
            .toolbarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
    }
}

/// "Measure with me" (option C): one measurement per screen, figure + steps + one big number, Next / Skip.
/// Values are typed straight into the log sheet's fields, so the list shows them when the guide closes.
struct MeasureGuideView: View {
    struct Step: Identifiable {
        let key: String
        let metric: BodyMetric
        var side: LimbSide?
        var last: Double?
        var id: String { key }
    }

    let steps: [Step]
    @Binding var text: [String: String]
    @State var index = 0
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    static func title(_ metric: BodyMetric, _ side: LimbSide?) -> String {
        guard let side else { return metric.label }
        return "\(metric.label) · \(side == .left ? "left" : "right")"
    }

    private var step: Step { steps[min(index, steps.count - 1)] }
    private var isLast: Bool { index >= steps.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            MeasureFigure(metric: step.metric, side: step.side)
                .padding(12)
                .frame(minHeight: 70, maxHeight: .infinity)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(step.metric.category.gradient))
                .overlay(alignment: .topTrailing) {
                    if let side = step.side {
                        Text(side == .left ? "LEFT" : "RIGHT")
                            .font(Theme.label(11)).tracking(1.2)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(.black.opacity(0.25)))
                            .padding(12)
                    }
                }
            Text(Self.title(step.metric, step.side)).font(Theme.display(28)).lineLimit(1).minimumScaleFactor(0.7)
            MeasureSteps(steps: step.metric.guide.steps, font: .footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
            entry
            LimeActionButton(title: isLast ? "Done" : "Next: \(Self.title(steps[index + 1].metric, steps[index + 1].side))") { advance() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .readableColumn()
        .background(Theme.bg.ignoresSafeArea())
        .animation(.snappy, value: index)
        .onAppear { focused = true }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardStrong))
                }
                .accessibilityLabel("Close")
                Spacer()
                Text("\(index + 1) / \(steps.count)").font(Theme.label(13)).foregroundStyle(Theme.muted)
                Spacer()
                Button("Skip") { advance() }
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.lime)
                    .frame(width: 34 + 20, alignment: .trailing)
            }
            HStack(spacing: 4) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule().fill(i <= index ? Theme.lime : Theme.cardStrong).frame(height: 5)
                }
            }
        }
    }

    private var entry: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField(step.metric.label, text: Binding(get: { text[step.key] ?? "" }, set: { text[step.key] = $0 }),
                          prompt: Text(step.last.map(MeasureFormat.value) ?? "–").foregroundStyle(.white.opacity(0.3)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(Theme.display(56).monospacedDigit())
                    .focused($focused)
                    .fixedSize()
                Text(step.metric.unit.uppercased()).font(Theme.label(15)).foregroundStyle(Theme.muted)
            }
            if let last = step.last {
                Text("Last time \(MeasureFormat.value(last)) \(step.metric.unit)").font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private func advance() {
        if isLast { dismiss() } else { index += 1 }
    }
}
