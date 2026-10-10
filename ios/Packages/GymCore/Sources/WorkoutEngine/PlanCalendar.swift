import Foundation

// MARK: - Away periods (#68)

/// Why a period is marked: no training at all, or training somewhere else.
public enum AwayKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Can't train (any reason): sessions move to other free days of that week.
    case off
    /// Temporary location (business trip, holiday): sessions are rebuilt for the equipment there.
    case travel
    public var id: String { rawValue }
}

/// What a temporary location offers. Each preset maps to an equipment list; it can be fine-tuned per trip.
public enum TravelSetup: String, Codable, CaseIterable, Sendable, Identifiable {
    case hotelGym = "hotel-gym"
    case dumbbells
    case bodyweight
    case bands
    case fullGym = "full-gym"
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .hotelGym: "Hotel gym"
        case .dumbbells: "Dumbbells only"
        case .bodyweight: "Bodyweight only"
        case .bands: "Bands"
        case .fullGym: "Full gym nearby"
        }
    }

    public var blurb: String {
        switch self {
        case .hotelGym: "Dumbbells, bench, a cardio machine"
        case .dumbbells: "A pair of dumbbells and some floor"
        case .bodyweight: "Hotel room, park, beach"
        case .bands: "Travel bands + bodyweight"
        case .fullGym: "Day pass at a commercial gym"
        }
    }

    public var equipment: [Equipment] {
        switch self {
        case .hotelGym: [.dumbbells, .bench, .mat, .treadmill, .bike, .elliptical, .foamRoller]
        case .dumbbells: [.dumbbells, .mat]
        case .bodyweight: [.mat]
        case .bands: [.bands, .mat]
        case .fullGym: Equipment.allCases
        }
    }
}

/// A date or date range (inclusive) the user can't train, or trains somewhere else.
/// Dates are calendar days ("yyyy-MM-dd") so they mean the same day in any time zone.
public struct AwayPeriod: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: AwayKind
    public var start: String
    public var end: String
    /// Optional reason or place ("Dentist", "Berlin").
    public var note: String?
    /// Travel only; nil = hotel gym.
    public var setup: TravelSetup?
    /// Travel only: fine-tuned equipment; nil = the preset's list.
    public var equipment: [Equipment]?
    /// Travel only: gym found by search for a day pass.
    public var gym: GymRef?

    public init(
        id: UUID = UUID(), kind: AwayKind, start: String, end: String, note: String? = nil,
        setup: TravelSetup? = nil, equipment: [Equipment]? = nil, gym: GymRef? = nil
    ) {
        self.id = id
        self.kind = kind
        self.start = min(start, end)
        self.end = max(start, end)
        self.note = note
        self.setup = setup
        self.equipment = equipment
        self.gym = gym
    }

    public func covers(_ day: String) -> Bool { start <= day && day <= end }

    /// Equipment available on a trip.
    public var travelEquipment: [Equipment] { equipment ?? (setup ?? .hotelGym).equipment }

    /// "Hotel gym", "Berlin · Bodyweight only", "Dentist", "Can't train".
    public var title: String {
        let what = kind == .travel ? (gym?.name ?? (setup ?? .hotelGym).label) : "Can't train"
        guard let n = note?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return what }
        return "\(n) · \(what)"
    }
}

// MARK: - Calendar

/// Dated view of the plan for the coming weeks, adapted around away periods (#68).
///
/// Cycle weeks advance one per calendar week from the current one. A week touched by an away period is
/// re-planned: sessions move to free days (climbing and spacing rules as in `WeekSchedule`); with fewer free
/// days than sessions the smaller split is used (fewer, fuller sessions, weekly balance kept); sessions on
/// travel days are rebuilt for the equipment there. In the current week, done sessions stay put and only
/// days from today on are re-planned.
public enum PlanCalendar {
    /// Weeks shown by the calendar.
    public static let horizonWeeks = 6

    // MARK: Days

    public static func key(_ date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func date(_ key: String, _ cal: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Day keys of a week, Monday first (index 0 = weekday 1).
    public static func dayKeys(weekStart: Date, _ cal: Calendar) -> [String] {
        (0..<7).map { key(cal.date(byAdding: .day, value: $0, to: weekStart)!, cal) }
    }

    /// Cycle week (1…4) `offset` weeks after `current`.
    public static func cycleWeek(current: Int, offset: Int) -> Int {
        let n = Rules.mesocycleWeeks
        return ((current - 1 + offset) % n + n) % n + 1
    }

    /// Whether any away period overlaps the week starting at `weekStart`.
    public static func touches(_ away: [AwayPeriod], weekStart: Date, _ cal: Calendar) -> Bool {
        let keys = dayKeys(weekStart: weekStart, cal)
        return away.contains { $0.start <= keys[6] && $0.end >= keys[0] }
    }

    // MARK: Adapting a week

    public struct Week: Sendable, Identifiable {
        public var start: Date
        /// Day keys, Monday first.
        public var days: [String]
        public var plan: WeekPlan
        /// Weekdays (1 = Monday) marked "can't train".
        public var off: [Int: AwayPeriod]
        /// Weekdays spent at a temporary location.
        public var travel: [Int: AwayPeriod]
        /// Climbing weekdays still on (off / travel days removed).
        public var climbing: [Int]
        /// Sessions that no longer fit this week.
        public var dropped: Int
        /// Sessions placed on other days than the regular plan.
        public var adapted: Bool
        public var id: String { days[0] }

        public func date(_ weekday: Int, _ cal: Calendar) -> Date? { PlanCalendar.date(days[weekday - 1], cal) }
    }

    /// Plans one week around away periods.
    /// - Parameters:
    ///   - base: the week as already planned (current week); nil = generate it.
    ///   - done: ids of sessions already done; they keep their day.
    ///   - firstDay: first weekday that can still be planned (today's weekday for the current week).
    public static func adapt(
        _ profile: Profile, week: Int, seed: UInt32, weekStart: Date, away: [AwayPeriod],
        base: WeekPlan? = nil, done: Set<String> = [], firstDay: Int = 1, calendar cal: Calendar
    ) -> Week {
        let days = dayKeys(weekStart: weekStart, cal)
        var off: [Int: AwayPeriod] = [:]
        var travel: [Int: AwayPeriod] = [:]
        for wd in WeekSchedule.weekdays {
            if let a = away.first(where: { $0.kind == .off && $0.covers(days[wd - 1]) }) {
                off[wd] = a
            } else if let a = away.first(where: { $0.kind == .travel && $0.covers(days[wd - 1]) }) {
                travel[wd] = a
            }
        }
        // No climbing at home while away.
        let climbing = profile.climbingDays.filter { off[$0] == nil && travel[$0] == nil }
        var plan = base ?? Generator.generateWeek(profile, week: week, seed: seed)
        let untouched = off.isEmpty && travel.isEmpty && firstDay <= 1
        if untouched && plan.sessions.allSatisfy({ $0.weekday != nil }) {
            return Week(start: weekStart, days: days, plan: plan, off: off, travel: travel, climbing: climbing, dropped: 0, adapted: false)
        }

        let pinned = plan.sessions.filter { done.contains($0.id) }
        let taken = Set(pinned.compactMap(\.weekday))
        let free = WeekSchedule.weekdays.filter { $0 >= firstDay && off[$0] == nil && !taken.contains($0) }
        let regular = Dictionary(plan.sessions.map { ($0.id, $0.weekday) }, uniquingKeysWith: { a, _ in a })
        var used = profile
        var movable = plan.sessions.filter { !done.contains($0.id) }
        var resplit = false
        // Too few free days: switch to the smaller split so the week stays balanced.
        if pinned.isEmpty && movable.count > free.count && !free.isEmpty && max(2, free.count) < profile.sessionsPerWeek {
            used.sessionsPerWeek = max(2, free.count)
            plan = Generator.generateWeek(used, week: week, seed: seed)
            movable = plan.sessions
            resplit = true
        }
        var dropped = 0
        while movable.count > free.count {
            // Conditioning goes first, then the last session of the week.
            if let i = movable.lastIndex(where: { $0.focus == .conditioning }) { movable.remove(at: i) } else { movable.removeLast() }
            dropped += 1
        }

        let preferred = Set(profile.gymDays).intersection(free)
        let slots = place(movable.map(\.focus), on: free, climbing: Set(climbing),
                          gym: preferred.count >= movable.count ? preferred : [], prefs: profile.climbPrefs)
        var trips: [UUID: WeekPlan] = [:]
        var placed: [Session] = []
        var remaining = movable
        for slot in slots {
            guard let i = remaining.firstIndex(where: { $0.focus == slot.focus }) else { continue }
            var s = remaining.remove(at: i)
            if let trip = travel[slot.weekday] {
                if trips[trip.id] == nil {
                    var p = used
                    p.equipment = trip.travelEquipment
                    trips[trip.id] = Generator.generateWeek(p, week: week, seed: seed)
                }
                if let t = trips[trip.id]?.sessions.first(where: { $0.id == s.id && $0.focus == s.focus }) {
                    s.blocks = t.blocks
                    s.estMin = t.estMin
                    s.title = "\(t.title) · \(trip.gym?.name ?? (trip.setup ?? .hotelGym).label)"
                }
            }
            s.weekday = slot.weekday
            placed.append(s)
        }
        let moved = placed.contains { s in regular[s.id].flatMap { $0 }.map { $0 != s.weekday } ?? false }
        plan.sessions = (pinned + placed).sorted { ($0.weekday ?? 0, $0.index) < ($1.weekday ?? 0, $1.index) }
        return Week(start: weekStart, days: days, plan: plan, off: off, travel: travel, climbing: climbing,
                    dropped: dropped, adapted: resplit || moved || dropped > 0 || !travel.isEmpty)
    }

    /// Best placement of `foci` on `free` weekdays, scored like `WeekSchedule.assign`.
    static func place(_ foci: [Focus], on free: [Int], climbing: Set<Int>, gym: Set<Int>, prefs: ClimbPrefs) -> [WeekSchedule.Slot] {
        guard !foci.isEmpty, free.count >= foci.count else { return [] }
        let orders = WeekSchedule.distinctPermutations(foci)
        var best: [WeekSchedule.Slot] = []
        var bestScore = Double.infinity
        for days in WeekSchedule.combinations(free, foci.count) {
            for order in orders {
                let s = WeekSchedule.score(days: days, order: order, climbing: climbing, gym: gym, prefs: prefs)
                if s < bestScore - 1e-9 {
                    bestScore = s
                    best = zip(days, order).map { WeekSchedule.Slot(weekday: $0, focus: $1) }
                }
            }
        }
        return best
    }

    // MARK: Coming weeks

    /// The current week (from the app's plan, done state kept) followed by the coming weeks.
    public static func weeks(
        _ profile: Profile, seed: UInt32, currentWeek: Int, current: WeekPlan?, done: Set<String>,
        away: [AwayPeriod], now: Date = Date(), count: Int = horizonWeeks, calendar cal: Calendar
    ) -> [Week] {
        let thisMonday = Progression.weekStart(now, cal)
        let today = WeekSchedule.fromCalendar(cal.component(.weekday, from: now))
        return (0..<max(1, count)).map { offset in
            let start = cal.date(byAdding: .weekOfYear, value: offset, to: thisMonday)!
            if offset == 0 {
                // An untouched weekday plan is shown as is (missed sessions stay where they were).
                let touched = touches(away, weekStart: start, cal) || current?.sessions.contains { $0.weekday == nil } ?? true
                return adapt(profile, week: currentWeek, seed: seed, weekStart: start, away: away,
                             base: current, done: done, firstDay: touched ? today : 1, calendar: cal)
            }
            return adapt(profile, week: cycleWeek(current: currentWeek, offset: offset), seed: seed,
                         weekStart: start, away: away, calendar: cal)
        }
    }

    /// Planned (not done) sessions between two dates, inclusive, with their date.
    public static func planned(in weeks: [Week], from: Date, to: Date, done: Set<String>, calendar cal: Calendar) -> [(date: Date, session: Session)] {
        let lo = key(from, cal), hi = key(to, cal)
        var out: [(date: Date, session: Session)] = []
        for (i, w) in weeks.enumerated() {
            for s in w.plan.sessions {
                guard let wd = s.weekday, !(i == 0 && done.contains(s.id)) else { continue }
                let k = w.days[wd - 1]
                if k >= lo, k <= hi, let d = date(k, cal) { out.append((d, s)) }
            }
        }
        return out
    }
}
