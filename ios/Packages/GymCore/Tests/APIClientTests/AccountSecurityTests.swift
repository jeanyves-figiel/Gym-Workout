import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import APIClient

private func client(_ host: String, tokens: TokenStore) -> APIClient {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [StubProtocol.self]
    return APIClient(baseURL: URL(string: "https://\(host)")!, tokens: tokens, session: URLSession(configuration: cfg), deviceName: "Test")
}

private func user(_ email: String) -> String {
    #"{"id":"u1","email":"\#(email)","name":null,"emailVerified":true,"hasPassword":true,"appleLinked":true,"createdAt":"2026-10-07T10:00:00.000Z"}"#
}

private let pairJSON = #"{"tokenType":"Bearer","accessToken":"access-1","accessTokenExpiresIn":900,"refreshToken":"refresh-1","refreshTokenExpiresAt":"2026-12-07T10:00:00.000Z"}"#

private func json(_ data: Data?) -> [String: String] {
    guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return obj.compactMapValues { $0 as? String }
}

@Suite struct AccountSecurityTests {
    @Test func appleSignInSendsAuthorizationCode() async throws {
        StubProtocol.register("apple-code.test") { req, body in
            guard req.url!.path == "/v1/auth/apple" else { return (404, "{}") }
            let b = json(body)
            return b["identityToken"] == "id-token" && b["authorizationCode"] == "auth-code"
                ? (200, #"{"user":\#(user("a@b.c")),"tokens":\#(pairJSON),"created":false}"#)
                : (400, #"{"error":"invalid_request","message":"missing code"}"#)
        }
        let api = client("apple-code.test", tokens: InMemoryTokenStore())
        let u = try await api.signInWithApple(identityToken: "id-token", name: nil, authorizationCode: "auth-code")
        #expect(u.appleLinked)
    }

    @Test func changeEmailRequestThenConfirm() async throws {
        let store = InMemoryTokenStore(StoredTokens(accessToken: "access-1", accessExpiresAt: Date().addingTimeInterval(900), refreshToken: "refresh-1"))
        StubProtocol.register("email.test") { req, body in
            guard req.value(forHTTPHeaderField: "Authorization") == "Bearer access-1" else { return (401, #"{"error":"invalid_token","message":"x"}"#) }
            switch req.url!.path {
            case "/v1/me/email":
                let b = json(body)
                return b["newEmail"] == "new@b.c" && b["password"] == "pw"
                    ? (202, #"{"status":"verification_required","message":"ok"}"#)
                    : (401, #"{"error":"invalid_credentials","message":"Password is incorrect."}"#)
            case "/v1/me/email/confirm":
                return json(body)["code"] == "123456"
                    ? (200, #"{"user":\#(user("new@b.c"))}"#)
                    : (400, #"{"error":"invalid_code","message":"Invalid or expired code."}"#)
            default: return (404, "{}")
            }
        }
        let api = client("email.test", tokens: store)
        try await api.requestEmailChange(newEmail: "new@b.c", password: "pw")
        await #expect(throws: APIError.server(status: 400, code: "invalid_code", message: "Invalid or expired code.")) {
            _ = try await api.confirmEmailChange(code: "000000")
        }
        #expect(try await api.confirmEmailChange(code: "123456").email == "new@b.c")
    }
}
