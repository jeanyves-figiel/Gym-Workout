import Foundation

/// Any sport a member does next to the gym (#416). Climbing keeps its own fields and MonkeyGrade link;
/// every other sport plugs into the same "around sport days" planning through `SportPlan`.
public enum Sport: String, Codable, CaseIterable, Identifiable, Sendable {
    case climbing, snowboard, ski, crossCountrySki, mountainBike, roadBike, run, trailRun, hike, mountaineering
    case hyrox, crossfit, swim, rowing, football, basketball, volleyball, tennis, padel, squash
    case martialArts, boxing, surf, scubaDiving, skate, golf, yoga, other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .climbing: "Climbing"
        case .snowboard: "Snowboard"
        case .ski: "Ski"
        case .crossCountrySki: "Cross-country ski"
        case .mountainBike: "Mountain bike"
        case .roadBike: "Road bike"
        case .run: "Run"
        case .trailRun: "Trail run"
        case .hike: "Hike"
        case .mountaineering: "Mountaineering"
        case .hyrox: "Hyrox"
        case .crossfit: "CrossFit"
        case .swim: "Swim"
        case .rowing: "Rowing"
        case .football: "Football"
        case .basketball: "Basketball"
        case .volleyball: "Volleyball"
        case .tennis: "Tennis"
        case .padel: "Padel"
        case .squash: "Squash"
        case .martialArts: "Martial arts"
        case .boxing: "Boxing"
        case .surf: "Surf"
        case .scubaDiving: "Scuba diving"
        case .skate: "Skate"
        case .golf: "Golf"
        case .yoga: "Yoga"
        case .other: "Other sport"
        }
    }

    /// Short name for chips and notes ("MTB").
    public var short: String {
        switch self {
        case .mountainBike: "MTB"
        case .crossCountrySki: "XC ski"
        case .scubaDiving: "Dive"
        case .martialArts: "Martial arts"
        case .other: "Sport"
        default: label
        }
    }

    /// Body load of a typical session, used to plan gym days around it.
    public var load: SportLoad {
        switch self {
        case .climbing: SportLoad(legs: 0.2, pull: 1, push: 0, cardio: 0.3)
        case .snowboard, .ski: SportLoad(legs: 1, pull: 0, push: 0, cardio: 0.4)
        case .crossCountrySki: SportLoad(legs: 0.8, pull: 0.5, push: 0.2, cardio: 1)
        case .mountainBike: SportLoad(legs: 1, pull: 0.3, push: 0.2, cardio: 0.8)
        case .roadBike: SportLoad(legs: 0.9, pull: 0, push: 0, cardio: 1)
        case .run, .trailRun: SportLoad(legs: 0.9, pull: 0, push: 0, cardio: 1)
        case .hike: SportLoad(legs: 0.6, pull: 0, push: 0, cardio: 0.5)
        case .mountaineering: SportLoad(legs: 1, pull: 0.4, push: 0, cardio: 0.7)
        case .hyrox, .crossfit: SportLoad(legs: 1, pull: 0.6, push: 0.6, cardio: 1)
        case .swim: SportLoad(legs: 0.2, pull: 0.8, push: 0.4, cardio: 1)
        case .rowing: SportLoad(legs: 0.7, pull: 0.9, push: 0, cardio: 1)
        case .football, .basketball: SportLoad(legs: 1, pull: 0, push: 0, cardio: 0.9)
        case .volleyball: SportLoad(legs: 0.8, pull: 0, push: 0.4, cardio: 0.6)
        case .tennis, .padel, .squash: SportLoad(legs: 0.7, pull: 0.2, push: 0.4, cardio: 0.8)
        case .martialArts: SportLoad(legs: 0.6, pull: 0.6, push: 0.5, cardio: 0.8)
        case .boxing: SportLoad(legs: 0.4, pull: 0.2, push: 0.8, cardio: 0.9)
        case .surf: SportLoad(legs: 0.4, pull: 0.6, push: 0.6, cardio: 0.6)
        case .scubaDiving: SportLoad(legs: 0.3, pull: 0.1, push: 0.1, cardio: 0.3)
        case .skate: SportLoad(legs: 0.8, pull: 0, push: 0, cardio: 0.5)
        case .golf: SportLoad(legs: 0.2, pull: 0.2, push: 0.2, cardio: 0.2)
        case .yoga: SportLoad(legs: 0.1, pull: 0, push: 0.1, cardio: 0.1)
        case .other: SportLoad(legs: 0.5, pull: 0.3, push: 0.3, cardio: 0.6)
        }
    }

    /// Typical MET at a solid effort, for a rough energy estimate.
    public var met: Double {
        switch self {
        case .climbing: 8
        case .snowboard, .ski: 5.3
        case .crossCountrySki: 9
        case .mountainBike: 8.5
        case .roadBike: 7.5
        case .run: 9.8
        case .trailRun: 10
        case .hike: 6
        case .mountaineering: 8
        case .hyrox, .crossfit: 9
        case .swim: 7
        case .rowing: 7
        case .football, .basketball: 7.5
        case .volleyball: 4
        case .tennis, .padel: 7
        case .squash: 9
        case .martialArts: 10
        case .boxing: 9
        case .surf: 3.5
        case .scubaDiving: 7
        case .skate: 5
        case .golf: 4.5
        case .yoga: 2.8
        case .other: 6
        }
    }

    /// Gym days around the sport when the member hasn't chosen: light before, light after, no gym the same day.
    /// Diving: hard exercise after a dive raises the risk of decompression sickness, so the day after is kept free.
    public var defaultBefore: ClimbNeighbour { .light }
    public var defaultAfter: ClimbNeighbour { self == .scubaDiving ? .rest : .light }

    /// Gym on the same day can be allowed (never for diving).
    public var allowsSameDayGym: Bool { self != .scubaDiving }

    /// Main body area in a few words, e.g. "legs" or "grip · pull".
    public var loadLabel: String { load.label }
}

/// How hard a sport works each area, 0 … 1.
public struct SportLoad: Hashable, Sendable {
    public var legs: Double
    public var pull: Double
    public var push: Double
    public var cardio: Double

    public init(legs: Double, pull: Double, push: Double, cardio: Double) {
        self.legs = legs
        self.pull = pull
        self.push = push
        self.cardio = cardio
    }

    public var label: String {
        if legs >= 0.6 && pull >= 0.6 && push >= 0.6 { return "full body" }
        var parts: [String] = []
        if pull >= 0.8 && legs < 0.5 { parts.append("grip") }
        if legs >= 0.6 { parts.append("legs") }
        if pull >= 0.6 { parts.append("pull") }
        if push >= 0.6 { parts.append("push") }
        if parts.isEmpty { parts.append(cardio >= 0.6 ? "cardio" : "light") }
        return parts.joined(separator: " · ")
    }

    /// How much a gym session of this type clashes with the sport, 0 … ~3.
    public func clash(_ f: Focus) -> Double {
        legs * WeekSchedule.legDemand(f) + pull * WeekSchedule.pullLoad(f) + push * WeekSchedule.pushDemand(f)
    }
}

/// A sport the member does on set weekdays (#416), optionally only in season or building to an event.
/// Climbing is not stored here: it keeps `climbingWeekdays` and `climbBefore`/`climbAfter`/`climbSameDay`.
public struct SportPlan: Codable, Hashable, Sendable, Identifiable {
    public var sport: Sport
    /// 1 = Monday … 7 = Sunday.
    public var weekdays: [Int]
    /// Months (1 … 12) the sport is done; nil or empty = all year.
    public var seasonMonths: [Int]?
    /// Race or event day ("2027-03-14"), e.g. a Hyrox; nil = none.
    public var eventDate: String?
    /// Gym day before / after a sport day; nil = `.light`.
    public var before: ClimbNeighbour?
    public var after: ClimbNeighbour?
    /// Gym on sport days; nil = `.avoid`.
    public var sameDay: ClimbSameDay?
    /// Switched off for now on its card in Your week (#474): days kept, not planned around. nil = on.
    public var paused: Bool?

    public var id: String { sport.rawValue }
    public var isOn: Bool { paused != true }

    public init(sport: Sport, weekdays: [Int] = [], seasonMonths: [Int]? = nil, eventDate: String? = nil,
                before: ClimbNeighbour? = nil, after: ClimbNeighbour? = nil, sameDay: ClimbSameDay? = nil, paused: Bool? = nil) {
        self.paused = paused
        self.sport = sport
        self.weekdays = weekdays
        self.seasonMonths = seasonMonths
        self.eventDate = eventDate
        self.before = before
        self.after = after
        self.sameDay = sameDay
    }

    /// In season on `date` (always, without season months).
    public func inSeason(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool {
        guard let months = seasonMonths, !months.isEmpty else { return true }
        return months.contains(calendar.component(.month, from: date))
    }

    /// Days of the week planned around this sport on `date`: none out of season.
    public func days(on date: Date) -> [SportDay] {
        guard isOn, inSeason(date) else { return [] }
        return WeekSchedule.normalized(weekdays).map {
            SportDay(weekday: $0, sport: sport, before: before ?? sport.defaultBefore, after: after ?? sport.defaultAfter,
                     sameDay: sport.allowsSameDayGym ? sameDay ?? .avoid : .avoid)
        }
    }

    /// The event as a date, when set and valid.
    public var event: Date? {
        guard let eventDate else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: eventDate)
    }
}

/// A dated sport day or trip (#474): a snowboard week, a one-off race or hike. No gym on those days; the days
/// around it are planned like weekly sport days. Day keys as in `PlanCalendar` ("2027-02-13").
public struct SportTrip: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var sport: Sport
    public var start: String
    public var end: String
    /// "Laax week"; nil = the sport's name.
    public var name: String?

    public init(id: UUID = UUID(), sport: Sport, start: String, end: String, name: String? = nil) {
        self.id = id
        self.sport = sport
        self.start = min(start, end)
        self.end = max(start, end)
        self.name = name
    }

    public func covers(_ day: String) -> Bool { start <= day && day <= end }
    public var isTrip: Bool { start != end }

    /// "Laax week", "Snowboard trip", "Run day".
    public var title: String {
        if let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        return "\(sport.label) \(isTrip ? "trip" : "day")"
    }
}

/// One weekday of a sport, with how the gym days around it are planned.
public struct SportDay: Hashable, Sendable {
    public var weekday: Int
    public var sport: Sport
    public var before: ClimbNeighbour
    public var after: ClimbNeighbour
    public var sameDay: ClimbSameDay

    public init(weekday: Int, sport: Sport, before: ClimbNeighbour = .light, after: ClimbNeighbour = .light, sameDay: ClimbSameDay = .avoid) {
        self.weekday = weekday
        self.sport = sport
        self.before = before
        self.after = after
        self.sameDay = sameDay
    }
}

extension WeekSchedule {
    /// Leg demand of a session type (heavy squats, hinges, jumps).
    static func legDemand(_ f: Focus) -> Double {
        switch f {
        case .lower, .legs, .fullLower, .posterior: 3
        case .fullPower: 2.5
        case .conditioning: 1.5
        case .fullUpper: 0.5
        case .upper, .push, .pull, .chestTri, .backBi, .shouldersArms, .chestBack: 0
        }
    }

    /// Pressing demand of a session type.
    static func pushDemand(_ f: Focus) -> Double {
        switch f {
        case .push, .chestTri: 3
        case .upper, .fullUpper, .chestBack: 2
        case .shouldersArms: 1.5
        case .fullPower: 1
        case .lower, .legs, .fullLower, .posterior, .pull, .backBi, .conditioning: 0
        }
    }

    /// Score added by the member's other sports (#416), on top of climbing. Same rules as climbing days, with the
    /// clash taken from the sport's body load: a legs sport keeps leg days away, a pulling sport pull days.
    static func sportScore(day d: Int, focus f: Focus, sports: [SportDay]) -> Double {
        var s = 0.0
        var antagonist = 0.0
        for sd in sports {
            let clash = sd.sport.load.clash(f)
            if sd.weekday == d { s += sd.sameDay == .allow ? 1 + clash : 12 }
            if sd.weekday == next(d) {
                switch sd.before {
                case .light: s += 1.5 * clash; antagonist = max(antagonist, 1)
                case .strong: s += 0.75 * clash; antagonist = max(antagonist, 1)
                case .rest: s += 8
                case .any: break
                }
            }
            if sd.weekday == previous(d) {
                switch sd.after {
                case .light: s += clash; antagonist = max(antagonist, 1)
                case .strong: s += 0.5 * clash; antagonist = max(antagonist, 1)
                case .rest: s += 8
                case .any: break
                }
            }
        }
        // A session that spares what the sport works fits next to it.
        if antagonist > 0 {
            let worst = sports.filter { $0.weekday == next(d) || $0.weekday == previous(d) }.map { $0.sport.load.clash(f) }.max() ?? 0
            s -= 0.5 * max(0, 1.5 - worst)
        }
        return s
    }

    /// Short reason on a session card for a nearby sport day ("Snowboard tomorrow · heavy legs kept light").
    static func sportNote(weekday: Int, sports: [SportDay]) -> String? {
        if let sd = sports.first(where: { $0.weekday == weekday }) {
            return sd.sameDay == .allow ? "\(sd.sport.short) day too · gym first" : "\(sd.sport.short) day too · keep it light"
        }
        if let sd = sports.first(where: { $0.weekday == next(weekday) }) {
            return sd.before == .any ? "\(sd.sport.short) tomorrow" : "\(sd.sport.short) tomorrow · \(sd.sport.loadLabel) kept light"
        }
        if let sd = sports.first(where: { $0.weekday == previous(weekday) }) {
            return sd.sport == .scubaDiving ? "Day after diving · keep it easy" : "Day after \(sd.sport.short)"
        }
        return nil
    }

    /// Why a session type is a poor fit next to a sport day, nil when it fits.
    static func sportWarning(_ f: Focus, on weekday: Int, sports: [SportDay]) -> String? {
        for sd in sports where sd.sport.load.clash(f) >= 2 {
            if sd.weekday == next(weekday), sd.before != .any { return "\(sd.sport.label) the next day: \(sd.sport.loadLabel) still needed" }
            if sd.weekday == previous(weekday), sd.after != .any { return "\(sd.sport.label) the day before: \(sd.sport.loadLabel) still tired" }
        }
        return nil
    }
}

extension Profile {
    /// Other sports' days planned around this week (#416); empty without sports or out of season.
    public func sportDays(on date: Date = Date(), calendar cal: Calendar = Progression.calendar()) -> [SportDay] {
        var out = (sports ?? []).filter { $0.sport != .climbing }.flatMap { $0.days(on: date) }
        // Dated sport days and trips (#474) of that week take their weekday over.
        guard let trips = sportTrips, !trips.isEmpty else { return out }
        let keys = PlanCalendar.dayKeys(weekStart: Progression.weekStart(date, cal), cal)
        for (i, key) in keys.enumerated() {
            guard let t = trips.first(where: { $0.covers(key) }) else { continue }
            let plan = sports?.first { $0.sport == t.sport }
            out.removeAll { $0.weekday == i + 1 }
            out.append(SportDay(weekday: i + 1, sport: t.sport, before: plan?.before ?? t.sport.defaultBefore,
                                after: plan?.after ?? t.sport.defaultAfter, sameDay: .avoid))
        }
        return out.sorted { $0.weekday < $1.weekday }
    }

    /// The dated sport day or trip covering a day key ("2027-02-13"), if any (#474).
    public func sportTrip(on key: String) -> SportTrip? {
        sportTrips?.first { $0.covers(key) }
    }

    /// Picked sports other than climbing.
    public var otherSports: [SportPlan] { (sports ?? []).filter { $0.sport != .climbing } }
}

/// Hyrox settings (#426), kept with the profile so every device and the Watch share them. Plain values: the race
/// model itself lives in the LiftSensor package, shared with the Watch.
public struct HyroxProfile: Codable, Hashable, Sendable {
    /// "open", "pro", "doubles", "relay".
    public var category: String
    /// "men", "women", "mixed".
    public var group: String
    /// Goal time for a full race, minutes.
    public var goalMinutes: Int?
    public var raceName: String?

    public init(category: String = "open", group: String = "men", goalMinutes: Int? = nil, raceName: String? = nil) {
        self.category = category
        self.group = group
        self.goalMinutes = goalMinutes
        self.raceName = raceName
    }
}
