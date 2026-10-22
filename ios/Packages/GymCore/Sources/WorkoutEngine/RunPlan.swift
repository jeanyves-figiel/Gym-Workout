import Foundation

// MARK: - Run & cardio programmes (#618, designs A + B + C from `apple-tech-radar/x1.png`)

/// Race distances a run programme trains for.
public enum RunDistance: String, Codable, CaseIterable, Identifiable, Sendable {
    case k5, k10, half

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .k5: "5K"
        case .k10: "10K"
        case .half: "Half marathon"
        }
    }
    public var short: String { self == .half ? "Half" : label }
    public var km: Double {
        switch self {
        case .k5: 5
        case .k10: 10
        case .half: 21.0975
        }
    }
    /// Goal time when none is set: a steady first race.
    public var defaultTarget: Int {
        switch self {
        case .k5: 28 * 60
        case .k10: 58 * 60
        case .half: 2 * 3600 + 5 * 60
        }
    }
    /// Programme length when the race is far enough away.
    public var weeks: Int {
        switch self {
        case .k5: 8
        case .k10: 10
        case .half: 12
        }
    }
}

/// The member's run goal (#618): a race on a date with a goal time (design A), or Hybrid, fitter and stronger
/// with no race (design C). Kept in the profile, so every device plans the same runs.
public struct RunGoal: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Sendable { case race, hybrid }

    public var mode: Mode
    public var distance: RunDistance
    /// Race day, "2027-03-15"; nil in Hybrid mode.
    public var raceDate: String?
    /// Goal time, seconds; nil = the distance's default.
    public var targetSeconds: Int?
    public var raceName: String?
    /// Runs (or cardio sessions) a week next to lifting, 2…4.
    public var perWeek: Int

    public init(mode: Mode = .race, distance: RunDistance = .k10, raceDate: String? = nil, targetSeconds: Int? = nil,
                raceName: String? = nil, perWeek: Int = 3) {
        self.mode = mode
        self.distance = distance
        self.raceDate = raceDate
        self.targetSeconds = targetSeconds
        self.raceName = raceName
        self.perWeek = perWeek
    }

    public var target: Int { targetSeconds ?? distance.defaultTarget }
    /// Race pace, seconds per km.
    public var racePace: Int { Int((Double(target) / distance.km).rounded()) }

    public func race(_ cal: Calendar) -> Date? {
        guard mode == .race, let raceDate else { return nil }
        let p = raceDate.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// Whole days to race day (0 on the day); nil in Hybrid mode.
    public func daysLeft(now: Date, _ cal: Calendar) -> Int? {
        race(cal).flatMap { cal.dateComponents([.day], from: cal.startOfDay(for: now), to: $0).day }
    }
}

public enum RunKind: String, Codable, Sendable {
    case easy, intervals, tempo, long, race, strides, bike, row

    public var hard: Bool { self == .intervals || self == .tempo || self == .race }
}

/// One step of a run workout: what the Watch run player shows as a big block (design B) and Apple's Workout app gets
/// as a step (#610).
public struct RunStep: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case warmup, work, recover, cooldown, steady }

    public var kind: Kind
    public var meters: Int?
    public var seconds: Int?
    /// Target pace, seconds per km.
    public var pace: Int?
    /// Target heart-rate zone 1…5.
    public var zone: Int?
    /// Rep number and count, for "REP 3 OF 6".
    public var rep: Int?
    public var of: Int?

    public init(_ kind: Kind, meters: Int? = nil, seconds: Int? = nil, pace: Int? = nil, zone: Int? = nil, rep: Int? = nil, of: Int? = nil) {
        self.kind = kind
        self.meters = meters
        self.seconds = seconds
        self.pace = pace
        self.zone = zone
        self.rep = rep
        self.of = of
    }

    /// Rough length, seconds (distance steps at their pace, else 6:00/km).
    public var estSeconds: Int {
        if let seconds { return seconds }
        guard let meters else { return 0 }
        return Int(Double(meters) / 1000 * Double(pace ?? 360))
    }
}

/// A planned run or cardio session.
public struct RunWorkout: Codable, Hashable, Sendable, Identifiable {
    /// "run-2026-10-24".
    public var id: String
    public var kind: RunKind
    public var title: String
    /// "6 × 400 m @ 4:30/km".
    public var detail: String
    public var steps: [RunStep]
    /// Whole-session heart-rate zone (Zone 2 days); nil for intervals.
    public var zone: Int?
    /// Run, road bike or rowing.
    public var sport: Sport

    public var minutes: Int { max(1, Int((Double(steps.map(\.estSeconds).reduce(0, +)) / 60).rounded())) }
    /// Rep count for interval sessions.
    public var reps: Int { steps.filter { $0.kind == .work }.count }
}

public struct RunDay: Hashable, Sendable, Identifiable {
    /// 1 = Monday … 7 = Sunday.
    public var weekday: Int
    public var workout: RunWorkout

    public var id: String { workout.id }
}

public enum RunPhase: String, Sendable {
    case base, build, peak, taper, race

    public var label: String {
        switch self {
        case .base: "Base"
        case .build: "Build"
        case .peak: "Peak"
        case .taper: "Taper"
        case .race: "Race week"
        }
    }
}

public enum RunPlanner {
    /// Phase of the week starting `weekStart`; nil after race day (the goal is done) or in Hybrid mode.
    public static func phase(_ goal: RunGoal, weekStart: Date, _ cal: Calendar) -> RunPhase? {
        guard let race = goal.race(cal) else { return nil }
        guard let left = cal.dateComponents([.weekOfYear], from: weekStart, to: Progression.weekStart(race, cal)).weekOfYear,
              left >= 0 else { return nil }
        switch left {
        case 0: return .race
        case 1: return .taper
        case 2...3: return .peak
        case 4...7: return .build
        default: return .base
        }
    }

    /// Paces in seconds per km: easy, long, tempo, interval.
    public static func paces(_ goal: RunGoal) -> (easy: Int, long: Int, tempo: Int, interval: Int) {
        let rp = Double(goal.racePace)
        let tempo = goal.distance == .k5 ? 1.10 : goal.distance == .k10 ? 1.06 : 1.0
        let interval = goal.distance == .k5 ? 0.97 : goal.distance == .k10 ? 0.95 : 0.92
        return (Int((rp * 1.22).rounded()), Int((rp * 1.27).rounded()), Int((rp * tempo).rounded()), Int((rp * interval).rounded()))
    }

    /// The week's runs placed around lifting (design A): long run on Saturday, never on or the day after a legs day;
    /// hard runs not the day after legs; gym-free days first. Hybrid adds two Zone 2 sessions and one interval day.
    public static func week(_ goal: RunGoal, weekStart: Date, lifting: [(weekday: Int, focus: Focus)], _ cal: Calendar) -> [RunDay] {
        let workouts: [RunWorkout]
        var fixed: [Int: RunWorkout] = [:]
        if goal.mode == .hybrid {
            workouts = hybrid(goal)
        } else {
            guard let phase = phase(goal, weekStart: weekStart, cal), let race = goal.race(cal) else { return [] }
            let weeksLeft = cal.dateComponents([.weekOfYear], from: weekStart, to: Progression.weekStart(race, cal)).weekOfYear ?? 0
            let progress = 1 - min(1, Double(max(weeksLeft - 1, 0)) / Double(goal.distance.weeks))
            var list = runs(goal, phase: phase, progress: progress)
            if phase == .race {
                let wd = WeekSchedule.fromCalendar(cal.component(.weekday, from: race))
                fixed[wd] = raceDay(goal)
                list = Array(list.prefix(max(1, goal.perWeek - 1)))
            }
            workouts = list
        }
        let legs = Set(lifting.filter { legHeavy($0.focus) }.map(\.weekday))
        let gym = Set(lifting.map(\.weekday))
        var used = Set(fixed.keys)
        var hardDays = Set(fixed.keys)
        var days: [RunDay] = fixed.map { RunDay(weekday: $0.key, workout: $0.value) }
        for w in workouts {
            let preferred = w.kind == .long ? 6 : w.kind.hard ? 2 : 4
            let pick = (1...7).filter { !used.contains($0) }.min { score($0, w, legs, gym, hardDays, preferred) < score($1, w, legs, gym, hardDays, preferred) }
            guard let d = pick else { break }
            used.insert(d)
            if w.kind.hard || w.kind == .long { hardDays.insert(d) }
            days.append(RunDay(weekday: d, workout: w))
        }
        return days.sorted { $0.weekday < $1.weekday }.map { day in
            var d = day
            let date = cal.date(byAdding: .day, value: day.weekday - 1, to: weekStart) ?? weekStart
            d.workout.id = "run-" + dayKey(date, cal)
            return d
        }
    }

    /// Legs, lower, full lower, posterior and power days load the legs.
    public static func legHeavy(_ f: Focus) -> Bool {
        [.legs, .lower, .fullLower, .posterior, .fullPower].contains(f)
    }

    private static func score(_ d: Int, _ w: RunWorkout, _ legs: Set<Int>, _ gym: Set<Int>, _ hard: Set<Int>, _ preferred: Int) -> Double {
        var s = Double(abs(d - preferred)) * 0.3
        if gym.contains(d) { s += 2 }
        if legs.contains(d) { s += 6 }
        let afterLegs = legs.contains(d == 1 ? 7 : d - 1)
        if afterLegs && (w.kind == .long || w.kind.hard) { s += 10 }
        if hard.contains(d - 1) || hard.contains(d + 1) { s += w.kind.hard || w.kind == .long ? 3 : 0.5 }
        return s
    }

    private static func runs(_ goal: RunGoal, phase: RunPhase, progress: Double) -> [RunWorkout] {
        let p = paces(goal)
        let (longLow, longHigh): (Double, Double) = switch goal.distance {
        case .k5: (35, 55)
        case .k10: (45, 80)
        case .half: (60, 115)
        }
        var longMin = Int(longLow + (longHigh - longLow) * progress)
        if phase == .taper || phase == .race { longMin = Int(Double(longMin) * 0.6) }
        let long = steady(.long, "Long run", minutes: longMin, pace: p.long)
        let easy = steady(.easy, "Easy run", minutes: phase == .base ? 30 : 35, pace: p.easy)
        let short = steady(.easy, "Easy run", minutes: 25, pace: p.easy)
        let order: [RunWorkout] = switch phase {
        case .base: [long, easy, strides(p.easy), short]
        case .build: [intervals(goal, reps: 0, pace: p.interval, easy: p.easy), long, easy, tempo(goal, pace: p.tempo, easy: p.easy)]
        case .peak: [intervals(goal, reps: 2, pace: p.interval, easy: p.easy), tempo(goal, pace: p.tempo, easy: p.easy), long, easy]
        case .taper: [intervals(goal, reps: -2, pace: p.interval, easy: p.easy), short, long, short]
        case .race: [strides(p.easy), short, short]
        }
        return Array(order.prefix(min(max(goal.perWeek, 2), 4)))
    }

    private static func hybrid(_ goal: RunGoal) -> [RunWorkout] {
        var bike = steady(.bike, "Zone 2 ride", minutes: 40, pace: nil)
        bike.sport = .roadBike
        bike.detail = "40′ bike or run, Zone 2"
        var row = steady(.row, "Zone 2 row", minutes: 30, pace: nil)
        row.sport = .rowing
        row.detail = "30′ row, Zone 2"
        var steps = [RunStep(.warmup, seconds: 600, zone: 2)]
        for i in 1...8 {
            steps.append(RunStep(.work, seconds: 60, zone: 4, rep: i, of: 8))
            steps.append(RunStep(.recover, seconds: 60, zone: 2))
        }
        steps.append(RunStep(.cooldown, seconds: 300, zone: 1))
        let hard = RunWorkout(id: "", kind: .intervals, title: "Intervals", detail: "8 × 1′ hard, 1′ easy", steps: steps, zone: nil, sport: .run)
        return Array([bike, hard, row, steady(.easy, "Easy run", minutes: 30, pace: nil)].prefix(min(max(goal.perWeek, 2), 4)))
    }

    private static func steady(_ kind: RunKind, _ title: String, minutes: Int, pace: Int?) -> RunWorkout {
        RunWorkout(id: "", kind: kind, title: title, detail: "\(minutes)′ Zone 2" + (pace.map { " · ~\(clock($0))/km" } ?? ""),
                   steps: [RunStep(.steady, seconds: minutes * 60, pace: pace, zone: 2)], zone: 2, sport: .run)
    }

    private static func strides(_ easy: Int) -> RunWorkout {
        var steps = [RunStep(.steady, seconds: 20 * 60, pace: easy, zone: 2)]
        for i in 1...6 {
            steps.append(RunStep(.work, seconds: 20, zone: 4, rep: i, of: 6))
            steps.append(RunStep(.recover, seconds: 60, zone: 2))
        }
        return RunWorkout(id: "", kind: .strides, title: "Easy + strides", detail: "20′ easy · 6 × 20″ quick", steps: steps, zone: nil, sport: .run)
    }

    private static func intervals(_ goal: RunGoal, reps extra: Int, pace: Int, easy: Int) -> RunWorkout {
        let (meters, reps, rest): (Int, Int, Int) = switch goal.distance {
        case .k5: (400, 6, 90)
        case .k10: (800, 5, 120)
        case .half: (1000, 5, 120)
        }
        let n = max(3, reps + extra)
        var steps = [RunStep(.warmup, seconds: 600, pace: easy, zone: 2)]
        for i in 1...n {
            steps.append(RunStep(.work, meters: meters, pace: pace, zone: 4, rep: i, of: n))
            if i < n { steps.append(RunStep(.recover, seconds: rest, zone: 2)) }
        }
        steps.append(RunStep(.cooldown, seconds: 300, pace: easy, zone: 1))
        return RunWorkout(id: "", kind: .intervals, title: "Intervals", detail: "\(n) × \(meters) m @ \(clock(pace))/km", steps: steps, zone: nil, sport: .run)
    }

    private static func tempo(_ goal: RunGoal, pace: Int, easy: Int) -> RunWorkout {
        let mins = goal.distance == .k5 ? 15 : goal.distance == .k10 ? 20 : 25
        let steps = [RunStep(.warmup, seconds: 600, pace: easy, zone: 2), RunStep(.work, seconds: mins * 60, pace: pace, zone: 3, rep: 1, of: 1),
                     RunStep(.cooldown, seconds: 300, pace: easy, zone: 1)]
        return RunWorkout(id: "", kind: .tempo, title: "Tempo", detail: "\(mins)′ @ \(clock(pace))/km", steps: steps, zone: nil, sport: .run)
    }

    private static func raceDay(_ goal: RunGoal) -> RunWorkout {
        let m = Int(goal.distance.km * 1000)
        return RunWorkout(id: "", kind: .race, title: goal.raceName ?? "\(goal.distance.label) race",
                          detail: "Goal \(clock(goal.target)) · \(clock(goal.racePace))/km",
                          steps: [RunStep(.work, meters: m, pace: goal.racePace, rep: 1, of: 1)], zone: nil, sport: .run)
    }

    /// "4:30", "1:05:00".
    public static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    public static func dayKey(_ d: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
