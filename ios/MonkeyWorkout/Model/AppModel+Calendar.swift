import Foundation
import WorkoutEngine

/// Training calendar (#68): coming weeks, "can't train" dates and travel periods, synced with the profile.
extension AppModel {
    var planCalendar: Calendar { Progression.calendar() }

    /// All away periods, earliest first.
    var away: [AwayPeriod] { (state.synced?.away ?? []).sorted { ($0.start, $0.end) < ($1.start, $1.end) } }

    /// Away periods that end today or later.
    var upcomingAway: [AwayPeriod] {
        let today = PlanCalendar.key(Date(), planCalendar)
        return away.filter { $0.end >= today }
    }

    var doneIds: Set<String> { Set(state.done.filter(\.value).keys) }

    /// This week (as on the Train tab) and the coming weeks, dated and adapted around away periods.
    func calendarWeeks(count: Int = PlanCalendar.horizonWeeks, now: Date = Date()) -> [PlanCalendar.Week] {
        guard let sp = state.synced else { return [] }
        return PlanCalendar.weeks(sp.profile, seed: sp.seed, currentWeek: sp.week, current: state.plan, done: doneIds,
                                  away: away, now: now, count: count, calendar: planCalendar)
    }

    /// Planned, not yet done sessions with their date, from `from` to `to` inclusive (e.g. for reminders).
    func plannedSessions(from: Date, to: Date) -> [(date: Date, session: Session)] {
        let cal = planCalendar
        let weeks = Int(ceil(to.timeIntervalSince(Progression.weekStart(Date(), cal)) / (7 * 86_400))) + 1
        return PlanCalendar.planned(in: calendarWeeks(count: min(52, max(1, weeks))), from: from, to: to, done: doneIds, calendar: cal)
    }

    /// The away period covering a weekday of the current week, if any.
    func awayThisWeek(_ weekday: Int, now: Date = Date()) -> AwayPeriod? {
        let keys = PlanCalendar.dayKeys(weekStart: Progression.weekStart(now, planCalendar), planCalendar)
        return away.first { $0.covers(keys[weekday - 1]) }
    }

    func saveAway(_ period: AwayPeriod) {
        guard state.synced != nil else { return }
        var list = state.synced?.away ?? []
        if let i = list.firstIndex(where: { $0.id == period.id }) { list[i] = period } else { list.append(period) }
        // Periods that ended more than 8 weeks ago are dropped.
        let cutoff = PlanCalendar.key(planCalendar.date(byAdding: .day, value: -56, to: Date())!, planCalendar)
        state.synced?.away = list.filter { $0.end >= cutoff }
        state.profileDirty = true
        replanCurrentWeek()
        persist()
        Task { await sync() }
    }

    func deleteAway(_ id: UUID) {
        guard state.synced != nil else { return }
        state.synced?.away?.removeAll { $0.id == id }
        state.profileDirty = true
        replanCurrentWeek()
        persist()
        Task { await sync() }
    }

    /// Moves a session of this week to the next free day by marking its day as "can't train"
    /// (today when the session has no weekday). Returns the session's new date, nil if it no longer fits.
    @discardableResult
    func reschedule(sessionId: String, now: Date = Date()) -> Date? {
        let cal = planCalendar
        let monday = Progression.weekStart(now, cal)
        let today = WeekSchedule.fromCalendar(cal.component(.weekday, from: now))
        guard let session = plan?.sessions.first(where: { $0.id == sessionId }) else { return nil }
        let weekday = session.weekday ?? today
        let key = PlanCalendar.dayKeys(weekStart: monday, cal)[weekday - 1]
        if !away.contains(where: { $0.kind == .off && $0.covers(key) }) {
            saveAway(AwayPeriod(kind: .off, start: key, end: key, note: weekday < today ? "Missed" : "Moved"))
        }
        guard let moved = plan?.sessions.first(where: { $0.id == sessionId })?.weekday else { return nil }
        return cal.date(byAdding: .day, value: moved - 1, to: monday)
    }

    /// Re-plans the current week around away periods (done sessions stay, only today onward changes);
    /// restores the regular week when no away period touches it any more.
    func replanCurrentWeek(now: Date = Date()) {
        guard let sp = state.synced else { return }
        let cal = planCalendar
        let monday = Progression.weekStart(now, cal)
        var regular = Generator.generateWeek(sp.profile, week: sp.week, seed: sp.seed)
        if PlanCalendar.touches(away, weekStart: monday, cal) {
            // Done sessions keep the day and content they were done with.
            let done = doneIds
            for i in regular.sessions.indices where done.contains(regular.sessions[i].id) {
                if let s = state.plan?.sessions.first(where: { $0.id == regular.sessions[i].id }) { regular.sessions[i] = s }
            }
            let today = WeekSchedule.fromCalendar(cal.component(.weekday, from: now))
            let adapted = PlanCalendar.adapt(sp.profile, week: sp.week, seed: sp.seed, weekStart: monday, away: away,
                                             base: regular, done: done, firstDay: today, calendar: cal).plan
            if adapted != state.plan { state.plan = adapted }
        } else if let plan = state.plan, layout(plan) != layout(regular) {
            state.plan = regular
        }
    }

    /// Ids, days and titles: what adapting changes (exercise swaps don't).
    private func layout(_ plan: WeekPlan) -> [String] {
        plan.sessions.map { "\($0.id)|\($0.weekday ?? 0)|\($0.title)|\($0.focus.rawValue)" }
    }
}
