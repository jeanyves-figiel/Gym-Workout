import SwiftUI
import UIKit

// MARK: - Pull to refresh that stays on its screen (#1005)
//
// SwiftUI's `.refreshable` is an environment value: every sheet or pushed screen presented from inside it inherits
// it, so their ScrollView pulls to refresh instead of letting the sheet swipe down (Add workout from Train could not
// be closed with the gesture). `.scopedRefreshable` puts a UIRefreshControl on the enclosing scroll view only.
// Rule: never use `.refreshable` in the app; apply this to the scroll view's content (inside the ScrollView).

extension View {
    /// Pull to refresh on the scroll view this content sits in, and nowhere else. `enabled: false` in a sheet,
    /// where the pull must close the sheet instead.
    @ViewBuilder func scopedRefreshable(enabled: Bool = true, _ action: @escaping @MainActor () async -> Void) -> some View {
        if enabled {
            background(RefreshAttacher(action: action).frame(width: 0, height: 0).allowsHitTesting(false))
        } else {
            self
        }
    }
}

private struct RefreshAttacher: UIViewRepresentable {
    let action: @MainActor () async -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Probe {
        let v = Probe()
        v.isUserInteractionEnabled = false
        v.coordinator = context.coordinator
        context.coordinator.action = action
        return v
    }

    func updateUIView(_ v: Probe, context: Context) {
        context.coordinator.action = action
    }

    @MainActor final class Coordinator: NSObject {
        var action: (@MainActor () async -> Void)?

        func attach(to scroll: UIScrollView) {
            if let c = scroll.refreshControl, c.allTargets.contains(AnyHashable(self)) { return }
            let c = UIRefreshControl()
            c.addTarget(self, action: #selector(pulled(_:)), for: .valueChanged)
            scroll.refreshControl = c
        }

        @objc func pulled(_ control: UIRefreshControl) {
            Task { @MainActor in
                await action?()
                control.endRefreshing()
            }
        }
    }

    final class Probe: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var v = superview
            while let s = v {
                if let scroll = s as? UIScrollView {
                    coordinator?.attach(to: scroll)
                    return
                }
                v = s.superview
            }
        }
    }
}
