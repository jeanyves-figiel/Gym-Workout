import Foundation
import WorkoutEngine

/// The same day actions on every day card and strip day, in any week (#671, design A from
/// `day-card-consistency/proposals.png`): workout days Move · Plan sport · Skip, sport days Workout · Change · Rest day,
/// rest days Workout · Plan sport · Recover.
extension AppModel {
    private func weekKey(_ date: Date) -> String { PlanCalendar.key(Progression.weekStart(date, planCalendar), planCalendar) }

    // MARK: Later weeks

    /// Sessions moved in later weeks: that week's Monday → session id → weekday.
    func laterMoves(_ now: Date = Date()) -> [String: [String: Int]] {
        let monday = weekKey(now)
        var out: [String: [String: Int]] = [:]
        for m in state.synced?.moves ?? [] where m.weekOf > monday { out[m.weekOf, default: [:]][m.sessionId] = m.weekday }
        return out
    }

    /// Moves a session of a later week to another day of that week, that week only; a session already there swaps.
    func moveSession(_ sessionId: String, to weekday: Int, in week: PlanCalendar.Week) {
        guard var sp = state.synced else { return }
        let changes = PlanCalendar.moving(sessionId, to: weekday, in: week.plan, done: [])
        guard !changes.isEmpty else { return }
        let weekOf = PlanCalendar.key(week.start, planCalendar)
        var moves = sp.moves ?? []
        for (id, wd) in changes {
            moves.removeAll { $0.weekOf == weekOf && $0.sessionId == id }
            moves.append(SessionMove(weekOf: weekOf, sessionId: id, weekday: wd))
        }
        sp.moves = moves
        state.synced = sp
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    /// Days a later week's session can move to: any day of that week but its own and days off.
    func moveTargets(_ s: Session, in week: PlanCalendar.Week) -> [Int] {
        WeekSchedule.weekdays.filter { $0 != s.weekday && week.off[$0] == nil }
    }

    /// A later week's session skipped ahead; it becomes a normal skip when its week starts.
    func isSkipped(_ sessionId: String, in week: PlanCalendar.Week) -> Bool {
        state.skippedAhead?[PlanCalendar.key(week.start, planCalendar)]?.contains(sessionId) ?? false
    }

    /// Skipped on the Calendar (#784): this week's skips or a later week's skips ahead.
    func isSkipped(_ sessionId: String, in week: PlanCalendar.Week, current: Bool) -> Bool {
        current ? skippedIds.contains(sessionId) : isSkipped(sessionId, in: week)
    }

    /// Skipped is gone (#849): once the Undo toast is over, a skipped workout leaves its day for good, never shown
    /// with Unskip again. This week's (`week` nil) still shows when done or under way.
    func skippedOff(_ s: Session, in week: PlanCalendar.Week? = nil) -> Bool {
        guard let week else { return skippedIds.contains(s.id) && !doneIds.contains(s.id) && activeWorkout(s.id) == nil }
        return isSkipped(s.id, in: week)
    }

    func setSkipped(_ skipped: Bool, _ sessionId: String, in week: PlanCalendar.Week) {
        let key = PlanCalendar.key(week.start, planCalendar)
        var all = state.skippedAhead ?? [:]
        var ids = all[key] ?? []
        ids.removeAll { $0 == sessionId }
        if skipped { ids.append(sessionId) } else { clearRemoved(sessionId, in: week) }
        all[key] = ids.isEmpty ? nil : ids
        state.skippedAhead = all.isEmpty ? nil : all
        persist()
    }

    // MARK: Remove (#784)

    private func removedKey(_ sessionId: String, in week: PlanCalendar.Week?) -> String {
        (week.map { PlanCalendar.key($0.start, planCalendar) } ?? weekKey(Date())) + ":" + sessionId
    }

    /// Removed from its day only (#784): skipped without a "skipped · Unskip" line. `week` nil = this week.
    func isRemoved(_ sessionId: String, in week: PlanCalendar.Week?) -> Bool {
        state.removed?.contains(removedKey(sessionId, in: week)) ?? false
    }

    /// Removes a workout of this week (`week` nil) or a later week from its day only: the day turns into a rest day.
    func removeSession(_ sessionId: String, in week: PlanCalendar.Week?) {
        let key = removedKey(sessionId, in: week)
        state.removed = (state.removed ?? []).filter { $0 != key } + [key]
        if let week { setSkipped(true, sessionId, in: week) } else { skipMissed(sessionId) }
    }

    /// Drops the removed mark of a workout put back on its day (#818: Unskip used to leave it, hiding a later skip).
    func clearRemoved(_ sessionId: String, in week: PlanCalendar.Week?) {
        let key = removedKey(sessionId, in: week)
        guard state.removed?.contains(key) == true else { return }
        state.removed = state.removed?.filter { $0 != key }
        if state.removed?.isEmpty == true { state.removed = nil }
    }

    /// Puts a removed workout back (Undo).
    func restoreSession(_ sessionId: String, in week: PlanCalendar.Week?) {
        clearRemoved(sessionId, in: week)
        if let week { setSkipped(false, sessionId, in: week) } else { unskip(sessionId) }
    }

    /// Whether "Every <weekday>" fits `s` (#818): a workout of the regular week on one of the member's gym days, not
    /// an added one or one moved there for that week only.
    func canRemoveEveryWeek(_ s: Session, weekday: Int, in week: PlanCalendar.Week?) -> Bool {
        guard !s.isPlanInsert, let p = profile else { return false }
        let moved = week.map { laterMoves()[PlanCalendar.key($0.start, planCalendar)]?[s.id] != nil } ?? (movesThisWeek()[s.id] != nil)
        // A planned HIIT day (#841) goes off its weekday through HIIT settings, whatever the gym days.
        return !moved && (isPlannedHiit(s) || p.gymDays.isEmpty || p.gymDays.contains(weekday))
    }

    /// A HIIT day the plan adds from HIIT settings (#841), not one added from Explore.
    func isPlannedHiit(_ s: Session) -> Bool { s.hiit != nil && !s.isPlanInsert && profile?.hiit?.days ?? 0 > 0 }

    /// Stops training on `weekday` every week (#784). Returns the profile before, for Undo.
    @discardableResult
    func removeEveryWeek(_ weekday: Int, hiit: Bool = false) -> Profile? {
        guard let p = profile else { return nil }
        // A HIIT day (#841): one HIIT day fewer, lifting days as they are.
        if hiit {
            updateProfile(p.droppingHiitDay(weekday, planned: (plan?.sessions ?? []).filter { $0.hiit != nil }.compactMap(\.weekday)))
            return p
        }
        updateProfile(p.droppingGymDay(weekday, planned: (plan?.sessions ?? []).filter { $0.hiit == nil }.compactMap(\.weekday)))
        return p
    }

    // MARK: Sport day → rest day

    enum SportOffScope { case day, everyWeek, wholeTrip }

    /// Turns the sport day `key` into a rest day: that day only, the weekday every week, or the whole trip.
    /// Returns the profile before, for Undo.
    @discardableResult
    func dropSport(on key: String, weekday: Int, scope: SportOffScope) -> Profile? {
        guard var p = profile else { return nil }
        let before = p
        switch scope {
        case .day:
            let cutoff = PlanCalendar.key(planCalendar.date(byAdding: .day, value: -56, to: Date())!, planCalendar)
            p.sportOff = ((p.sportOff ?? []).filter { $0 >= cutoff && $0 != key }) + [key]
        case .wholeTrip:
            guard let trip = p.sportTrip(on: key) else { return nil }
            p.sportTrips?.removeAll { $0.id == trip.id }
            if p.sportTrips?.isEmpty == true { p.sportTrips = nil }
        case .everyWeek:
            guard let sport = p.sport(onWeekday: weekday, key: nil) else { return nil }
            if sport == .climbing {
                p.climbingWeekdays = p.climbingDays.filter { $0 != weekday }
                p.syncClimbingDays()
            } else if let i = p.sports?.firstIndex(where: { $0.sport == sport }) {
                p.sports?[i].weekdays.removeAll { $0 == weekday }
            }
        }
        updateProfile(p)
        return before
    }

    /// Puts the profile back after Rest day's Undo.
    func restoreSportDay(_ before: Profile) { updateProfile(before) }
}
