import Foundation

public struct User: Codable, Sendable, Equatable {
    public var id: String
    public var email: String?
    public var name: String?
    public var emailVerified: Bool
    public var hasPassword: Bool
    public var appleLinked: Bool
    public var createdAt: String
}

public struct TokenPair: Codable, Sendable, Equatable {
    public var tokenType: String
    public var accessToken: String
    public var accessTokenExpiresIn: Int
    public var refreshToken: String
    public var refreshTokenExpiresAt: String
}

public struct StoredTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var accessExpiresAt: Date
    public var refreshToken: String

    public init(accessToken: String, accessExpiresAt: Date, refreshToken: String) {
        self.accessToken = accessToken
        self.accessExpiresAt = accessExpiresAt
        self.refreshToken = refreshToken
    }
}

public struct ActiveSession: Codable, Sendable, Equatable {
    public var device: String?
    public var createdAt: String
    public var expiresAt: String
}

public struct LogEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var exerciseId: String
    public var sessionId: String?
    public var weightKg: Double?
    public var reps: Int?
    /// 0-based set number within the session (per-set logging). Nil for legacy one-weight-per-exercise logs.
    public var setIndex: Int?
    /// Reps in reserve for that set (optional).
    public var rir: Int?

    public init(
        id: UUID = UUID(), date: Date, exerciseId: String, sessionId: String? = nil, weightKg: Double? = nil, reps: Int? = nil,
        setIndex: Int? = nil, rir: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.exerciseId = exerciseId
        self.sessionId = sessionId
        self.weightKg = weightKg
        self.reps = reps
        self.setIndex = setIndex
        self.rir = rir
    }
}

struct AuthResponse: Decodable {
    var user: User
    var tokens: TokenPair
}

struct UserResponse: Decodable { var user: User }
struct TokensResponse: Decodable { var tokens: TokenPair }
struct SessionsResponse: Decodable { var sessions: [ActiveSession] }
struct LogsResponse: Decodable {
    private var list: LossyArray<LogEntry>
    var logs: [LogEntry] { list.elements }
    /// With `?since=`: ids deleted on the server since then (#432). Absent on older servers.
    var deleted: [String]?
    enum CodingKeys: String, CodingKey { case list = "logs", deleted }
}

/// A delta pull of set logs: changed entries plus ids deleted on the server since then (#432).
public struct LogChanges: Sendable, Equatable {
    public var logs: [LogEntry]
    public var deleted: Set<UUID>

    public init(logs: [LogEntry], deleted: Set<UUID> = []) {
        self.logs = logs
        self.deleted = deleted
    }
}

/// List that skips elements it can't decode (a record a newer app version wrote, a bad row), so one of them
/// doesn't fail the whole pull. Also used for the app's state file, so one bad record doesn't wipe a list.
public struct LossyArray<Element: Decodable>: Decodable {
    public var elements: [Element]
    /// Elements that didn't decode and were left out (nulls not counted).
    public var skipped = 0

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var out: [Element] = []
        while !c.isAtEnd {
            let index = c.currentIndex
            if try c.decodeNil() { continue }
            if let e = try? c.decode(Element.self) {
                out.append(e)
            } else {
                skipped += 1
                _ = try? c.decode(Skip.self)
            }
            // A failed decode doesn't always advance the container: never spin on one element.
            if c.currentIndex == index { break }
        }
        elements = out
    }

    /// Consumes any one value.
    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
struct ProfileResponse<T: Decodable>: Decodable {
    var data: T?
    var updatedAt: String?
}

struct ErrorBody: Decodable {
    var error: String
    var message: String
    var mfaToken: String?
}

public enum APIError: Error, Equatable, LocalizedError {
    /// Server returned `{error, message}`; `code` is the machine-readable error.
    case server(status: Int, code: String, message: String)
    /// Session gone (refresh failed) — user must sign in again.
    case signedOut
    case network(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case let .server(_, _, message): message
        case .signedOut: "Your session expired. Please sign in again."
        case let .network(m): "Network problem: \(m)"
        case .decoding: "Unexpected server response."
        }
    }

    public var code: String? {
        if case let .server(_, code, _) = self { return code }
        return nil
    }
}

/// Result of `POST /v1/me/push-test`.
public struct PushTestResult: Codable, Sendable, Equatable {
    public var devices: Int
    public var sent: Int
    public var pushConfigured: Bool
}

/// `POST /v1/me/achievements` item: stable id, kind ("badge", "pr") and the line followers see.
public struct AchievementAnnouncement: Codable, Sendable, Equatable {
    public var id: String
    public var type: String
    public var text: String

    public init(id: String, type: String, text: String) {
        self.id = id
        self.type = type
        self.text = text
    }
}
