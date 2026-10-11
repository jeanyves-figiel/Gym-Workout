import Foundation

/// MonkeyWorkout Pro (#126): what the server says this account may use.
public struct Entitlement: Codable, Sendable, Equatable {
    /// off: nothing shown; preview: Pro visible, nothing locked; enforced: Pro features need `pro`.
    public enum Mode: String, Codable, Sendable { case off, preview, enforced }
    public enum Source: String, Codable, Sendable { case subscription, grant, none }
    public struct Grant: Codable, Sendable, Equatable { public var until: Date? }

    public var mode: Mode
    /// Active subscription (trial and grace period included) or free access given by the owner.
    public var pro: Bool
    /// What the app may use right now: `pro`, or everything unless enforced.
    public var access: Bool
    public var source: Source
    public var productId: String?
    public var expiresAt: Date?
    public var trial: Bool?
    /// One-time Lifetime purchase: no expiry, all future updates included.
    public var lifetime: Bool?
    public var willRenew: Bool?
    public var environment: String?
    public var grant: Grant?
    public var products: [String]

    public init(mode: Mode, pro: Bool, access: Bool, source: Source, productId: String? = nil, expiresAt: Date? = nil,
                trial: Bool? = nil, lifetime: Bool? = nil, willRenew: Bool? = nil, grant: Grant? = nil, products: [String] = []) {
        self.mode = mode
        self.pro = pro
        self.access = access
        self.source = source
        self.productId = productId
        self.expiresAt = expiresAt
        self.trial = trial
        self.lifetime = lifetime
        self.willRenew = willRenew
        self.grant = grant
        self.products = products
    }

    public static let free = Entitlement(mode: .off, pro: false, access: true, source: .none)
}

extension APIClient {
    public func entitlement() async throws -> Entitlement {
        try await authorized("GET", "/v1/me/entitlement", Empty?.none, as: Entitlement.self)
    }

    /// Hands a StoreKit 2 transaction (its JWS) to the server, which verifies it with Apple's certificate chain.
    public func submitTransaction(_ signedTransaction: String, renewalInfo: String? = nil) async throws -> Entitlement {
        struct Body: Encodable { var signedTransaction: String; var signedRenewalInfo: String? }
        return try await authorized("POST", "/v1/me/subscriptions/transactions",
                                    Body(signedTransaction: signedTransaction, signedRenewalInfo: renewalInfo), as: Entitlement.self)
    }
}
