import Foundation
import WorkoutEngine

/// Heart-rate zones (#609) and run & cardio programmes (#618): the member's zones, this week's runs placed around
/// lifting, and which of them a Health workout already covers.
extension AppModel {
    /// Apple's zones when Health has five (iOS 27), else from age and resting heart rate.
    var heartZones: HeartZones {
        if let starts = health?.snapshot.zoneStarts {
            let z = HeartZones(starts: starts)
            if z.isValid { return z }
        }
        return .standard(age: profile?.age, restingHR: health?.snapshot.restingHR)
    }

    var runGoal: RunGoal? { profile?.runGoal }

    func saveRunGoal(_ goal: RunGoal?) {
        guard var prof = profile, prof.runGoal != goal else { return }
        prof.runGoal = goal
        updateProfile(prof)
    }

    /// This week's runs, placed around this week's lifting days.
    var runWeek: [RunDay] {
        guard let goal = runGoal else { return [] }
        let cal = planCalendar
        let lifting = (plan?.sessions ?? []).compactMap { s in s.weekday.map { (weekday: $0, focus: s.focus) } }
        // Hybrid sessions grow through the block (#685), like the plan's own weeks.
        return RunPlanner.week(goal, weekStart: Progression.weekStart(Date(), cal), lifting: lifting, cal, step: plan.map(RunPlanner.step) ?? 0)
    }

    var todayRun: RunDay? { runWeek.first { $0.weekday == todayWeekday } }

    /// Done: a run, ride or row of at least half the planned time on that day, logged here or from any app via Health
    /// (Apple's Workout app included, #610).
    func runDone(_ day: RunDay) -> Bool {
        let cal = planCalendar
        guard let date = cal.date(byAdding: .day, value: day.weekday - 1, to: Progression.weekStart(Date(), cal)) else { return false }
        let family: Set<Sport> = switch day.workout.sport {
        case .roadBike, .mountainBike: [.roadBike, .mountainBike]
        case .rowing: [.rowing]
        default: [.run, .trailRun, .roadBike, .rowing]
        }
        let entries = Sports.merged(local: sportLogs, health: health?.snapshot.recentSports ?? [])
        return entries.contains { e in
            family.contains(e.sport) && cal.isDate(e.start, inSameDayAs: date)
                && e.end.timeIntervalSince(e.start) >= Double(day.workout.minutes) * 30
        }
    }

    /// Flattened for the Watch run player.
    static func watchRun(_ w: RunWorkout) -> WRun {
        WRun(id: w.id, title: w.title, detail: w.detail, sport: w.sport.rawValue, zone: w.zone,
             steps: w.steps.map { WRunStep(kind: $0.kind.rawValue, meters: $0.meters, seconds: $0.seconds, pace: $0.pace, zone: $0.zone,
                                           rep: $0.rep, of: $0.of) })
    }
}

/// Zone buzz on the Watch (#609), on by default.
enum ZonePrefs {
    private static let buzzKey = "zones.buzz"
    static var buzz: Bool {
        get { UserDefaults.standard.object(forKey: buzzKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: buzzKey) }
    }
}

/// Where a run or cardio session starts (#610, design C): MonkeyFit's player on the Watch or Apple's Workout app,
/// remembered per sport once "Remember" is ticked.
enum RunStartChoice: String {
    case monkey, apple

    private static func key(_ sport: Sport) -> String { "runStart.\(sport.rawValue)" }

    static func remembered(_ sport: Sport) -> RunStartChoice? {
        UserDefaults.standard.string(forKey: key(sport)).flatMap(RunStartChoice.init(rawValue:))
    }

    static func remember(_ choice: RunStartChoice?, for sport: Sport) {
        UserDefaults.standard.set(choice?.rawValue, forKey: key(sport))
    }
}
