import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import APIClient

/// Scripted HTTP stub. Each test uses its own host so parallel tests don't collide.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest, Data?) -> (Int, String)
    nonisolated(unsafe) static var handlers: [String: Handler] = [:]
    static let lock = NSLock()

    static func register(_ host: String, _ h: @escaping Handler) { lock.withLock { handlers[host] = h } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let h = StubProtocol.lock.withLock { StubProtocol.handlers[request.url!.host!] }!
        let (status, body) = h(request, request.httpBody ?? request.bodyStreamData())
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension URLRequest {
    func bodyStreamData() -> Data? {
        guard let s = httpBodyStream else { return nil }
        s.open()
        defer { s.close() }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while s.hasBytesAvailable {
            let n = s.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Int] = [:]
    func hit(_ k: String) -> Int { lock.withLock { values[k, default: 0] += 1; return values[k]! } }
    func get(_ k: String) -> Int { lock.withLock { values[k, default: 0] } }
}

private func makeClient(_ host: String, tokens: TokenStore, now: @escaping @Sendable () -> Date = { Date() }) -> APIClient {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [StubProtocol.self]
    return APIClient(baseURL: URL(string: "https://\(host)")!, tokens: tokens, session: URLSession(configuration: cfg), deviceName: "Test", now: now)
}

private let userJSON = #"{"id":"u1","email":"a@b.c","name":null,"emailVerified":true,"hasPassword":true,"appleLinked":false,"createdAt":"2026-10-07T10:00:00.000Z"}"#
private func tokensJSON(_ n: Int) -> String {
    #"{"tokenType":"Bearer","accessToken":"access-\#(n)","accessTokenExpiresIn":900,"refreshToken":"refresh-\#(n)","refreshTokenExpiresAt":"2026-12-07T10:00:00.000Z"}"#
}

@Suite struct APIClientTests {
    @Test func loginStoresTokensAndSendsBearer() async throws {
        let store = InMemoryTokenStore()
        StubProtocol.register("login.test") { req, _ in
            switch req.url!.path {
            case "/v1/auth/login": return (200, #"{"user":\#(userJSON),"tokens":\#(tokensJSON(1))}"#)
            case "/v1/me":
                return req.value(forHTTPHeaderField: "Authorization") == "Bearer access-1" ? (200, #"{"user":\#(userJSON)}"#) : (401, #"{"error":"invalid_token","message":"x"}"#)
            default: return (404, "{}")
            }
        }
        let api = makeClient("login.test", tokens: store)
        let user = try await api.login(email: "a@b.c", password: "pw")
        #expect(user.id == "u1")
        #expect(store.load()?.refreshToken == "refresh-1")
        #expect(try await api.me().email == "a@b.c")
    }

    @Test func mapsServerErrors() async {
        StubProtocol.register("err.test") { _, _ in (403, #"{"error":"email_not_verified","message":"Verify your email first."}"#) }
        let api = makeClient("err.test", tokens: InMemoryTokenStore())
        await #expect(throws: APIError.server(status: 403, code: "email_not_verified", message: "Verify your email first.")) {
            try await api.login(email: "a@b.c", password: "pw")
        }
    }

    @Test func refreshesExpiredTokenOnceForConcurrentCalls() async throws {
        let counter = Counter()
        let store = InMemoryTokenStore(StoredTokens(accessToken: "old", accessExpiresAt: Date().addingTimeInterval(-10), refreshToken: "refresh-0"))
        StubProtocol.register("refresh.test") { req, body in
            switch req.url!.path {
            case "/v1/auth/refresh":
                let n = counter.hit("refresh")
                let sent = String(decoding: body ?? Data(), as: UTF8.self)
                return sent.contains("refresh-0") && n == 1 ? (200, tokensJSON(1)) : (401, #"{"error":"invalid_refresh_token","message":"x"}"#)
            case "/v1/me":
                _ = counter.hit("me")
                return req.value(forHTTPHeaderField: "Authorization") == "Bearer access-1" ? (200, #"{"user":\#(userJSON)}"#) : (401, #"{"error":"invalid_token","message":"x"}"#)
            default: return (404, "{}")
            }
        }
        let api = makeClient("refresh.test", tokens: store)
        async let a = api.me()
        async let b = api.me()
        async let c = api.me()
        let users = try await [a, b, c]
        #expect(users.count == 3)
        #expect(counter.get("refresh") == 1)
        #expect(store.load()?.accessToken == "access-1")
    }

    @Test func retriesOnceAfter401WithFreshToken() async throws {
        let store = InMemoryTokenStore(StoredTokens(accessToken: "revoked", accessExpiresAt: Date().addingTimeInterval(600), refreshToken: "refresh-0"))
        StubProtocol.register("retry.test") { req, _ in
            switch req.url!.path {
            case "/v1/auth/refresh": return (200, tokensJSON(2))
            case "/v1/me":
                return req.value(forHTTPHeaderField: "Authorization") == "Bearer access-2" ? (200, #"{"user":\#(userJSON)}"#) : (401, #"{"error":"invalid_token","message":"x"}"#)
            default: return (404, "{}")
            }
        }
        let api = makeClient("retry.test", tokens: store)
        #expect(try await api.me().id == "u1")
    }

    @Test func rejectedRefreshSignsOut() async {
        let store = InMemoryTokenStore(StoredTokens(accessToken: "old", accessExpiresAt: .distantPast, refreshToken: "stolen"))
        StubProtocol.register("signout.test") { _, _ in (401, #"{"error":"invalid_refresh_token","message":"x"}"#) }
        let api = makeClient("signout.test", tokens: store)
        let flag = Counter()
        await api.setOnSignedOut { _ = flag.hit("out") }
        await #expect(throws: APIError.signedOut) { try await api.me() }
        #expect(store.load() == nil)
        #expect(flag.get("out") == 1)
    }

    @Test func deleteAccountSendsConfirmationAndClearsTokens() async throws {
        let store = InMemoryTokenStore(StoredTokens(accessToken: "a", accessExpiresAt: Date().addingTimeInterval(600), refreshToken: "r"))
        StubProtocol.register("delete.test") { req, body in
            let json = (try? JSONSerialization.jsonObject(with: body ?? Data())) as? [String: Any]
            let ok = req.httpMethod == "DELETE" && json?["confirm"] as? String == "DELETE" && json?["password"] as? String == "pw"
            return ok ? (204, "") : (400, #"{"error":"invalid_request","message":"x"}"#)
        }
        let api = makeClient("delete.test", tokens: store)
        try await api.deleteAccount(password: "pw")
        #expect(store.load() == nil)
    }

    @Test func logsRoundTripWithISODates() async throws {
        let store = InMemoryTokenStore(StoredTokens(accessToken: "a", accessExpiresAt: Date().addingTimeInterval(600), refreshToken: "r"))
        StubProtocol.register("logs.test") { req, body in
            if req.httpMethod == "POST" {
                let s = String(decoding: body ?? Data(), as: UTF8.self)
                return s.contains(#""date":"2026-10-07T10:00:00Z""#) ? (200, #"{"saved":1}"#) : (400, #"{"error":"invalid_request","message":"\#(s)"}"#)
            }
            #expect(req.url!.query?.contains("since=2026") == true)
            return (200, #"{"logs":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":"2026-10-07T10:00:00Z","exerciseId":"back-squat","sessionId":null,"weightKg":80,"reps":5,"updatedAt":"2026-10-07T10:00:01.123Z"}],"serverTime":"x"}"#)
        }
        let api = makeClient("logs.test", tokens: store)
        let date = Date(timeIntervalSince1970: 1_791_367_200) // 2026-10-07T10:00:00Z
        try await api.pushLogs([LogEntry(date: date, exerciseId: "back-squat", weightKg: 80, reps: 5)])
        let logs = try await api.fetchLogs(since: date)
        #expect(logs.first?.weightKg == 80)
        #expect(logs.first?.date == date)
    }

    @Test func logChangesDecodeDeletedIds() async throws {
        let store = InMemoryTokenStore(StoredTokens(accessToken: "a", accessExpiresAt: Date().addingTimeInterval(600), refreshToken: "r"))
        StubProtocol.register("logs-deleted.test") { req, _ in
            req.url!.query?.contains("since=") == true
                ? (200, #"{"logs":[],"deleted":["6f9619ff-8b86-d011-b42d-00c04fc964ff","not-a-uuid"],"serverTime":"2026-10-07T10:00:00.250Z"}"#)
                : (200, #"{"logs":[],"serverTime":"x"}"#)
        }
        let api = makeClient("logs-deleted.test", tokens: store)
        let changes = try await api.fetchLogChanges(since: Date())
        #expect(changes.deleted == [UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!])
        #expect(changes.serverTime == Date(timeIntervalSince1970: 1_791_367_200.25))
        #expect(!changes.fullResync)
        let full = try await api.fetchLogChanges()
        #expect(full.deleted.isEmpty)
        // A bad server time doesn't fail the pull; the app falls back to its own clock.
        #expect(full.serverTime == nil)
    }

    @Test func workoutsRoundTrip() async throws {
        struct W: Codable, Sendable, Equatable, ServerVersioned { var id: UUID; var startedAt: Date; var title: String; var updatedAt: String? }
        let store = InMemoryTokenStore(StoredTokens(accessToken: "a", accessExpiresAt: Date().addingTimeInterval(600), refreshToken: "r"))
        StubProtocol.register("workouts.test") { req, body in
            if req.httpMethod == "POST" {
                let s = String(decoding: body ?? Data(), as: UTF8.self)
                return s.contains(#""workouts":[{"#) && s.contains(#""startedAt":"2026-10-07T10:00:00Z""#) ? (200, #"{"saved":1}"#) : (400, #"{"error":"x","message":"\#(s)"}"#)
            }
            return (200, #"{"workouts":[{"id":"6F9619FF-8B86-4011-B42D-00C04FC964FF","startedAt":"2026-10-07T10:00:00Z","title":"Legs","updatedAt":"2026-10-07T10:00:01.123Z"}],"serverTime":"x"}"#)
        }
        let api = makeClient("workouts.test", tokens: store)
        let date = Date(timeIntervalSince1970: 1_791_367_200)
        try await api.pushWorkouts([W(id: UUID(), startedAt: date, title: "Legs")])
        let got = try await api.fetchWorkouts(W.self)
        #expect(got.first?.title == "Legs")
        #expect(got.first?.startedAt == date)
        #expect(got.first?.updatedAt == "2026-10-07T10:00:01.123Z")
    }

    @Test func undecodableWorkoutsAndLogsAreSkipped() async throws {
        struct W: Codable, Sendable, Equatable { var id: UUID; var startedAt: Date; var title: String }
        let store = InMemoryTokenStore(StoredTokens(accessToken: "a", accessExpiresAt: Date().addingTimeInterval(600), refreshToken: "r"))
        StubProtocol.register("lossy.test") { req, _ in
            if req.url!.path == "/v1/me/logs" {
                return (200, #"{"logs":[{"id":"bad"},{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":"2026-10-07T10:00:00Z","exerciseId":"back-squat","weightKg":80}],"serverTime":"x"}"#)
            }
            // Missing title, a number, null and a bad date around one good record.
            return (200, #"{"workouts":[{"id":"6F9619FF-8B86-4011-B42D-00C04FC964FF","startedAt":"2026-10-07T10:00:00Z"},7,null,{"id":"6F9619FF-8B86-4011-B42D-00C04FC964FE","startedAt":"yesterday","title":"x"},{"id":"6F9619FF-8B86-4011-B42D-00C04FC964FD","startedAt":"2026-10-07T10:00:00Z","title":"Legs"}],"serverTime":"x"}"#)
        }
        let api = makeClient("lossy.test", tokens: store)
        let got = try await api.fetchWorkouts(W.self)
        #expect(got.map(\.title) == ["Legs"])
        let logs = try await api.fetchLogs()
        #expect(logs.map(\.exerciseId) == ["back-squat"])
    }

    @Test func customWorkoutsRoundTrip() async throws {
        struct C: Codable, Sendable, Equatable, ServerVersioned { var id: UUID; var name: String; var createdAt: Date; var updatedAt: String? }
        let id = UUID(uuidString: "6F9619FF-8B86-4011-B42D-00C04FC964FF")!
        let store = InMemoryTokenStore(StoredTokens(accessToken: "a", accessExpiresAt: Date().addingTimeInterval(600), refreshToken: "r"))
        StubProtocol.register("custom.test") { req, body in
            let path = req.url!.path
            switch req.httpMethod {
            case "POST":
                let s = String(decoding: body ?? Data(), as: UTF8.self)
                let ok = path == "/v1/me/custom-workouts" && s.contains(#""workouts":[{"#) && s.contains(#""createdAt":"2026-10-07T10:00:00Z""#)
                return ok ? (200, #"{"saved":1}"#) : (400, #"{"error":"x","message":"\#(s)"}"#)
            case "DELETE":
                return path == "/v1/me/custom-workouts/\(id.uuidString)" ? (204, "") : (404, #"{"error":"x","message":"\#(path)"}"#)
            default:
                guard path == "/v1/me/custom-workouts" else { return (404, #"{"error":"x","message":"\#(path)"}"#) }
                return (200, #"{"workouts":[{"id":"\#(id.uuidString)","name":"Push","createdAt":"2026-10-07T10:00:00Z","updatedAt":"2026-10-07T10:00:01.123Z"}],"serverTime":"x"}"#)
            }
        }
        let api = makeClient("custom.test", tokens: store)
        let date = Date(timeIntervalSince1970: 1_791_367_200)
        try await api.pushCustomWorkouts([C(id: id, name: "Push", createdAt: date)])
        let got = try await api.fetchCustomWorkouts(C.self)
        #expect(got == [C(id: id, name: "Push", createdAt: date, updatedAt: "2026-10-07T10:00:01.123Z")])
        try await api.deleteCustomWorkout(id)
    }

    @Test func fullResyncIsDecoded() async throws {
        let store = InMemoryTokenStore(StoredTokens(accessToken: "a", accessExpiresAt: Date().addingTimeInterval(600), refreshToken: "r"))
        StubProtocol.register("logs-resync.test") { _, _ in
            (200, #"{"logs":[],"deleted":[],"fullResync":true,"serverTime":"2026-10-07T10:00:00.250Z"}"#)
        }
        let api = makeClient("logs-resync.test", tokens: store)
        #expect(try await api.fetchLogChanges(since: Date(timeIntervalSince1970: 0)).fullResync)
    }

    @Test func uploadsSendBaseVersionAndReturnConflicts() async throws {
        let known = UUID(uuidString: "6F9619FF-8B86-4011-B42D-00C04FC964FF")!
        let fresh = UUID(uuidString: "6F9619FF-8B86-4011-B42D-00C04FC964FE")!
        let store = InMemoryTokenStore(StoredTokens(accessToken: "a", accessExpiresAt: Date().addingTimeInterval(600), refreshToken: "r"))
        let bodies = BodyLog()
        StubProtocol.register("conflicts.test") { _, body in
            bodies.append(String(decoding: body ?? Data(), as: UTF8.self))
            return (200, #"{"saved":1,"serverTime":"2026-10-08T09:00:00.500Z","conflicts":[{"id":"\#(known.uuidString)","date":"2026-10-07T10:00:00Z","exerciseId":"back-squat","weightKg":90,"updatedAt":"2026-10-08T08:00:00.000Z"}]}"#)
        }
        let api = makeClient("conflicts.test", tokens: store)
        let date = Date(timeIntervalSince1970: 1_791_367_200)
        let edited = LogEntry(id: known, date: date, exerciseId: "back-squat", weightKg: 85, updatedAt: "2026-10-07T10:00:01.123Z")
        let added = LogEntry(id: fresh, date: date, exerciseId: "bench", weightKg: 60)
        let result = try await api.pushLogs([edited, added])
        let sent = bodies.all.joined()
        // The known one carries its base version; the new one has none, so it's written as before.
        #expect(sent.contains(#""baseUpdatedAt":"2026-10-07T10:00:01.123Z""#))
        #expect(sent.components(separatedBy: "baseUpdatedAt").count == 2)
        #expect(result.conflictIds == [known])
        #expect(result.conflicts.first?.weightKg == 90)
        #expect(result.versions == [fresh: "2026-10-08T09:00:00.500Z"])

        // Applied: the server copy replaces the edit and leaves the queue; the new one keeps its version.
        let (list, pending) = result.applied(to: [edited, added], pending: [known, fresh])
        #expect(list.first { $0.id == known }?.weightKg == 90)
        #expect(list.first { $0.id == known }?.updatedAt == "2026-10-08T08:00:00.000Z")
        #expect(list.first { $0.id == fresh }?.updatedAt == "2026-10-08T09:00:00.500Z")
        #expect(pending == [fresh])
    }

    @Test func oldServerAnswerAppliesNothing() async throws {
        struct W: Codable, Sendable, Equatable, ServerVersioned { var id: UUID; var startedAt: Date; var updatedAt: String? }
        let store = InMemoryTokenStore(StoredTokens(accessToken: "a", accessExpiresAt: Date().addingTimeInterval(600), refreshToken: "r"))
        StubProtocol.register("old-upload.test") { _, _ in (200, #"{"saved":1}"#) }
        let api = makeClient("old-upload.test", tokens: store)
        let w = W(id: UUID(), startedAt: Date(timeIntervalSince1970: 1_791_367_200), updatedAt: "2026-10-07T10:00:01.123Z")
        let result = try await api.pushWorkouts([w])
        #expect(result.isEmpty)
        let (list, pending) = result.applied(to: [w], pending: [w.id])
        #expect(list == [w])
        #expect(pending == [w.id])
    }

    @Test func coachCallNameGoesInHeaderNotURL() async throws {
        let store = InMemoryTokenStore(StoredTokens(accessToken: "a", accessExpiresAt: Date().addingTimeInterval(600), refreshToken: "r"))
        StubProtocol.register("call.test") { req, _ in
            let ok = req.url!.path == "/v1/me/coach-voices/joanna/call/hype.mp3" && req.url!.query == nil
                && req.value(forHTTPHeaderField: "X-Call-Name") == "Zo%C3%A9%20Lou"
            return ok ? (200, "mp3") : (400, #"{"error":"x","message":"\#(req.url!.absoluteString)"}"#)
        }
        let api = makeClient("call.test", tokens: store)
        let data = try await api.coachVoiceCall(voice: "joanna", style: "hype", name: "Zoé Lou")
        #expect(String(decoding: data, as: UTF8.self) == "mp3")
    }

    @Test func exportAndScanLimitsReadPolitely() async throws {
        let store = InMemoryTokenStore(StoredTokens(accessToken: "a", accessExpiresAt: Date().addingTimeInterval(600), refreshToken: "r"))
        StubProtocol.register("limits.test") { req, _ in
            switch req.url!.path {
            case "/v1/me/export": return (429, #"{"error":"rate_limited","message":"Too many requests. Slow down."}"#)
            case "/v1/me/food-scan": return (403, #"{"error":"verification_required","message":"x"}"#)
            default: return (429, #"{"error":"daily_limit","message":"That's 5 scans today. Scan more tomorrow!"}"#)
            }
        }
        let api = makeClient("limits.test", tokens: store)
        await #expect(throws: APIError.server(status: 429, code: "rate_limited", message: APIClient.exportLimitMessage)) {
            _ = try await api.exportData()
        }
        await #expect(throws: APIError.server(status: 403, code: "verification_required", message: APIClient.scanVerifyMessage)) {
            _ = try await api.foodScan(jpeg: Data([0xFF, 0xD8]), catalog: [])
        }
        // Daily limits keep the server's own wording.
        await #expect(throws: APIError.server(status: 429, code: "daily_limit", message: "That's 5 scans today. Scan more tomorrow!")) {
            _ = try await api.gymScan(jpeg: Data([0xFF, 0xD8]), catalog: [])
        }
    }

    @Test func undecodableConflictCopyStillLeavesTheQueue() {
        let id = UUID()
        let mine = LogEntry(id: id, date: Date(timeIntervalSince1970: 0), exerciseId: "x", weightKg: 1, updatedAt: "2026-01-01T00:00:00.000Z")
        let r = UploadResult<LogEntry>(conflictIds: [id])
        let (list, pending) = r.applied(to: [mine], pending: [id])
        #expect(list == [mine])
        #expect(pending.isEmpty)
    }
}

final class BodyLog: @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [String] = []
    func append(_ s: String) { lock.withLock { bodies.append(s) } }
    var all: [String] { lock.withLock { bodies } }
}

@Suite struct LogEntryCodingTests {
    @Test func legacyLogsDecodeWithoutPerSetFields() throws {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":"2026-10-07T10:00:00Z","exerciseId":"back-squat","sessionId":null,"weightKg":80,"reps":null}"#
        let l = try dec.decode(LogEntry.self, from: Data(json.utf8))
        #expect(l.weightKg == 80)
        #expect(l.setIndex == nil)
        #expect(l.rir == nil)
    }

    @Test func perSetFieldsRoundTrip() throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let l = LogEntry(date: Date(timeIntervalSince1970: 1_791_367_200), exerciseId: "back-squat", sessionId: "w1s1",
                         weightKg: 82.5, reps: 8, setIndex: 2, rir: 1)
        let back = try dec.decode(LogEntry.self, from: enc.encode(l))
        #expect(back == l)
        // Nil per-set fields are omitted, so old servers see exactly the legacy payload.
        let legacy = try String(decoding: enc.encode(LogEntry(date: l.date, exerciseId: "x", weightKg: 1)), as: UTF8.self)
        #expect(!legacy.contains("setIndex"))
        #expect(!legacy.contains("rir"))
    }

    @Test func lossyArrayCountsSkippedElements() throws {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let json = #"[{"id":"bad"},null,{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":"2026-10-07T10:00:00Z","exerciseId":"back-squat"},7]"#
        let l = try dec.decode(LossyArray<LogEntry>.self, from: Data(json.utf8))
        #expect(l.elements.map(\.exerciseId) == ["back-squat"])
        #expect(l.skipped == 2)
        let clean = try dec.decode(LossyArray<LogEntry>.self, from: Data("[]".utf8))
        #expect(clean.elements.isEmpty && clean.skipped == 0)
    }
}

@Suite struct EntitlementTests {
    @Test func decodesServerEntitlement() throws {
        let json = #"{"mode":"preview","pro":true,"access":true,"source":"subscription","productId":"monkeyworkout.pro.yearly","expiresAt":"2026-10-18T10:00:00.000Z","trial":true,"willRenew":true,"environment":"Sandbox","products":["monkeyworkout.pro.weekly"]}"#
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            return APIClient.parseISO(s)!
        }
        let e = try d.decode(Entitlement.self, from: Data(json.utf8))
        #expect(e.mode == .preview && e.pro && e.trial == true && e.source == .subscription && e.grant == nil)
        let g = try d.decode(Entitlement.self, from: Data(#"{"mode":"enforced","pro":true,"access":true,"source":"grant","grant":{},"products":[]}"#.utf8))
        #expect(g.source == .grant && g.grant?.until == nil && g.test == nil)
        let t = try d.decode(Entitlement.self, from: Data(#"{"mode":"enforced","pro":false,"access":false,"source":"none","products":[],"test":{"mode":"enforced"}}"#.utf8))
        #expect(t.test?.mode == .enforced)
        let s = try d.decode(Entitlement.self, from: Data(#"{"mode":"off","pro":false,"access":true,"source":"none","products":[],"test":{}}"#.utf8))
        #expect(s.test != nil && s.test?.mode == nil)
    }
}
