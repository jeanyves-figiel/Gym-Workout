import Foundation
import WorkoutEngine

/// App level and modules (#1052, design A + B): picked at sign up, changed in Settings → My app. Synced with the
/// profile; nil = everything, so members from before see the app as it was.
extension AppModel {
    var appModules: AppModules { state.synced?.appModules ?? .everything }

    /// Whether a module is on.
    func shows(_ module: AppModule) -> Bool { appModules.shows(module) }

    func setAppLevel(_ level: AppLevel) {
        saveModules(AppModules(level: level))
    }

    func setModule(_ module: AppModule, on: Bool) {
        var m = appModules
        m.set(module, on: on)
        saveModules(m)
    }

    private func saveModules(_ m: AppModules) {
        guard state.synced != nil else { return }
        // A module just turned on shows its tab again on this device too (My tabs, #1004).
        let was = appModules
        for tab in MainTab.allCases {
            guard let module = tab.module, m.shows(module), !was.shows(module) else { continue }
            TabsPref.shared.set(tab, shown: true)
        }
        state.synced?.appModules = m == .everything ? nil : m
        state.profileDirty = true
        persist()
        Task { await sync() }
    }
}

/// Part of a plan (#1052 D): only some days, one workout at a time or own workouts, each workout full, lifts only or
/// quick. Applied last to the plan, so the generated week underneath stays as it is.
extension AppModel {
    var planFollow: PlanFollow { state.synced?.planFollow ?? .whole }

    /// The week as the member follows it; sessions done or in progress are kept as they are.
    func followed(_ p: WeekPlan) -> WeekPlan {
        guard let f = state.synced?.planFollow, f != .whole else { return p }
        var keep = Set(state.done.filter { $0.value }.map { $0.key })
        if let active = state.activeWorkout?.sessionId { keep.insert(active) }
        return f.applying(to: p, keep: keep, today: todayWeekday)
    }

    func setPlanFollow(_ f: PlanFollow) {
        guard state.synced != nil else { return }
        state.synced?.planFollow = f == .whole ? nil : f
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    /// Weekdays of the plan's own sessions (before Some days), for the day picker.
    var planWeekdays: [Int] {
        let days = (unguardedPlan()?.sessions ?? []).compactMap { $0.isPlanInsert ? nil : $0.weekday }
        return Array(Set(days)).sorted()
    }
}
