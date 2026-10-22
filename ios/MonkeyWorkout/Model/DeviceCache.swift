import Foundation

/// Last server answers kept on the device (#641), so screens show them at launch and offline instead of a spinner
/// until the server answers. Each file belongs to one account; another account's file reads as nothing.
enum DeviceCache {
    private struct Box<T: Codable>: Codable {
        var userId: String
        var value: T
    }

    private static func url(_ name: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cache", isDirectory: true).appendingPathComponent(name)
    }

    static func load<T: Codable>(_ type: T.Type, _ name: String, userId: String?) -> T? {
        guard let userId, let data = try? Data(contentsOf: url(name)),
              let box = try? JSONDecoder().decode(Box<T>.self, from: data), box.userId == userId else { return nil }
        return box.value
    }

    /// Saves `value` for `userId`; nil (value or user) removes the file.
    static func save<T: Codable>(_ value: T?, _ name: String, userId: String?) {
        guard let value, let userId, let data = try? JSONEncoder().encode(Box(userId: userId, value: value)) else {
            remove(name)
            return
        }
        let u = url(name)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func remove(_ name: String) { try? FileManager.default.removeItem(at: url(name)) }

    /// Sign-out and account switch.
    static func wipe() {
        try? FileManager.default.removeItem(at: url("x").deletingLastPathComponent())
    }
}
