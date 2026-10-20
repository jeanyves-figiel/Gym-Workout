import Foundation
import WorkoutEngine

/// What the plan is made from besides `state`: Apple Health (readiness easing, auto-tune), the day (today's
/// session, the Lift Focus week, the programme week) and the demo's "today".
struct DerivedKey: Equatable {
    var state: Int
    var health: Int
    var day: Date
    var demoToday: Int?
}

/// Derived values of `AppModel` that views read many times per render, kept until what they are made from changes.
/// Each value is the same as computing it again; only the work is saved.
struct DerivedCache {
    var plan: (key: DerivedKey, value: WeekPlan?)?
    /// Calendar weeks per `count`, for the day of the `now` they were made for.
    var weeks: [Int: (key: DerivedKey, day: Date, value: [PlanCalendar.Week])] = [:]
    var game: (key: Int, moveXP: Int, value: GameProgress)?
    var badges: (key: Int, value: [Badge])?
    var setLogs: (key: Int, value: [SetLog])?
    var history: (key: Int, value: [WorkoutRecord])?
}

extension AppModel {
    /// `stateVersion`, read through `state` so a view that gets a cached value still observes the state.
    var observedStateVersion: Int {
        _ = state.profileDirty
        return stateVersion
    }

    /// Key of the plan cache. Reads `state`, the Health snapshot and the demo day, so a view that gets the cached plan
    /// still observes what it is made from.
    var derivedKey: DerivedKey {
        var healthVersion = -1
        if let health {
            _ = health.snapshot
            healthVersion = health.snapshotVersion
        }
        return DerivedKey(state: observedStateVersion, health: healthVersion, day: Calendar.current.startOfDay(for: Date()),
                          demoToday: demoToday)
    }
}
