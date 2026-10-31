import AVFoundation
import AVKit
import Foundation
import Network
import Observation
import SwiftUI

/// Chromecasts and Google TVs on the Wi-Fi (#724), found over Bonjour.
@MainActor @Observable
final class CastDevices {
    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
        let endpoint: NWEndpoint
    }

    var devices: [Device] = []
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_googlecast._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { results, _ in
            let list = results.compactMap { r -> Device? in
                guard case let .service(name, _, _, _) = r.endpoint else { return nil }
                var friendly: String?
                if case let .bonjour(txt) = r.metadata { friendly = txt["fn"] }
                return Device(id: name, name: friendly ?? name, endpoint: r.endpoint)
            }
            .sorted { $0.name < $1.name }
            MainActor.assumeIsolated { self.devices = list }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}

/// Casts the workout to a Chromecast. Speaks the Cast v2 protocol directly (TLS on 8009, length-prefixed protobuf
/// `CastMessage`s with JSON payloads).
/// Native (#1008): our receiver (`/cast/receiver`, App ID in the OTA value `castReceiverAppId`) draws the workout on the
/// TV itself; the phone only sends `TVLive` as small JSON messages, and the movement clip plays on the TV. Smooth and
/// instant, like any cast app. Without an App ID: the older phone-recorded video in Google's Default Media Receiver.
@MainActor @Observable
final class CastSession {
    static let shared = CastSession()
    /// Google's Default Media Receiver.
    static let mediaApp = "CC1AD845"
    /// Our own receiver's namespace (backend `src/routes/cast.ts`).
    static let workoutNamespace = "urn:x-cast:cloud.monkeygrade.workout"

    /// Our receiver in the Google Cast console (Custom Receiver at `/cast/receiver`).
    static let defaultReceiverAppId = "E195DE34"

    /// Our receiver's App ID; the OTA value `castReceiverAppId` overrides it, and an empty one falls back to video.
    static var receiverAppId: String? {
        guard case let .string(id)? = Remote.shared.value("castReceiverAppId") else { return defaultReceiverAppId }
        let trimmed = id.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    enum State: Equatable { case idle, connecting, casting, failed(String) }

    var state = State.idle
    var deviceName: String?

    private var connection: NWConnection?
    private var buffer = Data()
    private var transportId: String?
    private var sessionId: String?
    private var loaded = false
    private var requestId = 1
    private var heartbeat: Timer?
    /// The App ID launched for this cast: our receiver, or the Default Media Receiver.
    private var appId = CastSession.mediaApp
    private var native: Bool { appId != Self.mediaApp }

    private enum NS {
        static let connection = "urn:x-cast:com.google.cast.tp.connection"
        static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
        static let receiver = "urn:x-cast:com.google.cast.receiver"
        static let media = "urn:x-cast:com.google.cast.media"
    }

    func cast(to device: CastDevices.Device) {
        stop()
        deviceName = device.name
        state = .connecting
        appId = Self.receiverAppId ?? Self.mediaApp
        if !native { TVStreamer.shared.start(for: "chromecast") }
        let tls = NWProtocolTLS.Options()
        // Cast devices use their own self-signed certificate.
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, done in done(true) }, .main)
        let connection = NWConnection(to: device.endpoint, using: NWParameters(tls: tls, tcp: .init()))
        connection.stateUpdateHandler = { [weak connection] s in
            MainActor.assumeIsolated {
                // A TV left behind by an earlier cast says nothing more.
                guard let connection, connection === CastSession.shared.connection else { return }
                CastSession.shared.changed(s)
            }
        }
        self.connection = connection
        connection.start(queue: .main)
        receive(connection)
    }

    func stop() {
        if let sessionId {
            send(NS.receiver, to: "receiver-0", ["type": "STOP", "sessionId": sessionId, "requestId": nextId()])
        }
        heartbeat?.invalidate()
        heartbeat = nil
        connection?.cancel()
        connection = nil
        buffer = Data()
        transportId = nil
        sessionId = nil
        loaded = false
        deviceName = nil
        if state != .idle, !native { TVStreamer.shared.stop(for: "chromecast") }
        state = .idle
    }

    private func changed(_ s: NWConnection.State) {
        switch s {
        case .ready:
            send(NS.connection, to: "receiver-0", ["type": "CONNECT"])
            send(NS.receiver, to: "receiver-0", ["type": "LAUNCH", "appId": appId, "requestId": nextId()])
            heartbeat = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                MainActor.assumeIsolated { CastSession.shared.send(NS.heartbeat, to: "receiver-0", ["type": "PING"]) }
            }
        case .failed, .cancelled:
            fail("Lost the TV")
        default:
            break
        }
    }

    private func fail(_ why: String) {
        stop()
        state = .failed(why)
    }

    private func nextId() -> Int {
        requestId += 1
        return requestId
    }

    private func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, done, error in
            MainActor.assumeIsolated {
                let me = CastSession.shared
                guard c === me.connection else { return }
                if let data { me.buffer.append(data) }
                me.drain()
                if !done, error == nil { me.receive(c) }
            }
        }
    }

    private func drain() {
        while buffer.count >= 4 {
            let len = buffer.prefix(4).reduce(0) { $0 << 8 | Int($1) }
            guard buffer.count >= 4 + len else { return }
            let body = Data(buffer.dropFirst(4).prefix(len))
            buffer = Data(buffer.dropFirst(4 + len))
            if let m = CastMessage.decode(body) { handle(m) }
        }
    }

    private func handle(_ m: CastMessage) {
        guard let json = try? JSONSerialization.jsonObject(with: Data(m.payload.utf8)) as? [String: Any],
              let type = json["type"] as? String else { return }
        switch type {
        case "PING":
            send(NS.heartbeat, to: m.source, ["type": "PONG"])
        case "RECEIVER_STATUS":
            let apps = (json["status"] as? [String: Any])?["applications"] as? [[String: Any]] ?? []
            guard let app = apps.first(where: { $0["appId"] as? String == appId }),
                  let transport = app["transportId"] as? String else {
                if transportId != nil { stop() }  // closed on the TV
                return
            }
            sessionId = app["sessionId"] as? String
            guard transportId != transport else { return }
            transportId = transport
            send(NS.connection, to: transport, ["type": "CONNECT"])
            if native {
                state = .casting
                sendLive(play: true)
            } else {
                Task { await load(transport) }
            }
        case "MEDIA_STATUS":
            state = .casting
        case "LOAD_FAILED", "LOAD_CANCELLED", "LAUNCH_ERROR":
            fail("The TV couldn't play it")
        case "CLOSE":
            if m.source != "receiver-0" { stop() }
        default:
            break
        }
    }

    /// The player changed what the TV shows (#1008): our receiver gets the new state; a new exercise or set replays the
    /// movement there, as on the phone.
    func liveChanged(from old: TVLive?) {
        guard native, state == .casting else { return }
        let live = TVCast.shared.live
        let newExercise = old?.exercise.id != live?.exercise.id
        sendLive(play: live != nil && (newExercise || old?.set != live?.set), newExercise: newExercise)
    }

    private func sendLive(play: Bool, newExercise: Bool = true) {
        guard let transportId else { return }
        guard let live = TVCast.shared.live else {
            return send(Self.workoutNamespace, to: transportId, ["type": "state"])
        }
        send(Self.workoutNamespace, to: transportId, ["type": "state", "live": TVReceiverMessage.state(live)])
        if play {
            send(Self.workoutNamespace, to: transportId, TVReceiverMessage.play(live, newExercise: newExercise))
        }
    }

    /// Waits for a few seconds of video, then asks the TV's player to play the live stream.
    private func load(_ transport: String) async {
        for _ in 0..<60 where TVStreamer.shared.segments < 3 {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard !loaded, transportId == transport else { return }
        guard let url = TVStreamer.shared.url?.absoluteString else { return fail("Join the TV's Wi-Fi") }
        loaded = true
        send(NS.media, to: transport, [
            "type": "LOAD", "requestId": nextId(), "autoplay": true,
            "media": [
                "contentId": url, "contentUrl": url, "streamType": "LIVE",
                "contentType": "application/x-mpegurl", "hlsSegmentFormat": "fmp4", "hlsVideoSegmentFormat": "fmp4",
                "metadata": ["metadataType": 0, "title": TVCast.shared.live?.title ?? "MonkeyWorkout workout"],
            ] as [String: Any],
        ])
    }

    private func send(_ namespace: String, to destination: String, _ payload: [String: Any]) {
        guard let connection, let json = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: json, encoding: .utf8) else { return }
        let m = CastMessage(source: "sender-0", destination: destination, namespace: namespace, payload: text)
        connection.send(content: m.framed(), completion: .contentProcessed { _ in })
    }
}

/// Cast v2 `CastMessage` (protobuf): version 0, string payload. Only the fields the sender needs.
struct CastMessage: Equatable {
    var source: String
    var destination: String
    var namespace: String
    var payload: String

    /// 4-byte big-endian length, then the message.
    func framed() -> Data {
        var m = Data()
        func varint(_ value: Int) {
            var v = UInt64(value)
            repeat {
                var b = UInt8(v & 0x7F)
                v >>= 7
                if v != 0 { b |= 0x80 }
                m.append(b)
            } while v != 0
        }
        func string(_ field: Int, _ s: String) {
            let d = Data(s.utf8)
            varint(field << 3 | 2)
            varint(d.count)
            m.append(d)
        }
        varint(1 << 3); varint(0)  // protocol_version CASTV2_1_0
        string(2, source)
        string(3, destination)
        string(4, namespace)
        varint(5 << 3); varint(0)  // payload_type STRING
        string(6, payload)
        let n = UInt32(m.count)
        return Data([UInt8(n >> 24 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)]) + m
    }

    static func decode(_ data: Data) -> CastMessage? {
        let bytes = [UInt8](data)
        var i = 0
        func varint() -> Int? {
            var v = 0, shift = 0
            while i < bytes.count {
                let b = bytes[i]
                i += 1
                v |= Int(b & 0x7F) << shift
                if b & 0x80 == 0 { return v }
                shift += 7
                if shift > 56 { return nil }
            }
            return nil
        }
        var strings: [Int: String] = [:]
        while i < bytes.count {
            guard let key = varint() else { return nil }
            switch key & 7 {
            case 0:
                guard varint() != nil else { return nil }
            case 2:
                guard let len = varint(), len >= 0, i + len <= bytes.count else { return nil }
                strings[key >> 3] = String(decoding: bytes[i..<i + len], as: UTF8.self)
                i += len
            default:
                return nil
            }
        }
        return CastMessage(source: strings[2] ?? "", destination: strings[3] ?? "", namespace: strings[4] ?? "",
                           payload: strings[6] ?? "")
    }
}

/// AirPlay of the workout video from the system picker (#724): Apple TVs and AirPlay 2 TVs play it themselves.
/// #1008: the TV only took the sound when picked before the video was ready, or with the app's mixable audio session.
/// Now the picker opens only once the player plays, with a long-form video session (the picker then sends the
/// picture); if a TV still takes only the sound, `soundOnly` says so and the sheet points to Screen Mirroring, which
/// shows the native TV screen (`TVSceneDelegate`).
@MainActor @Observable
final class AirPlayStream {
    static let shared = AirPlayStream()
    /// A TV plays the video.
    private(set) var active = false
    /// The player plays: the picker can send the picture.
    private(set) var ready = false
    /// An AirPlay TV got the sound but not the picture.
    private(set) var soundOnly = false
    /// The audio session is set for long-form video: the coach's voice leaves it as it is.
    private(set) var holdsSession = false
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var watch: NSKeyValueObservation?
    @ObservationIgnored private var status: NSKeyValueObservation?
    @ObservationIgnored private var routes: NSObjectProtocol?

    /// Ready before the picker opens, so picking a TV sends the video.
    func prepare() {
        TVStreamer.shared.start(for: "airplay")
        guard player == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo, options: [])
        holdsSession = true
        routes = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AirPlayStream.shared.routeChanged() }
        }
        Task {
            for _ in 0..<60 where TVStreamer.shared.segments < 2 { try? await Task.sleep(for: .milliseconds(250)) }
            guard let url = TVStreamer.shared.url, player == nil, holdsSession else { return }
            let p = AVPlayer(url: url)
            p.allowsExternalPlayback = true
            p.usesExternalPlaybackWhileExternalScreenIsActive = true
            p.automaticallyWaitsToMinimizeStalling = false
            p.isMuted = true
            player = p
            status = p.observe(\.timeControlStatus, options: [.initial, .new]) { p, _ in
                let playing = p.timeControlStatus == .playing
                Task { @MainActor in if playing { AirPlayStream.shared.ready = true } }
            }
            watch = p.observe(\.isExternalPlaybackActive) { p, _ in
                let active = p.isExternalPlaybackActive
                Task { @MainActor in
                    let me = AirPlayStream.shared
                    let was = me.active
                    me.active = active
                    if active { me.soundOnly = false }
                    if was, !active { me.end() }
                }
            }
            try? session.setActive(true)
            p.play()
        }
    }

    /// A TV picked: the picture should follow within a few seconds, or only its sound went there.
    private func routeChanged() {
        let airPlay = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .airPlay }
        guard airPlay, !active else {
            if !airPlay { soundOnly = false }
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            let still = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .airPlay }
            if still, !active, !TVCast.shared.connected { soundOnly = true }
        }
    }

    /// Sheet closed without a TV picked, or the TV let go.
    func releaseIfIdle() {
        if !active { end() }
    }

    func end() {
        active = false
        ready = false
        watch = nil
        status = nil
        if let routes { NotificationCenter.default.removeObserver(routes) }
        routes = nil
        player?.pause()
        player = nil
        if holdsSession {
            holdsSession = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        TVStreamer.shared.stop(for: "airplay")
    }
}

/// System AirPlay picker, video devices first. The sheet keeps one out of sight and opens it from a tap anywhere on the
/// AirPlay card (#1008) through `AirPlayPicker.Opener`.
struct AirPlayPicker: UIViewRepresentable {
    /// Opens the picker it is attached to.
    @MainActor final class Opener {
        fileprivate weak var view: AVRoutePickerView?

        func open() {
            guard let view else { return }
            func button(in v: UIView) -> UIButton? {
                if let b = v as? UIButton { return b }
                return v.subviews.lazy.compactMap(button(in:)).first
            }
            button(in: view)?.sendActions(for: .touchUpInside)
        }
    }

    var opener: Opener?

    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.prioritizesVideoDevices = true
        v.activeTintColor = UIColor(Theme.lime)
        v.tintColor = .white
        opener?.view = v
        return v
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        opener?.view = uiView
    }
}
