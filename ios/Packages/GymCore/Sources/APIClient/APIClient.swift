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
    let now: @Sendable () -> Date
    private var refreshTask: Task<StoredTokens, Error>?
    private var onSignedOut: (@Sendable () -> Void)?
    /// "Confirm it's you" grant (#257), sent as `X-Reauth-Token` on account calls until it expires.
    var reauthGrant: (token: String, expiresAt: Date)?

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

    /// Default session: no HTTP cache, so personal responses (tokens, workouts, exports) never land in the
    /// shared on-disk `URLCache`.
    public static let uncachedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    public init(
        baseURL: URL,
        tokens: TokenStore,
        session: URLSession = APIClient.uncachedSession,
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

    /// Drops stored tokens without calling the server (e.g. Keychain left over from an earlier install).
    public func forgetTokens() {
        tokens.clear()
        reauthGrant = nil
    }

    // MARK: Registration & sign-in

    public func register(email: String, password: String, name: String?, acceptedTerms: Bool) async throws {
        struct Body: Encodable { var email, password: String; var name: String?; var acceptedTerms: Bool }
        _ = try await send("POST", "/v1/auth/register", Body(email: email, password: password, name: name, acceptedTerms: acceptedTerms))
    }

    /// `password`: whoever proves the inbox sets it (#432); left out of the body when nil.
    public func verifyEmail(email: String, code: String, password: String? = nil) async throws -> User {
        struct Body: Encodable { var email, code: String; var password: String? }
        return try await authenticate("/v1/auth/verify-email", Body(email: email, code: code, password: password))
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
    /// `nonce`: the raw `AppleNonce` whose hash was set on the Apple request (#432).
    public func signInWithApple(identityToken: String, name: String?, authorizationCode: String? = nil, nonce: String? = nil) async throws -> User {
        struct Body: Encodable { var identityToken: String; var authorizationCode: String?; var name: String?; var nonce: String? }
        return try await authenticate("/v1/auth/apple", Body(identityToken: identityToken, authorizationCode: authorizationCode, name: name, nonce: nonce))
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
        reauthGrant = nil
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

    /// Needs a fresh "confirm it's you" (#257); the server answers `reauth_required` otherwise.
    public func changePassword(current: String? = nil, new: String) async throws {
        struct Body: Encodable { var currentPassword: String?; var newPassword: String }
        let r = try await authorized("POST", "/v1/me/password", Body(currentPassword: current, newPassword: new), as: TokensResponse.self)
        store(r.tokens)
    }

    /// Emails a 6-digit code to `newEmail`. Needs a fresh "confirm it's you" (#257).
    public func requestEmailChange(newEmail: String, password: String? = nil) async throws {
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

    /// Permanently deletes the account and all server data. Needs a fresh "confirm it's you" (#257).
    public func deleteAccount(password: String? = nil) async throws {
        struct Body: Encodable { var confirm = "DELETE"; var password: String? }
        _ = try await authorizedRaw("DELETE", "/v1/me", Body(password: password))
        tokens.clear()
        reauthGrant = nil
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
        try await fetchLogChanges(since: since).logs
    }

    /// Like `fetchLogs`, plus the ids deleted on the server since `since` (another device's undo, #432).
    public func fetchLogChanges(since: Date? = nil) async throws -> LogChanges {
        var path = "/v1/me/logs"
        if let since {
            let s = ISO8601DateFormatter().string(from: since)
            path += "?since=\(s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s)"
        }
        let r = try await authorized("GET", path, Empty?.none, as: LogsResponse.self)
        return LogChanges(logs: r.logs, deleted: Set((r.deleted ?? []).compactMap(UUID.init(uuidString:))),
                          serverTime: r.serverTime.flatMap { Self.parseISO($0) }, fullResync: r.fullResync == true)
    }

    /// Uploads set logs; ones changed on the server since their `updatedAt` come back as conflicts (not written).
    @discardableResult
    public func pushLogs(_ logs: [LogEntry]) async throws -> UploadResult<LogEntry> {
        struct Body: Encodable { var logs: [VersionedUpload<LogEntry>] }
        return try await upload("/v1/me/logs", logs, chunk: 500) { Body(logs: $0) }
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

    @discardableResult
    public func pushWorkouts<T: Codable & Sendable & ServerVersioned>(_ workouts: [T]) async throws -> UploadResult<T> {
        try await upload("/v1/me/workouts", workouts, chunk: 100) { WorkoutsBody(workouts: $0) }
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

    @discardableResult
    public func pushCustomWorkouts<T: Codable & Sendable & ServerVersioned>(_ workouts: [T]) async throws -> UploadResult<T> {
        try await upload("/v1/me/custom-workouts", workouts, chunk: 100) { WorkoutsBody(workouts: $0) }
    }

    public func deleteCustomWorkout(_ id: UUID) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/me/custom-workouts/\(id.uuidString)", Empty?.none)
    }

    /// User-built exercises (app-defined, must encode `id` and `name`; may carry a base64 `photo`).
    public func fetchCustomExercises<T: Decodable & Sendable>(_: T.Type) async throws -> [T] {
        try await authorized("GET", "/v1/me/custom-exercises", Empty?.none, as: ExercisesResponse<T>.self).exercises
    }

    /// One per request: photos make records large (server body limit 1 MB).
    @discardableResult
    public func pushCustomExercises<T: Codable & Sendable & ServerVersioned>(_ exercises: [T]) async throws -> UploadResult<T> {
        try await upload("/v1/me/custom-exercises", exercises, chunk: 1) { ExercisesBody(exercises: $0) }
    }

    /// Personal-record attempts (app-defined; must encode `id`, `exerciseId`, `date`, `kind`, `kg`, `reps`, `success`).
    public func fetchPRAttempts<T: Decodable & Sendable>(_: T.Type) async throws -> [T] {
        try await authorized("GET", "/v1/me/pr-attempts", Empty?.none, as: AttemptsResponse<T>.self).attempts
    }

    @discardableResult
    public func pushPRAttempts<T: Codable & Sendable & ServerVersioned>(_ attempts: [T]) async throws -> UploadResult<T> {
        try await upload("/v1/me/pr-attempts", attempts, chunk: 200) { AttemptsBody(attempts: $0) }
    }

    /// Climbing sessions (#312; app-defined; must encode `id`, `start`, `minutes`, `effort`, `kind`).
    public func fetchClimbs<T: Decodable & Sendable>(_: T.Type) async throws -> [T] {
        try await authorized("GET", "/v1/me/climbs", Empty?.none, as: ClimbsResponse<T>.self).climbs
    }

    @discardableResult
    public func pushClimbs<T: Codable & Sendable & ServerVersioned>(_ climbs: [T]) async throws -> UploadResult<T> {
        try await upload("/v1/me/climbs", climbs, chunk: 200) { ClimbsBody(climbs: $0) }
    }

    public func deleteClimb(_ id: UUID) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/me/climbs/\(id.uuidString)", Empty?.none)
    }

    /// Other sport sessions (#416; app-defined; must encode `id`, `start`, `minutes`, `effort`, `sport`).
    public func fetchSports<T: Decodable & Sendable>(_: T.Type) async throws -> [T] {
        try await authorized("GET", "/v1/me/sports", Empty?.none, as: SportsResponse<T>.self).sports
    }

    @discardableResult
    public func pushSports<T: Codable & Sendable & ServerVersioned>(_ sports: [T]) async throws -> UploadResult<T> {
        try await upload("/v1/me/sports", sports, chunk: 200) { SportsBody(sports: $0) }
    }

    public func deleteSport(_ id: UUID) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/me/sports/\(id.uuidString)", Empty?.none)
    }

    /// Upload-only key for the Watch (#426): lets it post a Hyrox race to `/v1/watch/sports` on its own network.
    /// A new key replaces the previous one.
    public func watchUploadKey() async throws -> String {
        struct Response: Decodable { var key: String }
        return try await authorized("POST", "/v1/me/watch-key", Empty(), as: Response.self).key
    }

    /// Machine setup notes (#355; app-defined; must encode `id`, `gymId`, `gymName`, `exerciseId`, `fields`).
    public func fetchMachineNotes<T: Decodable & Sendable>(_: T.Type) async throws -> [T] {
        try await authorized("GET", "/v1/me/machine-notes", Empty?.none, as: MachineNotesResponse<T>.self).notes
    }

    @discardableResult
    public func pushMachineNotes<T: Codable & Sendable & ServerVersioned>(_ notes: [T]) async throws -> UploadResult<T> {
        try await upload("/v1/me/machine-notes", notes, chunk: 200) { MachineNotesBody(notes: $0) }
    }

    public func deleteMachineNote(_ id: UUID) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/me/machine-notes/\(id.uuidString)", Empty?.none)
    }

    /// JPEG ≤ 512 KB, 64–1024 px per side; the server strips metadata. Returns the new photo id.
    public func uploadMachineNotePhoto(noteId: UUID, jpeg: Data) async throws -> String {
        struct R: Decodable { var photoId: String }
        let data = try await authorizedRaw("PUT", "/v1/me/machine-notes/\(noteId.uuidString)/photo", Empty?.none, raw: (jpeg, "image/jpeg"))
        return try decode(R.self, data).photoId
    }

    public func deleteMachineNotePhoto(noteId: UUID) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/me/machine-notes/\(noteId.uuidString)/photo", Empty?.none)
    }

    /// The photo's JPEG bytes; only its owner can read it.
    public func machineNotePhoto(_ photoId: String) async throws -> Data {
        try await authorizedRaw("GET", "/v1/me/machine-notes/photos/\(photoId)", Empty?.none)
    }

    public func deleteLog(_ id: UUID) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/me/logs/\(id.uuidString)", Empty?.none)
    }

    public func deletePRAttempt(_ id: UUID) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/me/pr-attempts/\(id.uuidString)", Empty?.none)
    }

    // MARK: Body measurements (#185)

    public func fetchBodyMeasurements<T: Decodable & Sendable>(_: T.Type) async throws -> [T] {
        try await authorized("GET", "/v1/me/body-measurements", Empty?.none, as: MeasurementsResponse<T>.self).measurements
    }

    @discardableResult
    public func pushBodyMeasurements<T: Codable & Sendable & ServerVersioned>(_ measurements: [T]) async throws -> UploadResult<T> {
        try await upload("/v1/me/body-measurements", measurements, chunk: 200) { MeasurementsBody(measurements: $0) }
    }

    public func deleteBodyMeasurement(_ id: UUID) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/me/body-measurements/\(id.uuidString)", Empty?.none)
    }

    // MARK: Notifications (#69)

    /// Registers this install's APNs token (hex). `env`: "sandbox" (debug builds) or "production".
    public func registerPushDevice(token: String, env: String, topic: String, timeZone: String) async throws {
        struct Body: Encodable { var token, env, topic, tz: String }
        _ = try await authorizedRaw("PUT", "/v1/me/push-device", Body(token: token, env: env, topic: topic, tz: timeZone))
    }

    public func unregisterPushDevice(token: String) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/me/push-device/\(token)", Empty?.none)
    }

    /// Notification preferences (app-defined; server validates the known keys).
    public func saveNotificationPrefs<T: Encodable & Sendable>(_ prefs: T) async throws {
        _ = try await authorizedRaw("PUT", "/v1/me/notification-prefs", PrefsBody(prefs: prefs))
    }

    /// Achievements just unlocked on this device; the server pushes them to followers (once per id).
    public func announceAchievements(_ list: [AchievementAnnouncement]) async throws {
        struct Body: Encodable { var achievements: [AchievementAnnouncement] }
        _ = try await authorizedRaw("POST", "/v1/me/achievements", Body(achievements: list))
    }

    /// Sends a test push to this account's registered devices. Returns devices reached.
    public func sendTestPush() async throws -> PushTestResult {
        try await authorized("POST", "/v1/me/push-test", Empty(), as: PushTestResult.self)
    }

    // MARK: Workout library (#62)

    /// Workouts other members shared (app-defined type), newest first; needs a community profile.
    public func fetchSharedWorkouts<T: Decodable & Sendable>(_: T.Type, query: String? = nil, limit: Int = 50) async throws -> [T] {
        var path = "/v1/library/shared?limit=\(limit)"
        if let q = query?.trimmingCharacters(in: .whitespaces), !q.isEmpty {
            path += "&q=\(q.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
        }
        return try await authorized("GET", path, Empty?.none, as: WorkoutsResponse<T>.self).workouts
    }

    /// Counts a copy into "My workouts" for the author; the copy itself is a new custom workout.
    public func countSharedWorkoutSave(_ id: UUID) async throws {
        _ = try await authorizedRaw("POST", "/v1/library/shared/\(id.uuidString.lowercased())/save", Empty?.none)
    }

    /// Reports a shared workout (spam, harassment, hate, sexual, violence, other); returns whether it is now hidden.
    @discardableResult
    public func reportSharedWorkout(_ id: UUID, reason: String, details: String? = nil) async throws -> Bool {
        struct Body: Encodable { var reason: String; var details: String? }
        struct Response: Decodable { var hidden: Bool }
        return try await authorized("POST", "/v1/library/shared/\(id.uuidString.lowercased())/report", Body(reason: reason, details: details), as: Response.self).hidden
    }

    // MARK: Internals

    struct Empty: Codable {}
    struct ProfileBody<T: Encodable>: Encodable { var data: T }
    struct PrefsBody<T: Encodable>: Encodable { var prefs: T }
    struct WorkoutsBody<T: Encodable>: Encodable { var workouts: [T] }
    /// Lossy: an undecodable workout is skipped, not the whole list.
    struct WorkoutsResponse<T: Decodable>: Decodable {
        private var list: LossyArray<T>
        var workouts: [T] { list.elements }
        enum CodingKeys: String, CodingKey { case list = "workouts" }
    }
    struct ExercisesBody<T: Encodable>: Encodable { var exercises: [T] }
    struct ExercisesResponse<T: Decodable>: Decodable { var exercises: [T] }
    struct AttemptsBody<T: Encodable>: Encodable { var attempts: [T] }
    struct AttemptsResponse<T: Decodable>: Decodable { var attempts: [T] }
    struct ClimbsBody<T: Encodable>: Encodable { var climbs: [T] }
    struct ClimbsResponse<T: Decodable>: Decodable { var climbs: [T] }
    struct SportsBody<T: Encodable>: Encodable { var sports: [T] }
    struct SportsResponse<T: Decodable>: Decodable { var sports: [T] }
    struct MachineNotesBody<T: Encodable>: Encodable { var notes: [T] }
    struct MachineNotesResponse<T: Decodable>: Decodable { var notes: [T] }
    struct MeasurementsBody<T: Encodable>: Encodable { var measurements: [T] }
    struct MeasurementsResponse<T: Decodable>: Decodable { var measurements: [T] }

    /// Uploads `items` in chunks of `size`, each with its `baseUpdatedAt`; collects the conflicts and new versions.
    /// An answer this app can't read doesn't fail the upload (it was written): it just adds nothing.
    private func upload<T: Codable & Sendable & ServerVersioned, B: Encodable>(
        _ path: String, _ items: [T], chunk size: Int, body: ([VersionedUpload<T>]) -> B
    ) async throws -> UploadResult<T> {
        var result = UploadResult<T>()
        for start in stride(from: 0, to: items.count, by: size) {
            let chunk = Array(items[start..<min(start + size, items.count)])
            let data = try await authorizedRaw("POST", path, body(chunk.map { VersionedUpload(item: $0) }))
            let response = try? decode(UploadResponse<T>.self, data)
            let ids = try? decode(UploadConflictIds.self, data)
            result.add(response, ids: ids, uploaded: chunk)
        }
        return result
    }

    func authenticate(_ path: String, _ body: some Encodable) async throws -> User {
        let data = try await send("POST", path, body)
        let r = try decode(AuthResponse.self, data)
        store(r.tokens)
        return r.user
    }

    @discardableResult
    private func store(_ t: TokenPair) -> StoredTokens {
        let stored = StoredTokens(
            accessToken: t.accessToken,
            accessExpiresAt: now().addingTimeInterval(TimeInterval(t.accessTokenExpiresIn)),
            refreshToken: t.refreshToken)
        tokens.save(stored)
        return stored
    }

    func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try decoder.decode(type, from: data) } catch { throw APIError.decoding(String(describing: error)) }
    }

    func authorized<T: Decodable>(_ method: String, _ path: String, _ body: (some Encodable)?, as type: T.Type) async throws -> T {
        try decode(type, try await authorizedRaw(method, path, body))
    }

    /// Adds bearer token; refreshes proactively (≤30 s left) and once on 401.
    func authorizedRaw(_ method: String, _ path: String, _ body: (some Encodable)?, raw: (data: Data, contentType: String)? = nil) async throws -> Data {
        guard var t = tokens.load() else { throw APIError.signedOut }
        if t.accessExpiresAt.timeIntervalSince(now()) < 30 { t = try await refreshed(t) }
        do {
            return try await send(method, path, body, bearer: t.accessToken, raw: raw)
        } catch let APIError.server(status, _, _) where status == 401 {
            t = try await refreshed(t)
            return try await send(method, path, body, bearer: t.accessToken, raw: raw)
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
                // The tokens just received, not a Keychain read-back that can fail (#351).
                return store(pair)
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

    func send(
        _ method: String, _ path: String, _ body: (some Encodable)?, bearer: String? = nil, raw: (data: Data, contentType: String)? = nil
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.network("Bad URL \(path)") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let deviceName { req.setValue(deviceName, forHTTPHeaderField: "X-Device-Name") }
        if let bearer {
            req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            if let g = reauthGrant, g.expiresAt > now() { req.setValue(g.token, forHTTPHeaderField: "X-Reauth-Token") }
        }
        if let raw {
            req.setValue(raw.contentType, forHTTPHeaderField: "Content-Type")
            req.httpBody = raw.data
        } else if let body {
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
                // Password was right, 2-step is on (#257): finish with `completeTwoStep`.
                if e.error == "mfa_required", let token = e.mfaToken { throw TwoStepRequired(token: token) }
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
