public struct Gym: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let location: String
    public let equipment: [Equipment]
    public let amenities: [String]
    /// Assumptions to verify on site.
    public let note: String

    public static let puls5 = Gym(
        id: "fitnesspark-puls5",
        name: "Fitnesspark Puls 5",
        location: "Giessereistrasse 18, 8005 Zürich",
        equipment: Equipment.allCases,
        amenities: ["Sauna ×2", "Steam bath", "Whirlpool", "Group classes"],
        note: "Large full-service club: free weights, machine circuits, functional zone, full cardio floor. Inventory assumed — untick anything missing."
    )

    /// Gyms with a scoped equipment inventory, offered first when picking a gym.
    public static let scoped: [Gym] = [puls5]

    public static func scopedGym(id: String) -> Gym? { scoped.first { $0.id == id } }

    /// Note for gyms found by search, whose inventory is unknown.
    public static let searchedNote = "Inventory unknown — a full commercial gym is assumed. Untick anything missing."

    public var ref: GymRef { GymRef(id: id, name: name, address: location) }
}

/// The gym saved in a profile: a scoped gym (by id) or one picked from a map search.
public struct GymRef: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var address: String
    public var latitude: Double?
    public var longitude: Double?

    public init(id: String, name: String, address: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }

    /// The scoped gym this refers to, if any.
    public var scoped: Gym? { Gym.scopedGym(id: id) }
}
