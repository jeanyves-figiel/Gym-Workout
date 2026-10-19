import SwiftUI
import WorkoutEngine

/// Explore top menu (#483, design C): one rounded card bar like the 2D/3D switch.
/// The picked section widens, fills with its own colour and shows its name; the others show only their icon.
struct ExploreMenu: View {
    @Binding var mode: LibraryView.Mode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LibraryView.Mode.allCases) { m in segment(m) }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cardStrong))
        .sensoryFeedback(.selection, trigger: mode)
    }

    private func segment(_ m: LibraryView.Mode) -> some View {
        let on = m == mode
        return Button {
            withAnimation(.snappy(duration: 0.25)) { mode = m }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: m.symbol)
                    .font(.system(size: on ? 16 : 17, weight: .bold))
                if on {
                    Text(m.short)
                        .font(Theme.label(14))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(on ? .white : m.tint)
            // Picked segment takes the free width; the others stay compact icon tiles.
            .frame(maxWidth: on ? .infinity : nil)
            .frame(width: on ? nil : 50, height: 46)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(m.gradient)
                        .shadow(color: m.tint.opacity(0.5), radius: 8, y: 4)
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
    /// Dock label: short so all five fit on the smallest iPhone.
    var short: String {
        switch self {
        case .muscles: "Muscles"
        case .machines: "Machines"
        case .categories: "Types"
        case .workouts: "Workouts"
        case .programmes: "Plans"
        }
    }

    var symbol: String {
        switch self {
        case .muscles: "figure.strengthtraining.traditional"
        case .machines: "gearshape.2.fill"
        case .categories: "square.grid.2x2.fill"
        case .workouts: "list.bullet.rectangle.fill"
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
        case .programmes: .power
        }
    }

    var gradient: LinearGradient { palette.gradient }
    var tint: Color { palette.color }
}
