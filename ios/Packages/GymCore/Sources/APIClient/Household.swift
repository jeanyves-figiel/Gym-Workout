import Foundation

// MARK: Fuel with a partner (#1014): a household sharing one meal plan + grocery list, and one-off copies.

public struct HouseholdPerson: Codable, Sendable, Equatable, Hashable {
    public var userId: String
    public var nickname: String

    public init(userId: String, nickname: String) {
        self.userId = userId
        self.nickname = nickname
    }
}

/// `State` is the app's shared plan (plan days, recipes used, plan settings); the server keeps it as sent.
public struct Household<State: Codable & Sendable>: Decodable, Sendable {
    public struct Member: Codable, Sendable, Equatable, Hashable, Identifiable {
        public var userId: String
        public var nickname: String
        public var joinedAt: String
        public var me: Bool
        public var id: String { userId }
    }

    public struct Tick: Codable, Sendable, Equatable, Hashable {
        public var itemId: String
        /// Nil once that member's account is gone.
        public var by: HouseholdPerson?
        public var at: String
    }

    public var id: String
    /// Bumped on every plan write; send it back with the next write.
    public var rev: Int
    /// Nil until someone writes the first plan.
    public var state: State?
    public var updatedAt: String?
    public var updatedBy: HouseholdPerson?
    /// Me first.
    public var members: [Member]
    public var bought: [Tick]

    public var others: [Member] { members.filter { !$0.me } }

    enum CodingKeys: String, CodingKey { case id, rev, state, updatedAt, updatedBy, members, bought }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        rev = try c.decode(Int.self, forKey: .rev)
        // A plan another app version wrote that this one can't read counts as none: never fail the whole household.
        state = try? c.decodeIfPresent(State.self, forKey: .state)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        updatedBy = try c.decodeIfPresent(HouseholdPerson.self, forKey: .updatedBy)
        members = try c.decode([Member].self, forKey: .members)
        bought = try c.decode([Tick].self, forKey: .bought)
    }
}

public struct HouseholdInvite: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    /// Incoming only.
    public var from: HouseholdPerson?
    /// Outgoing only.
    public var to: HouseholdPerson?
    /// People already in the inviter's household (incoming).
    public var members: Int?
    public var createdAt: String
}

public struct HouseholdView<State: Codable & Sendable>: Decodable, Sendable {
    public struct Invites: Codable, Sendable, Equatable {
        public var incoming: [HouseholdInvite]
        public var outgoing: [HouseholdInvite]
    }

    public var household: Household<State>?
    public var invites: Invites
}

public enum FuelShareKind: String, Codable, Sendable, CaseIterable {
    case plan, groceries, both
}

/// A grocery line in a copy: enough to read and to add to one's own list.
public struct SharedGroceryLine: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var grams: Double

    public init(id: String, name: String, grams: Double) {
        self.id = id
        self.name = name
        self.grams = grams
    }
}

public struct FuelSharePayload<Plan: Codable & Sendable>: Codable, Sendable {
    public var plan: Plan?
    public var groceries: [SharedGroceryLine]?
    public var note: String?

    public init(plan: Plan? = nil, groceries: [SharedGroceryLine]? = nil, note: String? = nil) {
        self.plan = plan
        self.groceries = groceries
        self.note = note
    }

    enum CodingKeys: String, CodingKey { case plan, groceries, note }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan = try? c.decodeIfPresent(Plan.self, forKey: .plan)
        groceries = try? c.decodeIfPresent([SharedGroceryLine].self, forKey: .groceries)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

public struct FuelShare<Plan: Codable & Sendable>: Decodable, Sendable, Identifiable {
    public var id: String
    public var from: HouseholdPerson
    public var kind: FuelShareKind
    public var payload: FuelSharePayload<Plan>
    public var createdAt: String
}

// Request and response bodies (types can't be nested in generic functions).
private struct HouseholdInviteBody: Encodable { var userId: String }
private struct HouseholdAcceptBody: Encodable { var leaveCurrent: Bool }
private struct HouseholdStateBody<S: Encodable & Sendable>: Encodable, Sendable { var rev: Int; var state: S }
private struct HouseholdRevResponse: Decodable { var rev: Int }
private struct HouseholdBoughtBody: Encodable { var itemIds: [String]; var bought: Bool }
private struct FuelShareBody<P: Codable & Sendable>: Encodable { var toUserId: String; var kind: FuelShareKind; var payload: FuelSharePayload<P> }
private struct FuelSharesResponse<P: Codable & Sendable>: Decodable { var shares: [FuelShare<P>] }

extension APIClient {
    public func household<S: Codable & Sendable>(_ state: S.Type) async throws -> HouseholdView<S> {
        try await authorized("GET", "/v1/household", Empty?.none, as: HouseholdView<S>.self)
    }

    /// Invite a Social member; makes your household on the first invite.
    public func inviteToHousehold<S: Codable & Sendable>(_ userId: String, _ state: S.Type) async throws -> HouseholdView<S> {
        try await authorized("POST", "/v1/household/invites", HouseholdInviteBody(userId: userId), as: HouseholdView<S>.self)
    }

    /// Accept; `leaveCurrent` leaves the plan you share with others (server answers 409 `in_household` without it).
    public func acceptHouseholdInvite<S: Codable & Sendable>(_ id: String, leaveCurrent: Bool = false, _ state: S.Type) async throws -> HouseholdView<S> {
        try await authorized("POST", "/v1/household/invites/\(id)/accept", HouseholdAcceptBody(leaveCurrent: leaveCurrent), as: HouseholdView<S>.self)
    }

    /// Decline (theirs) or cancel (yours).
    public func dropHouseholdInvite(_ id: String) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/household/invites/\(id)", Empty?.none)
    }

    /// Writes the shared plan; throws `APIError.server(409, "stale", _)` when someone wrote first (read again).
    public func putHouseholdState<S: Codable & Sendable>(rev: Int, state: S) async throws -> Int {
        try await authorized("PUT", "/v1/household/state", HouseholdStateBody(rev: rev, state: state), as: HouseholdRevResponse.self).rev
    }

    public func setHouseholdBought(_ itemIds: [String], bought: Bool) async throws {
        _ = try await authorizedRaw("PUT", "/v1/household/bought", HouseholdBoughtBody(itemIds: itemIds, bought: bought))
    }

    public func leaveHousehold() async throws {
        _ = try await authorizedRaw("DELETE", "/v1/household/me", Empty?.none)
    }

    /// Send a copy to a friend who follows you back (or shares your plan).
    public func sendFuelShare<P: Codable & Sendable>(to userId: String, kind: FuelShareKind, payload: FuelSharePayload<P>) async throws {
        _ = try await authorizedRaw("POST", "/v1/fuel-shares", FuelShareBody(toUserId: userId, kind: kind, payload: payload))
    }

    public func fuelShares<P: Codable & Sendable>(_ plan: P.Type) async throws -> [FuelShare<P>] {
        try await authorized("GET", "/v1/fuel-shares", Empty?.none, as: FuelSharesResponse<P>.self).shares
    }

    public func dropFuelShare(_ id: String) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/fuel-shares/\(id)", Empty?.none)
    }
}
