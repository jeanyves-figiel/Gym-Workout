import AVFoundation
import CoreImage
import UIKit
import WorkoutEngine

/// Movement clips (#944): every catalog exercise drawn with 61 in-betweens from start to end and played at 60 fps
/// (ios/Tools/illustrations/video.py). The light clip is bundled (`motion-<id>.mp4`); the HD pack brings the full-size
/// one. A clip runs start → end → start and has no alpha channel: each picture is stacked, colour on top and its
/// alpha as grey below, and the player masks one with the other.
enum MotionClips {
    /// The exercise's clip: HD when the pack has it, else the bundled one; nil without one (custom exercises).
    @MainActor static func url(_ exerciseId: String) -> URL? {
        HDAnimations.shared.clipURL(exerciseId) ?? Bundle.main.url(forResource: "motion-\(exerciseId)", withExtension: "mp4")
    }
}

/// Plays a movement clip at the tempo of a `MotionPlayback`: its pieces (out, hold, back, hold per rep) are cut from
/// the clip and stretched into one composition, decoded a few pictures ahead of the display (`ClipReader`).
/// `image(at:)` gives the picture for a time into the play, on the same clock as the path dot and tempo chip. No
/// AVPlayer: nothing touches the audio session, so a member's music keeps playing.
@MainActor
final class MotionClipPlayer {
    /// Held for the play: a track only weakly refers to its asset, and without it the composition comes out empty
    /// (#949: build 87 showed the resting frame with only the path dot moving).
    private let asset: AVURLAsset
    private let track: AVAssetTrack
    /// End of the clip in the file.
    private let clipEnd: CMTime
    private var reader: ClipReader?
    private var last: CGImage?
    /// The clip gave no picture in time (unreadable, empty composition): the play falls back to the frames.
    private(set) var failed = false
    /// No picture this far into a play: the clip counts as failed.
    private static let firstPictureDeadline = 0.4

    private static let timescale: CMTimeScale = 60_000

    private init(asset: AVURLAsset, track: AVAssetTrack, end: CMTime) {
        self.asset = asset
        self.track = track
        clipEnd = end
    }

    /// The clip at `url`, nil when it can't be read.
    static func load(_ url: URL) async -> MotionClipPlayer? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let range = try? await track.load(.timeRange) else { return nil }
        return MotionClipPlayer(asset: asset, track: track, end: range.end)
    }

    /// Starts decoding `pieces` (MotionPlayback.clipPieces) for a play starting now.
    func play(_ pieces: [MotionPlayback.ClipPiece]) {
        reader?.cancel()
        reader = nil
        failed = false
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return }
        let fps = MotionPlayback.clipFPS
        var at = CMTime.zero
        for piece in pieces where piece.duration > 0 {
            let start = CMTime(seconds: piece.start / fps, preferredTimescale: Self.timescale)
            let length = CMTime(seconds: piece.length / fps, preferredTimescale: Self.timescale)
            let source = CMTimeRange(start: start, duration: CMTimeMinimum(length, clipEnd - start))
            guard source.duration > .zero, (try? video.insertTimeRange(source, of: track, at: at)) != nil else { continue }
            let duration = CMTime(seconds: piece.duration, preferredTimescale: Self.timescale)
            video.scaleTimeRange(CMTimeRange(start: at, duration: source.duration), toDuration: duration)
            at = at + duration
        }
        guard at > .zero, let frozen = composition.copy() as? AVComposition else {
            failed = true
            return
        }
        reader = ClipReader(frozen)
    }

    /// Back to rest: the still frames show again.
    func stop() {
        reader?.cancel()
        reader = nil
        last = nil
    }

    /// Picture `t` seconds into the play; nil before the first one is decoded.
    func image(at t: Double) -> CGImage? {
        if let next = reader?.frame(at: t) { last = next }
        if last == nil, t > Self.firstPictureDeadline || reader?.failed == true { failed = true }
        return last
    }
}

/// Decodes a composition on a background queue, at most `ahead` pictures ahead of the display, each masked into a
/// picture with alpha.
final class ClipReader: @unchecked Sendable {
    private static let ahead = 8
    /// Colour values pass through untouched: the alpha half is a mask, not a picture.
    private static let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(),
                                                     .cacheIntermediates: false])

    private let lock = NSLock()
    private var pending: [(time: Double, image: CGImage)] = []
    private var cancelled = false
    private var broken = false
    /// Free places in `pending`. Starts at 0 and is raised: a semaphore must not end below its start value.
    private let space = DispatchSemaphore(value: 0)

    init(_ composition: AVComposition) {
        for _ in 0..<Self.ahead { space.signal() }
        DispatchQueue.global(qos: .userInitiated).async { [self] in decode(composition) }
    }

    func cancel() {
        lock.withLock { cancelled = true }
        space.signal()
    }

    private var isCancelled: Bool { lock.withLock { cancelled } }
    /// The composition could not be read.
    var failed: Bool { lock.withLock { broken } }

    /// The latest decoded picture due by `t`, nil when none is new.
    func frame(at t: Double) -> CGImage? {
        lock.withLock {
            var due: CGImage?
            while let first = pending.first, first.time <= t {
                due = first.image
                pending.removeFirst()
                space.signal()
            }
            return due
        }
    }

    private func decode(_ composition: AVComposition) {
        guard let track = composition.tracks.first(where: { $0.mediaType == .video }),
              let reader = try? AVAssetReader(asset: composition) else { return fail() }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return fail() }
        reader.add(output)
        guard reader.startReading() else { return fail() }
        defer { reader.cancelReading() }
        while !isCancelled, let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample), let image = Self.picture(buffer) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            space.wait()
            if isCancelled { return }
            lock.withLock { pending.append((time, image)) }
        }
    }

    private func fail() { lock.withLock { broken = true } }

    /// The stacked picture's colour (top half) masked by its alpha (bottom half).
    private static func picture(_ buffer: CVPixelBuffer) -> CGImage? {
        let full = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
        let width = full.extent.width, height = (full.extent.height / 2).rounded(.down)
        // Core Image's origin is bottom-left: the colour half is the upper one.
        let lift = full.extent.height - height
        let colour = full.cropped(to: CGRect(x: 0, y: lift, width: width, height: height))
            .transformed(by: CGAffineTransform(translationX: 0, y: -lift))
        let mask = full.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        let clear = CIImage(color: .clear).cropped(to: mask.extent)
        let masked = colour.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: mask,
        ])
        return context.createCGImage(masked, from: mask.extent, format: .RGBA8,
                                     colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
}
