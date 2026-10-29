import Foundation

/// A workout Coach read from a video's caption, screenshots or the member's words (#909).
public struct WorkoutImportResult: Codable, Sendable {
    public struct Item: Codable, Sendable, Hashable {
        /// The move as the post or member named it.
        public var said: String
        /// Closest catalog id, "" when nothing fits.
        public var id: String
        public var sets: Int
        public var reps: Int
        /// "reps", "sec" or "min".
        public var unit: String
        public var sure: Bool
    }

    public struct Source: Codable, Sendable, Hashable {
        /// "tiktok", "instagram", "youtube" or "web".
        public var platform: String
        public var url: String
        public var author: String?
    }

    public var name: String
    public var minutes: Int
    public var items: [Item]
    public var source: Source?
    public var remainingToday: Int
}

extension APIClient {
    /// Save a workout seen on TikTok / Instagram (#909): any of the post's link, its caption, up to 4 JPEG screenshots
    /// and the member's own words. Errors: `pro_required` (402), `verification_required` (403), `nothing_to_read` (422),
    /// `daily_limit` / `busy` (429), `import_failed` (502), `import_unavailable` (503), `bad_link` / `bad_photo` (400).
    public func workoutImport(link: String?, caption: String?, text: String?, photos: [Data], catalog: [GymScanItem]) async throws -> WorkoutImportResult {
        struct Body: Encodable {
            var link: String?
            var caption: String?
            var text: String?
            var photos: [String]
            var catalog: [GymScanItem]
        }
        let body = Body(link: link, caption: caption, text: text, photos: photos.map { $0.base64EncodedString() }, catalog: catalog)
        return try await scanRequest("/v1/me/workout-import", body, as: WorkoutImportResult.self)
    }
}
