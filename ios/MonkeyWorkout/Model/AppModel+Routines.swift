import Foundation
import WorkoutEngine

/// Daily routines (#689): which routines sit on Train, the length picked for each, and the days each was done.
/// Tile picks and lengths are this device's (`RoutinePrefs`); done days come from history. A member's own routines
/// (#732) are custom workouts with a `RoutineLook`, keyed by their session id; built-ins by their raw value.
extension AppModel {
    /// The member's own routines, oldest first.
    var myRoutines: [CustomWorkout] { customWorkouts.filter { $0.routine != nil } }

    /// Every routine on offer: the built-ins, then the member's own.
    var dailyRoutines: [DailyRoutine] { Routine.allCases.map(DailyRoutine.init) + myRoutines.map(DailyRoutine.init) }

    func dailyRoutine(_ key: String) -> DailyRoutine? {
        if let r = Routine(rawValue: key) { return DailyRoutine(r) }
        return customWorkout(sessionId: key).flatMap { $0.routine == nil ? nil : DailyRoutine($0) }
    }

    /// Routines on Train's Daily row, resolved (an own routine deleted since drops out).
    func dailyTiles(_ raw: String) -> [DailyRoutine] {
        RoutinePrefs.tiles(raw, used: usedRoutines, known: { dailyRoutine($0) != nil }).compactMap(dailyRoutine)
    }

    /// Days (start of day) with a finished routine `key`, any length.
    func routineDays(_ key: String) -> Set<Date> { allRoutineDays[key] ?? [] }

    /// Done days of every routine from one pass over history, kept until the state changes (#720: read per tile).
    private var allRoutineDays: [String: Set<Date>] {
        let version = observedStateVersion
        if let c = derived.routineDays, c.key == version { return c.value }
        let cal = planCalendar
        let mine = Set(myRoutines.map(\.sessionId))
        var out: [String: Set<Date>] = [:]
        for h in state.history {
            if let k = Self.routineKey(h.sessionId, mine: mine) { out[k, default: []].insert(cal.startOfDay(for: h.startedAt)) }
        }
        derived.routineDays = (version, out)
        return out
    }

    private static func routineKey(_ sessionId: String, mine: Set<String>) -> String? {
        Routine.of(sessionId: sessionId)?.rawValue ?? (mine.contains(sessionId) ? sessionId : nil)
    }

    /// Routines the member has finished at least once, most recent first (#696: they keep their Daily row).
    var usedRoutines: [String] {
        let version = observedStateVersion
        if let c = derived.usedRoutines, c.key == version { return c.value }
        let mine = Set(myRoutines.map(\.sessionId))
        var seen: [String] = []
        for h in history {
            if let k = Self.routineKey(h.sessionId, mine: mine), !seen.contains(k) { seen.append(k) }
        }
        derived.usedRoutines = (version, seen)
        return seen
    }

    func routineDoneToday(_ key: String, now: Date = Date()) -> Bool {
        routineDays(key).contains(planCalendar.startOfDay(for: now))
    }

    func routineStreak(_ key: String, now: Date = Date()) -> Int {
        Routine.streak(routineDays(key), today: now, calendar: planCalendar)
    }

    /// Today is one of the member's climbing days: daily hangs stay easy or wait for tomorrow.
    var climbingToday: Bool { profile?.climbingDays.contains(todayWeekday) ?? false }

    var isClimber: Bool { profile.map(Generator.isClimber) ?? false }

    /// Coach pick of the day (#732 C), from today's planned session (none = rest day) and climbing days.
    var coachRoutinePick: (routine: Routine, why: String) {
        let today = plan?.sessions.first { $0.weekday == todayWeekday }
        return Routine.coachPick(focus: today?.focus, climbing: climbingToday)
    }
}

/// A built-in routine or one of the member's own (#732), as Train and Explore show it.
struct DailyRoutine: Identifiable, Hashable {
    /// Built-in raw value, or the own routine's session id.
    let key: String
    let label: String
    let short: String
    let tag: String
    let symbol: String
    /// Offered lengths in minutes; an own routine has one (its moves as built).
    let lengths: [Int]
    let defaultLength: Int
    let builtIn: Routine?
    let mine: CustomWorkout?

    var id: String { key }

    init(_ r: Routine) {
        key = r.rawValue; label = r.label; short = r.short; tag = r.tag; symbol = r.symbol
        lengths = r.lengths; defaultLength = r.defaultLength; builtIn = r; mine = nil
    }

    init(_ w: CustomWorkout) {
        let n = w.playableItems.count
        let est = max(1, w.session.estMin)
        key = w.sessionId; label = w.name; short = w.name; tag = "Mine · \(n) move\(n == 1 ? "" : "s")"
        symbol = w.routine?.symbol ?? RoutineLook.symbols[0]
        lengths = [est]; defaultLength = est; builtIn = nil; mine = w
    }

    /// Session to open at `minutes` (an own routine has one).
    func sessionId(minutes: Int) -> String { builtIn?.template(minutes: minutes).sessionId ?? key }

    /// Up to three lengths for a half-width tile, around the picked one.
    func tileLengths(_ picked: Int) -> [Int] {
        guard lengths.count > 3, let i = lengths.firstIndex(of: picked) else { return Array(lengths.prefix(3)) }
        let start = min(max(i - 1, 0), lengths.count - 3)
        return Array(lengths[start..<(start + 3)])
    }
}

/// Stored strings behind `@AppStorage` (views re-render when they change). Entries are `DailyRoutine.key`s.
enum RoutinePrefs {
    /// Comma-separated routines on Train; empty = not picked yet (routines already done, else none), "off" = row hidden.
    static let tilesKey = "dailyRoutines"
    /// "dismissed" once the member closes the Add daily routines card under the day card (#732).
    static let offerKey = "dailyRoutineOffer"
    /// Coach pick closes (#732 C): "<day number>:<closes>"; closed today or three times = not shown.
    static let coachKey = "dailyRoutineCoach"
    /// "stretch:10,hangs:15".
    static let lengthsKey = "dailyRoutineLengths"
    /// Where each routine happens (#700, design C): "hangs:home,stretch:gym"; missing = the routine's default.
    static let placesKey = "dailyRoutinePlaces"

    /// Days since 1970 in `calendar`'s time zone, so "today" turns over at local midnight.
    static func dayNumber(_ date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return Int((utc.date(from: c)?.timeIntervalSince1970 ?? 0) / 86_400)
    }

    static let coachCloseLimit = 3

    /// Coach pick shows unless closed today or closed `coachCloseLimit` times.
    static func coachOffers(_ raw: String, today: Int) -> Bool {
        let kv = raw.split(separator: ":").compactMap { Int($0) }
        guard kv.count == 2 else { return true }
        return kv[0] != today && kv[1] < coachCloseLimit
    }

    static func closingCoach(_ raw: String, today: Int) -> String {
        let kv = raw.split(separator: ":").compactMap { Int($0) }
        return "\(today):\((kv.count == 2 ? kv[1] : 0) + 1)"
    }

    /// Default check for stored keys: a built-in or an own routine's session id (views resolve and drop deleted ones).
    static func isKey(_ key: String) -> Bool { Routine(rawValue: key) != nil || key.hasPrefix(CustomWorkout.sessionPrefix) }

    static func place(_ raw: String, _ key: String) -> RoutinePlace {
        for part in raw.split(separator: ",") {
            let kv = part.split(separator: ":")
            if kv.count == 2, kv[0] == key, let p = RoutinePlace(rawValue: String(kv[1])) { return p }
        }
        return key == Routine.hangs.rawValue ? .home : .anywhere
    }

    static func setting(_ raw: String, _ key: String, place: RoutinePlace) -> String {
        var parts = raw.split(separator: ",").map(String.init).filter { !$0.hasPrefix(key + ":") }
        parts.append("\(key):\(place.rawValue)")
        return parts.joined(separator: ",")
    }

    /// Daily is the member's choice (#696): nothing until picked, except routines they already did.
    static func tiles(_ raw: String, used: [String] = [], known: (String) -> Bool = RoutinePrefs.isKey) -> [String] {
        if raw == "off" { return [] }
        let picked = raw.split(separator: ",").map(String.init).filter(known)
        return Array((picked.isEmpty ? used.filter(known) : picked).prefix(2))
    }

    /// Exactly `keys` on Train (up to two); none = row hidden.
    static func choosing(_ keys: [String]) -> String {
        keys.isEmpty ? "off" : keys.prefix(2).joined(separator: ",")
    }

    static func length(_ raw: String, _ d: DailyRoutine) -> Int {
        for part in raw.split(separator: ",") {
            let kv = part.split(separator: ":")
            if kv.count == 2, kv[0] == d.key, let m = Int(kv[1]), d.lengths.contains(m) { return m }
        }
        return d.defaultLength
    }

    static func setting(_ raw: String, _ key: String, to minutes: Int) -> String {
        var parts = raw.split(separator: ",").map(String.init).filter { !$0.hasPrefix(key + ":") }
        parts.append("\(key):\(minutes)")
        return parts.joined(separator: ",")
    }

    /// Takes `key` off Train (#703); the last one off hides the row (Explore pins one back).
    static func removing(_ raw: String, _ key: String, used: [String] = [], known: (String) -> Bool = RoutinePrefs.isKey) -> String {
        choosing(tiles(raw, used: used, known: known).filter { $0 != key })
    }

    /// Puts `key` on Train in place of `replacing` (or first, pushing the second off).
    static func pinning(_ raw: String, _ key: String, replacing: String? = nil, used: [String] = [],
                        known: (String) -> Bool = RoutinePrefs.isKey) -> String {
        var t = tiles(raw == "off" ? "" : raw, used: used, known: known)
        if t.contains(key) { return t.joined(separator: ",") }
        if let replacing, let i = t.firstIndex(of: replacing) { t[i] = key } else { t.insert(key, at: 0) }
        return t.prefix(2).joined(separator: ",")
    }
}

/// Where a daily routine happens (#700): at home, at the day's gym, or anywhere (no kit needed).
enum RoutinePlace: String, CaseIterable, Identifiable {
    case home, gym, anywhere

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: "Home"
        case .gym: "Gym"
        case .anywhere: "Anywhere"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .gym: "dumbbell.fill"
        case .anywhere: "location.circle"
        }
    }
}
