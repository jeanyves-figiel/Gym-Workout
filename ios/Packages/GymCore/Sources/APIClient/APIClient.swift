import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Typed client for the MonkeyWorkout API. Handles token storage and transparent, single-flight refresh.
public actor APIClient {
    public let baseURL: URL
    private let session: URLSession
    private let tokens: TokenStore
    private let deviceName: String?
    private let now: @Sendable () -> Date
    private var refreshTask: Task<StoredTokens, Error>?
    private var onSignedOut: (@Sendable () -> Void)?

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = APIClient.parseISO(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "Bad date \(s)"))
        }
        return d
    }()

    public init(
        baseURL: URL,
        tokens: TokenStore,
        session: URLSession = .shared,
        deviceName: String? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.baseURL = baseURL
        self.tokens = tokens
        self.session = session
        self.deviceName = deviceName
        self.now = now
    }

    /// Called when the session is irrecoverably gone (refresh rejected).
    public func setOnSignedOut(_ handler: @escaping @Sendable () -> Void) { onSignedOut = handler }

    public var hasSession: Bool { tokens.load() != nil }

    // MARK: Registration & sign-in

    public func register(email: String, password: String, name: String?, acceptedTerms: Bool) async throws {
        struct Body: Encodable { var email, password: String; var name: String?; var acceptedTerms: Bool }
        _ = try await send("POST", "/v1/auth/register", Body(email: email, password: password, name: name, acceptedTerms: acceptedTerms))
    }

    public func verifyEmail(email: String, code: String) async throws -> User {
        struct Body: Encodable { var email, code: String }
        return try await authenticate("/v1/auth/verify-email", Body(email: email, code: code))
    }

    public func resendVerification(email: String) async throws {
        struct Body: Encodable { var email: String }
        _ = try await send("POST", "/v1/auth/resend-verification", Body(email: email))
    }

    public func login(email: String, password: String) async throws -> User {
        struct Body: Encodable { var email, password: String }
        return try await authenticate("/v1/auth/login", Body(email: email, password: password))
    }

    /// `authorizationCode` lets the server obtain an Apple refresh token, revoked when the account is deleted.
    public func signInWithApple(identityToken: String, name: String?, authorizationCode: String? = nil) async throws -> User {
        struct Body: Encodable { var identityToken: String; var authorizationCode: String?; var name: String? }
        return try await authenticate("/v1/auth/apple", Body(identityToken: identityToken, authorizationCode: authorizationCode, name: name))
    }

    public func forgotPassword(email: String) async throws {
        struct Body: Encodable { var email: String }
        _ = try await send("POST", "/v1/auth/password/forgot", Body(email: email))
    }

    public func resetPassword(email: String, code: String, newPassword: String) async throws {
        struct Body: Encodable { var email, code, newPassword: String }
        _ = try await send("POST", "/v1/auth/password/reset", Body(email: email, code: code, newPassword: newPassword))
    }

    /// Revokes this device's refresh token (best effort) and forgets tokens locally.
    public func logout() async {
        struct Body: Encodable { var refreshToken: String }
        if let t = tokens.load() { _ = try? await send("POST", "/v1/auth/logout", Body(refreshToken: t.refreshToken)) }
        tokens.clear()
    }

    // MARK: Account

    public func me() async throws -> User {
        try await authorized("GET", "/v1/me", Empty?.none, as: UserResponse.self).user
    }

    public func updateName(_ name: String?) async throws -> User {
        struct Body: Encodable {
            var name: String?
            func encode(to e: Encoder) throws {
                var c = e.container(keyedBy: CodingKeys.self)
                try c.encode(name, forKey: .name) // explicit null clears the name
            }
            enum CodingKeys: String, CodingKey { case name }
        }
        return try await authorized("PATCH", "/v1/me", Body(name: name), as: UserResponse.self).user
    }

    public func changePassword(current: String?, new: String) async throws {
        struct Body: Encodable { var currentPassword: String?; var newPassword: String }
        let r = try await authorized("POST", "/v1/me/password", Body(currentPassword: current, newPassword: new), as: TokensResponse.self)
        store(r.tokens)
    }

    /// Emails a 6-digit code to `newEmail`; `password` is required when the account has one.
    public func requestEmailChange(newEmail: String, password: String?) async throws {
        struct Body: Encodable { var newEmail: String; var password: String? }
        _ = try await authorizedRaw("POST", "/v1/me/email", Body(newEmail: newEmail, password: password))
    }

    /// Confirms the pending email change; the old address is notified by the server.
    public func confirmEmailChange(code: String) async throws -> User {
        struct Body: Encodable { var code: String }
        return try await authorized("POST", "/v1/me/email/confirm", Body(code: code), as: UserResponse.self).user
    }

    public func sessions() async throws -> [ActiveSession] {
        try await authorized("GET", "/v1/me/sessions", Empty?.none, as: SessionsResponse.self).sessions
    }

    public func logoutAllDevices() async throws {
        _ = try await authorizedRaw("POST", "/v1/me/logout-all", Empty())
        tokens.clear()
    }

    /// Permanently deletes the account and all server data.
    public func deleteAccount(password: String?) async throws {
        struct Body: Encodable { var confirm = "DELETE"; var password: String? }
        _ = try await authorizedRaw("DELETE", "/v1/me", Body(password: password))
        tokens.clear()
    }

    /// Full JSON export of everything stored for the account.
    public func exportData() async throws -> Data {
        try await authorizedRaw("GET", "/v1/me/export", Empty?.none)
    }

    // MARK: Sync

    public func fetchProfile<T: Decodable & Sendable>(_: T.Type) async throws -> T? {
        try await authorized("GET", "/v1/me/profile", Empty?.none, as: ProfileResponse<T>.self).data
    }

    public func saveProfile<T: Encodable & Sendable>(_ profile: T) async throws {
        _ = try await authorizedRaw("PUT", "/v1/me/profile", ProfileBody(data: profile))
    }

    public func fetchLogs(since: Date? = nil) async throws -> [LogEntry] {
        var path = "/v1/me/logs"
        if let since {
            let s = ISO8601DateFormatter().string(from: since)
            path += "?since=\(s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s)"
        }
        return try await authorized("GET", path, Empty?.none, as: LogsResponse.self).logs
    }

    public func pushLogs(_ logs: [LogEntry]) async throws {
        struct Body: Encodable { var logs: [LogEntry] }
        for chunk in stride(from: 0, to: logs.count, by: 500).map({ Array(logs[$0..<min($0 + 500, logs.count)]) }) {
            _ = try await authorizedRaw("POST", "/v1/me/logs", Body(logs: chunk))
        }
    }

    /// Completed workout records (app-defined, must encode `id` + `startedAt`).
    public func fetchWorkouts<T: Decodable & Sendable>(_: T.Type, since: Date? = nil) async throws -> [T] {
        var path = "/v1/me/workouts"
        if let since {
            let s = ISO8601DateFormatter().string(from: since)
            path += "?since=\(s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s)"
        }
        return try await authorized("GET", path, Empty?.none, as: WorkoutsResponse<T>.self).workouts
    }

    public func pushWorkouts<T: Encodable & Sendable>(_ workouts: [T]) async throws {
        for chunk in stride(from: 0, to: workouts.count, by: 100).map({ Array(workouts[$0..<min($0 + 100, workouts.count)]) }) {
            _ = try await authorizedRaw("POST", "/v1/me/workouts", WorkoutsBody(workouts: chunk))
        }
    }

    public func deleteWorkout(_ id: UUID) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/me/workouts/\(id.uuidString)", Empty?.none)
    }

    /// User-built workouts (app-defined, must encode `id`, `name` and `items[].exerciseId`).
    public func fetchCustomWorkouts<T: Decodable & Sendable>(_: T.Type, since: Date? = nil) async throws -> [T] {
        var path = "/v1/me/custom-workouts"
        if let since {
            let s = ISO8601DateFormatter().string(from: since)
            path += "?since=\(s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s)"
        }
        return try await authorized("GET", path, Empty?.none, as: WorkoutsResponse<T>.self).workouts
    }

    public func pushCustomWorkouts<T: Encodable & Sendable>(_ workouts: [T]) async throws {
        for chunk in stride(from: 0, to: workouts.count, by: 100).map({ Array(workouts[$0..<min($0 + 100, workouts.count)]) }) {
            _ = try await authorizedRaw("POST", "/v1/me/custom-workouts", WorkoutsBody(workouts: chunk))
        }
    }

    public func deleteCustomWorkout(_ id: UUID) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/me/custom-workouts/\(id.uuidString)", Empty?.none)
    }

    /// User-built exercises (app-defined, must encode `id` and `name`; may carry a base64 `photo`).
    public func fetchCustomExercises<T: Decodable & Sendable>(_: T.Type) async throws -> [T] {
        try await authorized("GET", "/v1/me/custom-exercises", Empty?.none, as: ExercisesResponse<T>.self).exercises
    }

    /// One per request: photos make records large (server body limit 1 MB).
    public func pushCustomExercises<T: Encodable & Sendable>(_ exercises: [T]) async throws {
        for e in exercises {
            _ = try await authorizedRaw("POST", "/v1/me/custom-exercises", ExercisesBody(exercises: [e]))
        }
    }

    /// Personal-record attempts (app-defined; must encode `id`, `exerciseId`, `date`, `kind`, `kg`, `reps`, `success`).
    public func fetchPRAttempts<T: Decodable & Sendable>(_: T.Type) async throws -> [T] {
        try await authorized("GET", "/v1/me/pr-attempts", Empty?.none, as: AttemptsResponse<T>.self).attempts
    }

    public func pushPRAttempts<T: Encodable & Sendable>(_ attempts: [T]) async throws {
        for chunk in stride(from: 0, to: attempts.count, by: 200).map({ Array(attempts[$0..<min($0 + 200, attempts.count)]) }) {
            _ = try await authorizedRaw("POST", "/v1/me/pr-attempts", AttemptsBody(attempts: chunk))
        }
    }

    public func deleteLog(_ id: UUID) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/me/logs/\(id.uuidString)", Empty?.none)
    }

    public func deletePRAttempt(_ id: UUID) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/me/pr-attempts/\(id.uuidString)", Empty?.none)
    }

    // MARK: Internals

    struct Empty: Codable {}
    struct ProfileBody<T: Encodable>: Encodable { var data: T }
    struct WorkoutsBody<T: Encodable>: Encodable { var workouts: [T] }
    struct WorkoutsResponse<T: Decodable>: Decodable { var workouts: [T] }
    struct ExercisesBody<T: Encodable>: Encodable { var exercises: [T] }
    struct ExercisesResponse<T: Decodable>: Decodable { var exercises: [T] }
    struct AttemptsBody<T: Encodable>: Encodable { var attempts: [T] }
    struct AttemptsResponse<T: Decodable>: Decodable { var attempts: [T] }

    private func authenticate(_ path: String, _ body: some Encodable) async throws -> User {
        let data = try await send("POST", path, body)
        let r = try decode(AuthResponse.self, data)
        store(r.tokens)
        return r.user
    }

    private func store(_ t: TokenPair) {
        tokens.save(StoredTokens(
            accessToken: t.accessToken,
            accessExpiresAt: now().addingTimeInterval(TimeInterval(t.accessTokenExpiresIn)),
            refreshToken: t.refreshToken))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try decoder.decode(type, from: data) } catch { throw APIError.decoding(String(describing: error)) }
    }

    private func authorized<T: Decodable>(_ method: String, _ path: String, _ body: (some Encodable)?, as type: T.Type) async throws -> T {
        try decode(type, try await authorizedRaw(method, path, body))
    }

    /// Adds bearer token; refreshes proactively (≤30 s left) and once on 401.
    private func authorizedRaw(_ method: String, _ path: String, _ body: (some Encodable)?) async throws -> Data {
        guard var t = tokens.load() else { throw APIError.signedOut }
        if t.accessExpiresAt.timeIntervalSince(now()) < 30 { t = try await refreshed(t) }
        do {
            return try await send(method, path, body, bearer: t.accessToken)
        } catch let APIError.server(status, _, _) where status == 401 {
            t = try await refreshed(t)
            return try await send(method, path, body, bearer: t.accessToken)
        }
    }

    /// Single-flight refresh: concurrent callers await the same task (server rotates and rejects replays).
    private func refreshed(_ stale: StoredTokens) async throws -> StoredTokens {
        if let current = tokens.load(), current.accessToken != stale.accessToken { return current }
        if let task = refreshTask { return try await task.value }
        let task = Task<StoredTokens, Error> {
            struct Body: Encodable { var refreshToken: String }
            do {
                let data = try await send("POST", "/v1/auth/refresh", Body(refreshToken: stale.refreshToken))
                let pair = try decode(TokenPair.self, data)
                store(pair)
                return tokens.load()!
            } catch let APIError.server(status, _, _) where status == 401 {
                tokens.clear()
                onSignedOut?()
                throw APIError.signedOut
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func send(_ method: String, _ path: String, _ body: (some Encodable)?, bearer: String? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.network("Bad URL \(path)") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let deviceName { req.setValue(deviceName, forHTTPHeaderField: "X-Device-Name") }
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.network("No HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            if let e = try? JSONDecoder().decode(ErrorBody.self, from: data) {
                throw APIError.server(status: http.statusCode, code: e.error, message: e.message)
            }
            throw APIError.server(status: http.statusCode, code: "http_\(http.statusCode)", message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
        return data
    }

    static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
