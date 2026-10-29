import Foundation

/// A post shared to MonkeyFit from TikTok, Instagram or any app (#909 A): the share extension drops it in the App Group,
/// the app picks it up on open and shows *Save from a video* with it. Screenshots are kept only until then.
struct VideoShare: Codable {
    var link: String?
    var text: String?
    /// File names of the shared images, next to `share.json`.
    var images: [String]
    var at: Date
}

enum VideoInbox {
    /// `MWAppGroup` = $(APP_GROUP) in both Info.plists, so DEV and App Store builds keep separate inboxes.
    private static var folder: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "MWAppGroup") as? String,
              let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return base.appendingPathComponent("video-inbox", isDirectory: true)
    }

    /// Extension side: replaces whatever was waiting (only the latest share matters). JPEGs, at most 4.
    @discardableResult
    static func put(link: String?, text: String?, jpegs: [Data]) -> Bool {
        guard let folder else { return false }
        let fm = FileManager.default
        try? fm.removeItem(at: folder)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var names: [String] = []
            for (i, data) in jpegs.prefix(4).enumerated() {
                let name = "shot-\(i).jpg"
                try data.write(to: folder.appendingPathComponent(name), options: .atomic)
                names.append(name)
            }
            let share = VideoShare(link: link, text: text, images: names, at: Date())
            try JSONEncoder().encode(share).write(to: folder.appendingPathComponent("share.json"), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// App side: the waiting share with its images (a day at most), then the inbox is emptied.
    static func take(now: Date = Date()) -> (share: VideoShare, images: [Data])? {
        guard let folder else { return nil }
        defer { try? FileManager.default.removeItem(at: folder) }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("share.json")),
              let share = try? JSONDecoder().decode(VideoShare.self, from: data),
              now.timeIntervalSince(share.at) < 86_400 else { return nil }
        let images = share.images.compactMap { try? Data(contentsOf: folder.appendingPathComponent($0)) }
        return (share, images)
    }
}
