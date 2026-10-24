import SwiftUI

/// One pickable chip (#718), shared by the length, filter, place and option rows: white (or `onFill`) when picked,
/// a dark fill otherwise. The chip draws at `height`; its tap area is at least 44 pt tall.
struct SelectChip: View {
    let title: String
    var symbol: String?
    let on: Bool
    var onFill = AnyShapeStyle(Color.white)
    var offFill = AnyShapeStyle(Theme.card)
    var onInk: Color = Theme.ink
    var offInk: Color = .white.opacity(0.85)
    var size: CGFloat = 13
    var height: CGFloat = 40
    /// Shares the row with its neighbours; false: hugs its title.
    var fills = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
            }
            .font(Theme.label(size)).lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(on ? onInk : offInk)
            .padding(.horizontal, fills ? 4 : 10)
            .frame(maxWidth: fills ? .infinity : nil, minHeight: height)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? onFill : offFill))
            .padding(.vertical, max(0, (44 - height) / 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
