import Foundation

/// Invite a friend (#745): your code, how many friends joined and subscribed, and who invited you.
public struct ReferralSummary: Codable, Sendable, Equatable {
    public struct Inviter: Codable, Sendable, Equatable {
        public var nickname: String?
        public var at: String
    }

    public var code: String
    /// Server-relative invite page; resolve with `APIClient.resolve(_:)`.
    public var path: String
    public var joined: Int
    /// Friends with a paid (not trial) Pro subscription.
    public var subscribed: Int
    public var invitedBy: Inviter?
    /// A new account (first 14 days) that hasn't entered a code yet.
    public var canRedeem: Bool

    public init(code: String, path: String, joined: Int = 0, subscribed: Int = 0, invitedBy: Inviter? = nil, canRedeem: Bool = false) {
        self.code = code
        self.path = path
        self.joined = joined
        self.subscribed = subscribed
        self.invitedBy = invitedBy
        self.canRedeem = canRedeem
    }
}

/// Social handles on a member profile (#745), without "@".
public struct SocialHandles: Codable, Sendable, Equatable {
    public var instagram: String?
    public var tiktok: String?
    public var strava: String?
    public var youtube: String?

    public init(instagram: String? = nil, tiktok: String? = nil, strava: String? = nil, youtube: String? = nil) {
        self.instagram = instagram
        self.tiktok = tiktok
        self.strava = strava
        self.youtube = youtube
    }

    public var isEmpty: Bool { [instagram, tiktok, strava, youtube].allSatisfy { ($0 ?? "").isEmpty } }
}

/// Who sees your socials: everyone, members who follow you, nobody.
public enum SocialsVisibility: String, Codable, Sendable, CaseIterable, Identifiable {
    case everyone, following, nobody
    public var id: String { rawValue }
}

extension APIClient {
    public func referrals() async throws -> ReferralSummary {
        try await authorized("GET", "/v1/referrals/me", Empty?.none, as: ReferralSummary.self)
    }

    /// Enter a friend's code (new accounts, once).
    public func redeemReferral(_ code: String) async throws -> ReferralSummary {
        struct Body: Encodable { var code: String }
        return try await authorized("POST", "/v1/referrals/redeem", Body(code: code), as: ReferralSummary.self)
    }

    public func setSocials(_ socials: SocialHandles, visibility: SocialsVisibility) async throws {
        struct Body: Encodable { var socials: SocialHandles; var visibility: SocialsVisibility }
        _ = try await authorizedRaw("PUT", "/v1/community/me/socials", Body(socials: socials, visibility: visibility))
    }
}
