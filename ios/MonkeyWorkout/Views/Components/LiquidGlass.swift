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

    /// Screens with a pinned search, chips or jump bar under the title (#727, design A from
    /// `pinned-headers/proposals.png`): the title bar is solid app background, so it and the pinned row read as one
    /// block and nothing scrolls through the glass above them.
    @ViewBuilder func solidNavBar() -> some View {
        if #available(iOS 26, *) {
            toolbarBackground(Theme.bg, for: .navigationBar)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
                .scrollEdgeEffectHidden(true, for: .top)
        } else {
            toolbarBackground(Theme.bg, for: .navigationBar)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        }
    }

    /// The pinned row under a `solidNavBar()`: opaque app background with a soft fade below, so cards slide under it.
    func solidPinnedHeader() -> some View {
        background(Theme.bg)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Theme.bg, Theme.bg.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 12)
                    .offset(y: 12)
                    .allowsHitTesting(false)
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
