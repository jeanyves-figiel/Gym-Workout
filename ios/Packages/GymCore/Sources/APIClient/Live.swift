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
    /// False when you keep your live set from this buddy (#675). Nil from older servers: shared.
    public var shareLive: Bool?
    public var sharesLive: Bool { shareLive ?? true }
    public var id: String { userId }
    public var author: CommunityAuthor { CommunityAuthor(userId: userId, nickname: nickname, avatarUrl: avatarUrl, level: level) }

    public init(userId: String, nickname: String, avatarUrl: String? = nil, level: Int? = nil, status: Status, live: LiveSet? = nil, shareLive: Bool? = nil) {
        self.userId = userId
        self.nickname = nickname
        self.avatarUrl = avatarUrl
        self.level = level
        self.status = status
        self.live = live
        self.shareLive = shareLive
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
    /// For time, finished under the cap (#748).
    public var seconds: Int?
    /// Easy / Rx / Beast (#748); nil from older servers: Rx.
    public var tier: ChallengeTier?
    /// Doing the challenge right now.
    public var live: Bool
    public var me: Bool
    public var id: String { userId }

    public init(rank: Int, userId: String, nickname: String, rounds: Int, reps: Int, seconds: Int? = nil, tier: ChallengeTier? = nil,
                live: Bool = false, me: Bool = false) {
        self.rank = rank
        self.userId = userId
        self.nickname = nickname
        self.rounds = rounds
        self.reps = reps
        self.seconds = seconds
        self.tier = tier
        self.live = live
        self.me = me
    }
}

// MARK: Week challenge deck + member weeks (#748)

public enum ChallengeFormat: String, Codable, Sendable, CaseIterable, Identifiable {
    case amrap, emom, fortime, tabata
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .amrap: "AMRAP"
        case .emom: "EMOM"
        case .fortime: "For time"
        case .tabata: "Tabata"
        }
    }
}

/// Easy: half the reps; Rx: as written; Beast: one extra round or a vest. Ranks first on the board.
public enum ChallengeTier: String, Codable, Sendable, CaseIterable, Identifiable {
    case easy, rx, beast
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .easy: "Easy"
        case .rx: "Rx"
        case .beast: "Beast"
        }
    }
}

public struct ChallengeAuthor: Codable, Sendable, Equatable, Hashable {
    public var userId: String
    public var nickname: String
    public init(userId: String, nickname: String) {
        self.userId = userId
        self.nickname = nickname
    }
}

/// The week's WOD from the server: a deck card, or on a member week the members' winner.
public struct ChallengeWod: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var format: ChallengeFormat
    /// AMRAP / For time: the cap; EMOM: one minute per round; Tabata: 4′ per move.
    public var minutes: Int
    public var moves: [String]
    public var by: ChallengeAuthor?
    public var memberWeek: Bool?
    /// Deck card number this year (nil on a member week).
    public var card: Int?
    public var deckSize: Int?

    public init(name: String, format: ChallengeFormat, minutes: Int, moves: [String], by: ChallengeAuthor? = nil, memberWeek: Bool? = nil,
                card: Int? = nil, deckSize: Int? = nil) {
        self.name = name
        self.format = format
        self.minutes = minutes
        self.moves = moves
        self.by = by
        self.memberWeek = memberWeek
        self.card = card
        self.deckSize = deckSize
    }

    /// "AMRAP 12′", "EMOM 14′", "For time · 15′ cap", "Tabata 12′".
    public var headline: String {
        format == .fortime ? "For time · \(minutes)′ cap" : "\(format.label) \(minutes)′"
    }

    /// What to do, one line under the name.
    public var rule: String {
        switch format {
        case .amrap: "As many rounds as you can in \(minutes)′"
        case .emom: "Every minute, the next move; \(minutes) rounds"
        case .fortime: "All reps, fastest time; cap \(minutes)′"
        case .tabata: "8 × 20″ on / 10″ off per move"
        }
    }
}

public struct ChallengeNext: Decodable, Sendable, Equatable {
    public var week: String
    public var memberWeek: Bool
    public var format: ChallengeFormat?
    public var minutes: Int?
    public var moveCount: Int?
}

public struct ChallengePast: Decodable, Sendable, Equatable, Identifiable {
    public var week: String
    public var name: String
    public var rank: Int?
    public var id: String { week }

    public init(week: String, name: String, rank: Int?) {
        self.week = week
        self.name = name
        self.rank = rank
    }
}

public struct ChallengeFinalist: Decodable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var format: ChallengeFormat
    public var minutes: Int
    public var moves: [String]
    public var by: ChallengeAuthor
    public var votes: Int
    public var mine: Bool

    public init(id: String, name: String, format: ChallengeFormat, minutes: Int, moves: [String], by: ChallengeAuthor, votes: Int, mine: Bool) {
        self.id = id
        self.name = name
        self.format = format
        self.minutes = minutes
        self.moves = moves
        self.by = by
        self.votes = votes
        self.mine = mine
    }
}

public struct ChallengeVote: Decodable, Sendable, Equatable {
    /// The member week voted for.
    public var week: String
    public var endsAt: Date
    public var finalists: [ChallengeFinalist]

    public init(week: String, endsAt: Date, finalists: [ChallengeFinalist]) {
        self.week = week
        self.endsAt = endsAt
        self.finalists = finalists
    }
}

public struct ChallengeSuggestion: Decodable, Sendable, Equatable, Identifiable {
    public enum Status: String, Decodable, Sendable { case pending, approved, rejected }
    public var id: String
    public var name: String
    public var format: ChallengeFormat
    public var minutes: Int
    public var moves: [String]
    public var status: Status
    /// The member week it ran.
    public var week: String?
    public var createdAt: Date
}

public struct ChallengeRoom: Decodable, Sendable, Equatable {
    public var week: String
    /// Nil from older servers: the app's own rotation.
    public var wod: ChallengeWod?
    public var next: ChallengeNext?
    public var history: [ChallengePast]?
    public var vote: ChallengeVote?
    public var joined: Int
    /// Members doing it right now.
    public var training: Int
    public var leaderboard: [ChallengeEntry]
    public var me: ChallengeEntry?

    public init(week: String, wod: ChallengeWod? = nil, next: ChallengeNext? = nil, history: [ChallengePast]? = nil, vote: ChallengeVote? = nil,
                joined: Int = 0, training: Int = 0, leaderboard: [ChallengeEntry] = [], me: ChallengeEntry? = nil) {
        self.week = week
        self.wod = wod
        self.next = next
        self.history = history
        self.vote = vote
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
    public var seconds: Int?
    public var tier: ChallengeTier?
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

    /// Keep your live set from this buddy, or share it again (#675).
    public func setBuddyShareLive(_ userId: String, _ share: Bool) async throws {
        struct Body: Encodable { var shareLive: Bool }
        _ = try await authorizedRaw("PATCH", "/v1/community/buddies/\(userId)", Body(shareLive: share))
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

    /// AMRAP / EMOM: rounds + reps; Tabata: reps; For time: seconds when finished, else reps (#748).
    public func sendChallengeScore(week: String, rounds: Int, reps: Int, seconds: Int? = nil, tier: ChallengeTier = .rx) async throws -> ChallengeScoreResult {
        struct Body: Encodable { var week: String; var rounds, reps: Int; var seconds: Int?; var tier: ChallengeTier }
        return try await authorized("PUT", "/v1/community/challenge/score", Body(week: week, rounds: rounds, reps: reps, seconds: seconds, tier: tier),
                                    as: ChallengeScoreResult.self)
    }

    struct SuggestionsResponse: Decodable { var suggestions: [ChallengeSuggestion]; var moves: [String] }
    struct SuggestionResponse: Decodable { var suggestion: ChallengeSuggestion }
    public struct ChallengeVoteResult: Decodable, Sendable { public var week: String; public var suggestionId: String }

    /// Your suggestions and the move list they use.
    public func challengeSuggestions() async throws -> (suggestions: [ChallengeSuggestion], moves: [String]) {
        let r = try await authorized("GET", "/v1/community/challenge/suggestions", Empty?.none, as: SuggestionsResponse.self)
        return (r.suggestions, r.moves)
    }

    public func suggestChallenge(name: String, format: ChallengeFormat, minutes: Int, moves: [String]) async throws -> ChallengeSuggestion {
        struct Body: Encodable { var name: String; var format: ChallengeFormat; var minutes: Int; var moves: [String] }
        return try await authorized("POST", "/v1/community/challenge/suggestions", Body(name: name, format: format, minutes: minutes, moves: moves),
                                    as: SuggestionResponse.self).suggestion
    }

    public func withdrawChallengeSuggestion(_ id: String) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/community/challenge/suggestions/\(id)", Empty?.none)
    }

    @discardableResult
    public func voteChallenge(_ suggestionId: String) async throws -> ChallengeVoteResult {
        struct Body: Encodable { var suggestionId: String }
        return try await authorized("PUT", "/v1/community/challenge/vote", Body(suggestionId: suggestionId), as: ChallengeVoteResult.self)
    }
}
