import Foundation
import Security

/// Read-only link to the user's MonkeyGrade account (#48): climbing sessions with sends, grades and RPE.
/// Uses MonkeyGrade's existing native API (Bearer token from email + password). The token stays in this
/// device's Keychain and is never sent to the MonkeyWorkout backend.
@MainActor @Observable
final class MonkeyGradeLink {
    static let shared = MonkeyGradeLink()

    static let baseURL = URL(string: "https://api.monkeygrade.cloud")!

    struct Stored: Codable {
        var token: String
        var expires: Date
        var email: String
        /// MonkeyWorkout user the link belongs to; other users on this device never see it.
        var ownerId: String
    }

    private(set) var stored: Stored?
    private(set) var sessions: [ClimbEntry] = []
    private(set) var lastFetch: Date?
    private(set) var busy = false
    var error: String?

    private let keychain = Keychain(service: (Bundle.main.bundleIdentifier ?? "Com.app.MonkeyWorkout") + ".monkeygrade")

    init() { stored = keychain.load() }

    func isConnected(for userId: String?) -> Bool {
        guard let s = stored, let userId else { return false }
        return s.ownerId == userId
    }

    func climbs(for userId: String?) -> [ClimbEntry] { isConnected(for: userId) ? sessions : [] }

    #if DEBUG
    /// Demo mode: two MonkeyGrade sessions matching the demo Health climbs, no network.
    func loadDemo(ownerId: String) {
        stored = Stored(token: "", expires: .distantFuture, email: "climber@example.com", ownerId: ownerId)
        let day: Double = 86_400
        var a = ClimbEntry(id: Self.monkeyGradeId(1), start: Date().addingTimeInterval(-4 * day), end: Date().addingTimeInterval(-4 * day + 7_200),
                           source: "MonkeyGrade", kind: .boulder, effort: 7, topGrade: "7A")
        a.detail = "14 sends · 4 flashes"
        var b = ClimbEntry(id: Self.monkeyGradeId(2), start: Date().addingTimeInterval(-9 * day), end: Date().addingTimeInterval(-9 * day + 5_400),
                           source: "MonkeyGrade", kind: .boulder, effort: 6, topGrade: "6C+")
        b.detail = "11 sends · 2 flashes"
        sessions = [a, b]
        lastFetch = Date()
    }
    #endif

    // MARK: Sign in / out

    enum SignInResult { case connected, needsCode, failed }

    func signIn(email: String, password: String, code: String?, ownerId: String) async -> SignInResult {
        busy = true
        defer { busy = false }
        error = nil
        var body: [String: String] = ["email": email.trimmingCharacters(in: .whitespaces), "password": password]
        if let code, !code.isEmpty { body["totp_code"] = code }
        do {
            let (data, status) = try await request("POST", "/api/auth/token", body: body)
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if status == 200, let token = json["token"] as? String {
                let ttl = (json["expires_in"] as? NSNumber)?.doubleValue ?? 30 * 86_400
                let s = Stored(token: token, expires: Date().addingTimeInterval(ttl), email: body["email"]!, ownerId: ownerId)
                keychain.save(s)
                stored = s
                await refresh(force: true)
                return .connected
            }
            if json["requires_2fa"] as? Bool == true {
                if code?.isEmpty == false { error = (json["error"] as? String) ?? "Invalid 2FA code." }
                return .needsCode
            }
            if json["needs_verification"] as? Bool == true {
                error = "Verify your MonkeyGrade email first, then try again."
            } else {
                error = (json["error"] as? String) ?? "MonkeyGrade sign-in failed (\(status))."
            }
            return .failed
        } catch {
            self.error = "Can't reach MonkeyGrade. Check your connection."
            return .failed
        }
    }

    func disconnect() {
        keychain.clear()
        stored = nil
        sessions = []
        lastFetch = nil
        error = nil
    }

    // MARK: Sessions

    /// Fetches the latest climbing sessions (home gym). Skips when fetched in the last 10 minutes unless forced.
    func refresh(force: Bool = false) async {
        guard let s = stored else { return }
        if s.expires < Date() {
            disconnect()
            error = "MonkeyGrade sign-in expired. Connect again."
            return
        }
        if !force, let last = lastFetch, Date().timeIntervalSince(last) < 600 { return }
        do {
            let (data, status) = try await request("GET", "/api/sessions?limit=30", token: s.token)
            if status == 401 {
                disconnect()
                error = "MonkeyGrade signed you out. Connect again."
                return
            }
            guard status == 200 else {
                error = status == 403 ? "Session logs aren't enabled at your MonkeyGrade gym." : "MonkeyGrade error (\(status))."
                return
            }
            sessions = Self.parseSessions(data)
            lastFetch = Date()
            error = nil
        } catch {
            self.error = "Can't reach MonkeyGrade. Check your connection."
        }
    }

    private func request(_ method: String, _ path: String, body: [String: String]? = nil, token: String? = nil) async throws -> (Data, Int) {
        var req = URLRequest(url: URL(string: path, relativeTo: Self.baseURL)!)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    // MARK: Parsing

    private struct SessionsResponse: Decodable {
        struct Discipline: Decodable {
            var count: Int?
            var flashes: Int?
            var grade_spread: [String]?
        }

        struct Session: Decodable {
            var id: Int
            var status: String?
            var started_at: String?
            var ended_at: String?
            var rpe: Int?
            var volume: Int?
            var flashes: Int?
            var per_discipline: [String: Discipline]?
        }

        var sessions: [Session]
    }

    static func parseSessions(_ data: Data) -> [ClimbEntry] {
        guard let r = try? JSONDecoder().decode(SessionsResponse.self, from: data) else { return [] }
        return r.sessions.compactMap { s in
            guard s.status != "active", let start = s.started_at.flatMap(parseDate), let end = s.ended_at.flatMap(parseDate), end > start else { return nil }
            let disciplines = s.per_discipline ?? [:]
            let main = disciplines.max { ($0.value.count ?? 0) < ($1.value.count ?? 0) }
            var e = ClimbEntry(
                id: monkeyGradeId(s.id), start: start, end: end, source: "MonkeyGrade",
                kind: kind(main?.key), effort: s.rpe, topGrade: Climbs.hardest(main?.value.grade_spread ?? []))
            if let v = s.volume, v > 0 {
                e.detail = "\(v) send\(v == 1 ? "" : "s")" + ((s.flashes ?? 0) > 0 ? " · \(s.flashes!) flash\(s.flashes! == 1 ? "" : "es")" : "")
            }
            return e
        }
        .sorted { $0.start > $1.start }
    }

    /// Stable UUID per MonkeyGrade session id.
    static func monkeyGradeId(_ id: Int) -> UUID {
        UUID(uuidString: String(format: "4d475300-0000-4000-8000-%012lx", id)) ?? UUID()
    }

    static func kind(_ discipline: String?) -> ClimbKind? {
        guard let d = discipline?.lowercased() else { return nil }
        if d.contains("outdoor") { return .outdoor }
        if d.contains("top") { return .topRope }
        if d.contains("lead") || d.contains("rope") { return .lead }
        return .boulder
    }

    /// ISO 8601 with or without fractional seconds (any digits) or time zone (UTC assumed).
    static func parseDate(_ raw: String) -> Date? {
        var s = raw.replacingOccurrences(of: " ", with: "T")
        if let dot = s.firstIndex(of: ".") {
            let digits = s[s.index(after: dot)...].prefix { $0.isNumber }
            s.replaceSubrange(dot..<s.index(dot, offsetBy: digits.count + 1), with: "")
        }
        let hasZone = s.hasSuffix("Z") || s.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil
        if !hasZone { s += "Z" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// Small generic-password Keychain wrapper (this device only).
private struct Keychain {
    let service: String
    private let account = "link"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func load() -> MonkeyGradeLink.Stored? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(MonkeyGradeLink.Stored.self, from: data)
    }

    func save(_ value: MonkeyGradeLink.Stored) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            _ = SecItemAdd(query.merging(attrs) { $1 } as CFDictionary, nil)
        }
    }

    func clear() { _ = SecItemDelete(query as CFDictionary) }
}
