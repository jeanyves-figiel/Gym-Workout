import SwiftUI
import WatchKit

// iPhone → Watch start prompt (#347): the iPhone started a workout and woke this Watch.

/// Join card: the workout and one big START; Not now leaves the Watch alone.
struct PhoneStartView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let theme = store.theme
        let w = store.phoneWorkout
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                switch theme {
                case .colour: colour(w)
                case .tiles: tiles(w)
                case .game: game(w)
                }
                LimeButton(title: theme == .game ? "▶ GO!" : "▶ START ON WATCH") {
                    Task { await store.trackPhoneWorkout() }
                }
                .accessibilityHint("Tracks heart rate and calories and shows the iPhone workout controls")
                Button { store.declineOffer() } label: {
                    Text("Not now").font(W.label(12)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(Capsule().fill(.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
        }
        .modifier(ThemeBackground(theme: theme, colour: W.gradient(w.tint, 0x8A3DFF), glow: theme == .game ? 0x8A3DFF : w.tint))
        .onAppear { WKInterfaceDevice.current().play(.start) }
    }

    private func summary(_ w: (title: String, estMin: Int?, exercises: Int?, tint: UInt32)) -> String {
        [w.estMin.map { "\($0)'" }, w.exercises.map { "\($0) ex" }].compactMap { $0 }.joined(separator: " · ")
    }

    private func colour(_ w: (title: String, estMin: Int?, exercises: Int?, tint: UInt32)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(text: "📱 Started on iPhone", color: .white.opacity(0.9))
            if !summary(w).isEmpty { Text(summary(w)).font(W.label(10)).opacity(0.85) }
            Text(w.title).font(W.display(22)).lineLimit(2).minimumScaleFactor(0.6)
        }
        .padding(.bottom, 6)
    }

    private func tiles(_ w: (title: String, estMin: Int?, exercises: Int?, tint: UInt32)) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Eyebrow(text: "📱 iPhone", color: W.lime)
            HStack(spacing: 7) {
                Image(systemName: "iphone.radiowaves.left.and.right").font(.system(size: 13, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.28)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(w.title).font(W.display(15)).lineLimit(2).minimumScaleFactor(0.6)
                    Text([summary(w), "on iPhone"].filter { !$0.isEmpty }.joined(separator: " · ")).font(W.label(9)).opacity(0.85)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(W.gradient(w.tint, 0x8A3DFF)))
        }
        .padding(.bottom, 6)
    }

    private func game(_ w: (title: String, estMin: Int?, exercises: Int?, tint: UInt32)) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Eyebrow(text: "Quest!", color: W.lime)
            HStack(alignment: .bottom, spacing: 2) {
                MonkeyFace(mood: .fired, gear: store.snapshot.game?.rank.gear)
                Text("Phone started \(w.title). Join me?")
                    .font(W.label(11)).foregroundStyle(W.ink)
                    .lineLimit(3).minimumScaleFactor(0.8)
                    .padding(.horizontal, 7).padding(.vertical, 5)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 11, bottomLeadingRadius: 3, bottomTrailingRadius: 11,
                                                       topTrailingRadius: 11, style: .continuous).fill(.white))
            }
            if let ex = w.exercises {
                Text("+\(WGame.xp(sets: ex * 3)) XP · \(ex) bosses").font(W.label(10)).foregroundStyle(W.lime)
            }
        }
        .padding(.bottom, 4)
    }
}

/// Heart rate while the Watch tracks an iPhone workout (#347), with a way to stop tracking.
struct TrackingBar: View {
    @Environment(WatchStore.self) private var store
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        if workout.phoneSessionId != nil {
            HStack(spacing: 6) {
                Text(workout.heartRate.map { "♥ \(Int($0))" } ?? "♥ --").font(W.label(11)).foregroundStyle(W.color(0xFF5A75))
                Text("\(Int(workout.activeKcal)) kcal").font(W.label(11))
                Spacer(minLength: 0)
                Button { store.stopTracking() } label: {
                    Image(systemName: "stop.fill").font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24).background(Circle().fill(.white.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop tracking on Watch")
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(.black.opacity(0.25)))
        }
    }
}
