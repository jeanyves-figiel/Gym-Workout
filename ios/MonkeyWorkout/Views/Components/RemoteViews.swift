import SwiftUI
import WorkoutEngine

// Over-the-air prompts (#583, designs A + B + C from `ota-updates/proposals.png`).

private func gradient(_ a: UInt32, _ b: UInt32) -> LinearGradient {
    LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// A: newer build recommended. Top of Train, closable per recommended build.
struct UpdateBanner: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("remote.bannerClosed") private var closedFor = -1
    private var remote: Remote { .shared }

    var body: some View {
        if remote.updateNeed == .recommended, closedFor != remote.config.recommendedBuild {
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.25)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(remote.update.title).font(Theme.label(16)).lineLimit(1)
                    Text(remote.update.body).font(.caption.weight(.semibold)).opacity(0.9).lineLimit(2)
                }
                Spacer(minLength: 4)
                Button("Update") { openURL(remote.updateURL) }
                    .font(Theme.label(14))
                    .foregroundStyle(Color(hex: 0x7A2CFF))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                Button { closedFor = remote.config.recommendedBuild } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).opacity(0.8)
                }
                .accessibilityLabel("Later")
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18).fill(gradient(0x2F6BFF, 0xD63CFF)))
            .buttonStyle(.plain)
        }
    }
}

/// B: this build is too old to keep working. Covers the whole app until updated.
struct RequiredUpdateView: View {
    @Environment(\.openURL) private var openURL
    private var remote: Remote { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Text("🐒").font(.system(size: 40))
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.25)))
            Text(remote.update.title).font(Theme.display(34)).fixedSize(horizontal: false, vertical: true)
            Text(remote.update.body).font(.body.weight(.semibold)).opacity(0.92)
            Spacer()
            Button { openURL(remote.updateURL) } label: {
                Text("Update now").font(Theme.label(17)).foregroundStyle(Color(hex: 0x7A2CFF))
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white))
            }
            .buttonStyle(.plain)
            Text("Your workouts stay on this phone.").font(.footnote.weight(.semibold)).opacity(0.8)
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: Theme.readableWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color(hex: 0xFF3C7A), Color(hex: 0x7A2CFF), Color(hex: 0x2F6BFF)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
    }
}

/// C: a feature the server paused, shown over the feature's screen.
struct PausedCard: View {
    let message: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.25)))
                    Text("Paused for now").font(Theme.label(18))
                }
                Text(message).font(.subheadline.weight(.semibold)).opacity(0.95)
                Button { dismiss() } label: {
                    Text("OK").font(Theme.label(15)).frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.25)))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20).fill(gradient(0xFF8A00, 0xFF3C7A)))
            .padding(20)
            .frame(maxWidth: Theme.readableWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }
}

extension View {
    /// The feature's screen, or the paused card when the server switched `flag` off (#583).
    func remotePaused(_ flag: RemoteFlag) -> some View {
        modifier(RemotePaused(flag: flag))
    }
}

private struct RemotePaused: ViewModifier {
    let flag: RemoteFlag

    func body(content: Content) -> some View {
        if let m = Remote.shared.pausedMessage(flag) { PausedCard(message: m) } else { content }
    }
}
