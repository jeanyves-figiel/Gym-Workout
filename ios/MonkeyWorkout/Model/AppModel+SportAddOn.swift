import Foundation
import WorkoutEngine

/// Sport season blocks (#620): the add-on (C) and the Coach's suggestion of it (B).
extension AppModel {
    var sportAddOn: SportAddOnPref? { state.synced?.sportAddOn }

    /// Sets or removes the add-on; the plan picks it up at once.
    func setSportAddOn(_ pref: SportAddOnPref?) {
        guard var sp = state.synced, sp.sportAddOn != pref else { return }
        sp.sportAddOn = pref
        state.synced = sp
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    /// A season sport logged 3+ times in 14 days (sports and climbs) while no add-on runs.
    var sportAddOnSuggestion: (sport: SeasonSport, count: Int)? {
        guard sportAddOn == nil else { return nil }
        let logs = (state.sportLogs ?? []).map { (sport: $0.sport, start: $0.start) }
            + (state.climbs ?? []).map { (sport: Sport.climbing, start: $0.start) }
        return SportAddOn.suggestion(logs, now: Date())
    }
}
