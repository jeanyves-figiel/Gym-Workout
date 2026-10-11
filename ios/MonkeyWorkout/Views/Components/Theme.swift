import SwiftUI
import WorkoutEngine

/// Bold, dark-first visual language: near-black canvas, heavy rounded type, one signature lime,
/// and a vivid gradient per training category.
enum Theme {
    static let bg = Color(red: 0.035, green: 0.04, blue: 0.055)
    static let card = Color.white.opacity(0.06)
    static let cardStrong = Color.white.opacity(0.10)
    static let stroke = Color.white.opacity(0.10)
    static let lime = Color(red: 0.80, green: 1.0, blue: 0.24)
    static let ink = Color(red: 0.04, green: 0.05, blue: 0.06)
    static let muted = Color.white.opacity(0.55)

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded) }
    static func label(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .heavy, design: .rounded) }

    /// 0 → cool lime, 1 → hot red. Used for muscle heat.
    static func heat(_ v: Double) -> Color {
        let h = max(0, min(1, v))
        return Color(hue: 0.22 * (1 - h), saturation: 0.85, brightness: 1)
    }
}

private func hex(_ v: UInt32) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

extension WorkoutEngine.Category {
    var colors: [Color] {
        switch self {
        case .warmup: [hex(0xFF8A00), hex(0xFFC93D)]
        case .power: [hex(0xFF2D55), hex(0xFF6FB5)]
        case .strength: [hex(0x2F6BFF), hex(0x8A4DFF)]
        case .mobility: [hex(0xA64DFF), hex(0xFF4DD8)]
        case .cardio: [hex(0x00C9A7), hex(0x2EC5FF)]
        case .stretch: [hex(0x1ED98A), hex(0xB6FF6B)]
        }
    }

    var color: Color { colors[0] }
    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }

    var symbol: String {
        switch self {
        case .warmup: "flame.fill"
        case .power: "bolt.fill"
        case .strength: "dumbbell.fill"
        case .mobility: "figure.flexibility"
        case .cardio: "heart.fill"
        case .stretch: "figure.cooldown"
        }
    }
}

extension BlockKind {
    var gradient: LinearGradient { category.gradient }
    var symbol: String { category.symbol }
}

// MARK: - Building blocks

struct Card: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.stroke))
    }
}

/// Selectable gradient card (#88). Picked: full gradient + ring. Unpicked: only the fill is dimmed and
/// desaturated (thin outline instead of a ring); the white text on top stays full opacity so it still reads.
struct SelectableGradient: ViewModifier {
    let fill: AnyShapeStyle
    let selected: Bool
    var cornerRadius: CGFloat = 24
    var ring: Color = .white

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background {
                shape.fill(fill)
                    .saturation(selected ? 1 : 0.6)
                    .opacity(selected ? 1 : 0.42)
            }
            .overlay(shape.strokeBorder(selected ? ring : Color.white.opacity(0.22), lineWidth: selected ? 3 : 1))
            .animation(.spring(duration: 0.25), value: selected)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(Card(padding: padding)) }

    func selectableGradient<S: ShapeStyle>(_ fill: S, selected: Bool, cornerRadius: CGFloat = 24, ring: Color = .white) -> some View {
        modifier(SelectableGradient(fill: AnyShapeStyle(fill), selected: selected, cornerRadius: cornerRadius, ring: ring))
    }

    /// Explore-style card: vivid gradient fill, white type. The gradient counterpart of `card()`.
    func gradientCard(_ gradient: LinearGradient, padding: CGFloat = 16) -> some View {
        foregroundStyle(.white)
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(gradient))
    }

    /// Dark canvas behind system forms/lists; keyboard dismisses on scroll or via a Done button.
    func themedForm() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .bold()
                }
            }
    }

    /// Small uppercase section label.
    func eyebrow() -> some View {
        font(Theme.label(11)).tracking(1.6).foregroundStyle(Theme.muted).textCase(.uppercase)
    }
}

struct CategoryPill: View {
    let category: WorkoutEngine.Category
    var title: String?
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: category.symbol)
            Text((title ?? category.label).uppercased()).tracking(1)
        }
        .font(Theme.label(compact ? 10 : 12))
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.vertical, compact ? 4 : 6)
        .background(Capsule().fill(category.gradient))
    }
}

struct MuscleChip: View {
    let muscle: Muscle
    var primary = true

    var body: some View {
        Text(muscle.name)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(primary ? Theme.ink : .white)
            .background {
                if primary { Capsule().fill(Theme.lime) } else { Capsule().strokeBorder(Color.white.opacity(0.35)) }
            }
            .accessibilityLabel("\(muscle.name), \(primary ? "primary" : "secondary")")
    }
}

/// Wrapping row of muscle chips: primary filled, secondary outlined.
struct MuscleChips: View {
    let primary: [Muscle]
    var secondary: [Muscle] = []

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(primary) { MuscleChip(muscle: $0, primary: true) }
            ForEach(secondary.filter { !primary.contains($0) }) { MuscleChip(muscle: $0, primary: false) }
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 10
    var colors: [Color] = [Theme.lime, Color(red: 0.2, green: 0.9, blue: 0.6)]

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(AngularGradient(colors: colors + [colors[0]], center: .center), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: progress)
        }
    }
}

/// Session timeline stripe — one gradient segment per block, width ∝ minutes.
struct BlockStripe: View {
    let blocks: [Block]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let total = CGFloat(max(1, blocks.reduce(0) { $0 + max(1, $1.targetMin) }))
            let gaps = CGFloat(max(0, blocks.count - 1)) * 3
            HStack(spacing: 3) {
                ForEach(blocks) { b in
                    Capsule()
                        .fill(b.kind.gradient)
                        .frame(width: max(4, (geo.size.width - gaps) * CGFloat(max(1, b.targetMin)) / total))
                }
            }
        }
        .frame(height: height)
    }
}

struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.display(26)).monospacedDigit()
            Text(label).eyebrow()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

/// White ~20 % rounded tile holding an icon, left of Explore-style gradient cards.
struct IconTile: View {
    let symbol: String
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .bold))
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(.white.opacity(0.2)))
    }
}

/// Explore-style section: gradient card with an icon tile and heavy title over its content.
struct GradientSection<Content: View>: View {
    let symbol: String
    let title: String
    let gradient: LinearGradient
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconTile(symbol: symbol, size: 40)
                Text(title).font(Theme.display(20)).lineLimit(2).minimumScaleFactor(0.8)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gradientCard(gradient)
    }
}

struct LimeButtonStyle: ButtonStyle {
    var fill: Color = Theme.lime
    var text: Color = Theme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(17))
            .tracking(1.5)
            .foregroundStyle(text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Capsule().fill(fill))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: fill.opacity(0.35), radius: configuration.isPressed ? 4 : 16, y: 6)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
