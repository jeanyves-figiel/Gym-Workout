import SwiftUI

/// Day strip that slides day by day under a centre lens (#486, design B), shared by Train's week strip and Fuel (#510).
/// One continuous run of days `range` (offsets from today); 3 blank cells each side let the end days reach the lens.
/// The middle day is big, neighbours shrink and fade; the day that settles under the lens is picked, and a new
/// `selected` glides under it.
struct LensDayStrip<Cell: View>: View {
    var range: ClosedRange<Int>
    /// Day under the lens, in days from today.
    var selected: Int
    var onPick: (Int) -> Void
    @ViewBuilder var cell: (Int) -> Cell
    /// Leftmost cell in view; the day under the lens is `first + 3`.
    @State private var first: Int?
    @State private var width: CGFloat = 0
    /// Pick after the strip settles, so the content doesn't rebuild under the finger.
    @State private var settle: Task<Void, Never>?

    static var visible: Int { 7 }
    static var spacing: CGFloat { 5 }

    var body: some View {
        let w = width
        let step = (w - Self.spacing * CGFloat(Self.visible - 1)) / CGFloat(Self.visible) + Self.spacing
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Self.spacing) {
                    ForEach((range.lowerBound - 3)...(range.upperBound + 3), id: \.self) { o in
                        Group {
                            if range.contains(o) { cell(o) } else { Color.clear.accessibilityHidden(true) }
                        }
                        .containerRelativeFrame(.horizontal, count: Self.visible, spacing: Self.spacing)
                        .visualEffect { content, geo in
                            let d = step > 0 ? abs(geo.frame(in: .scrollView).midX - w / 2) / step : 0
                            let scale = 1.18 - min(d, 1) * 0.22 - max(0, min(d, 4) - 1) * 0.08
                            return content.scaleEffect(scale).opacity(max(0.35, 1 - max(0, d - 1) * 0.22))
                        }
                        .id(o)
                    }
                }
                .padding(.vertical, 5)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $first, anchor: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onAppear {
                let start = lensStart
                first = start
                proxy.scrollTo(start, anchor: .leading)
            }
            // A tap or the content picking another day glides it under the lens.
            .onChange(of: selected) {
                let start = lensStart
                if first != start { withAnimation(.snappy) { proxy.scrollTo(start, anchor: .leading) } }
            }
            // Slide = pick: the day that settles under the lens is picked.
            .onChange(of: first) { _, f in
                settle?.cancel()
                guard let f else { return }
                let centre = min(max(f + 3, range.lowerBound), range.upperBound)
                guard centre != selected else { return }
                settle = Task {
                    try? await Task.sleep(for: .milliseconds(220))
                    guard !Task.isCancelled else { return }
                    onPick(centre)
                }
            }
            .onDisappear { settle?.cancel() }
        }
    }

    private var lensStart: Int { min(max(selected, range.lowerBound), range.upperBound) - 3 }
}
