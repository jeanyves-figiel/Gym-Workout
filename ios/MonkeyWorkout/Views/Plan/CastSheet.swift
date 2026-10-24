import SwiftUI
import WorkoutEngine

/// Player top bar: cast the workout to a TV (#724). Lime while a TV shows it.
struct CastButton: View {
    @State private var open = false

    private var onTV: Bool {
        TVCast.shared.connected || CastSession.shared.state == .casting || AirPlayStream.shared.active
    }

    var body: some View {
        Button { open = true } label: {
            Image(systemName: onTV ? "tv.fill" : "tv").font(.system(size: 15, weight: .heavy))
                .foregroundStyle(onTV ? Theme.ink : .white)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(onTV ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.cardStrong)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(onTV ? "On your TV" : "Cast to TV")
        .accessibilityIdentifier("player.cast")
        .sheet(isPresented: $open, onDismiss: { AirPlayStream.shared.releaseIfIdle() }) {
            CastSheet()
                .presentationDetents([.medium, .large])
        }
    }
}

/// Chromecasts on the Wi-Fi and the AirPlay picker, as gradient tiles.
struct CastSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var finder = CastDevices()
    /// Demo screen: TVs without a network.
    var demoDevices: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cast to TV").font(Theme.display(26))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .heavy))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.cardStrong))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            if TVCast.shared.connected {
                tile(icon: "rectangle.on.rectangle", title: "On your TV now", detail: "Screen Mirroring · no delay",
                     gradient: WorkoutEngine.Category.stretch.gradient, ink: Theme.ink) { EmptyView() }
            }
            ForEach(finder.devices) { d in
                let mine = CastSession.shared.deviceName == d.name
                Button {
                    mine ? CastSession.shared.stop() : CastSession.shared.cast(to: d)
                } label: {
                    tile(icon: "tv", title: d.name, detail: mine ? status : "Chromecast · Google TV",
                         gradient: WorkoutEngine.Category.power.gradient) {
                        Text(mine ? "STOP" : "CAST").font(Theme.label(12))
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(demoDevices, id: \.self) { name in
                tile(icon: "tv", title: name, detail: "Chromecast · Google TV", gradient: WorkoutEngine.Category.power.gradient) {
                    Text("CAST").font(Theme.label(12))
                }
            }
            if finder.devices.isEmpty, demoDevices.isEmpty {
                tile(icon: "wifi", title: "Looking for Chromecasts…", detail: "Same Wi-Fi as this iPhone",
                     gradient: WorkoutEngine.Category.mobility.gradient) { ProgressView().tint(.white) }
            }
            tile(icon: "airplayvideo", title: "AirPlay", detail: "Apple TV and AirPlay TVs",
                 gradient: WorkoutEngine.Category.strength.gradient) {
                AirPlayPicker().frame(width: 44, height: 44)
            }
            if case let .failed(why) = CastSession.shared.state {
                Text(why).font(Theme.label(13)).foregroundStyle(Theme.lime)
            }
            Text("Your TV shows the workout a few seconds behind. Keep MonkeyFit open while you train.")
                .font(.footnote.weight(.semibold)).opacity(0.7)
            Spacer(minLength: 0)
        }
        .padding(16)
        .foregroundStyle(.white)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            finder.start()
            AirPlayStream.shared.prepare()
        }
        .onDisappear { finder.stop() }
    }

    private var status: String {
        switch CastSession.shared.state {
        case .connecting: "Starting…"
        case .casting: "Casting"
        default: "Chromecast · Google TV"
        }
    }

    private func tile<Trailing: View>(icon: String, title: String, detail: String, gradient: LinearGradient, ink: Color = .white,
                                      @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20, weight: .heavy))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.display(18)).lineLimit(1)
                Text(detail).font(Theme.label(12)).opacity(0.85).lineLimit(1)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .foregroundStyle(ink)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(gradient))
    }
}
