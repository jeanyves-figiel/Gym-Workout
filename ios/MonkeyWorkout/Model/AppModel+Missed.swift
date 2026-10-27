import APIClient
import Foundation
import WorkoutEngine

/// Missed sessions (#266): a session of an earlier day this week that wasn't done. Train moves on to the next
/// training day; the member can log it after the fact, mark it done as planned, do it today or skip it.
extension AppModel {
    /// Today, 1 = Monday … 7 = Sunday.
    var todayWeekday: Int { demoToday ?? WeekSchedule.fromCalendar(planCalendar.component(.weekday, from: Date())) }

    var skippedIds: Set<String> { Set((state.skipped ?? [:]).filter(\.value).keys) }

    /// Missed sessions this week, skipped ones included (they still count as missed). Removed ones (#784) are rest
    /// days, not missed (#818).
    var missedSessions: [Session] {
        (plan.map { WeekProgress.missed($0, today: todayWeekday, done: doneIds) } ?? []).filter { !isRemoved($0.id, in: nil) }
    }

    /// Missed sessions still waiting for the member: not skipped.
    var missedToHandle: [Session] { missedSessions.filter { !skippedIds.contains($0.id) } }

    /// Sessions still to do this week, from today on (skipped ones don't count, #643).
    var remainingCount: Int { plan.map { WeekProgress.remaining($0, today: todayWeekday, done: doneIds.union(skippedIds)) } ?? 0 }

    /// This week's sessions the ring and tiles count (#818): skipped and removed ones leave the week unless done.
    var weekSessionCount: Int {
        let done = doneIds, skipped = skippedIds
        return plan?.sessions.filter { done.contains($0.id) || !skipped.contains($0.id) }.count ?? 0
    }

    /// "Today", "Tomorrow" or the weekday of a session coming up.
    func upcomingDayLabel(_ s: Session) -> String {
        guard let wd = s.weekday else { return s.dayLabel }
        return wd == todayWeekday ? "Today" : wd == todayWeekday + 1 ? "Tomorrow" : s.dayLabel
    }

    /// Coach monkey's "week done": target reached, or nothing left and no missed session waiting (skipped ones let go).
    func weekDone(thisWeek: Int, target: Int) -> Bool {
        thisWeek >= target || (nextSession == nil && missedToHandle.isEmpty)
    }

    /// The date of a session's day this week (today for an unscheduled one).
    func day(of s: Session, now: Date = Date()) -> Date {
        let cal = planCalendar
        guard let wd = s.weekday else { return cal.startOfDay(for: now) }
        return cal.date(byAdding: .day, value: wd - 1, to: Progression.weekStart(now, cal)) ?? now
    }

    /// Default start of a workout logged after the fact: 18:00 on its day.
    func defaultStart(of s: Session) -> Date {
        planCalendar.date(bySettingHour: 18, minute: 0, second: 0, of: day(of: s)) ?? day(of: s)
    }

    /// Marks a missed session done as planned: every set, the last weights used, the planned length.
    /// Returns the record, for the Undo bar (#822).
    @discardableResult
    func markMissedDone(_ s: Session) -> WorkoutRecord {
        var sets: [String: Int] = [:]
        for b in s.blocks { for it in b.items { sets[it.uid] = it.prescription.sets } }
        return logMissed(s, setsDone: sets, weights: [:], start: defaultStart(of: s), minutes: s.estMin)
    }

    /// Records a missed session after the fact on its day: sets done per item, weights per exercise.
    @discardableResult
    func logMissed(_ s: Session, setsDone: [String: Int], weights: [String: Double], start: Date, minutes: Int) -> WorkoutRecord {
        for (exerciseId, kg) in weights {
            let entry = LogEntry(date: start, exerciseId: exerciseId, sessionId: s.id, weightKg: kg)
            state.logs.append(entry)
            state.pendingLogIds.insert(entry.id)
        }
        // Only a session of this week's plan ticks its exercises: a copy logged as an extra on a past day (#800)
        // shares the planned one's uids (#818).
        if plan?.sessions.contains(where: { $0.id == s.id }) == true {
            for b in s.blocks { for it in b.items where (setsDone[it.uid] ?? 0) > 0 { state.ticked[it.uid] = true } }
        }
        state.skipped?[s.id] = nil
        return recordWorkout(session: s, setsDone: setsDone, startedAt: start,
                      endedAt: start.addingTimeInterval(TimeInterval(max(1, minutes) * 60)), bodyMassKg: body.weightKg)
    }

    /// Lets a missed session go (#340): no more catch-up prompts, chips or counts for it; it stays missed in history.
    func skipMissed(_ sessionId: String) {
        var s = state.skipped ?? [:]
        s[sessionId] = true
        state.skipped = s
        persist()
    }

    /// Skips today's or a later session this week without moving it (#643): Next up moves on, the day shows
    /// skipped and it becomes a skipped missed session once the day is over.
    func skipSession(_ sessionId: String) { skipMissed(sessionId) }

    /// Puts a skipped session back on its day (#643).
    func unskip(_ sessionId: String) {
        state.skipped?[sessionId] = nil
        // Back on its day: no longer removed either (#818).
        clearRemoved(sessionId, in: nil)
        persist()
    }

    /// Whether a session of today or later can be skipped: not done, not running, not skipped yet.
    func canSkip(_ s: Session) -> Bool {
        !doneIds.contains(s.id) && !skippedIds.contains(s.id) && state.activeWorkout?.sessionId != s.id
            && (s.weekday ?? todayWeekday) >= todayWeekday
    }

    /// Moves a missed session to today, next to anything already planned today.
    func doMissedToday(_ sessionId: String) {
        state.skipped?[sessionId] = nil
        moveSession(sessionId, to: todayWeekday, swap: false)
    }

    /// A new calendar week moves the plan on (#266): next cycle week, this week's ticks, moves, library inserts,
    /// variation and per-workout styles cleared. A running programme sets its weeks itself.
    /// Never under a workout in progress (saved in the last few hours): it rolls on the next foreground or Train visit
    /// after the finish. A workout paused long ago doesn't hold the week back.
    func rollWeekIfNeeded(now: Date = Date()) {
        let inProgress = state.activeWorkout.map { now.timeIntervalSince($0.updatedAt) < Self.interruptedWindow } ?? false
        guard !inProgress, let sp = state.synced else { return }
        let cal = planCalendar
        let monday = Progression.weekStart(now, cal)
        let key = PlanCalendar.key(monday, cal)
        guard let of = sp.weekOf, let ofDate = PlanCalendar.date(of, cal) else {
            state.synced?.weekOf = key
            state.profileDirty = true
            persist()
            return
        }
        let weeks = WeekProgress.weeksBetween(ofDate, monday, cal)
        guard weeks > 0 else { return }
        // A running programme rolls its own plan (`syncProgramme`); the calendar week still moves on (#818): this
        // week's Monday, skips made ahead for it, removals of past weeks dropped.
        guard runningProgramme == nil else {
            state.synced?.weekOf = key
            state.profileDirty = true
            let ahead = state.skippedAhead?[key] ?? []
            state.skippedAhead = state.skippedAhead?.filter { $0.key > key }
            if state.skippedAhead?.isEmpty == true { state.skippedAhead = nil }
            state.removed = state.removed?.filter { $0 >= key }
            if state.removed?.isEmpty == true { state.removed = nil }
            if !ahead.isEmpty {
                var skipped = state.skipped ?? [:]
                for id in ahead { skipped[id] = true }
                state.skipped = skipped
            }
            persist()
            Task { await sync() }
            return
        }
        state.synced?.weekOf = key
        state.synced?.planInserts = nil
        state.synced?.variation = nil
        state.synced?.sessionStyles = nil
        state.synced?.sessionFoci = nil
        state.done = [:]
        state.ticked = [:]
        let ahead = state.skippedAhead?[key] ?? []
        state.skippedAhead = state.skippedAhead?.filter { $0.key > key }
        state.removed = state.removed?.filter { $0 >= key }
        if state.removed?.isEmpty == true { state.removed = nil }
        applyProfile(sp.profile, seed: sp.seed, week: PlanCalendar.cycleWeek(current: sp.week, offset: weeks), rolled: true)
        // Sessions skipped ahead for the new week (#671) are its skips now: after the roll, which clears skips.
        guard !ahead.isEmpty else { return }
        state.skipped = Dictionary(ahead.map { ($0, true) }, uniquingKeysWith: { a, _ in a })
        persist()
    }
}
