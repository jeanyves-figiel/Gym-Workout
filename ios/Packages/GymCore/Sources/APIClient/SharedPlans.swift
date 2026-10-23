import Foundation

// MARK: Shared plans (#666): member-made programmes others browse in Community → Plans and copy.

public enum SharedPlanLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case beginner, intermediate, advanced
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .beginner: "Beginner"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        }
    }
}

/// A shared plan; `programme` is the app's own record (opaque to the server).
public struct SharedPlan<Programme: Codable & Sendable & Hashable>: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var about: String?
    public var level: SharedPlanLevel
    public var goal: String?
    public var weeks: Int
    public var sessionsPerWeek: Int
    public var programme: Programme
    public var author: CommunityAuthor
    public var mine: Bool
    public var visibility: CommunityVisibility
    public var copies: Int
    public var copiedByMe: Bool
    public var hidden: Bool

    public init(
        id: String, name: String, about: String? = nil, level: SharedPlanLevel, goal: String? = nil, weeks: Int, sessionsPerWeek: Int,
        programme: Programme, author: CommunityAuthor, mine: Bool, visibility: CommunityVisibility = .members, copies: Int = 0,
        copiedByMe: Bool = false, hidden: Bool = false
    ) {
        self.id = id
        self.name = name
        self.about = about
        self.level = level
        self.goal = goal
        self.weeks = weeks
        self.sessionsPerWeek = sessionsPerWeek
        self.programme = programme
        self.author = author
        self.mine = mine
        self.visibility = visibility
        self.copies = copies
        self.copiedByMe = copiedByMe
        self.hidden = hidden
    }
}

/// What the app sends to share or update a plan.
public struct SharedPlanDraft<Programme: Codable & Sendable>: Encodable, Sendable {
    public var name: String
    public var about: String?
    public var level: SharedPlanLevel
    public var goal: String?
    public var weeks: Int
    public var sessionsPerWeek: Int
    public var programme: Programme
    public var visibility: CommunityVisibility

    public init(name: String, about: String?, level: SharedPlanLevel, goal: String?, weeks: Int, sessionsPerWeek: Int, programme: Programme,
                visibility: CommunityVisibility) {
        self.name = name
        self.about = about
        self.level = level
        self.goal = goal
        self.weeks = weeks
        self.sessionsPerWeek = sessionsPerWeek
        self.programme = programme
        self.visibility = visibility
    }
}

struct SharedPlansResponse<P: Codable & Sendable & Hashable>: Decodable, Sendable {
    /// Lossy: a plan this app version can't read is skipped, not the whole list.
    var programs: [SharedPlan<P>]

    init(from decoder: any Decoder) throws {
        struct Skip: Decodable {}
        var c = try decoder.container(keyedBy: CodingKeys.self).nestedUnkeyedContainer(forKey: .programs)
        var list: [SharedPlan<P>] = []
        while !c.isAtEnd {
            if let p = try? c.decode(SharedPlan<P>.self) { list.append(p) } else { _ = try? c.decode(Skip.self) }
        }
        programs = list
    }

    enum CodingKeys: String, CodingKey { case programs }
}

struct SharedPlanResponse<P: Codable & Sendable & Hashable>: Decodable, Sendable { var program: SharedPlan<P> }

extension APIClient {
    /// Members' plans, newest first (`mine`: your own, private ones too). Needs a community profile.
    public func sharedPlans<P: Codable & Sendable & Hashable>(
        _: P.Type, query: String? = nil, level: SharedPlanLevel? = nil, mine: Bool = false, limit: Int = 30
    ) async throws -> [SharedPlan<P>] {
        var path = "/v1/community/programs?limit=\(limit)"
        if mine { path += "&mine=1" }
        if let level { path += "&level=\(level.rawValue)" }
        if let q = query?.trimmingCharacters(in: .whitespaces), !q.isEmpty {
            path += "&q=\(q.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
        }
        return try await authorized("GET", path, Empty?.none, as: SharedPlansResponse<P>.self).programs
    }

    /// Shares a plan, or updates it when `id` is yours already.
    public func saveSharedPlan<P: Codable & Sendable & Hashable>(id: String, _ draft: SharedPlanDraft<P>) async throws -> SharedPlan<P> {
        try await authorized("PUT", "/v1/community/programs/\(id.lowercased())", draft, as: SharedPlanResponse<P>.self).program
    }

    public func deleteSharedPlan(_ id: String) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/community/programs/\(id.lowercased())", Empty?.none)
    }

    /// Counts a copy for the author (once per member); the copy itself is saved by the app.
    public func countSharedPlanCopy<P: Codable & Sendable & Hashable>(_ id: String, as _: P.Type) async throws -> SharedPlan<P> {
        try await authorized("POST", "/v1/community/programs/\(id.lowercased())/copy", Empty?.none, as: SharedPlanResponse<P>.self).program
    }

    /// Reports a shared plan; returns whether it is now hidden.
    @discardableResult
    public func reportSharedPlan(_ id: String, reason: CommunityReportReason, details: String? = nil) async throws -> Bool {
        struct Body: Encodable { var reason: CommunityReportReason; var details: String? }
        struct Response: Decodable { var hidden: Bool }
        return try await authorized("POST", "/v1/community/programs/\(id.lowercased())/report", Body(reason: reason, details: details), as: Response.self).hidden
    }
}
