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

    @Test func workoutsRoundTrip() async throws {
        struct W: Codable, Sendable, Equatable { var id: UUID; var startedAt: Date; var title: String }
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
    }

    @Test func customWorkoutsRoundTrip() async throws {
        struct C: Codable, Sendable, Equatable { var id: UUID; var name: String; var createdAt: Date }
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
        #expect(got == [C(id: id, name: "Push", createdAt: date)])
        try await api.deleteCustomWorkout(id)
    }
}
