import Foundation

/// The phone snapshot shared by the Watch app with its complications (#190) through the App Group container.
/// Compiled into the Watch app (writes) and the complications extension (reads).
enum SharedSnapshot {
    /// From Info.plist (`MWAppGroup` = $(APP_GROUP)), so DEV and App Store builds keep separate containers.
    static let group = Bundle.main.object(forInfoDictionaryKey: "MWAppGroup") as? String

    static var url: URL? {
        group.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }?
            .appendingPathComponent("snapshot.json")
    }

    static func load() -> WatchSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.watch.decode(WatchSnapshot.self, from: data)
    }

    static func save(_ data: Data) {
        guard let url else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
