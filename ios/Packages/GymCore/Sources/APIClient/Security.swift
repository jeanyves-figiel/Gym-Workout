import Foundation

// Account security (#257): "confirm it's you", 2-step sign-in (authenticator app), passkeys.

/// Thrown by `login` when the password was right and the member turned on 2-step: finish with `completeTwoStep`.
public struct TwoStepRequired: Error, Equatable, LocalizedError {
    public let token: String
    public var errorDescription: String? { "Enter the 6-digit code from your authenticator app." }
}

/// Ways the member can confirm it's them, strongest first (`passkey`, `apple`, `password`, `totp`, `email_code`).
public enum ReauthMethod: String, Codable, Sendable, CaseIterable {
    case passkey, apple, password, totp, emailCode = "email_code"
}

public struct Passkey: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var createdAt: String
    public var lastUsedAt: String?

    public init(id: String, name: String, createdAt: String, lastUsedAt: String? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

/// `GET /v1/me/security`: what the Security page shows.
public struct SecurityOverview: Codable, Sendable, Equatable {
    public var hasPassword: Bool
    public var appleLinked: Bool
    public var mfaEnabled: Bool
    public var recoveryCodesLeft: Int
    public var passkeys: [Passkey]
    /// Unknown future methods are dropped.
    public var reauthMethods: [ReauthMethod]

    public init(hasPassword: Bool, appleLinked: Bool, mfaEnabled: Bool, recoveryCodesLeft: Int, passkeys: [Passkey], reauthMethods: [ReauthMethod]) {
        self.hasPassword = hasPassword
        self.appleLinked = appleLinked
        self.mfaEnabled = mfaEnabled
        self.recoveryCodesLeft = recoveryCodesLeft
        self.passkeys = passkeys
        self.reauthMethods = reauthMethods
    }

    enum CodingKeys: String, CodingKey { case hasPassword, appleLinked, mfaEnabled, recoveryCodesLeft, passkeys, reauthMethods }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasPassword = try c.decode(Bool.self, forKey: .hasPassword)
        appleLinked = try c.decode(Bool.self, forKey: .appleLinked)
        mfaEnabled = try c.decode(Bool.self, forKey: .mfaEnabled)
        recoveryCodesLeft = try c.decode(Int.self, forKey: .recoveryCodesLeft)
        passkeys = try c.decode([Passkey].self, forKey: .passkeys)
        reauthMethods = try c.decode([String].self, forKey: .reauthMethods).compactMap(ReauthMethod.init(rawValue:))
    }
}

public struct TotpSetup: Codable, Sendable, Equatable {
    /// Base32 secret, for typing into the authenticator by hand.
    public var secret: String
    public var otpauthUrl: String

    public init(secret: String, otpauthUrl: String) {
        self.secret = secret
        self.otpauthUrl = otpauthUrl
    }
}

/// Server WebAuthn options for creating a passkey (only what the iOS API needs).
public struct PasskeyRegistrationOptions: Decodable, Sendable {
    public struct Options: Decodable, Sendable {
        public struct RP: Decodable, Sendable { public var id: String }
        public struct UserInfo: Decodable, Sendable { public var id: String; public var name: String }
        public var challenge: String
        public var rp: RP
        public var user: UserInfo
    }
    public var challengeId: String
    public var options: Options
}

/// Server WebAuthn options for using a passkey (sign-in or confirm it's you).
public struct PasskeyAssertionOptions: Decodable, Sendable {
    public struct Options: Decodable, Sendable {
        public struct Credential: Decodable, Sendable { public var id: String }
        public var challenge: String
        public var rpId: String
        public var allowCredentials: [Credential]?
    }
    public var challengeId: String
    public var options: Options
}

/// What `ASAuthorizationPlatformPublicKeyCredentialRegistration` returns.
public struct PasskeyRegistration: Sendable {
    public var credentialId: Data
    public var clientDataJSON: Data
    public var attestationObject: Data
    public init(credentialId: Data, clientDataJSON: Data, attestationObject: Data) {
        self.credentialId = credentialId
        self.clientDataJSON = clientDataJSON
        self.attestationObject = attestationObject
    }
}

/// What `ASAuthorizationPlatformPublicKeyCredentialAssertion` returns.
public struct PasskeyAssertion: Sendable {
    public var credentialId: Data
    public var clientDataJSON: Data
    public var authenticatorData: Data
    public var signature: Data
    public var userHandle: Data?
    public init(credentialId: Data, clientDataJSON: Data, authenticatorData: Data, signature: Data, userHandle: Data?) {
        self.credentialId = credentialId
        self.clientDataJSON = clientDataJSON
        self.authenticatorData = authenticatorData
        self.signature = signature
        self.userHandle = userHandle
    }
}

public enum Base64URL {
    public static func encode(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b += String(repeating: "=", count: (4 - b.count % 4) % 4)
        return Data(base64Encoded: b)
    }
}

// WebAuthn JSON (RegistrationResponseJSON / AuthenticationResponseJSON) as the server expects it.
private struct RegistrationJSON: Encodable {
    struct Response: Encodable { var clientDataJSON, attestationObject: String; var transports = ["internal", "hybrid"] }
    var id, rawId: String
    var type = "public-key"
    var response: Response
    var clientExtensionResults: [String: String] = [:]
    var authenticatorAttachment = "platform"
    init(_ r: PasskeyRegistration) {
        id = Base64URL.encode(r.credentialId)
        rawId = id
        response = .init(clientDataJSON: Base64URL.encode(r.clientDataJSON), attestationObject: Base64URL.encode(r.attestationObject))
    }
}

private struct AssertionJSON: Encodable {
    struct Response: Encodable { var clientDataJSON, authenticatorData, signature: String; var userHandle: String? }
    var id, rawId: String
    var type = "public-key"
    var response: Response
    var clientExtensionResults: [String: String] = [:]
    var authenticatorAttachment = "platform"
    init(_ a: PasskeyAssertion) {
        id = Base64URL.encode(a.credentialId)
        rawId = id
        response = .init(clientDataJSON: Base64URL.encode(a.clientDataJSON), authenticatorData: Base64URL.encode(a.authenticatorData),
                         signature: Base64URL.encode(a.signature), userHandle: a.userHandle.map(Base64URL.encode))
    }
}

private struct ReauthResponse: Decodable { var reauthToken: String; var expiresIn: Int }
private struct PasskeysResponse: Decodable { var passkeys: [Passkey] }
public struct RecoveryCodes: Decodable, Sendable, Equatable { public var recoveryCodes: [String] }

extension APIClient {
    // MARK: Overview

    public func security() async throws -> SecurityOverview {
        try await authorized("GET", "/v1/me/security", Empty?.none, as: SecurityOverview.self)
    }

    /// True while a "confirm it's you" grant is live (no need to ask again).
    public var hasReauthGrant: Bool { (reauthGrant?.expiresAt ?? .distantPast) > now() }

    // MARK: Confirm it's you

    public func sendReauthCode() async throws {
        _ = try await authorizedRaw("POST", "/v1/me/reauth/email-code", Empty())
    }

    public func passkeyReauthOptions() async throws -> PasskeyAssertionOptions {
        try await authorized("POST", "/v1/me/reauth/passkey-options", Empty(), as: PasskeyAssertionOptions.self)
    }

    public func reauth(password: String) async throws {
        struct Body: Encodable { var method = "password"; var password: String }
        try await reauth(Body(password: password))
    }

    public func reauth(appleIdentityToken: String) async throws {
        struct Body: Encodable { var method = "apple"; var identityToken: String }
        try await reauth(Body(identityToken: appleIdentityToken))
    }

    /// `method`: `.totp` (authenticator) or `.emailCode` (after `sendReauthCode`).
    public func reauth(code: String, method: ReauthMethod) async throws {
        struct Body: Encodable { var method: String; var code: String }
        try await reauth(Body(method: method.rawValue, code: code))
    }

    public func reauth(passkey: PasskeyAssertion, challengeId: String) async throws {
        struct Body: Encodable { var method = "passkey"; var challengeId: String; var response: AssertionJSON }
        try await reauth(Body(challengeId: challengeId, response: AssertionJSON(passkey)))
    }

    private func reauth(_ body: some Encodable) async throws {
        let r = try await authorized("POST", "/v1/me/reauth", body, as: ReauthResponse.self)
        // A few seconds short so a call never leaves with a grant about to lapse.
        reauthGrant = (r.reauthToken, now().addingTimeInterval(TimeInterval(max(0, r.expiresIn - 10))))
    }

    // MARK: 2-step sign-in

    public func completeTwoStep(token: String, code: String? = nil, recoveryCode: String? = nil) async throws -> User {
        struct Body: Encodable { var mfaToken: String; var code: String?; var recoveryCode: String? }
        return try await authenticate("/v1/auth/mfa", Body(mfaToken: token, code: code, recoveryCode: recoveryCode))
    }

    public func startTwoStepSetup() async throws -> TotpSetup {
        try await authorized("POST", "/v1/me/mfa/totp/setup", Empty(), as: TotpSetup.self)
    }

    /// Confirms the first code; returns the 10 one-time recovery codes (shown once).
    public func enableTwoStep(code: String) async throws -> [String] {
        struct Body: Encodable { var code: String }
        return try await authorized("POST", "/v1/me/mfa/totp/enable", Body(code: code), as: RecoveryCodes.self).recoveryCodes
    }

    public func disableTwoStep() async throws {
        _ = try await authorizedRaw("DELETE", "/v1/me/mfa", Empty?.none)
    }

    public func newRecoveryCodes() async throws -> [String] {
        try await authorized("POST", "/v1/me/mfa/recovery-codes", Empty(), as: RecoveryCodes.self).recoveryCodes
    }

    // MARK: Passkeys

    public func passkeyRegistrationOptions() async throws -> PasskeyRegistrationOptions {
        try await authorized("POST", "/v1/me/passkeys/options", Empty(), as: PasskeyRegistrationOptions.self)
    }

    public func addPasskey(_ r: PasskeyRegistration, challengeId: String, name: String?) async throws -> [Passkey] {
        struct Body: Encodable { var challengeId: String; var response: RegistrationJSON; var name: String? }
        return try await authorized("POST", "/v1/me/passkeys", Body(challengeId: challengeId, response: RegistrationJSON(r), name: name),
                                    as: PasskeysResponse.self).passkeys
    }

    public func renamePasskey(id: String, name: String) async throws -> [Passkey] {
        struct Body: Encodable { var name: String }
        return try await authorized("PATCH", "/v1/me/passkeys/\(Self.pathSafe(id))", Body(name: name), as: PasskeysResponse.self).passkeys
    }

    public func deletePasskey(id: String) async throws -> [Passkey] {
        try await authorized("DELETE", "/v1/me/passkeys/\(Self.pathSafe(id))", Empty?.none, as: PasskeysResponse.self).passkeys
    }

    /// Sign-in options: any passkey saved for this app (no email needed).
    public func passkeySignInOptions() async throws -> PasskeyAssertionOptions {
        let data = try await send("POST", "/v1/auth/passkey/options", Empty())
        return try decode(PasskeyAssertionOptions.self, data)
    }

    /// Passkey sign-in skips 2-step (possession + Face ID).
    public func signInWithPasskey(_ a: PasskeyAssertion, challengeId: String) async throws -> User {
        struct Body: Encodable { var challengeId: String; var response: AssertionJSON }
        return try await authenticate("/v1/auth/passkey", Body(challengeId: challengeId, response: AssertionJSON(a)))
    }

    static func pathSafe(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-_"))) ?? id
    }
}
