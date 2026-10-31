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

/// Chromecast and AirPlay as two gradient cards; a tap anywhere on a card opens its choices (#1008): the Chromecasts on
/// the Wi-Fi to pick from (or stop), the system AirPlay picker.
struct CastSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var finder = CastDevices()
    @State private var airPlay = AirPlayPicker.Opener()
    /// Demo screen: TVs without a network.
    var demoDevices: [String] = []

    private var session: CastSession { CastSession.shared }
    private var stream: AirPlayStream { AirPlayStream.shared }
    private var names: [String] { demoDevices.isEmpty ? finder.devices.map(\.name) : demoDevices }

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
            chromecast
            airPlayCard
            if case let .failed(why) = session.state {
                Text(why).font(Theme.label(13)).foregroundStyle(Theme.lime)
            }
            if stream.soundOnly {
                Text("Your TV took only the sound. For the picture: Control Center → Screen Mirroring → your TV.")
                    .font(Theme.label(13)).foregroundStyle(Theme.lime)
            }
            Text("Keep the app open while you train. Apple TV: Screen Mirroring from Control Center gives the sharpest picture.") // no "MonkeyFit" (#823)
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

    /// One card for every Chromecast: its menu lists the TVs found, the one casting ticked, and Stop.
    private var chromecast: some View {
        Menu {
            if names.isEmpty {
                Text("Looking for TVs on your Wi-Fi…")
            }
            ForEach(names, id: \.self) { name in
                Button {
                    if let d = finder.devices.first(where: { $0.name == name }) { session.cast(to: d) }
                } label: {
                    if session.deviceName == name { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
            if session.deviceName != nil {
                Button("Stop casting", systemImage: "stop.fill", role: .destructive) { session.stop() }
            }
        } label: {
            tile(icon: "tv", title: session.deviceName ?? "Chromecast", detail: chromecastDetail,
                 gradient: WorkoutEngine.Category.power.gradient) {
                if names.isEmpty, demoDevices.isEmpty {
                    ProgressView().tint(.white)
                } else {
                    HStack(spacing: 4) {
                        Text(session.deviceName == nil ? "CHOOSE" : "CHANGE").font(Theme.label(12))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .heavy))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cast.chromecast")
    }

    private var chromecastDetail: String {
        switch session.state {
        case .connecting: return "Starting…"
        case .casting: return "Casting · tap to change or stop"
        default:
            if names.isEmpty { return "Looking on your Wi-Fi…" }
            return names.count == 1 ? "1 TV found · Google TV" : "\(names.count) TVs found · Google TV"
        }
    }

    /// The whole card opens the system AirPlay picker, once the video is ready to go with it.
    private var airPlayCard: some View {
        Button { airPlay.open() } label: {
            tile(icon: "airplayvideo", title: "AirPlay", detail: airPlayDetail,
                 gradient: WorkoutEngine.Category.strength.gradient) {
                ZStack {
                    if stream.ready || !demoDevices.isEmpty {
                        Image(systemName: stream.active ? "checkmark.circle.fill" : "airplayvideo")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(stream.active ? Theme.lime : .white)
                    } else {
                        ProgressView().tint(.white)
                    }
                    // The system picker, out of sight: the card opens it.
                    AirPlayPicker(opener: airPlay).frame(width: 1, height: 1).opacity(0.01).allowsHitTesting(false)
                }
                .frame(width: 44, height: 44)
            }
        }
        .buttonStyle(.plain)
        .disabled(!stream.ready && demoDevices.isEmpty)
        .accessibilityIdentifier("cast.airplay")
    }

    private var airPlayDetail: String {
        if stream.active { return "On your TV · tap to change" }
        return stream.ready || !demoDevices.isEmpty ? "Apple TV and AirPlay TVs" : "Getting the picture ready…"
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
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(gradient))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
