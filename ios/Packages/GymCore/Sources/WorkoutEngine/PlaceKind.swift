import Foundation

// Place types (#960, design A + B + C): every climb or sport place has a type, each sport lists only its types,
// gyms count for a sport through what they also have, and each group has a home spot.

/// What kind of place a session happened at.
public enum PlaceKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case gym, climbingGym, crag, skiResort, snowPark, nordicCentre, trail, bikePark, pool, beach, diveSite
    case court, field, studio, skatePark, golfCourse, other
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .gym: "Gym"
        case .climbingGym: "Climbing gym"
        case .crag: "Crag"
        case .skiResort: "Ski resort"
        case .snowPark: "Snow park"
        case .nordicCentre: "Nordic centre"
        case .trail: "Trail"
        case .bikePark: "Bike park"
        case .pool: "Pool"
        case .beach: "Beach / lake"
        case .diveSite: "Dive site"
        case .court: "Court"
        case .field: "Pitch / track"
        case .studio: "Studio"
        case .skatePark: "Skate park"
        case .golfCourse: "Golf course"
        case .other: "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .gym: "dumbbell.fill"
        case .climbingGym: "figure.climbing"
        case .crag: "mountain.2.fill"
        case .skiResort: "figure.skiing.downhill"
        case .snowPark: "figure.snowboarding"
        case .nordicCentre: "figure.skiing.crosscountry"
        case .trail: "figure.hiking"
        case .bikePark: "bicycle"
        case .pool: "figure.pool.swim"
        case .beach: "water.waves"
        case .diveSite: "water.waves.and.arrow.down"
        case .court: "tennis.racket"
        case .field: "sportscourt.fill"
        case .studio: "figure.yoga"
        case .skatePark: "figure.skateboarding"
        case .golfCourse: "figure.golf"
        case .other: "mappin"
        }
    }

    public var group: PlaceGroup {
        switch self {
        case .gym: .gym
        case .climbingGym, .crag: .climbing
        case .skiResort, .snowPark, .nordicCentre: .snow
        case .trail, .bikePark: .trails
        case .pool, .beach, .diveSite: .water
        case .court, .field: .courts
        case .studio: .studio
        case .skatePark, .golfCourse, .other: .other
        }
    }
}

/// Sections of Your places (design B): one home spot each.
public enum PlaceGroup: String, Codable, CaseIterable, Sendable, Identifiable {
    case gym, climbing, snow, trails, water, courts, studio, other
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .gym: "Gyms"
        case .climbing: "Climbing"
        case .snow: "Snow"
        case .trails: "Trails"
        case .water: "Water"
        case .courts: "Courts & pitches"
        case .studio: "Studios"
        case .other: "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .gym: "dumbbell.fill"
        case .climbing: "figure.climbing"
        case .snow: "figure.snowboarding"
        case .trails: "figure.hiking"
        case .water: "figure.pool.swim"
        case .courts: "sportscourt.fill"
        case .studio: "figure.yoga"
        case .other: "mappin"
        }
    }

    public var kinds: [PlaceKind] { PlaceKind.allCases.filter { $0.group == self } }

    /// The sport whose search adds a place to this section.
    public var sport: Sport {
        switch self {
        case .gym: .hyrox
        case .climbing: .climbing
        case .snow: .snowboard
        case .trails: .hike
        case .water: .swim
        case .courts: .tennis
        case .studio: .yoga
        case .other: .other
        }
    }
}

/// What a gym also has (design C): a gym counts for a sport only through these, unless the sport is a gym one.
public enum GymExtra: String, Codable, CaseIterable, Sendable, Identifiable {
    case boulderWall, pool, courts, studio, ring
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .boulderWall: "Boulder wall"
        case .pool: "Pool"
        case .courts: "Courts"
        case .studio: "Studio"
        case .ring: "Ring"
        }
    }

    public var symbol: String {
        switch self {
        case .boulderWall: "figure.climbing"
        case .pool: "figure.pool.swim"
        case .courts: "tennis.racket"
        case .studio: "figure.yoga"
        case .ring: "figure.boxing"
        }
    }

    public var sports: [Sport] {
        switch self {
        case .boulderWall: [.climbing]
        case .pool: [.swim, .scubaDiving]
        case .courts: [.squash, .padel, .tennis, .basketball, .volleyball]
        case .studio: [.yoga, .martialArts]
        case .ring: [.boxing, .martialArts]
        }
    }

    /// "Squash, padel, tennis…" under the tile.
    public var blurb: String {
        let names = sports.map(\.label)
        return names.prefix(3).joined(separator: ", ") + (names.count > 3 ? "…" : "")
    }
}

extension Sport {
    /// Place types this sport is done at, the usual one first.
    public var placeKinds: [PlaceKind] {
        switch self {
        case .climbing: [.climbingGym, .crag]
        case .snowboard: [.snowPark, .skiResort]
        case .ski: [.skiResort, .snowPark]
        case .crossCountrySki: [.nordicCentre, .trail]
        case .mountainBike: [.bikePark, .trail]
        case .roadBike, .trailRun, .hike: [.trail]
        case .run: [.trail, .field]
        case .mountaineering: [.trail, .crag]
        case .hyrox, .crossfit, .rowing: [.gym]
        case .swim: [.pool, .beach]
        case .football: [.field]
        case .basketball, .tennis, .padel, .squash: [.court]
        case .volleyball: [.court, .beach]
        case .martialArts, .boxing, .yoga: [.studio]
        case .surf: [.beach]
        case .scubaDiving: [.diveSite, .beach, .pool]
        case .skate: [.skatePark]
        case .golf: [.golfCourse]
        case .other: PlaceKind.allCases
        }
    }

    /// Section of Your places whose home spot a new log of this sport starts at.
    public var placeGroup: PlaceGroup { self == .other ? .other : placeKinds[0].group }

    /// Search field hint: "Climbing gym, crag…".
    public var placeHint: String {
        guard self != .other else { return "Gym, crag, spot…" }
        let names = placeKinds.prefix(2).enumerated().map { $0.offset == 0 ? $0.element.label : $0.element.label.lowercased() }
        return names.joined(separator: ", ") + "…"
    }
}

extension SavedGym {
    /// A gym fits gym sports (Hyrox, CrossFit, rowing) and the sports of what it also has.
    public func fits(_ sport: Sport) -> Bool {
        sport == .other || sport.placeKinds.contains(.gym) || (extras ?? []).contains { $0.sports.contains(sport) }
    }
}

/// Your places (design B): places typed by the member and the home spot of each group. Synced with the profile.
public struct PlaceBook: Codable, Hashable, Sendable {
    /// Places added or typed on Your places, newest first; their type wins over the one a log carries.
    public var places: [SessionPlace]
    /// Group raw value → place id: where a new log of that group's sports starts.
    public var homes: [String: String]

    public init(places: [SessionPlace] = [], homes: [String: String] = [:]) {
        self.places = places
        self.homes = homes
    }

    public static let maxPlaces = 60

    /// The place with the member's type, if they typed it.
    public func resolve(_ p: SessionPlace) -> SessionPlace {
        guard let mine = places.first(where: { $0.id == p.id }) else { return p }
        var out = p
        out.kind = mine.kind
        return out
    }

    public func home(_ group: PlaceGroup) -> SessionPlace? {
        homes[group.rawValue].flatMap { id in places.first { $0.id == id } }
    }

    public func isHome(_ p: SessionPlace) -> Bool { homes.values.contains(p.id) }

    /// Adds or replaces a place (newest first, capped).
    public mutating func save(_ p: SessionPlace) {
        let old = places.first { $0.id == p.id }
        places.removeAll { $0.id == p.id }
        places.insert(p, at: 0)
        if places.count > Self.maxPlaces { places = Array(places.prefix(Self.maxPlaces)) }
        // A home spot whose type moved to another group is no longer that group's home.
        if let oldGroup = old?.kind?.group, oldGroup != p.kind?.group, homes[oldGroup.rawValue] == p.id {
            homes[oldGroup.rawValue] = nil
        }
        homes = homes.filter { id in places.contains { $0.id == id.value } }
    }

    /// Makes `p` the home spot of its type's group (saving it), or clears it when it already is.
    public mutating func toggleHome(_ p: SessionPlace) {
        guard let group = p.kind?.group else { return }
        if homes[group.rawValue] == p.id {
            homes[group.rawValue] = nil
        } else {
            save(p)
            homes[group.rawValue] = p.id
        }
    }

    public mutating func remove(_ id: String) {
        places.removeAll { $0.id == id }
        homes = homes.filter { $0.value != id }
    }
}
