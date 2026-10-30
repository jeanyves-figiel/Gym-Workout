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
    /// Climbing gym, crag, ski resort… (#960); nil for places logged before types.
    public var kind: PlaceKind?

    public init(id: String, name: String, address: String? = nil, latitude: Double? = nil, longitude: Double? = nil, gymId: String? = nil,
                kind: PlaceKind? = nil) {
        self.id = id
        self.name = name
        self.address = address?.isEmpty == true ? nil : address
        self.latitude = latitude
        self.longitude = longitude
        self.gymId = gymId
        self.kind = kind
    }

    public init(gym: SavedGym) {
        self.init(id: gym.id, name: gym.ref.name, address: gym.ref.address, latitude: gym.ref.latitude, longitude: gym.ref.longitude, gymId: gym.id,
                  kind: .gym)
    }

    /// A map place: same name at about the same spot (≈100 m) keeps one id, so it lists once.
    public static func map(name: String, address: String?, latitude: Double?, longitude: Double?, kind: PlaceKind? = nil) -> SessionPlace {
        var id = "map:" + PlaceSuggest.fold(name)
        if let latitude, let longitude { id += String(format: "@%.3f,%.3f", latitude, longitude) }
        return SessionPlace(id: id, name: name, address: address, latitude: latitude, longitude: longitude, kind: kind)
    }

    public static func typed(_ name: String, kind: PlaceKind? = nil) -> SessionPlace {
        SessionPlace(id: "custom:" + PlaceSuggest.fold(name), name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind)
    }

    public var hasCoordinate: Bool { latitude != nil && longitude != nil }

    /// The type shown and filtered on: a saved gym is a gym.
    public var effectiveKind: PlaceKind? { kind ?? (gymId != nil ? .gym : nil) }

    /// Whether this sport can be done here (#960). A gym fits through what it also has; an untyped place fits
    /// only when `untyped` (the sport it was logged for).
    public func fits(_ sport: Sport, gyms: [SavedGym], untyped: Bool = false) -> Bool {
        if let gymId, let gym = gyms.first(where: { $0.id == gymId }) { return gym.fits(sport) }
        guard let k = effectiveKind else { return untyped }
        return sport.placeKinds.contains(k)
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

    /// Chips for the log card (#960): only places of this sport's types. `current` first, then the group's home
    /// spot, places used for this sport (newest first), Your places, gyms that fit, then typed places used for
    /// other sports. Each place once. `used` places are expected resolved through the book.
    public static func chips(for sport: Sport, current: SessionPlace? = nil, used: [Use], gyms: [SavedGym], book: PlaceBook = PlaceBook(),
                             limit: Int = 6) -> [SessionPlace] {
        let newest = used.sorted { $0.start > $1.start }
        var out: [SessionPlace] = []
        var seen = Set<String>()
        func add(_ p: SessionPlace, untyped: Bool = false) {
            guard out.count < limit, p.fits(sport, gyms: gyms, untyped: untyped), seen.insert(p.id).inserted else { return }
            out.append(p)
        }
        if let current, seen.insert(current.id).inserted { out.append(current) }
        if let home = book.home(sport.placeGroup) { add(home) }
        newest.filter { $0.sport == sport }.forEach { add($0.place, untyped: true) }
        book.places.forEach { add($0) }
        gyms.forEach { add(SessionPlace(gym: $0)) }
        newest.filter { $0.sport != sport }.forEach { add($0.place) }
        return out
    }

    /// Where a new log of this sport starts: the group's home spot, else where it was last done (if it still fits).
    public static func start(for sport: Sport, used: [Use], gyms: [SavedGym], book: PlaceBook = PlaceBook()) -> SessionPlace? {
        if let home = book.home(sport.placeGroup), home.fits(sport, gyms: gyms) { return home }
        return last(for: sport, used: used, gyms: gyms)
    }

    /// Where the member last did this sport, skipping a gym that doesn't (any more) fit it.
    public static func last(for sport: Sport, used: [Use], gyms: [SavedGym] = []) -> SessionPlace? {
        used.filter { $0.sport == sport && $0.place.fits(sport, gyms: gyms, untyped: true) }.max { $0.start < $1.start }?.place
    }
}
