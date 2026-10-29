import SwiftUI
import WorkoutEngine

/// Gradient of the HD animations card and welcome sheet (#932).
private let hdGradient = LinearGradient(colors: [Color(red: 0.61, green: 0.30, blue: 1), Color(red: 0.31, green: 0.49, blue: 0.99)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)

private func megabytes(_ bytes: Int64) -> String { "\(max(1, Int((Double(bytes) / 1_000_000).rounded()))) MB" }

/// A (#932): once per device, after sign-up and the tour (or after updating to this build): the light picture next to
/// the HD one, Download on Wi-Fi or Later. Settings → HD animations changes it later.
struct HDAnimationsOffer: View {
    @Environment(\.dismiss) private var dismiss
    private let hd = HDAnimations.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("HD MOVES · \(megabytes(hd.totalBytes))").font(Theme.label(11)).tracking(1.4).opacity(0.85)
                Text("Smoother moves,\nsharper muscles").font(Theme.display(30)).fixedSize(horizontal: false, vertical: true)
                Text("Every exercise in full detail: all the in-between poses, sharp muscles and machines. The app stays light until you want them.")
                    .font(.subheadline.weight(.semibold)).opacity(0.9)
                HStack(spacing: 8) {
                    preview(Image(uiImage: UIImage(named: ExerciseIllustrations.assetName("back-squat", frame: 4)) ?? UIImage()), "NOW")
                    preview(Image("hd-preview"), "HD")
                }
                Button {
                    hd.enable()
                    dismiss()
                } label: {
                    Label(hd.wifiOnly ? "Download HD (Wi-Fi)" : "Download HD", systemImage: "arrow.down.circle.fill")
                        .font(Theme.label(15)).foregroundStyle(Color(red: 0.48, green: 0.24, blue: 1))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hd.download")
                Button { later() } label: {
                    Text("Later").font(Theme.label(15)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hd.later")
                Text("Change it any time in Settings → HD animations.").font(.caption.weight(.semibold)).opacity(0.75)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(hdGradient))
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .toolbar { CloseToolbarItem { later() } }
    }

    private func later() {
        hd.offered = true
        dismiss()
    }

    private func preview(_ image: Image, _ tag: String) -> some View {
        image.resizable().aspectRatio(4 / 3, contentMode: .fit)
            .background(Color(red: 0.95, green: 0.94, blue: 0.91))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topLeading) {
                Text(tag).font(Theme.label(10)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.ink))
                    .padding(6)
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// B (#932): Settings → Look: HD animations switch, download progress, Wi-Fi only.
struct HDAnimationsSettingsCard: View {
    private let hd = HDAnimations.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("HD animations").font(Theme.display(17)).lineLimit(1).minimumScaleFactor(0.75)
                    Text(detail).font(.caption.weight(.semibold)).opacity(0.85)
                }
                Spacer(minLength: 6)
                if hd.status == .downloading {
                    Text("\(Int(hd.progress * 100))%").font(Theme.display(20)).monospacedDigit()
                }
                Toggle("HD animations", isOn: Binding(get: { hd.enabled }, set: { $0 ? hd.enable() : hd.remove() }))
                    .labelsHidden().tint(Theme.lime)
                    .accessibilityIdentifier("settings.hdAnimations")
            }
            if hd.status == .downloading {
                ProgressView(value: hd.progress).tint(.white)
            }
            if hd.enabled {
                Toggle(isOn: Binding(get: { hd.wifiOnly }, set: { hd.wifiOnly = $0 })) {
                    Text("Download on Wi-Fi only").font(.subheadline.weight(.semibold))
                }
                .tint(Theme.lime)
                if hd.status == .failed {
                    Button("Try again") { hd.resume() }.font(Theme.label(13)).foregroundStyle(Theme.lime)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(hdGradient))
    }

    private var icon: String {
        switch hd.status {
        case .downloading, .waitingForWiFi: "arrow.down.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "film.stack.fill"
        }
    }

    private var detail: String {
        switch hd.status {
        case .off: "Not downloaded · \(megabytes(hd.totalBytes))"
        case .waitingForWiFi: "Waiting for Wi-Fi · \(megabytes(hd.totalBytes))"
        case .downloading: "\(megabytes(hd.doneBytes)) of \(megabytes(hd.totalBytes))"
        case .ready: "Downloaded · \(megabytes(hd.totalBytes))"
        case .failed: "Download stopped · light moves for now"
        }
    }
}

/// B (#932): "HD moves ready" on the tabs when the pack has finished downloading; goes by itself.
struct HDReadyToast: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 13, weight: .heavy))
                .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.15)))
            VStack(alignment: .leading, spacing: 0) {
                Text("HD moves ready").font(Theme.label(14))
                Text("Every exercise now animates in full detail").font(.caption).opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.ink)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: [Theme.lime, Color(red: 0.25, green: 0.75, blue: 0.5)], startPoint: .leading, endPoint: .trailing)))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .frame(maxWidth: 360)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("hd.readyToast")
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
