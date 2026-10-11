import Foundation

// Gym memory (#162): members' equipment lists per gym, shared as counts only.

/// Other members' answers for one gym or one chain.
public struct GymTally: Codable, Sendable, Equatable {
    /// Members who reported.
    public var members: Int
    /// Yes-votes per equipment id.
    public var votes: [String: Int]
    /// Equipment ids at least half of them have.
    public var equipment: [String]
    /// Chain only: shared name ("holmes place") and how many branches were reported.
    public var name: String?
    public var gyms: Int?

    public init(members: Int, votes: [String: Int], equipment: [String], name: String? = nil, gyms: Int? = nil) {
        self.members = members
        self.votes = votes
        self.equipment = equipment
        self.name = name
        self.gyms = gyms
    }
}

public struct KnownGym: Codable, Sendable, Equatable {
    /// Reports at this place (same id, or same name within ~300 m).
    public var place: GymTally?
    /// Reports at other branches of the same chain.
    public var chain: GymTally?

    public init(place: GymTally? = nil, chain: GymTally? = nil) {
        self.place = place
        self.chain = chain
    }
}

/// A gym as the server matches it.
public struct GymPlace: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var latitude: Double?
    public var longitude: Double?

    public init(id: String, name: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

extension APIClient {
    private static func query(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? ""
    }

    /// What other members found at this gym and at other branches of its chain.
    public func knownGym(_ gym: GymPlace) async throws -> KnownGym {
        var path = "/v1/gyms/known?id=\(Self.query(gym.id))&name=\(Self.query(gym.name))"
        if let lat = gym.latitude, let lng = gym.longitude { path += "&lat=\(lat)&lng=\(lng)" }
        return try await authorized("GET", path, Empty?.none, as: KnownGym.self)
    }

    /// Your equipment list for a gym; replaces your earlier one.
    public func reportGym(_ gym: GymPlace, equipment: [String], unsure: [String]) async throws {
        struct Body: Encodable { var gym: GymPlace; var equipment: [String]; var unsure: [String] }
        _ = try await authorizedRaw("PUT", "/v1/gyms/reports", Body(gym: gym, equipment: equipment, unsure: unsure))
    }

    public func deleteGymReport(id: String) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/gyms/reports?id=\(Self.query(id))", Empty?.none)
    }
}
