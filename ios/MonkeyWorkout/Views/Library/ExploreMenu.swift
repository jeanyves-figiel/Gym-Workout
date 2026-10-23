import SwiftUI
import WorkoutEngine

/// Explore top menu (#516, two-level): Exercises | Ready-made switch, then the ways to browse that side
/// (By muscle / By machine / By type, or Workouts / Plans) as labelled square tiles, so every section is named.
struct ExploreMenu: View {
    @Binding var mode: LibraryView.Mode
    /// Last section picked on each side, so switching back returns there.
    @State private var lastExercises: LibraryView.Mode = .muscles
    @State private var lastReady: LibraryView.Mode = .workouts

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                side(.exercises)
                side(.readyMade)
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardStrong))
            HStack(spacing: 6) {
                ForEach(mode.group.modes) { m in segment(m) }
            }
        }
        .sensoryFeedback(.selection, trigger: mode)
        .onChange(of: mode, initial: true) { _, m in
            if m.group == .exercises { lastExercises = m } else { lastReady = m }
        }
    }

    private func side(_ g: LibraryView.Mode.MenuGroup) -> some View {
        let on = mode.group == g
        return Button {
            guard !on else { return }
            withAnimation(.snappy(duration: 0.25)) { mode = g == .exercises ? lastExercises : lastReady }
        } label: {
            Label(g.label, systemImage: g.symbol)
                .font(Theme.label(15))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(on ? Theme.ink : .white.opacity(0.75))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background {
                    if on { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func segment(_ m: LibraryView.Mode) -> some View {
        let on = m == mode
        return Button {
            withAnimation(.snappy(duration: 0.25)) { mode = m }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: m.symbol).font(.system(size: 14, weight: .bold))
                Text(m.short).font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(on ? .white : .white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .padding(.horizontal, 4)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(m.gradient)
                        .shadow(color: m.tint.opacity(0.45), radius: 7, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(m.rawValue)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

extension LibraryView.Mode {
    /// Exercises (browse the catalogue) or Ready-made (whole workouts and plans).
    enum MenuGroup: CaseIterable {
        case exercises, readyMade
        var label: String { self == .exercises ? "Exercises" : "Ready-made" }
        var symbol: String { self == .exercises ? "dumbbell.fill" : "list.bullet.rectangle.fill" }
        var modes: [LibraryView.Mode] { self == .exercises ? [.muscles, .machines, .categories] : [.workouts, .routines, .programmes] }
    }

    var group: MenuGroup { [.workouts, .routines, .programmes].contains(self) ? .readyMade : .exercises }

    /// Tile label under the Exercises / Ready-made switch.
    var short: String {
        switch self {
        case .muscles: "By muscle"
        case .machines: "By machine"
        case .categories: "By type"
        case .workouts: "Workouts"
        case .routines: "Routines"
        case .programmes: "Plans"
        }
    }

    var symbol: String {
        switch self {
        case .muscles: "figure.strengthtraining.traditional"
        case .machines: "gearshape.2.fill"
        case .categories: "square.grid.2x2.fill"
        case .workouts: "list.bullet.rectangle.fill"
        case .routines: "figure.flexibility"
        case .programmes: "flag.checkered"
        }
    }

    /// Own colour per section, borrowed from the category palette.
    private var palette: WorkoutEngine.Category {
        switch self {
        case .muscles: .strength
        case .machines: .warmup
        case .categories: .stretch
        case .workouts: .cardio
        case .routines: .stretch
        case .programmes: .power
        }
    }

    var gradient: LinearGradient { palette.gradient }
    var tint: Color { palette.color }
}
