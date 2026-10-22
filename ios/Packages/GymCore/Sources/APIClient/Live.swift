import Foundation

// MARK: Live group sessions (#626): gym buddies, live sets, cheers, weekly challenge room.

/// Cheers a buddy sends while you train; they buzz on the Watch.
public enum LiveCheer: String, Codable, CaseIterable, Sendable, Identifiable {
    case fire, banana, beast
    public var id: String { rawValue }
    public var emoji: String {
        switch self {
        case .fire: "🔥"
        case .banana: "🍌"
        case .beast: "🦍"
        }
    }
}

/// What a member is doing right now: one row, replaced per set.
public struct LiveSet: Codable, Sendable, Equatable, Hashable {
    public enum State: String, Codable, Sendable { case set, rest, done }
    public var title: String
    public var exercise: String
    public var detail: String?
    public var state: State
    /// The weekly challenge being done, so the room shows "training now".
    public var challengeWeek: String?
    public var updatedAt: Date?

    public init(title: String, exercise: String, detail: String? = nil, state: State, challengeWeek: String? = nil) {
        self.title = title
        self.exercise = exercise
        self.detail = detail
        self.state = state
        self.challengeWeek = challengeWeek
    }
}

public struct GymBuddy: Decodable, Sendable, Identifiable, Equatable, Hashable {
    public enum Status: String, Decodable, Sendable { case paired, invited, invitesYou = "invites_you" }
    public var userId: String
    public var nickname: String
    public var avatarUrl: String?
    public var level: Int?
    public var status: Status
    /// Only for a paired buddy training in the last 10′.
    public var live: LiveSet?
    public var id: String { userId }
    public var author: CommunityAuthor { CommunityAuthor(userId: userId, nickname: nickname, avatarUrl: avatarUrl, level: level) }

    public init(userId: String, nickname: String, avatarUrl: String? = nil, level: Int? = nil, status: Status, live: LiveSet? = nil) {
        self.userId = userId
        self.nickname = nickname
        self.avatarUrl = avatarUrl
        self.level = level
        self.status = status
        self.live = live
    }
}

public struct ReceivedCheer: Decodable, Sendable, Identifiable, Equatable {
    public struct From: Decodable, Sendable, Equatable {
        public var userId: String
        public var nickname: String
    }
    public var id: Int
    public var from: From
    public var kind: LiveCheer
    public var at: Date
}

public struct ChallengeEntry: Decodable, Sendable, Identifiable, Equatable {
    public var rank: Int
    public var userId: String
    public var nickname: String
    public var avatarUrl: String?
    public var level: Int?
    public var rounds: Int
    public var reps: Int
    /// Doing the challenge right now.
    public var live: Bool
    public var me: Bool
    public var id: String { userId }

    public init(rank: Int, userId: String, nickname: String, rounds: Int, reps: Int, live: Bool = false, me: Bool = false) {
        self.rank = rank
        self.userId = userId
        self.nickname = nickname
        self.rounds = rounds
        self.reps = reps
        self.live = live
        self.me = me
    }
}

public struct ChallengeRoom: Decodable, Sendable, Equatable {
    public var week: String
    public var joined: Int
    /// Members doing it right now.
    public var training: Int
    public var leaderboard: [ChallengeEntry]
    public var me: ChallengeEntry?

    public init(week: String, joined: Int = 0, training: Int = 0, leaderboard: [ChallengeEntry] = [], me: ChallengeEntry? = nil) {
        self.week = week
        self.joined = joined
        self.training = training
        self.leaderboard = leaderboard
        self.me = me
    }
}

public struct ChallengeScoreResult: Decodable, Sendable, Equatable {
    public var week: String
    public var rounds: Int
    public var reps: Int
    public var rank: Int
    /// This score is the member's best of the week.
    public var best: Bool
}

extension APIClient {
    struct BuddiesResponse: Decodable { var buddies: [GymBuddy] }
    struct BuddyStatusResponse: Decodable { var status: GymBuddy.Status }
    struct CheersResponse: Decodable { var cheers: [ReceivedCheer]; var last: Int }

    public func gymBuddies() async throws -> [GymBuddy] {
        try await authorized("GET", "/v1/community/buddies", Empty?.none, as: BuddiesResponse.self).buddies
    }

    /// Invite, or accept an invite; returns paired or invited.
    public func addBuddy(_ userId: String) async throws -> GymBuddy.Status {
        try await authorized("PUT", "/v1/community/buddies/\(userId)", Empty?.none, as: BuddyStatusResponse.self).status
    }

    public func removeBuddy(_ userId: String) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/community/buddies/\(userId)", Empty?.none)
    }

    public func cheerBuddy(_ userId: String, _ kind: LiveCheer) async throws {
        struct Body: Encodable { var kind: LiveCheer }
        _ = try await authorizedRaw("POST", "/v1/community/buddies/\(userId)/cheers", Body(kind: kind))
    }

    /// nil: the workout ended.
    public func setLive(_ live: LiveSet?) async throws {
        if let live {
            _ = try await authorizedRaw("PUT", "/v1/community/live", live)
        } else {
            _ = try await authorizedRaw("DELETE", "/v1/community/live", Empty?.none)
        }
    }

    public func liveCheers(after: Int) async throws -> (cheers: [ReceivedCheer], last: Int) {
        let r = try await authorized("GET", "/v1/community/live/cheers?after=\(after)", Empty?.none, as: CheersResponse.self)
        return (r.cheers, r.last)
    }

    public func challengeRoom(week: String? = nil) async throws -> ChallengeRoom {
        try await authorized("GET", "/v1/community/challenge" + (week.map { "?week=\($0)" } ?? ""), Empty?.none, as: ChallengeRoom.self)
    }

    public func sendChallengeScore(week: String, rounds: Int, reps: Int) async throws -> ChallengeScoreResult {
        struct Body: Encodable { var week: String; var rounds, reps: Int }
        return try await authorized("PUT", "/v1/community/challenge/score", Body(week: week, rounds: rounds, reps: reps), as: ChallengeScoreResult.self)
    }
}
