import Foundation

// Member problem reports (#467): Report a problem page, shake to report, Report on errors.

public struct ProblemReport: Encodable, Sendable, Equatable {
    public struct AppInfo: Encodable, Sendable, Equatable {
        public var version: String
        public var build: String
        public var os: String
        public var device: String
        public var locale: String?

        public init(version: String, build: String, os: String, device: String, locale: String? = nil) {
            self.version = version
            self.build = build
            self.os = os
            self.device = device
            self.locale = locale
        }
    }

    /// "bug", "broken" or "idea".
    public var kind: String
    public var area: String
    public var text: String
    public var screen: String?
    public var error: String?
    /// "settings", "shake" or "error".
    public var via: String
    public var app: AppInfo
    /// Base64 JPEGs, ≤ 1024 px per side and 512 KB each, at most 3.
    public var screenshots: [String]

    public init(kind: String, area: String, text: String, screen: String? = nil, error: String? = nil, via: String,
                app: AppInfo, screenshots: [Data] = []) {
        self.kind = kind
        self.area = area
        self.text = text
        self.screen = screen
        self.error = error
        self.via = via
        self.app = app
        self.screenshots = screenshots.map { $0.base64EncodedString() }
    }
}

extension APIClient {
    /// Sends a report to the team. Returns the GitHub issue number when one was opened.
    public func sendProblemReport(_ report: ProblemReport) async throws -> Int? {
        struct R: Decodable { var issueNumber: Int? }
        return try await authorized("POST", "/v1/me/reports", report, as: R.self).issueNumber
    }
}
