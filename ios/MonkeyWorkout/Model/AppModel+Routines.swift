import Foundation
import WorkoutEngine

/// Daily routines (#689): which routines sit on Train, the length picked for each, and the days each was done.
/// Tile picks and lengths are this device's (`RoutinePrefs`); done days come from history.
extension AppModel {
    /// Days (start of day) with a finished `routine`, any length.
    func routineDays(_ routine: Routine) -> Set<Date> { allRoutineDays[routine] ?? [] }

    /// Done days of every routine from one pass over history, kept until the state changes (#720: read per tile).
    private var allRoutineDays: [Routine: Set<Date>] {
        let version = observedStateVersion
        if let c = derived.routineDays, c.key == version { return c.value }
        let cal = planCalendar
        var out: [Routine: Set<Date>] = [:]
        for h in state.history {
            if let r = Routine.of(sessionId: h.sessionId) { out[r, default: []].insert(cal.startOfDay(for: h.startedAt)) }
        }
        derived.routineDays = (version, out)
        return out
    }

    /// Routines the member has finished at least once, most recent first (#696: they keep their Daily row).
    var usedRoutines: [Routine] {
        let version = observedStateVersion
        if let c = derived.usedRoutines, c.key == version { return c.value }
        var seen: [Routine] = []
        for h in history {
            if let r = Routine.of(sessionId: h.sessionId), !seen.contains(r) { seen.append(r) }
        }
        derived.usedRoutines = (version, seen)
        return seen
    }

    func routineDoneToday(_ routine: Routine, now: Date = Date()) -> Bool {
        routineDays(routine).contains(planCalendar.startOfDay(for: now))
    }

    func routineStreak(_ routine: Routine, now: Date = Date()) -> Int {
        routine.streak(routineDays(routine), today: now, calendar: planCalendar)
    }

    /// Today is one of the member's climbing days: daily hangs stay easy or wait for tomorrow.
    var climbingToday: Bool { profile?.climbingDays.contains(todayWeekday) ?? false }

    var isClimber: Bool { profile.map(Generator.isClimber) ?? false }
}

/// Stored strings behind `@AppStorage` (views re-render when they change).
enum RoutinePrefs {
    /// Comma-separated routines on Train; empty = not picked yet (routines already done, else none), "off" = row hidden.
    static let tilesKey = "dailyRoutines"
    /// "dismissed" once the member closes the Add a daily routine suggestion.
    static let suggestionKey = "dailyRoutineSuggestion"
    /// "stretch:10,hangs:15".
    static let lengthsKey = "dailyRoutineLengths"
    /// Where each routine happens (#700, design C): "hangs:home,stretch:gym"; missing = the routine's default.
    static let placesKey = "dailyRoutinePlaces"

    static func place(_ raw: String, _ r: Routine) -> RoutinePlace {
        for part in raw.split(separator: ",") {
            let kv = part.split(separator: ":")
            if kv.count == 2, kv[0] == r.rawValue, let p = RoutinePlace(rawValue: String(kv[1])) { return p }
        }
        return r == .hangs ? .home : .anywhere
    }

    static func setting(_ raw: String, _ r: Routine, place: RoutinePlace) -> String {
        var parts = raw.split(separator: ",").map(String.init).filter { !$0.hasPrefix(r.rawValue + ":") }
        parts.append("\(r.rawValue):\(place.rawValue)")
        return parts.joined(separator: ",")
    }

    /// Daily is the member's choice (#696): nothing until picked, except routines they already did.
    static func tiles(_ raw: String, used: [Routine] = []) -> [Routine] {
        if raw == "off" { return [] }
        let picked = raw.split(separator: ",").compactMap { Routine(rawValue: String($0)) }
        return Array((picked.isEmpty ? used : picked).prefix(2))
    }

    /// Show the Add a daily routine suggestion: nothing on Train and not dismissed or hidden.
    static func suggests(_ raw: String, dismissed: String, used: [Routine] = []) -> Bool {
        raw != "off" && dismissed != "dismissed" && tiles(raw, used: used).isEmpty
    }

    /// Exactly `routines` on Train (up to two); none = row hidden.
    static func choosing(_ routines: [Routine]) -> String {
        routines.isEmpty ? "off" : routines.prefix(2).map(\.rawValue).joined(separator: ",")
    }

    static func length(_ raw: String, _ r: Routine) -> Int {
        for part in raw.split(separator: ",") {
            let kv = part.split(separator: ":")
            if kv.count == 2, kv[0] == r.rawValue, let m = Int(kv[1]), r.lengths.contains(m) { return m }
        }
        return r.defaultLength
    }

    static func setting(_ raw: String, _ r: Routine, to minutes: Int) -> String {
        var parts = raw.split(separator: ",").map(String.init).filter { !$0.hasPrefix(r.rawValue + ":") }
        parts.append("\(r.rawValue):\(minutes)")
        return parts.joined(separator: ",")
    }

    /// Takes `r` off Train (#703); the last one off hides the row (Explore pins one back).
    static func removing(_ raw: String, _ r: Routine, used: [Routine] = []) -> String {
        choosing(tiles(raw, used: used).filter { $0 != r })
    }

    /// Puts `r` on Train in place of `replacing` (or first, pushing the second off).
    static func pinning(_ raw: String, _ r: Routine, replacing: Routine? = nil, used: [Routine] = []) -> String {
        var t = tiles(raw == "off" ? "" : raw, used: used)
        if t.contains(r) { return t.map(\.rawValue).joined(separator: ",") }
        if let replacing, let i = t.firstIndex(of: replacing) { t[i] = r } else { t.insert(r, at: 0) }
        return t.prefix(2).map(\.rawValue).joined(separator: ",")
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
