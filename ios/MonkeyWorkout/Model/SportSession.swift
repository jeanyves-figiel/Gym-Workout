import Foundation
import LiftSensor
import WorkoutEngine

/// A sport session other than climbing (#416): logged here, or a Health workout the member rated (Spotted).
/// Synced like climbs; written to Apple Health unless it came from there.
struct SportLog: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var sport: Sport = .snowboard
    var start: Date
    var minutes: Int = 120
    /// 1 (very easy) … 10 (max effort).
    var effort: Int = 6
    var distanceKm: Double?
    var notes: String?
    /// Rated from an Apple Health workout (Spotted, #416): `id` is that workout's id; never written back to Health.
    var fromHealth: Bool?
    /// Hyrox race or sim recorded on the Watch (#426): splits, Roxzone, division and goal.
    var hyrox: HyroxRace?

    var end: Date { start.addingTimeInterval(Double(minutes) * 60) }
}

/// One sport session shown in the app: logged here or read from Apple Health (Watch, Strava, Garmin, Slopes…).
struct SportEntry: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let sport: Sport
    let start: Date
    let end: Date
    /// App that recorded it ("MonkeyWorkout" when logged here).
    let source: String
    var effort: Int?
    var distanceKm: Double?
    var elevationM: Double?
    var avgHR: Double?
    var maxHR: Double?
    var kcal: Double?
    /// True when logged in this app (can be deleted here).
    var local = false

    var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }

    /// Average speed in km/h, when the distance is known.
    var avgSpeed: Double? {
        guard let d = distanceKm, d > 0, minutes > 0 else { return nil }
        return d / (Double(minutes) / 60)
    }

    /// Hard on the body: effort ≥ 7, or ≥ 2 h when the effort is unknown.
    var isHard: Bool {
        if let effort { return effort >= 7 }
        return minutes >= 120
    }

    init(id: UUID, sport: Sport, start: Date, end: Date, source: String, effort: Int? = nil, distanceKm: Double? = nil,
         elevationM: Double? = nil, avgHR: Double? = nil, maxHR: Double? = nil, kcal: Double? = nil, local: Bool = false) {
        self.id = id
        self.sport = sport
        self.start = start
        self.end = end
        self.source = source
        self.effort = effort
        self.distanceKm = distanceKm
        self.elevationM = elevationM
        self.avgHR = avgHR
        self.maxHR = maxHR
        self.kcal = kcal
        self.local = local
    }

    init(_ log: SportLog) {
        self.init(id: log.id, sport: log.sport, start: log.start, end: log.end, source: "MonkeyWorkout",
                  effort: log.effort, distanceKm: log.distanceKm, local: log.fromHealth != true)
    }
}

enum Sports {
    /// Logged sessions plus Health sessions, newest first. A rated Health session (same id) keeps Health's stats
    /// and the member's effort.
    static func merged(local: [SportLog], health: [SportEntry]) -> [SportEntry] {
        let byId = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out = health.map { h -> SportEntry in
            guard let log = byId[h.id] else { return h }
            var e = h
            e.effort = log.effort
            return e
        }
        let healthIds = Set(health.map(\.id))
        out += local.filter { !healthIds.contains($0.id) }.map { SportEntry($0) }
        return out.sorted { $0.start > $1.start }
    }

    static func thisWeek(_ entries: [SportEntry], now: Date = Date()) -> Int {
        let cal = Progression.calendar()
        let start = Progression.weekStart(now, cal)
        return entries.filter { $0.start >= start && $0.start <= now }.count
    }

    /// Health sessions of the last two days the member hasn't rated yet (Spotted, #416), newest first.
    static func spotted(_ entries: [SportEntry], rated: Set<UUID>, now: Date = Date()) -> [SportEntry] {
        let cal = Progression.calendar()
        guard let since = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now)) else { return [] }
        return entries.filter { !$0.local && !rated.contains($0.id) && $0.end >= since && $0.start <= now && $0.minutes >= 20 }
    }

    /// Hard session that ended yesterday or today: the next gym session should spare what it loaded.
    static func recentHard(_ entries: [SportEntry], now: Date = Date()) -> SportEntry? {
        let cal = Progression.calendar()
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now)) else { return nil }
        return entries.first { $0.isHard && $0.end >= yesterday && $0.start <= now }
    }

    /// The session type that spares what `sport` loaded most, when `focus` clashes with it; nil when it fits.
    static func swap(for focus: Focus, after sport: Sport) -> Focus? {
        let load = sport.load
        guard load.clash(focus) >= 2 else { return nil }
        let options: [Focus] = [.push, .pull, .upper, .lower, .fullUpper, .conditioning]
        return options.filter { $0 != focus }.min { load.clash($0) < load.clash($1) }
    }

    /// Rough active energy from the sport's MET, scaled by effort.
    static func kcal(_ log: SportLog, weightKg: Double?) -> Double? {
        guard let w = weightKg, w > 0 else { return nil }
        let met = log.sport.met * (0.7 + 0.06 * Double(min(max(log.effort, 1), 10)))
        return (met * w * Double(log.minutes) / 60).rounded()
    }
}
