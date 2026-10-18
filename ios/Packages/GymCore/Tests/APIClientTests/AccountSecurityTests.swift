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

    @Test func appleSignInSendsRawNonce() async throws {
        StubProtocol.register("apple-nonce.test") { req, body in
            guard req.url!.path == "/v1/auth/apple" else { return (404, "{}") }
            return json(body)["nonce"] == "raw-nonce-0123456789"
                ? (200, #"{"user":\#(user("a@b.c")),"tokens":\#(pairJSON),"created":false}"#)
                : (400, #"{"error":"invalid_request","message":"missing nonce"}"#)
        }
        let api = client("apple-nonce.test", tokens: InMemoryTokenStore())
        _ = try await api.signInWithApple(identityToken: "id-token", name: nil, nonce: "raw-nonce-0123456789")
    }

    @Test func appleNonceIsRandomHexAndHashIsSHA256Hex() {
        let a = AppleNonce(), b = AppleNonce()
        #expect(a.raw != b.raw)
        #expect(a.raw.count == 64 && a.raw.allSatisfy { "0123456789abcdef".contains($0) })
        #expect(AppleNonce(raw: "abc").hashed == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
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

/// Confirm it's you, 2-step sign-in, passkeys (#257).
@Suite struct ReauthTwoStepPasskeyTests {
    private func signedIn() -> InMemoryTokenStore {
        InMemoryTokenStore(StoredTokens(accessToken: "access-1", accessExpiresAt: Date().addingTimeInterval(900), refreshToken: "refresh-1"))
    }

    @Test func loginWithTwoStepThrowsTokenThenCompletes() async throws {
        StubProtocol.register("mfa.test") { req, body in
            switch req.url!.path {
            case "/v1/auth/login":
                return (403, #"{"error":"mfa_required","message":"Enter the code.","mfaToken":"mfa-tok","methods":["totp","recovery"]}"#)
            case "/v1/auth/mfa":
                let b = json(body)
                return b["mfaToken"] == "mfa-tok" && b["code"] == "123456"
                    ? (200, #"{"user":\#(user("a@b.c")),"tokens":\#(pairJSON)}"#)
                    : (401, #"{"error":"invalid_code","message":"Wrong code."}"#)
            default: return (404, "{}")
            }
        }
        let store = InMemoryTokenStore()
        let api = client("mfa.test", tokens: store)
        await #expect(throws: TwoStepRequired(token: "mfa-tok")) { _ = try await api.login(email: "a@b.c", password: "pw") }
        #expect(store.load() == nil)
        _ = try await api.completeTwoStep(token: "mfa-tok", code: "123456")
        #expect(store.load()?.accessToken == "access-1")
    }

    @Test func reauthGrantIsSentOnLaterCalls() async throws {
        StubProtocol.register("reauth.test") { req, body in
            switch req.url!.path {
            case "/v1/me/reauth":
                let b = json(body)
                return b["method"] == "email_code" && b["code"] == "654321"
                    ? (200, #"{"reauthToken":"grant-1","expiresIn":300}"#)
                    : (401, #"{"error":"reauth_failed","message":"x"}"#)
            case "/v1/me":
                return req.value(forHTTPHeaderField: "X-Reauth-Token") == "grant-1"
                    ? (204, "")
                    : (403, #"{"error":"reauth_required","message":"Confirm it's you first.","methods":["email_code"]}"#)
            default: return (404, "{}")
            }
        }
        let api = client("reauth.test", tokens: signedIn())
        await #expect(throws: APIError.server(status: 403, code: "reauth_required", message: "Confirm it's you first.")) {
            try await api.deleteAccount()
        }
        #expect(await !api.hasReauthGrant)
        try await api.reauth(code: "654321", method: .emailCode)
        #expect(await api.hasReauthGrant)
        try await api.deleteAccount()
    }

    @Test func securityOverviewDropsUnknownMethods() async throws {
        StubProtocol.register("sec.test") { _, _ in
            (200, #"{"hasPassword":false,"appleLinked":true,"mfaEnabled":false,"recoveryCodesLeft":0,"passkeys":[{"id":"c1","name":"iPhone","createdAt":"2026-10-13T20:00:00.000Z","lastUsedAt":null}],"reauthMethods":["passkey","apple","smoke_signal","email_code"]}"#)
        }
        let o = try await client("sec.test", tokens: signedIn()).security()
        #expect(o.reauthMethods == [.passkey, .apple, .emailCode])
        #expect(o.passkeys.map(\.name) == ["iPhone"])
    }

    @Test func passkeySignInSendsWebAuthnJSON() async throws {
        let cred = Data([0xfb, 0xff, 0x01])
        StubProtocol.register("pk.test") { req, body in
            switch req.url!.path {
            case "/v1/auth/passkey/options":
                return (200, #"{"challengeId":"ch-1","options":{"challenge":"Y2hhbGxlbmdl","rpId":"workout.monkeygrade.cloud","allowCredentials":[]}}"#)
            case "/v1/auth/passkey":
                guard let obj = try? JSONSerialization.jsonObject(with: body ?? Data()) as? [String: Any],
                      let r = obj["response"] as? [String: Any], let inner = r["response"] as? [String: Any] else { return (400, "{}") }
                let ok = obj["challengeId"] as? String == "ch-1" && r["id"] as? String == "-_8B" && r["rawId"] as? String == "-_8B"
                    && r["type"] as? String == "public-key" && inner["signature"] as? String == "c2ln" && inner["userHandle"] as? String == "dTE"
                return ok ? (200, #"{"user":\#(user("a@b.c")),"tokens":\#(pairJSON)}"#) : (400, #"{"error":"passkey_invalid","message":"x"}"#)
            default: return (404, "{}")
            }
        }
        let api = client("pk.test", tokens: InMemoryTokenStore())
        let o = try await api.passkeySignInOptions()
        #expect(o.options.rpId == "workout.monkeygrade.cloud")
        #expect(Base64URL.decode(o.options.challenge) == Data("challenge".utf8))
        let a = PasskeyAssertion(credentialId: cred, clientDataJSON: Data("{}".utf8), authenticatorData: Data([1]),
                                 signature: Data("sig".utf8), userHandle: Data("u1".utf8))
        #expect(try await api.signInWithPasskey(a, challengeId: o.challengeId).email == "a@b.c")
    }
}
