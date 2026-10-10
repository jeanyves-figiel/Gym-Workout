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
/// `animated` alternates the start/end frames as a simple two-frame animation.
struct ExerciseImage: View {
    let exercise: Exercise
    var animated = false
    var contentMode: ContentMode = .fill

    @State private var frames: [UIImage] = []
    @State private var frame = 0

    var body: some View {
        // The placeholder sets the size; the photo is laid over it so `.fill` never grows the view.
        placeholder
            .overlay {
                if !frames.isEmpty {
                    Image(uiImage: frames[min(frame, frames.count - 1)])
                        .resizable()
                        .aspectRatio(contentMode: exercise.hasIllustration ? .fit : contentMode)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(exercise.hasIllustration ? Color.clear : Color.white)
                        .id(frame)
                        .transition(.opacity)
                }
            }
            .clipped()
        .task(id: "\(exercise.id)|\(animated)") { await load() }
        // Decorative: the exercise name is always shown next to it.
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(exercise.category.gradient)
                if !exercise.hasIllustration {
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
        frames = []
        frame = 0
        if exercise.hasIllustration {
            let names = animated ? exercise.illustrationAssets : Array(exercise.illustrationAssets.prefix(1))
            frames = names.compactMap { UIImage(named: $0) }
            await cycle(frames.count)
            return
        }
        let urls = animated ? exercise.imageURLs : Array(exercise.imageURLs.prefix(1))
        var loaded: [UIImage] = []
        for url in urls {
            guard let image = await ExerciseImageLoader.shared.image(for: url), !Task.isCancelled else { break }
            loaded.append(image)
            if loaded.count == 1 { withAnimation(.easeIn(duration: 0.2)) { frames = loaded } }
        }
        guard !Task.isCancelled else { return }
        frames = loaded
        await cycle(loaded.count)
    }

    @MainActor
    private func cycle(_ count: Int) async {
        guard animated, count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { break }
            withAnimation(.easeInOut(duration: 0.3)) { frame = (frame + 1) % count }
        }
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

/// Large animated picture for the exercise page and the player. Renders nothing without media.
struct ExerciseImageHeader: View {
    let exercise: Exercise
    var height: CGFloat = 220
    var showsAttribution = true

    var body: some View {
        if exercise.hasMedia {
            VStack(alignment: .leading, spacing: 6) {
                ExerciseImage(exercise: exercise, animated: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.stroke))
                if showsAttribution, exercise.imageId != nil {
                    Link(destination: ExerciseImages.sourceURL) {
                        Text(ExerciseImages.attribution).font(.caption2).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }
}
