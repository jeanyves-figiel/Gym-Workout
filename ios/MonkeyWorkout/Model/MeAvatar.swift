import Foundation
import ImageIO
import UIKit

/// Your own photo kept on this device (#639), so the Me pill shows it at launch instead of after the profile calls
/// and the download (≈10 s on a cold server). Refreshed in the background when the photo's URL changes.
@MainActor @Observable
final class MeAvatar {
    static let shared = MeAvatar()

    private(set) var image: UIImage?
    private var saved: Saved?
    private var fetching: URL?

    private struct Saved: Codable {
        var userId: String
        var url: URL
    }

    private static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    private static var metaURL: URL { dir.appendingPathComponent("me-avatar.json") }
    private static var imageURL: URL { dir.appendingPathComponent("me-avatar.jpg") }

    private init() {
        guard let data = try? Data(contentsOf: Self.metaURL), let s = try? JSONDecoder().decode(Saved.self, from: data),
              let jpeg = try? Data(contentsOf: Self.imageURL) else { return }
        saved = s
        image = AvatarImages.downsample(jpeg, maxPixels: Self.pixels) ?? UIImage(data: jpeg)
    }

    /// The Me pill is small: the photo is kept decoded at this size, not the upload's (#720).
    private static let pixels = 240

    /// The kept photo, only for the account it was saved for.
    func image(for userId: String?) -> UIImage? {
        guard let userId, saved?.userId == userId else { return nil }
        return image
    }

    /// Follows the profile's photo once it is loaded: downloads a new URL, forgets a removed photo.
    func update(_ url: URL?, userId: String?) async {
        guard let userId else { return }
        guard let url else {
            if saved != nil { wipe() }
            return
        }
        if saved?.userId == userId, saved?.url == url, image != nil { return }
        guard fetching != url else { return }
        fetching = url
        defer { fetching = nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let img = AvatarImages.downsample(data, maxPixels: Self.pixels) ?? UIImage(data: data) else { return }
        let s = Saved(userId: userId, url: url)
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        try? data.write(to: Self.imageURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if let meta = try? JSONEncoder().encode(s) {
            try? meta.write(to: Self.metaURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        saved = s
        image = img
    }

    func wipe() {
        saved = nil
        image = nil
        try? FileManager.default.removeItem(at: Self.metaURL)
        try? FileManager.default.removeItem(at: Self.imageURL)
    }
}

/// Profile photos decoded at the size they are drawn (#720): a large upload shown in a 32 pt circle is no longer
/// decoded full size on the main thread, and a feed scrolling back finds them in a small cache.
enum AvatarImages {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 120
        return c
    }()

    private static func key(_ url: URL, _ pixels: Int) -> NSString { "\(pixels)|\(url.absoluteString)" as NSString }

    static func cached(_ url: URL, pixels: Int) -> UIImage? { cache.object(forKey: key(url, pixels)) }

    /// Downloads (through the shared URL cache) and downsamples the photo; nil when it can't be had.
    static func load(_ url: URL, pixels: Int) async -> UIImage? {
        if let hit = cached(url, pixels: pixels) { return hit }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let image = await Task.detached(priority: .utility) { downsample(data, maxPixels: pixels) }.value
        if let image { cache.setObject(image, forKey: key(url, pixels)) }
        return image
    }

    /// The image no larger than `maxPixels` on its long side, decoded once (ImageIO thumbnail).
    static func downsample(_ data: Data, maxPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixels),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}
