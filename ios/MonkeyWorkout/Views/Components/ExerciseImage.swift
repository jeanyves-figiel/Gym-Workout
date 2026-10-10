import SwiftUI
import UIKit
import WorkoutEngine

/// Loads exercise illustrations through a dedicated disk-backed `URLCache`.
/// The URLs are pinned to a commit (immutable), so cached responses are always reused — even stale or offline.
@MainActor
final class ExerciseImageLoader {
    static let shared = ExerciseImageLoader()

    private let session: URLSession
    private let decoded = NSCache<NSURL, UIImage>()

    private init() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ExerciseImages", isDirectory: true)
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024, directory: dir)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
        decoded.countLimit = 60
    }

    func image(for url: URL) async -> UIImage? {
        if let hit = decoded.object(forKey: url as NSURL) { return hit }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let image = UIImage(data: data) else { return nil }
            decoded.setObject(image, forKey: url as NSURL)
            return image
        } catch {
            return nil
        }
    }
}

/// Exercise picture: a free-exercise-db photo, or the app's own illustration (bundled SVG drawn on the
/// category gradient). The gradient + icon is the placeholder while a photo loads or offline.
/// Shows one still frame: 0 = start position, 1 = end position. Never animates by itself.
struct ExerciseImage: View {
    let exercise: Exercise
    var frame = 0
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    /// The user's own exercise (#52): photo or pose drawing from its record.
    private var custom: CustomExercise? {
        CustomExercise.isCustom(exercise.id) ? CustomExercises.shared.record(exercise.id) : nil
    }

    /// Frames this exercise has (2, 1 for a custom photo, or 0 without media).
    static func frameCount(_ e: Exercise) -> Int {
        if CustomExercise.isCustom(e.id) { return CustomExercises.shared.record(e.id)?.frameCount ?? 0 }
        return e.hasIllustration ? e.illustrationAssets.count : e.imageURLs.count
    }

    /// Has a picture: catalog photo/illustration or a custom exercise's photo/pose.
    static func hasMedia(_ e: Exercise) -> Bool { frameCount(e) > 0 }

    var body: some View {
        // The placeholder sets the size; the picture is laid over it so `.fill` never grows the view.
        placeholder
            .overlay {
                if let custom {
                    CustomExerciseArt(record: custom, frame: frame, contentMode: contentMode)
                } else if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: exercise.hasIllustration ? .fit : contentMode)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(exercise.hasIllustration ? Color.clear : Color.white)
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: "\(exercise.id)|\(frame)") { await load() }
            // Decorative: the exercise name is always shown next to it.
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(exercise.category.gradient)
                if !exercise.hasIllustration && !(custom?.hasArt ?? false) {
                    Image(systemName: exercise.category.symbol)
                        .font(.system(size: max(12, min(geo.size.width, geo.size.height) * 0.36), weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @MainActor
    private func load() async {
        if custom != nil { return }
        if exercise.hasIllustration {
            let names = exercise.illustrationAssets
            image = names.indices.contains(frame) ? UIImage(named: names[frame]) : nil
            return
        }
        let urls = exercise.imageURLs
        guard urls.indices.contains(frame) else {
            image = nil
            return
        }
        let loaded = await ExerciseImageLoader.shared.image(for: urls[frame])
        guard !Task.isCancelled else { return }
        withAnimation(.easeIn(duration: 0.2)) { image = loaded }
    }
}

/// Start and end position as a smooth, one-shot movement: shows the start frame; a tap (or `play`)
/// dissolves slowly to the end position, holds, and returns. No endless loop. With Reduce Motion
/// it switches frames without the dissolve. Shared by the exercise page and the workout player.
struct ExerciseMotionView: View {
    let exercise: Exercise
    var contentMode: ContentMode = .fill
    /// Change to replay from outside (e.g. when the player moves to a new set).
    var playTrigger = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showEnd = false
    @State private var playing = false

    private var canPlay: Bool { ExerciseImage.frameCount(exercise) > 1 }

    var body: some View {
        ZStack {
            ExerciseImage(exercise: exercise, frame: 0, contentMode: contentMode)
            if canPlay {
                ExerciseImage(exercise: exercise, frame: 1, contentMode: contentMode)
                    .opacity(showEnd ? 1 : 0)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if canPlay {
                Label(showEnd ? "End" : (playing ? "Start" : "Play movement"), systemImage: playing ? "figure.walk.motion" : "play.fill")
                    .font(Theme.label(11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.ink.opacity(0.55)))
                    .padding(10)
                    .animation(nil, value: showEnd)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if canPlay { playing = true } }
        .task(id: playing) {
            guard playing else { return }
            await play()
            playing = false
        }
        .onChange(of: playTrigger) { _, _ in if canPlay { playing = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.name), start and end position")
        .accessibilityAddTraits(canPlay ? .isButton : [])
        .accessibilityHint(canPlay ? "Shows the movement once" : "")
    }

    @MainActor
    private func play() async {
        let dissolve: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.9)
        for _ in 0..<2 {
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { break }
            withAnimation(dissolve) { showEnd = true }
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { break }
            withAnimation(dissolve) { showEnd = false }
            try? await Task.sleep(for: .seconds(1.2))
        }
        showEnd = false
    }
}

/// Small rounded thumbnail for lists and cards.
struct ExerciseThumbnail: View {
    let exercise: Exercise
    var size: CGFloat = 56

    var body: some View {
        ExerciseImage(exercise: exercise)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).strokeBorder(Theme.stroke))
    }
}

/// Large picture for the exercise page and the player. Renders nothing without media.
/// `.sequence`: start and end side by side, labelled (default, no motion).
/// `.motion`: one picture, tap to play the movement once (`ExerciseMotionView`).
struct ExerciseImageHeader: View {
    enum Style { case sequence, motion }

    let exercise: Exercise
    var height: CGFloat = 220
    var showsAttribution = true
    var style: Style = .sequence

    var body: some View {
        if ExerciseImage.hasMedia(exercise) {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if style == .sequence && ExerciseImage.frameCount(exercise) > 1 {
                        HStack(spacing: 6) {
                            panel(0, "Start")
                            panel(1, "End")
                        }
                        .overlay {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Theme.lime))
                                .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 3))
                        }
                    } else {
                        ExerciseMotionView(exercise: exercise)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.stroke))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                if showsAttribution, exercise.imageId != nil {
                    Link(destination: ExerciseImages.sourceURL) {
                        Text(ExerciseImages.attribution).font(.caption2).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    private func panel(_ frame: Int, _ label: String) -> some View {
        ExerciseImage(exercise: exercise, frame: frame)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.stroke))
            .overlay(alignment: .bottomLeading) {
                Text(label.uppercased())
                    .font(Theme.label(10))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.ink.opacity(0.6)))
                    .padding(8)
            }
    }
}
