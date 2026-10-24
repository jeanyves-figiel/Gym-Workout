import AVFoundation
import Network
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Live video of the TV layout (#724) for Chromecast and AirPlay: the phone draws `TVScreen` in a window behind the app,
/// encodes it to H.264 and serves it as a live HLS stream on the Wi-Fi. No page or app on the TV: its own player plays it.
@MainActor
final class TVStreamer {
    static let shared = TVStreamer()
    static let size = CGSize(width: 1280, height: 720)
    static let fps = 12

    private(set) var running = false
    private var window: UIWindow?
    private var timer: Timer?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var start: CFTimeInterval = 0
    private var lastTime = CMTime.invalid
    private let server = TVStreamServer()
    /// Who still needs the stream (Chromecast, AirPlay): it stops when none do.
    private var users = Set<String>()

    /// Playlist on this phone's Wi-Fi address; nil without Wi-Fi.
    var url: URL? { server.url("live.m3u8") }
    var segments: Int { server.segments }

    func start(for user: String) {
        users.insert(user)
        guard !running else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.session.role == .windowApplication }) else { return }
        do { try server.start() } catch { return }
        // Behind the app's window: drawn every frame (the movement plays) but never seen on the phone.
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: Self.size)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue - 1)
        window.isUserInteractionEnabled = false
        let host = UIHostingController(rootView: TVScreen().preferredColorScheme(.dark))
        host.view.frame = CGRect(origin: .zero, size: Self.size)
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        guard startWriter() else { return stopAll() }
        running = true
        start = CACurrentMediaTime()
        lastTime = .invalid
        timer = Timer.scheduledTimer(withTimeInterval: 1 / Double(Self.fps), repeats: true) { _ in
            MainActor.assumeIsolated { TVStreamer.shared.capture() }
        }
    }

    func stop(for user: String) {
        users.remove(user)
        if users.isEmpty { stopAll() }
    }

    private func stopAll() {
        users.removeAll()
        timer?.invalidate()
        timer = nil
        input?.markAsFinished()
        writer?.cancelWriting()
        writer = nil
        input = nil
        adaptor = nil
        window?.isHidden = true
        window = nil
        server.stop()
        running = false
    }

    private func startWriter() -> Bool {
        guard let type = UTType(AVFileType.mp4.rawValue) else { return false }
        let writer = AVAssetWriter(contentType: type)
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = CMTime(value: 1, timescale: 1)
        writer.initialSegmentStartTime = .zero
        writer.delegate = server
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(Self.size.width),
            AVVideoHeightKey: Int(Self.size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_500_000,
                // A key frame every second: each segment starts on one.
                AVVideoMaxKeyFrameIntervalKey: Self.fps,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false,
            ] as [String: Any],
        ])
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(Self.size.width),
            kCVPixelBufferHeightKey as String: Int(Self.size.height),
        ])
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)
        server.reset()
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        return true
    }

    /// One frame of the TV window into the encoder.
    private func capture() {
        guard let view = window?.rootViewController?.view, let input, let adaptor, input.isReadyForMoreMediaData,
              let pool = adaptor.pixelBufferPool else { return }
        let time = CMTime(seconds: CACurrentMediaTime() - start, preferredTimescale: 600)
        guard !lastTime.isValid || time > lastTime else { return }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: Int(Self.size.width), height: Int(Self.size.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        ctx.translateBy(x: 0, y: Self.size.height)
        ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx)
        view.drawHierarchy(in: CGRect(origin: .zero, size: Self.size), afterScreenUpdates: false)
        UIGraphicsPopContext()
        if adaptor.append(buffer, withPresentationTime: time) { lastTime = time }
    }
}

/// Tiny HTTP server for the live playlist and its fMP4 segments. All state lives on `queue`.
final class TVStreamServer: NSObject, AVAssetWriterDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "tv.stream.server")
    private var listener: NWListener?
    private var port: UInt16 = 0
    private var initSegment: Data?
    /// Latest segments, oldest first: sequence number, duration, data.
    private var parts: [(seq: Int, duration: Double, data: Data)] = []
    private var nextSeq = 0
    private static let window = 6

    var segments: Int { queue.sync { parts.count } }

    func url(_ path: String) -> URL? {
        let port = queue.sync { self.port }
        guard port != 0, let ip = Self.wifiAddress() else { return nil }
        return URL(string: "http://\(ip):\(port)/\(path)")
    }

    func start() throws {
        guard queue.sync(execute: { listener == nil }) else { return }
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] c in self?.serve(c) }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            if case .ready = state, let p = listener?.port?.rawValue { self?.port = p }
        }
        queue.sync { self.listener = listener }
        listener.start(queue: queue)
        // Ready within a moment; the first segment takes a second anyway.
        for _ in 0..<20 where queue.sync(execute: { port == 0 }) { Thread.sleep(forTimeInterval: 0.025) }
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            port = 0
            initSegment = nil
            parts = []
        }
    }

    func reset() {
        queue.sync {
            initSegment = nil
            parts = []
        }
    }

    func assetWriter(_ writer: AVAssetWriter, didOutputSegmentData segmentData: Data, segmentType: AVAssetSegmentType,
                     segmentReport: AVAssetSegmentReport?) {
        let duration = segmentReport?.trackReports.first.map { $0.duration.seconds } ?? 1
        queue.async { [self] in
            switch segmentType {
            case .initialization:
                initSegment = segmentData
            case .separable:
                parts.append((nextSeq, duration.isFinite && duration > 0 ? duration : 1, segmentData))
                nextSeq += 1
                if parts.count > Self.window { parts.removeFirst(parts.count - Self.window) }
            @unknown default:
                break
            }
        }
    }

    private func playlist() -> String {
        let target = Int((parts.map(\.duration).max() ?? 1).rounded(.up))
        var lines = ["#EXTM3U", "#EXT-X-VERSION:7", "#EXT-X-TARGETDURATION:\(max(1, target))",
                     "#EXT-X-MEDIA-SEQUENCE:\(parts.first?.seq ?? 0)", "#EXT-X-MAP:URI=\"init.mp4\""]
        for p in parts {
            lines.append(String(format: "#EXTINF:%.3f,", p.duration))
            lines.append("seg\(p.seq).m4s")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func serve(_ c: NWConnection) {
        c.start(queue: queue)
        c.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { return c.cancel() }
            let parts = request.split(separator: "\r\n").first?.split(separator: " ") ?? []
            let method = parts.first.map(String.init) ?? ""
            let path = parts.count > 1 ? String(parts[1].split(separator: "?").first ?? "") : ""
            let (status, type, body) = method == "OPTIONS" ? ("204 No Content", "text/plain", Data()) : self.respond(path)
            var head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
            // The Chromecast's player fetches from another origin.
            head += "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: *\r\nAccess-Control-Allow-Methods: GET, OPTIONS\r\n"
            head += "Cache-Control: no-cache\r\nConnection: close\r\n\r\n"
            let out = Data(head.utf8) + (method == "HEAD" ? Data() : body)
            c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
        }
    }

    private func respond(_ path: String) -> (String, String, Data) {
        let notFound = ("404 Not Found", "text/plain", Data())
        switch path {
        case "/live.m3u8":
            guard initSegment != nil, !parts.isEmpty else { return notFound }
            return ("200 OK", "application/vnd.apple.mpegurl", Data(playlist().utf8))
        case "/init.mp4":
            return initSegment.map { ("200 OK", "video/mp4", $0) } ?? notFound
        default:
            guard path.hasPrefix("/seg"), path.hasSuffix(".m4s"),
                  let seq = Int(path.dropFirst(4).dropLast(4)),
                  let part = parts.first(where: { $0.seq == seq }) else { return notFound }
            return ("200 OK", "video/iso.segment", part.data)
        }
    }

    /// IPv4 address of the Wi-Fi interface.
    static func wifiAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), String(cString: ifa.ifa_name) == "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            return String(cString: host)
        }
        return nil
    }
}
