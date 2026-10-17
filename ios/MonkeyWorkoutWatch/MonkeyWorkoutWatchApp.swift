import HealthKit
import SwiftUI
import WatchKit

/// The iPhone wakes the Watch app with a workout configuration when a workout starts there (#347).
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            if let store = WatchStore.current { store.phoneStarted() } else { WatchStore.pendingPhoneStart = true }
        }
    }
}

@main
struct MonkeyWorkoutWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    @State private var store = WatchStore()
    @State private var workout = WorkoutManager.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
                .environment(workout)
        }
    }
}

enum W {
    static let lime = Color(red: 0.80, green: 1.0, blue: 0.24)
    static let ink = Color(red: 0.04, green: 0.05, blue: 0.06)
    static let card = Color.white.opacity(0.10)
    /// Side margin of every screen (#389): keeps text off the rounded display edge.
    static let edge: CGFloat = 8

    static func color(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// The colour mixed halfway with white, for big numbers on its own colour wash.
    static func light(_ v: UInt32, _ amount: Double = 0.55) -> Color {
        func c(_ x: UInt32) -> Double { Double(x & 0xFF) / 255 * (1 - amount) + amount }
        return Color(red: c(v >> 16), green: c(v >> 8), blue: c(v))
    }

    static func gradient(_ a: UInt32, _ b: UInt32? = nil) -> LinearGradient {
        LinearGradient(colors: [color(a), color(b ?? a).opacity(b == nil ? 0.7 : 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded) }
    static func label(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .heavy, design: .rounded) }

    static let efforts: [(rir: Int, title: String, color: Color)] = [
        (0, "Fail", color(0xFF3D5A)), (1, "1 left", color(0xFF7A3D)), (2, "2 left", color(0xFFC23D)),
        (3, "3 left", lime), (4, "4+ easy", color(0x3DFFB0)),
    ]
    /// Second colour of each effort's gradient.
    static let effortEnd: [Color] = [color(0xB0105A), color(0xFF3D5A), color(0xFF7A3D), color(0x7FD320), color(0x1E9BFF)]
}

struct Eyebrow: View {
    let text: String
    var color: Color = .white.opacity(0.7)

    var body: some View {
        Text(text.uppercased()).font(W.label(10)).tracking(1).foregroundStyle(color).lineLimit(1)
    }
}

/// Bold white screen title (#389), in place of the grey system navigation title.
struct ScreenTitle: View {
    let text: String

    var body: some View {
        Text(text).font(W.display(18)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Screen side margins (#389).
    func watchMargins() -> some View { padding(.horizontal, W.edge) }

    /// Main button pinned at the bottom (#389): always visible, the list scrolls under it.
    func pinnedButton(_ title: String, action: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom, spacing: 4) {
            LimeButton(title: title, action: action)
                .controlSize(.small)
                .watchMargins()
                .padding(.top, 10)
                // Rows fade out under the button instead of showing around it.
                .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.9), .black], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom))
        }
    }
}

struct LimeButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(W.label(14)).foregroundStyle(W.ink).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(W.lime)
        .buttonBorderShape(.capsule)
        .shadow(color: W.lime.opacity(0.45), radius: 8)
    }
}

/// Root: mirrors an iPhone workout when one runs, otherwise browse or run a workout on the Watch.
struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    @State private var player: WatchPlayer?
    @State private var locked = false

    var body: some View {
        #if DEBUG
        if let screen = Demo.screen { Demo.view(screen) } else { main }
        #else
        main
        #endif
    }

    private var main: some View {
        screens
            .onAppear(perform: startFromActionButton)
            .onChange(of: ActionButton.shared.startRequested) { _, on in if on { startFromActionButton() } }
    }

    /// First Action button press (#349): start Next up (Pro lock as on the home screen).
    private func startFromActionButton() {
        let action = ActionButton.shared
        guard action.startRequested else { return }
        action.startRequested = false
        guard player == nil, store.live == nil, let s = store.next ?? store.snapshot.sessions.first(where: { !$0.done }) else { return }
        if store.snapshot.pro == false { locked = true } else { player = WatchPlayer(session: s) }
    }

    @ViewBuilder private var screens: some View {
        if store.offered, player == nil {
            PhoneStartView()
        } else if let live = store.live, player == nil {
            MirrorView(live: live)
        } else if let player {
            PlayerView(player: player) { self.player = nil }
        } else {
            NavigationStack {
                // Pro (#126): starting on the Watch needs Pro; mirroring an iPhone workout stays free.
                HomeView { s in if store.snapshot.pro == false { locked = true } else { player = WatchPlayer(session: s) } }
            }
            .sheet(isPresented: $locked) { ProLockView() }
        }
    }
}
