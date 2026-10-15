import Foundation
import WorkoutEngine

/// Changing a planned workout's focus from its page (#342): another session type this week only or every week,
/// or swapping days with another workout of this week.
extension AppModel {
    /// A generated plan day (not a library workout or extra), not done or started.
    func canChangeFocus(_ s: Session) -> Bool {
        guard !s.isPlanInsert, !s.isStandalone, uneditedPlan?.sessions.contains(where: { $0.id == s.id }) == true else { return false }
        return state.done[s.id] != true && activeWorkout(s.id) == nil
    }

    /// The session type the plan gives this workout before a this-week change.
    func plannedFocus(_ s: Session) -> Focus {
        guard let sp = state.synced, s.index >= 0 else { return s.focus }
        let order = Generator.weekOrder(sp.planProfile, week: sp.week)
        return order.indices.contains(s.index) ? order[s.index] : s.focus
    }

    /// Whether this workout trains another type than planned, this week only.
    func hasFocusChange(_ sessionId: String) -> Bool { state.synced?.sessionFoci?[sessionId] != nil }

    /// Every week needs the member's own split: a running programme keeps its own (#255).
    var canChangeFocusEveryWeek: Bool { runningProgramme == nil }

    /// `everyWeek`: becomes the plan's type for that day from now on (per-day picks, #200); otherwise this week only.
    func setSessionFocus(_ s: Session, to focus: Focus, everyWeek: Bool) {
        guard var sp = state.synced else { return }
        var foci = sp.sessionFoci ?? [:]
        foci[s.id] = nil
        if !everyWeek && focus != plannedFocus(s) { foci[s.id] = focus }
        sp.sessionFoci = foci.isEmpty ? nil : foci
        state.synced = sp
        if everyWeek {
            var p = sp.profile
            p.setPlanDay(s.index, to: focus, week: sp.week)
            updateProfile(p)
            return
        }
        regenerate(s.id)
    }

    /// Puts the focus changes back as they were (Undo).
    func restoreFocus(_ foci: [String: Focus]?, profile: Profile?) {
        guard var sp = state.synced else { return }
        sp.sessionFoci = foci
        state.synced = sp
        if let profile, profile != sp.profile { updateProfile(profile); return }
        let kept = doneIds.union([state.activeWorkout?.sessionId].compactMap { $0 })
        state.plan = Generator.generateWeek(sp.planProfile, week: sp.week, seed: sp.seed).keeping(kept, from: state.plan)
        replanCurrentWeek()
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    /// Regenerates one session of this week from the synced overrides; the other sessions stay as they are.
    private func regenerate(_ sessionId: String) {
        guard let sp = state.synced, var plan = state.plan,
              let i = plan.sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        if var fresh = Generator.generateWeek(sp.planProfile, week: sp.week, seed: sp.seed).sessions.first(where: { $0.id == sessionId }) {
            fresh.weekday = plan.sessions[i].weekday
            plan.sessions[i] = fresh
            state.plan = plan
        }
        replanCurrentWeek()
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    // MARK: Swap days

    /// Other workouts of this week that can trade days with `s`: from today on, not done or started. Past days stay
    /// as they are (missed workouts have their own catch-up, #266), and a swap never starts anything.
    func swapDayTargets(_ s: Session) -> [Session] {
        guard let day = s.weekday, day >= todayWeekday, state.done[s.id] != true, activeWorkout(s.id) == nil, let plan else { return [] }
        return WeekProgress.ordered(plan).filter { o in
            guard let d = o.weekday else { return false }
            return o.id != s.id && d >= todayWeekday && d != day && state.done[o.id] != true && activeWorkout(o.id) == nil
        }
    }

    /// `other` comes to this workout's day and this workout goes to `other`'s day, this week only (#113 moves).
    func swapDays(_ s: Session, with other: Session) {
        guard let day = s.weekday else { return }
        moveSession(other.id, to: day)
    }

    /// Why `focus` is a poor fit on `weekday` next to the member's climbing days, nil when it fits.
    func climbWarning(_ focus: Focus, on weekday: Int?) -> String? {
        guard let weekday, let p = profile else { return nil }
        return WeekSchedule.climbWarning(focus, on: weekday, climbing: p.climbingDays, prefs: p.climbPrefs)
    }
}
