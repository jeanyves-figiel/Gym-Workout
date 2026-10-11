import SwiftUI
import WorkoutEngine

/// M / F body figure tiles with a live figure preview (#110). Onboarding and Account → Body & Health.
/// Display only: the figure drawn on muscle maps, separate from the optional sex / gender fields.
struct BodyFigurePicker: View {
    @Binding var selection: BodyFigure
    var height: CGFloat = 150

    /// Sample load so the preview shows the heat colours.
    private static let sampleHeat: [Muscle: Double] = [.chest: 0.5, .quads: 0.85, .abs: 0.3, .frontDelts: 0.35, .biceps: 0.2]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(BodyFigure.allCases) { f in
                tile(f)
            }
        }
    }

    private func tile(_ f: BodyFigure) -> some View {
        let on = selection == f
        return Button {
            withAnimation(.spring(duration: 0.3)) { selection = f }
        } label: {
            VStack(spacing: 4) {
                BodyMapView(side: .front, heat: Self.sampleHeat, showLabel: false, onColor: on, figure: f)
                    .frame(height: height)
                Text(f.label).font(Theme.display(30))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(on ? AnyShapeStyle(WorkoutEngine.Category.mobility.gradient) : AnyShapeStyle(Theme.card))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(on ? Theme.lime : Theme.stroke, lineWidth: on ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Theme.ink, Theme.lime)
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(f == .male ? "Male body figure" : "Female body figure")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
