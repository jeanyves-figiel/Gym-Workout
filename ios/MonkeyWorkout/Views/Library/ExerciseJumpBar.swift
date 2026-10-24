import SwiftUI
import WorkoutEngine

/// Parts of the exercise page the jump bar leads to (#518).
enum ExercisePart: String, CaseIterable, Identifiable {
    case muscles, stats, setup, form, similar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .muscles: "Muscles"
        case .stats: "My stats"
        case .setup: "Setup"
        case .form: "Form"
        case .similar: "Similar"
        }
    }

    var symbol: String {
        switch self {
        case .muscles: "figure.arms.open"
        case .stats: "chart.line.uptrend.xyaxis"
        case .setup: "gearshape.2.fill"
        case .form: "checkmark.seal.fill"
        case .similar: "square.grid.2x2.fill"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .muscles: WorkoutEngine.Category.strength.gradient
        case .stats: WorkoutEngine.Category.power.gradient
        case .setup: WorkoutEngine.Category.warmup.gradient
        case .form: WorkoutEngine.Category.mobility.gradient
        case .similar: WorkoutEngine.Category.cardio.gradient
        }
    }
}

/// Sticky jump bar (#518, design A from `exercise-page-nav/proposals.png`): square chips that pin under the
/// title once scrolled; the part on screen lights up in its colour, a tap scrolls to it.
struct ExerciseJumpBar: View {
    let parts: [ExercisePart]
    let active: ExercisePart?
    let jump: (ExercisePart) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(parts) { p in
                        Button { jump(p) } label: { chip(p, on: p == active) }
                            .buttonStyle(.plain)
                            .id("chip-\(p.rawValue)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onChange(of: active) { _, p in
                guard let p else { return }
                withAnimation(.snappy) { proxy.scrollTo("chip-\(p.rawValue)", anchor: .center) }
            }
        }
        .solidPinnedHeader()
    }

    private func chip(_ p: ExercisePart, on: Bool) -> some View {
        Label(p.title, systemImage: p.symbol)
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(on ? .white : Theme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(on ? AnyShapeStyle(p.gradient) : AnyShapeStyle(Theme.card))
            }
            .animation(.snappy, value: on)
    }
}

/// Reports each part's frame in the page's scroll space: parts with nothing to show get no chip, and the part
/// under the bar lights up.
struct ExercisePartFrames: PreferenceKey {
    static let defaultValue: [ExercisePart: CGRect] = [:]
    static func reduce(value: inout [ExercisePart: CGRect], nextValue: () -> [ExercisePart: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension ExerciseJumpBar {
    static let space = "exercisePage"
    /// Height of the pinned bar: a jump lands the part just under it.
    static let height: CGFloat = 60
}

extension View {
    /// Marks a part of the exercise page as a jump-bar target.
    func exercisePart(_ part: ExercisePart) -> some View {
        background(alignment: .top) {
            // Scroll target sits one bar height above the part so the pinned bar doesn't cover its top.
            Color.clear.frame(height: 1).alignmentGuide(.top) { _ in ExerciseJumpBar.height }.id(part)
        }
        .background {
            GeometryReader { g in
                Color.clear.preference(key: ExercisePartFrames.self, value: [part: g.frame(in: .named(ExerciseJumpBar.space))])
            }
        }
    }
}
