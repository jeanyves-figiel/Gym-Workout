import Foundation

/// Where a climb or sport session happened (#832): a saved gym, a map place (crag, ski resort, trail) or one typed in.
public struct SessionPlace: Codable, Hashable, Sendable, Identifiable {
    /// The saved gym's id, "map:" + name and position for an Apple Maps place, "custom:" for a typed one.
    public var id: String
    public var name: String
    public var address: String?
    public var latitude: Double?
    public var longitude: Double?
    /// Set when it is one of the member's saved gyms.
    public var gymId: String?

    public init(id: String, name: String, address: String? = nil, latitude: Double? = nil, longitude: Double? = nil, gymId: String? = nil) {
        self.id = id
        self.name = name
        self.address = address?.isEmpty == true ? nil : address
        self.latitude = latitude
        self.longitude = longitude
        self.gymId = gymId
    }

    public init(gym: SavedGym) {
        self.init(id: gym.id, name: gym.ref.name, address: gym.ref.address, latitude: gym.ref.latitude, longitude: gym.ref.longitude, gymId: gym.id)
    }

    /// A map place: same name at about the same spot (≈100 m) keeps one id, so it lists once.
    public static func map(name: String, address: String?, latitude: Double?, longitude: Double?) -> SessionPlace {
        var id = "map:" + PlaceSuggest.fold(name)
        if let latitude, let longitude { id += String(format: "@%.3f,%.3f", latitude, longitude) }
        return SessionPlace(id: id, name: name, address: address, latitude: latitude, longitude: longitude)
    }

    public static func typed(_ name: String) -> SessionPlace {
        SessionPlace(id: "custom:" + PlaceSuggest.fold(name), name: name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public var hasCoordinate: Bool { latitude != nil && longitude != nil }
}

extension Sport {
    /// Never in a gym: the place picker leaves saved gyms out (#832).
    public var outdoorOnly: Bool {
        [.snowboard, .ski, .crossCountrySki, .mountainBike, .roadBike, .trailRun, .hike, .mountaineering, .surf, .scubaDiving, .golf]
            .contains(self)
    }
}

public enum SessionPlaces {
    /// One place used before: which sport, where, when.
    public struct Use: Sendable {
        public var sport: Sport
        public var place: SessionPlace
        public var start: Date
        public init(sport: Sport, place: SessionPlace, start: Date) {
            self.sport = sport
            self.place = place
            self.start = start
        }
    }

    /// Chips for the log card: places used for this sport (newest first), then saved gyms unless the sport is
    /// outdoor only, then places used for other sports. Each place once; `current` always listed first.
    public static func chips(for sport: Sport, current: SessionPlace? = nil, used: [Use], gyms: [SavedGym], limit: Int = 6) -> [SessionPlace] {
        let newest = used.sorted { $0.start > $1.start }
        var out: [SessionPlace] = []
        var seen = Set<String>()
        func add(_ p: SessionPlace) {
            guard out.count < limit, seen.insert(p.id).inserted else { return }
            out.append(p)
        }
        if let current { add(current) }
        newest.filter { $0.sport == sport }.forEach { add($0.place) }
        if !sport.outdoorOnly { gyms.forEach { add(SessionPlace(gym: $0)) } }
        newest.filter { $0.sport != sport }.forEach { add($0.place) }
        return out
    }

    /// Where the member last did this sport: the new log starts there.
    public static func last(for sport: Sport, used: [Use]) -> SessionPlace? {
        used.filter { $0.sport == sport }.max { $0.start < $1.start }?.place
    }
}
