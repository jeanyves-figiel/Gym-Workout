import Foundation

// Studio coach voices (#395): Polly neural recordings of the coach's lines, made once on the server and downloaded per voice.

public struct CoachVoiceCatalog: Codable, Sendable, Equatable {
    public struct Voice: Codable, Sendable, Equatable, Identifiable, Hashable {
        public var id: String
        public var name: String
        /// female | male
        public var gender: String
        /// us, gb, au, ie, in, za, nz
        public var accent: String
        public var label: String

        public init(id: String, name: String, gender: String, accent: String, label: String) {
            self.id = id
            self.name = name
            self.gender = gender
            self.accent = accent
            self.label = label
        }
    }

    public struct Line: Codable, Sendable, Equatable {
        /// `<style>-<kind>-<n>`
        public var id: String
        public var text: String
        public var hash: String

        public init(id: String, text: String, hash: String) {
            self.id = id
            self.text = text
            self.hash = hash
        }
    }

    public var available: Bool
    public var voices: [Voice]
    public var lines: [Line]

    public init(available: Bool, voices: [Voice], lines: [Line]) {
        self.available = available
        self.voices = voices
        self.lines = lines
    }
}

extension APIClient {
    public func coachVoices() async throws -> CoachVoiceCatalog {
        try await authorized("GET", "/v1/me/coach-voices", Empty?.none, as: CoachVoiceCatalog.self)
    }

    /// MP3 of one line in one voice.
    public func coachVoiceLine(voice: String, line: String) async throws -> Data {
        try await authorizedRaw("GET", "/v1/me/coach-voices/\(voice)/\(line).mp3", Empty?.none)
    }

    /// MP3 of the short call said before key lines (#415): "Alex!" (hype) or "Alex." (chill, drill).
    /// The name goes in `X-Call-Name`, never in the URL (kept out of request logs).
    public func coachVoiceCall(voice: String, style: String, name: String) async throws -> Data {
        try await authorizedRaw("GET", "/v1/me/coach-voices/\(voice)/call/\(style).mp3", Empty?.none,
                                headers: ["X-Call-Name": Self.callNameHeader(name)])
    }

    /// Percent-encoded UTF-8 (the server decodes it with `decodeURIComponent`): header values stay plain ASCII.
    static func callNameHeader(_ name: String) -> String {
        name.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// RFC 3986 unreserved characters, ASCII only (`.alphanumerics` would let "é" through unencoded).
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
