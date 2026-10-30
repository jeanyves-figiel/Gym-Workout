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

/// Plays the workout stream on a Chromecast with Google's own media player (Default Media Receiver): no page of ours on
/// the TV. Speaks the Cast v2 protocol directly (TLS on 8009, length-prefixed protobuf `CastMessage`s with JSON payloads).
@MainActor @Observable
final class CastSession {
    static let shared = CastSession()
    /// Google's Default Media Receiver.
    static let mediaApp = "CC1AD845"

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
        TVStreamer.shared.start(for: "chromecast")
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
        if state != .idle { TVStreamer.shared.stop(for: "chromecast") }
        state = .idle
    }

    private func changed(_ s: NWConnection.State) {
        switch s {
        case .ready:
            send(NS.connection, to: "receiver-0", ["type": "CONNECT"])
            send(NS.receiver, to: "receiver-0", ["type": "LAUNCH", "appId": Self.mediaApp, "requestId": nextId()])
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
            guard let app = apps.first(where: { $0["appId"] as? String == Self.mediaApp }),
                  let transport = app["transportId"] as? String else {
                if transportId != nil { stop() }  // closed on the TV
                return
            }
            sessionId = app["sessionId"] as? String
            guard transportId != transport else { return }
            transportId = transport
            send(NS.connection, to: transport, ["type": "CONNECT"])
            Task { await load(transport) }
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

/// AirPlay of the same stream from the system picker (#724): Apple TVs and AirPlay 2 TVs play it themselves.
@MainActor @Observable
final class AirPlayStream {
    static let shared = AirPlayStream()
    /// A TV plays the stream.
    private(set) var active = false
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var watch: NSKeyValueObservation?

    /// Ready before the picker opens, so picking a TV sends the video.
    func prepare() {
        TVStreamer.shared.start(for: "airplay")
        guard player == nil else { return }
        Task {
            for _ in 0..<60 where TVStreamer.shared.segments < 3 { try? await Task.sleep(for: .milliseconds(250)) }
            guard let url = TVStreamer.shared.url, player == nil else { return }
            let p = AVPlayer(url: url)
            p.allowsExternalPlayback = true
            p.isMuted = true
            p.play()
            player = p
            watch = p.observe(\.isExternalPlaybackActive) { p, _ in
                let active = p.isExternalPlaybackActive
                Task { @MainActor in
                    AirPlayStream.shared.active = active
                    if !active { AirPlayStream.shared.end() }
                }
            }
        }
    }

    /// Sheet closed without a TV picked, or the TV let go.
    func releaseIfIdle() {
        if !active { end() }
    }

    func end() {
        active = false
        watch = nil
        player?.pause()
        player = nil
        TVStreamer.shared.stop(for: "airplay")
    }
}

/// System AirPlay picker, video devices first.
struct AirPlayPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.prioritizesVideoDevices = true
        v.activeTintColor = UIColor(Theme.lime)
        v.tintColor = .white
        return v
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
