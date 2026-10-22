import Foundation
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
        image = UIImage(data: jpeg)
    }

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
              (response as? HTTPURLResponse)?.statusCode == 200, let img = UIImage(data: data) else { return }
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
