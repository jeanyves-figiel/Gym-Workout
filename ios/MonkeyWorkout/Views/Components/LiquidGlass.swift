import SwiftUI

// MARK: - Liquid Glass (#616, designs A + C from `apple-tech-radar/batch3.html`)
//
// Glass only on system chrome: the tab bar floats over content and sheets show their glass edges. Gradient cards,
// the player and its solid lime Log stay as they are; no glass capsules over large titles (titles are in content).
// iOS 18 keeps the solid look.

extension View {
    /// Tab bar (A): iOS 26 floats the glass bar over content, always full size (never folds on scroll, #677).
    @ViewBuilder func glassTabBar() -> some View {
        if #available(iOS 26, *) {
            tabBarMinimizeBehavior(.never)
        } else {
            toolbarBackground(Theme.bg, for: .tabBar)
        }
    }

    /// Sheets (C): iOS 26 shows the sheet's own glass behind the content (cards on it untouched); iOS 18 keeps the
    /// app background. Use in place of `.background(Theme.bg.ignoresSafeArea())` on a sheet's content.
    @ViewBuilder func glassSheetBackground() -> some View {
        if #available(iOS 26, *) {
            scrollContentBackground(.hidden)
        } else {
            background(Theme.bg.ignoresSafeArea())
        }
    }
}
