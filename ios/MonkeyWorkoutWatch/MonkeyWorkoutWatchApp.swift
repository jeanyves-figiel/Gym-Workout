import SwiftUI

@main
struct MonkeyWorkoutWatchApp: App {
    @State private var store = WatchStore()
    @State private var workout = WorkoutManager()

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

    static func color(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
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
}

struct Eyebrow: View {
    let text: String
    var color: Color = .white.opacity(0.7)

    var body: some View {
        Text(text.uppercased()).font(W.label(10)).tracking(1).foregroundStyle(color).lineLimit(1)
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
    }
}

/// Root: mirrors an iPhone workout when one runs, otherwise browse or run a workout on the Watch.
struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    @State private var player: WatchPlayer?

    var body: some View {
        if let live = store.live, player == nil {
            MirrorView(live: live)
        } else if let player {
            PlayerView(player: player) { self.player = nil }
        } else {
            NavigationStack {
                HomeView { player = WatchPlayer(session: $0) }
            }
        }
    }
}
