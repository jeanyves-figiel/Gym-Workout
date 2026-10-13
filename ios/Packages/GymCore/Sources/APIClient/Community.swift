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
    /// Members can find you by your gym (#152). Optional: older servers omit it.
    public var showGym: Bool?
    /// Your gym's name from the training profile, shown to others only with `showGym`.
    public var gym: String?
    public var sharedPosts: Int
    public var cheersReceived: Int
    public var followers: Int
    public var following: Int
    /// Game level reported by the app (#242); nil before the first report or from older servers.
    public var level: Int?

    public init(
        userId: String, nickname: String, bio: String? = nil, avatarUrl: String? = nil, defaultVisibility: CommunityVisibility = .onlyMe,
        autoShare: Bool = false, showGym: Bool? = nil, gym: String? = nil, sharedPosts: Int = 0, cheersReceived: Int = 0, followers: Int = 0, following: Int = 0,
        level: Int? = nil
    ) {
        self.level = level
        self.showGym = showGym
        self.gym = gym
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

/// Nickname, photo and about shown on Account and in Community (#108). Set before or after joining; same record either way.
public struct PublicProfile: Codable, Sendable, Equatable {
    public var nickname: String?
    public var bio: String?
    /// Server-relative path; resolve with `APIClient.resolve(_:)`.
    public var avatarUrl: String?
    /// Joined the community.
    public var member: Bool

    public init(nickname: String? = nil, bio: String? = nil, avatarUrl: String? = nil, member: Bool = false) {
        self.nickname = nickname
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.member = member
    }

    public var isEmpty: Bool { (nickname ?? "").isEmpty && (bio ?? "").isEmpty && avatarUrl == nil }
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
    /// Gym name, when the member shows it (#152).
    public var gym: String?
    /// Game level reported by the app (#242); nil before the first report or from older servers.
    public var level: Int?

    public init(
        userId: String, nickname: String, bio: String?, avatarUrl: String?, sharedPosts: Int, cheersReceived: Int, followers: Int = 0, following: Int = 0,
        gym: String? = nil, level: Int? = nil
    ) {
        self.level = level
        self.gym = gym
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
    /// Game level reported by the app (#242); nil before the first report or from older servers.
    public var level: Int?

    public init(userId: String, nickname: String, avatarUrl: String? = nil, level: Int? = nil) {
        self.level = level
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

/// Row in Find members and the Following list (#152).
public struct CommunityMemberSummary: Decodable, Sendable, Identifiable, Equatable, Hashable {
    public var userId: String
    public var nickname: String
    public var bio: String?
    public var avatarUrl: String?
    /// Gym name, when the member shows it.
    public var gym: String?
    public var sharedPosts: Int
    public var followers: Int
    public var followedByMe: Bool
    /// Game level reported by the app (#242); nil before the first report or from older servers.
    public var level: Int?
    public var id: String { userId }
    public var author: CommunityAuthor { CommunityAuthor(userId: userId, nickname: nickname, avatarUrl: avatarUrl, level: level) }

    public init(
        userId: String, nickname: String, bio: String? = nil, avatarUrl: String? = nil, gym: String? = nil, sharedPosts: Int = 0, followers: Int = 0,
        followedByMe: Bool = false, level: Int? = nil
    ) {
        self.level = level
        self.gym = gym
        self.userId = userId
        self.nickname = nickname
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.sharedPosts = sharedPosts
        self.followers = followers
        self.followedByMe = followedByMe
    }
}

public enum CommunityFeedScope: String, Sendable, CaseIterable { case members, following, mine }

extension APIClient {
    struct CommunityProfileResponse: Decodable { var profile: CommunityProfile? }
    struct CommunityPostResponse: Decodable { var post: CommunityPost }
    struct BlockedResponse: Decodable { var blocked: [BlockedMember] }
    struct MembersResponse: Decodable { var members: [CommunityMemberSummary] }
    struct FollowingResponse: Decodable { var following: [CommunityMemberSummary] }

    /// Absolute URL for a server-relative path such as an avatar.
    public nonisolated func resolve(_ path: String?) -> URL? {
        guard let path else { return nil }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    /// Public web page of a post shared with visibility "public".
    public nonisolated func shareURL(postId: String) -> URL? { resolve("/share/\(postId)") }

    struct PublicProfileResponse: Decodable { var profile: PublicProfile }

    public func publicProfile() async throws -> PublicProfile {
        try await authorized("GET", "/v1/me/public-profile", Empty?.none, as: PublicProfileResponse.self).profile
    }

    /// Saves nickname and about from Account. Empty clears (a member's nickname cannot be cleared).
    public func savePublicProfile(nickname: String, bio: String) async throws -> PublicProfile {
        struct Body: Encodable { var nickname, bio: String }
        return try await authorized("PUT", "/v1/me/public-profile", Body(nickname: nickname, bio: bio), as: PublicProfileResponse.self).profile
    }

    /// JPEG ≤ 512 KB; works before and after joining.
    public func uploadPublicAvatar(jpeg: Data) async throws -> PublicProfile {
        let data = try await authorizedRaw("PUT", "/v1/me/public-profile/avatar", Empty?.none, raw: (jpeg, "image/jpeg"))
        return try JSONDecoder().decode(PublicProfileResponse.self, from: data).profile
    }

    public func deletePublicAvatar() async throws -> PublicProfile {
        try await authorized("DELETE", "/v1/me/public-profile/avatar", Empty?.none, as: PublicProfileResponse.self).profile
    }

    /// Nil until the member joins the community.
    public func communityProfile() async throws -> CommunityProfile? {
        try await authorized("GET", "/v1/community/me", Empty?.none, as: CommunityProfileResponse.self).profile
    }

    /// Creates or updates the community profile. `acceptGuidelines` is required when joining. Empty bio clears it.
    /// Joining moves the Account profile (photo included) into the community profile.
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

    /// Deletes posts and cheers given. Nickname, photo and about stay on Account.
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

    /// Members whose nickname contains `query` (prefix matches first), then members showing a gym whose name contains it;
    /// suggestions when empty (#152).
    public func searchMembers(_ query: String, limit: Int = 25) async throws -> [CommunityMemberSummary] {
        let q = query.trimmingCharacters(in: .whitespaces).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? ""
        return try await authorized("GET", "/v1/community/members?q=\(q)&limit=\(limit)", Empty?.none, as: MembersResponse.self).members
    }

    /// Members who show the same gym as you; empty unless you show yours (#152).
    public func gymMembers() async throws -> [CommunityMemberSummary] {
        try await authorized("GET", "/v1/community/members?gym=mine", Empty?.none, as: MembersResponse.self).members
    }

    /// Let members find you by your gym (#152).
    public func setShowGym(_ on: Bool) async throws -> CommunityProfile {
        struct Body: Encodable { var showGym: Bool }
        guard let p = try await authorized("PUT", "/v1/community/me", Body(showGym: on), as: CommunityProfileResponse.self).profile else {
            throw APIError.decoding("missing profile")
        }
        return p
    }

    /// Reports the game level (#242) so members see your rank title.
    public func setCommunityLevel(_ level: Int) async throws {
        struct Body: Encodable { var level: Int }
        _ = try await authorizedRaw("PUT", "/v1/community/me/level", Body(level: level))
    }

    /// Members you follow, by nickname.
    public func followingMembers() async throws -> [CommunityMemberSummary] {
        try await authorized("GET", "/v1/community/follows", Empty?.none, as: FollowingResponse.self).following
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
