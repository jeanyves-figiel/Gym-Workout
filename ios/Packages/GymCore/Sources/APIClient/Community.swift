import Foundation

// MARK: Community (#61): profiles, shared progress, cheers, report + block.

/// Who can see a shared post. Raw values match the API.
public enum CommunityVisibility: String, Codable, CaseIterable, Sendable, Identifiable {
    case onlyMe = "private"
    case members
    case everyone = "public"
    public var id: String { rawValue }
}

/// Cheers members give each other.
public enum CommunityReaction: String, Codable, CaseIterable, Sendable, Identifiable {
    case like, strong, fire, clap
    public var id: String { rawValue }
}

public enum CommunityReportReason: String, Codable, CaseIterable, Sendable, Identifiable {
    case spam, harassment, hate, sexual, violence, other
    public var id: String { rawValue }
}

public struct CommunityProfile: Codable, Sendable, Equatable {
    public var userId: String
    public var nickname: String
    public var bio: String?
    /// Server-relative path; resolve with `APIClient.resolve(_:)`.
    public var avatarUrl: String?
    public var defaultVisibility: CommunityVisibility
    public var autoShare: Bool
    public var sharedPosts: Int
    public var cheersReceived: Int
    public var followers: Int
    public var following: Int

    public init(
        userId: String, nickname: String, bio: String? = nil, avatarUrl: String? = nil, defaultVisibility: CommunityVisibility = .onlyMe,
        autoShare: Bool = false, sharedPosts: Int = 0, cheersReceived: Int = 0, followers: Int = 0, following: Int = 0
    ) {
        self.followers = followers
        self.following = following
        self.userId = userId
        self.nickname = nickname
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.defaultVisibility = defaultVisibility
        self.autoShare = autoShare
        self.sharedPosts = sharedPosts
        self.cheersReceived = cheersReceived
    }
}

public struct CommunityMember: Codable, Sendable, Equatable {
    public var userId: String
    public var nickname: String
    public var bio: String?
    public var avatarUrl: String?
    public var sharedPosts: Int
    public var cheersReceived: Int
    public var followers: Int
    public var following: Int

    public init(
        userId: String, nickname: String, bio: String?, avatarUrl: String?, sharedPosts: Int, cheersReceived: Int, followers: Int = 0, following: Int = 0
    ) {
        self.followers = followers
        self.following = following
        self.userId = userId
        self.nickname = nickname
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.sharedPosts = sharedPosts
        self.cheersReceived = cheersReceived
    }
}

public struct CommunityAuthor: Codable, Sendable, Equatable, Hashable {
    public var userId: String
    public var nickname: String
    public var avatarUrl: String?

    public init(userId: String, nickname: String, avatarUrl: String? = nil) {
        self.userId = userId
        self.nickname = nickname
        self.avatarUrl = avatarUrl
    }
}

/// The card shown for a post: title, optional big number and up to 4 stats.
public struct CommunityCard: Codable, Sendable, Equatable {
    public struct Metric: Codable, Sendable, Equatable {
        public var value: String
        public var unit: String
        public init(value: String, unit: String) {
            self.value = value
            self.unit = unit
        }
    }

    public struct Stat: Codable, Sendable, Equatable, Hashable {
        public var label: String
        public var value: String
        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public var title: String
    public var subtitle: String?
    public var metric: Metric?
    /// Gradient key (training category raw value).
    public var style: String?
    public var stats: [Stat]?

    public init(title: String, subtitle: String? = nil, metric: Metric? = nil, style: String? = nil, stats: [Stat]? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.metric = metric
        self.style = style
        self.stats = stats
    }
}

public struct CommunityPost: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var author: CommunityAuthor
    public var mine: Bool
    /// workout | badge | record | climb | note
    public var kind: String
    public var refId: String?
    public var visibility: CommunityVisibility
    public var caption: String?
    public var payload: CommunityCard
    /// Hidden pending moderation review (only its author still sees it).
    public var hidden: Bool
    public var createdAt: Date
    public var reactions: [String: Int]
    public var myReactions: [String]

    public func count(_ r: CommunityReaction) -> Int { reactions[r.rawValue] ?? 0 }
    public func reacted(_ r: CommunityReaction) -> Bool { myReactions.contains(r.rawValue) }
    public var totalCheers: Int { reactions.values.reduce(0, +) }

    public init(
        id: String, author: CommunityAuthor, mine: Bool, kind: String, refId: String? = nil, visibility: CommunityVisibility,
        caption: String? = nil, payload: CommunityCard, hidden: Bool = false, createdAt: Date,
        reactions: [String: Int] = [:], myReactions: [String] = []
    ) {
        self.id = id
        self.author = author
        self.mine = mine
        self.kind = kind
        self.refId = refId
        self.visibility = visibility
        self.caption = caption
        self.payload = payload
        self.hidden = hidden
        self.createdAt = createdAt
        self.reactions = reactions
        self.myReactions = myReactions
    }
}

public struct CommunityFeedPage: Decodable, Sendable {
    public var posts: [CommunityPost]
    /// Pass back as `before` for the next page; nil at the end.
    public var nextBefore: String?
}

public struct CommunityMemberPage: Decodable, Sendable {
    public var member: CommunityMember
    public var posts: [CommunityPost]
    public var blockedByMe: Bool
    public var followedByMe: Bool

    public init(member: CommunityMember, posts: [CommunityPost], blockedByMe: Bool, followedByMe: Bool = false) {
        self.member = member
        self.posts = posts
        self.blockedByMe = blockedByMe
        self.followedByMe = followedByMe
    }
}

public struct BlockedMember: Decodable, Sendable, Identifiable, Equatable {
    public var userId: String
    public var nickname: String
    public var avatarUrl: String?
    public var id: String { userId }
}

public enum CommunityFeedScope: String, Sendable, CaseIterable { case members, following, mine }

extension APIClient {
    struct CommunityProfileResponse: Decodable { var profile: CommunityProfile? }
    struct CommunityPostResponse: Decodable { var post: CommunityPost }
    struct BlockedResponse: Decodable { var blocked: [BlockedMember] }

    /// Absolute URL for a server-relative path such as an avatar.
    public nonisolated func resolve(_ path: String?) -> URL? {
        guard let path else { return nil }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    /// Public web page of a post shared with visibility "public".
    public nonisolated func shareURL(postId: String) -> URL? { resolve("/share/\(postId)") }

    /// Nil until the member joins the community.
    public func communityProfile() async throws -> CommunityProfile? {
        try await authorized("GET", "/v1/community/me", Empty?.none, as: CommunityProfileResponse.self).profile
    }

    /// Creates or updates the community profile. `acceptGuidelines` is required when joining. Empty bio clears it.
    public func saveCommunityProfile(
        nickname: String, bio: String, defaultVisibility: CommunityVisibility, autoShare: Bool, acceptGuidelines: Bool
    ) async throws -> CommunityProfile {
        struct Body: Encodable {
            var nickname, bio: String
            var defaultVisibility: CommunityVisibility
            var autoShare, acceptGuidelines: Bool
        }
        let b = Body(nickname: nickname, bio: bio, defaultVisibility: defaultVisibility, autoShare: autoShare, acceptGuidelines: acceptGuidelines)
        guard let p = try await authorized("PUT", "/v1/community/me", b, as: CommunityProfileResponse.self).profile else {
            throw APIError.decoding("missing profile")
        }
        return p
    }

    /// JPEG ≤ 512 KB, 64–1024 px per side. The server strips metadata.
    public func uploadAvatar(jpeg: Data) async throws -> CommunityProfile {
        let data = try await authorizedRaw("PUT", "/v1/community/me/avatar", Empty?.none, raw: (jpeg, "image/jpeg"))
        guard let p = try JSONDecoder().decode(CommunityProfileResponse.self, from: data).profile else { throw APIError.decoding("missing profile") }
        return p
    }

    public func deleteAvatar() async throws -> CommunityProfile {
        guard let p = try await authorized("DELETE", "/v1/community/me/avatar", Empty?.none, as: CommunityProfileResponse.self).profile else {
            throw APIError.decoding("missing profile")
        }
        return p
    }

    /// Deletes the community profile, photo, posts and cheers given.
    public func leaveCommunity() async throws {
        _ = try await authorizedRaw("DELETE", "/v1/community/me", Empty?.none)
    }

    public func communityFeed(_ scope: CommunityFeedScope, before: String? = nil, limit: Int = 20) async throws -> CommunityFeedPage {
        var path = "/v1/community/feed?scope=\(scope.rawValue)&limit=\(limit)"
        if let before { path += "&before=\(before.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? before)" }
        return try await authorized("GET", path, Empty?.none, as: CommunityFeedPage.self)
    }

    /// Shares a win. Same `kind` + `refId` again updates the existing post. Nil visibility → profile default.
    public func sharePost(
        id: UUID = UUID(), kind: String, refId: String?, visibility: CommunityVisibility?, caption: String?, card: CommunityCard
    ) async throws -> CommunityPost {
        struct Body: Encodable {
            var id: UUID
            var kind: String
            var refId: String?
            var visibility: CommunityVisibility?
            var caption: String?
            var payload: CommunityCard
        }
        let b = Body(id: id, kind: kind, refId: refId, visibility: visibility, caption: caption, payload: card)
        return try await authorized("POST", "/v1/community/posts", b, as: CommunityPostResponse.self).post
    }

    public func updatePost(_ id: String, visibility: CommunityVisibility?, caption: String?) async throws -> CommunityPost {
        struct Body: Encodable { var visibility: CommunityVisibility?; var caption: String? }
        return try await authorized("PATCH", "/v1/community/posts/\(id)", Body(visibility: visibility, caption: caption), as: CommunityPostResponse.self).post
    }

    public func deletePost(_ id: String) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/community/posts/\(id)", Empty?.none)
    }

    /// Adds (`on`) or removes a cheer; returns the updated post.
    public func react(_ postId: String, _ reaction: CommunityReaction, on: Bool) async throws -> CommunityPost {
        try await authorized(on ? "PUT" : "DELETE", "/v1/community/posts/\(postId)/reactions/\(reaction.rawValue)", Empty?.none, as: CommunityPostResponse.self).post
    }

    public func communityMember(_ userId: String) async throws -> CommunityMemberPage {
        try await authorized("GET", "/v1/community/members/\(userId)", Empty?.none, as: CommunityMemberPage.self)
    }

    public func report(postId: String?, userId: String?, reason: CommunityReportReason, details: String?) async throws {
        struct Body: Encodable { var postId, userId: String?; var reason: CommunityReportReason; var details: String? }
        _ = try await authorizedRaw("POST", "/v1/community/reports", Body(postId: postId, userId: userId, reason: reason, details: details))
    }

    public func block(_ userId: String) async throws {
        struct Body: Encodable { var userId: String }
        _ = try await authorizedRaw("POST", "/v1/community/blocks", Body(userId: userId))
    }

    public func unblock(_ userId: String) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/community/blocks/\(userId)", Empty?.none)
    }

    public func follow(_ userId: String) async throws {
        _ = try await authorizedRaw("PUT", "/v1/community/follows/\(userId)", Empty?.none)
    }

    public func unfollow(_ userId: String) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/community/follows/\(userId)", Empty?.none)
    }

    public func blockedMembers() async throws -> [BlockedMember] {
        try await authorized("GET", "/v1/community/blocks", Empty?.none, as: BlockedResponse.self).blocked
    }
}
