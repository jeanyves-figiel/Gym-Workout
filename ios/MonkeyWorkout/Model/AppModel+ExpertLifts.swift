import Foundation
import WorkoutEngine

/// Lift Focus, Pro Sets and Lift Lab (#499, designs A + B + C from `expert-lifters/proposals.png`).
extension AppModel {
    // MARK: Plan

    /// The week with the Lift Focus block and the member's set styles applied. The focus lift keeps the block's sets.
    func expertPlan(_ p: WeekPlan) -> WeekPlan {
        guard let sp = state.synced else { return p }
        let focus = activeLiftFocus
        var styles = sp.setStyles ?? [:]
        if let focus { styles[focus.exerciseId] = nil }
        return p.applyingLiftFocus(focus, on: Date(), equipment: Set(sp.profile.equipment)).applyingSetStyles(styles)
    }

    // MARK: Lift Focus

    var liftFocus: LiftFocus? { state.synced?.liftFocus }

    /// The block when today is inside it.
    var activeLiftFocus: LiftFocus? {
        guard let f = liftFocus, f.week(on: Date()) != nil else { return nil }
        return f
    }

    func setLiftFocus(_ f: LiftFocus?) {
        guard state.synced != nil, state.synced?.liftFocus != f else { return }
        state.synced?.liftFocus = f
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    /// Estimated 1RM of a lift: best of the last 6 weeks of logs and PR attempts, else the best ever.
    func liveOneRepMax(_ exerciseId: String) -> Double? {
        let logs = setLogs.filter { $0.exerciseId == exerciseId }
        let attempts = (state.prAttempts ?? []).filter { $0.exerciseId == exerciseId }
        let recent = LiftLab.oneRepMax(exerciseId: exerciseId, logs: logs, since: Date().addingTimeInterval(-42 * 86400))
        let attempt = attempts.filter { $0.date > Date().addingTimeInterval(-42 * 86400) }.compactMap(\.estimatedOneRepMax).max()
        if let best = [recent, attempt].compactMap({ $0 }).max() { return best }
        return PRPlanner.estimatedOneRepMax(logs: logs, attempts: attempts)
    }

    /// Weekly best e1RM of a lift, oldest first.
    func oneRepMaxTrend(_ exerciseId: String) -> [(Date, Double)] {
        Progression.oneRepMaxTrend(exerciseId, records: state.history)
    }

    /// Starts a block on Monday of this week.
    func startLiftFocus(exerciseId: String, targetKg: Double, template: FocusTemplate, weeks: Int, weakPoint: WeakPoint, maintenance: Bool) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let monday = cal.date(byAdding: .day, value: -((cal.component(.weekday, from: today) + 5) % 7), to: today) ?? today
        let orm = liveOneRepMax(exerciseId) ?? targetKg * 0.9
        setLiftFocus(LiftFocus(exerciseId: exerciseId, targetKg: targetKg, start: monday, weeks: weeks, template: template,
                               startOneRepMax: orm, weakPoint: weakPoint, maintenance: maintenance))
    }

    // MARK: Pro Sets

    func setStyle(_ exerciseId: String) -> SetStyle { state.synced?.setStyles?[exerciseId] ?? .straight }

    func setSetStyle(_ style: SetStyle, for exerciseId: String) {
        guard state.synced != nil, setStyle(exerciseId) != style else { return }
        var all = state.synced?.setStyles ?? [:]
        all[exerciseId] = style == .straight ? nil : style
        state.synced?.setStyles = all.isEmpty ? nil : all
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    /// The sets of a planned item when they aren't all alike: the Lift Focus block's sets for the focus lift in a
    /// focus session, else the member's set style. nil = straight sets from the load suggestion.
    func plannedSets(for item: PlannedExercise, sessionId: String, workingKg: Double?) -> [PlannedSet]? {
        guard let e = Exercise.find(item.exerciseId), ProSets.eligible(e) else { return nil }
        if let f = activeLiftFocus, f.exerciseId == item.exerciseId, let w = f.week(on: Date()),
           let n = plan?.liftFocusIndex(sessionId: sessionId, focus: f) {
            let sets = f.plannedSets(week: w, index: n, live: liveOneRepMax(e.id), exercise: e)
            if sets.count == item.prescription.sets { return sets }
        }
        let style = setStyle(item.exerciseId)
        guard style != .straight, item.group == nil, item.supersetWith == nil else { return nil }
        let sets = ProSets.sets(style, prescription: item.prescription, workingKg: workingKg,
                                oneRepMax: liveOneRepMax(e.id), exercise: e)
        return sets.count == item.prescription.sets ? sets : nil
    }
}
