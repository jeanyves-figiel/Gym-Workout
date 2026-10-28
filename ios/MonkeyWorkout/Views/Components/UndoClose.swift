import SwiftUI
import UIKit

// MARK: - Close + Undo (#285)
//
// A screen closed with unsaved input (X, Cancel, swipe down or back) closes at once, and a gradient bar
// (design A from `cancel-confirm/toasts.png`) offers Undo for a few seconds: Undo reopens the screen with
// every value back. Untouched screens close silently. Screens opt in with `.undoableClose(_:offer:)`.

/// What a closed screen kept, and how to bring it back.
struct UndoOffer {
    /// "Programme closed".
    var title: String
    /// What was entered, e.g. "4 steps · Strength block".
    var detail: String
    /// SF Symbol for the icon tile.
    var symbol: String = "arrow.uturn.backward"
    var colors: [Color] = UndoOffer.warm
    /// Reopen full screen (screens that were a full-screen cover) instead of as a sheet.
    var fullScreen = false
    /// The screen rebuilt with the kept values. Captures values, never bindings or `@State`.
    var reopen: () -> AnyView
    /// Undo that puts a change back instead of reopening a screen (#342); `reopen` is then unused.
    var revert: (() -> Void)?

    static let warm = [Color(red: 1, green: 0.48, blue: 0.27), Color(red: 0.91, green: 0.27, blue: 0.37), Color(red: 0.76, green: 0.29, blue: 0.85)]
}

/// Held by a screen as `@State`. `done()` before closing on Save, so a saved screen offers no Undo.
final class CloseGuard {
    fileprivate(set) var saved = false
    func done() { saved = true }
    func reset() { saved = false }
}

extension View {
    /// Offers Undo when the screen is really closed (dismissed or popped, not covered by another screen)
    /// while `offer` is non-nil and the guard isn't `done()`. Build `offer` only when something was entered.
    func undoableClose(_ closeGuard: CloseGuard, offer: UndoOffer?) -> some View {
        background(CloseProbe(closeGuard: closeGuard, offer: offer).frame(width: 0, height: 0).allowsHitTesting(false))
    }
}

private struct CloseProbe: UIViewControllerRepresentable {
    let closeGuard: CloseGuard
    let offer: UndoOffer?

    func makeUIViewController(context: Context) -> ProbeController { ProbeController() }
    func updateUIViewController(_ vc: ProbeController, context: Context) {
        vc.closeGuard = closeGuard
        vc.offer = offer
    }
}

private final class ProbeController: UIViewController {
    var closeGuard: CloseGuard?
    var offer: UndoOffer?

    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
    }

    // `viewDidDisappear`, not `viewWillDisappear`: a swipe down or back swipe that's let go halfway brings
    // the screen back without closing it.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard let offer, closeGuard?.saved != true, isClosing else { return }
        UndoCloseCenter.shared.show(offer)
    }

    /// The sheet or pushed screen holding this probe is going away (not just covered by another one).
    private var isClosing: Bool {
        var vc: UIViewController? = self
        while let current = vc {
            if current.isBeingDismissed || current.isMovingFromParent { return true }
            vc = current.parent
        }
        return false
    }
}

/// Shows the Undo bar above everything (own window, so sheets don't hide it) and reopens screens.
@MainActor
final class UndoCloseCenter {
    static let shared = UndoCloseCenter()
    static let seconds: Double = 6

    /// Adds the app's environment (model, health, …) to a reopened screen. Set once by the app.
    var environment: (AnyView) -> AnyView = { $0 }

    private var window: PassthroughWindow?
    private let state = UndoBarState()

    /// Something was deleted at once (#539): no confirmation dialog, the Undo bar puts it back with `restore`.
    func deleted(_ title: String, detail: String = "", symbol: String = "trash.fill", restore: @escaping () -> Void) {
        Haptics.destructive()
        show(UndoOffer(title: title, detail: detail, symbol: symbol, reopen: { AnyView(EmptyView()) }, revert: restore), haptic: false)
    }

    func show(_ offer: UndoOffer, haptic: Bool = true) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        else { return }
        if window == nil || window?.windowScene !== scene {
            let w = PassthroughWindow(windowScene: scene)
            w.state = state
            w.windowLevel = .alert + 1
            let host = UIHostingController(rootView: UndoBarHost(state: state))
            host.view.backgroundColor = .clear
            w.rootViewController = host
            w.isHidden = false
            window = w
        }
        if haptic { Haptics.undo() }
        state.present(offer, lift: Self.tabBarLift())
        // Shown while the closed screen is still going away: measure the tab bar again once it is gone, so the bar
        // never sits on it (#857).
        Task { [state] in
            try? await Task.sleep(for: .milliseconds(600))
            let lift = Self.tabBarLift()
            guard state.shown != nil, lift != state.lift else { return }
            withAnimation(.spring(duration: 0.3)) { state.lift = lift }
        }
        UIAccessibility.post(notification: .announcement, argument: "\(offer.title). Undo available.")
    }

    func undo(_ offer: UndoOffer) {
        state.clear()
        Haptics.undo()
        if let revert = offer.revert { return revert() }
        let host = UIHostingController(rootView: environment(offer.reopen()))
        host.modalPresentationStyle = offer.fullScreen ? .fullScreen : .pageSheet
        Self.topController()?.present(host, animated: true)
    }

    /// Height the tab bar takes above the bottom safe area when it shows (no sheet over it), so the bar sits
    /// above it instead of covering it (#811).
    private static func tabBarLift() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow && !($0 is PassthroughWindow) })
                ?? scenes.flatMap(\.windows).first(where: { !($0 is PassthroughWindow) }),
              let root = window.rootViewController,
              root.presentedViewController == nil || root.presentedViewController?.isBeingDismissed == true,
              let tabs = tabController(in: root), !tabs.tabBar.isHidden, tabs.tabBar.alpha > 0.01
        else { return 0 }
        let top = tabs.tabBar.convert(tabs.tabBar.bounds, to: window).minY
        return max(0, window.bounds.height - window.safeAreaInsets.bottom - top)
    }

    private static func tabController(in vc: UIViewController) -> UITabBarController? {
        if let tabs = vc as? UITabBarController { return tabs }
        for child in vc.children { if let tabs = tabController(in: child) { return tabs } }
        return nil
    }

    private static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes.flatMap(\.windows).first { $0.isKeyWindow && !($0 is PassthroughWindow) }
            ?? scenes.flatMap(\.windows).first { !($0 is PassthroughWindow) }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
}

/// Touches go through except on the bar itself. SwiftUI answers every point with its hosting view, so the bar's
/// measured frame decides (#857): comparing against the hosting view let taps on Undo fall through to the app.
private final class PassthroughWindow: UIWindow {
    fileprivate weak var state: UndoBarState?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let state, state.shown != nil, state.barFrame.insetBy(dx: -4, dy: -4).contains(point) else { return nil }
        return super.hitTest(point, with: event) ?? rootViewController?.view
    }
}

@MainActor @Observable
private final class UndoBarState {
    struct Shown: Identifiable { let id = UUID(); let offer: UndoOffer }
    var shown: Shown?
    /// Room for the tab bar under the bar.
    var lift: CGFloat = 0
    /// Where the bar is, in window points: only touches there are taken.
    var barFrame: CGRect = .zero
    private var timer: Task<Void, Never>?

    func present(_ offer: UndoOffer, lift: CGFloat = 0) {
        let next = Shown(offer: offer)
        self.lift = lift
        withAnimation(.spring(duration: 0.35)) { shown = next }
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(UndoCloseCenter.seconds))
            guard !Task.isCancelled, self?.shown?.id == next.id else { return }
            self?.clear()
        }
    }

    func clear() {
        timer?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { shown = nil }
        barFrame = .zero
    }
}

private struct UndoBarHost: View {
    let state: UndoBarState

    var body: some View {
        VStack {
            Spacer()
            if let shown = state.shown {
                UndoBar(offer: shown.offer, undo: { UndoCloseCenter.shared.undo(shown.offer) }, close: { state.clear() })
                    .id(shown.id)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { state.barFrame = $0 }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8 + state.lift)
        .frame(maxWidth: Theme.readableWidth)
        .frame(maxWidth: .infinity)
    }
}

/// Design A: gradient bar, icon tile, what was closed, lime Undo inside a draining countdown ring.
/// Grabber on top (#811, design B from `undo-dismiss/proposals.png`): swipe down or tap the bar (outside
/// Undo) closes it at once; the first bars say so.
struct UndoBar: View {
    let offer: UndoOffer
    let undo: () -> Void
    var close: () -> Void = {}
    @State private var left: Double = 1
    @AppStorage("undoBarDismissHints") private var hintsShown = 0
    @State private var hint = false

    var body: some View {
        VStack(spacing: 4) {
            if hint {
                Text("Swipe down or tap to dismiss")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .accessibilityHidden(true)
            }
            bar
        }
        .onAppear {
            hint = hintsShown < 3
            if hint { hintsShown += 1 }
        }
    }

    private var bar: some View {
        HStack(spacing: 12) {
            Image(systemName: offer.symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(offer.title).font(Theme.label(15)).foregroundStyle(.white).lineLimit(1)
                if !offer.detail.isEmpty {
                    Text(offer.detail).font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: undo) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle().stroke(Theme.ink.opacity(0.2), lineWidth: 3)
                        Circle().trim(from: 0, to: left)
                            .stroke(Theme.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 10, weight: .black))
                    }
                    .frame(width: 22, height: 22)
                    Text("Undo").font(Theme.label(14))
                }
                .foregroundStyle(Theme.ink)
                .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 7)
                .background(Capsule().fill(Theme.lime))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo, reopen \(offer.title.lowercased())")
        }
        .padding(10)
        .padding(.top, 6)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: offer.colors, startPoint: .leading, endPoint: .trailing))
                .shadow(color: (offer.colors.dropFirst().first ?? .black).opacity(0.45), radius: 14, y: 6)
        )
        .overlay(alignment: .top) {
            Capsule().fill(.white.opacity(0.6)).frame(width: 36, height: 4).padding(.top, 5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: close)
        .gesture(DragGesture(minimumDistance: 10).onEnded { if $0.translation.height > 20 { close() } })
        .onAppear { withAnimation(.linear(duration: UndoCloseCenter.seconds)) { left = 0 } }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Undo", undo)
        .accessibilityAction(named: "Dismiss", close)
        .accessibilityAction(.escape, close)
    }
}

/// Short "a · b · c" detail line from the non-empty parts.
func undoDetail(_ parts: String?...) -> String {
    parts.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ")
}

/// A screen that was pushed (no X of its own), reopened by Undo as a sheet: own navigation stack and a close X.
struct UndoReopenedPush<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            content.toolbar { CloseToolbarItem { dismiss() } }
        }
    }
}
