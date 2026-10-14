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

    /// The travel period covering today, if any (#160).
    var currentTrip: AwayPeriod? {
        let today = PlanCalendar.key(Date(), planCalendar)
        return away.first { $0.kind == .travel && $0.covers(today) }
    }

    /// The next travel period starting within two weeks (#160).
    var nextTrip: AwayPeriod? {
        let cal = planCalendar
        let today = PlanCalendar.key(Date(), cal)
        let limit = PlanCalendar.key(cal.date(byAdding: .day, value: 14, to: Date()) ?? Date(), cal)
        return away.first { $0.kind == .travel && $0.start > today && $0.start <= limit }
    }

    /// "Away: Berlin · Hotel gym until 21 Oct" or "Trip: Berlin · Hotel gym from 18 Oct"; nil when no trip is near (#160).
    var tripLine: String? {
        func day(_ key: String) -> String {
            PlanCalendar.date(key, planCalendar)?.formatted(.dateTime.day().month(.abbreviated)) ?? key
        }
        if let t = currentTrip { return "Away: \(t.title) until \(day(t.end))" }
        if let t = nextTrip { return "Trip: \(t.title) from \(day(t.start))" }
        return nil
    }

    /// Home gym name from the training profile (default gym when none saved).
    var gymName: String { profile?.gym?.name ?? Gym.puls5.name }

    var doneIds: Set<String> { Set(state.done.filter(\.value).keys) }

    /// This week (as on the Train tab) and the coming weeks, dated and adapted around away periods.
    func calendarWeeks(count: Int = PlanCalendar.horizonWeeks, now: Date = Date()) -> [PlanCalendar.Week] {
        guard let sp = state.synced else { return [] }
        // Library extras and one-off moves (#113) show on their day this week.
        return PlanCalendar.weeks(sp.profile, seed: sp.seed, currentWeek: sp.week, current: plan, done: doneIds,
                                  away: away, now: now, count: count, fixed: movesThisWeek(now), calendar: planCalendar,
                                  future: programmeWeeks(sp))
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
        // Done sessions keep the day and content they were done with (also after a profile edit, #194).
        // The workout in progress keeps its content too.
        let done = doneIds
        let kept = done.union([state.activeWorkout?.sessionId].compactMap { $0 })
        let regular = Generator.generateWeek(sp.planProfile, week: sp.week, seed: sp.seed).keeping(kept, from: state.plan)
        if PlanCalendar.touches(away, weekStart: monday, cal) {
            let today = WeekSchedule.fromCalendar(cal.component(.weekday, from: now))
            let adapted = PlanCalendar.adapt(sp.planProfile, week: sp.week, seed: sp.seed, weekStart: monday, away: away,
                                             base: regular, done: done, firstDay: today, fixed: movesThisWeek(now), calendar: cal).plan
            if adapted != state.plan { state.plan = adapted }
        } else if let plan = state.plan {
            // Same sessions (exercise swaps kept) back on their regular days, in plan order, then this week's moves.
            var target = layout(plan) == layout(regular) ? plan : regular
            let days = Dictionary(regular.sessions.map { ($0.id, $0.weekday) }, uniquingKeysWith: { a, _ in a })
            for i in target.sessions.indices { target.sessions[i].weekday = days[target.sessions[i].id] ?? nil }
            target.sessions.sort { $0.index < $1.index }
            target = target.pinning(movesThisWeek(now))
            if target != plan { state.plan = target }
        }
    }

    /// Ids, titles and foci: what adapting changes apart from days (exercise swaps don't).
    private func layout(_ plan: WeekPlan) -> [String] {
        plan.sessions.map { "\($0.id)|\($0.title)|\($0.focus.rawValue)" }.sorted()
    }

    // MARK: One-off changes (#113)

    private func mondayKey(_ now: Date) -> String { PlanCalendar.key(Progression.weekStart(now, planCalendar), planCalendar) }

    /// Generated sessions moved this week (id → weekday).
    func movesThisWeek(_ now: Date = Date()) -> [String: Int] {
        let monday = mondayKey(now)
        return Dictionary((state.synced?.moves ?? []).filter { $0.weekOf == monday }.map { ($0.sessionId, $0.weekday) },
                          uniquingKeysWith: { _, b in b })
    }

    /// Days a session of this week can move to: any day of this week but its own and days off.
    func moveTargets(_ sessionId: String, now: Date = Date()) -> [Int] {
        guard let week = calendarWeeks(count: 1, now: now).first,
              let s = week.plan.sessions.first(where: { $0.id == sessionId }), !doneIds.contains(sessionId) else { return [] }
        return WeekSchedule.weekdays.filter { $0 != s.weekday && week.off[$0] == nil }
    }

    /// Moves a session of this week to `weekday`, this week only; a session already there (not done) takes its day.
    func moveSession(_ sessionId: String, to weekday: Int, now: Date = Date()) {
        guard var sp = state.synced, let week = calendarWeeks(count: 1, now: now).first else { return }
        let changes = PlanCalendar.moving(sessionId, to: weekday, in: week.plan, done: doneIds)
        guard !changes.isEmpty else { return }
        let monday = mondayKey(now)
        var moves = (sp.moves ?? []).filter { $0.weekOf == monday }
        for (id, wd) in changes {
            if let insId = week.plan.sessions.first(where: { $0.id == id })?.planInsertId,
               let i = sp.planInserts?.firstIndex(where: { $0.id == insId }) {
                if let r = sp.planInserts?[i].replacing {
                    // A library workout in place of a planned day moves with that day's slot.
                    guard let base = state.plan, base.sessions.indices.contains(r) else { continue }
                    moves.removeAll { $0.sessionId == base.sessions[r].id }
                    moves.append(SessionMove(weekOf: monday, sessionId: base.sessions[r].id, weekday: wd))
                } else {
                    sp.planInserts?[i].weekday = wd
                }
            } else {
                moves.removeAll { $0.sessionId == id }
                moves.append(SessionMove(weekOf: monday, sessionId: id, weekday: wd))
            }
        }
        sp.moves = moves
        state.synced = sp
        state.profileDirty = true
        replanCurrentWeek(now: now)
        persist()
        Task { await sync() }
    }

    /// Puts this week's moved sessions back on their planned days.
    func clearMoves(now: Date = Date()) {
        guard state.synced?.moves?.isEmpty == false else { return }
        state.synced?.moves = nil
        state.profileDirty = true
        replanCurrentWeek(now: now)
        persist()
        Task { await sync() }
    }

    /// Adds an extra session to a day of this week: a library workout, or a generated one (`generated` set).
    @discardableResult
    func addExtra(_ workout: CustomWorkout, generated: Session? = nil, weekday: Int) -> PlanInsert? {
        guard generated == nil else {
            guard var sp = state.synced, let base = state.plan else { return nil }
            let insert = PlanInsert(week: base.week, weekday: weekday, workout: CustomWorkout(name: workout.name), generated: generated)
            sp.planInserts = (sp.planInserts ?? []) + [insert]
            state.synced = sp
            state.profileDirty = true
            persist()
            Task { await sync() }
            return insert
        }
        return insertIntoPlan(workout, replacing: nil, weekday: weekday)
    }

    /// A quick generated session of `focus` for this week (equipment, goal and style from the profile);
    /// `minutes` sets its length (#178), nil = the plan's session length.
    func quickSession(_ focus: Focus, minutes: Int? = nil) -> Session? {
        guard let sp = state.synced else { return nil }
        return Generator.quickSession(sp.profile, focus: focus, week: sp.week, seed: quickSeed(sp), minutes: minutes)
    }

    /// A quick workout for chosen muscle groups (#178), sized to `minutes`; empty when nothing fits.
    func quickWorkout(_ groups: Set<MuscleGroup>, minutes: Int) -> CustomWorkout? {
        guard let sp = state.synced else { return nil }
        let w = Generator.quickWorkout(sp.profile, groups: groups, minutes: minutes, seed: quickSeed(sp))
        return w.items.isEmpty ? nil : w
    }

    private func quickSeed(_ sp: SyncedProfile) -> UInt32 {
        sp.seed &+ UInt32(truncatingIfNeeded: (sp.planInserts?.count ?? 0) + 1)
    }
}
