import Foundation
import WorkoutEngine

/// Training programmes (#255): while one runs it replaces the plan (goal, split, method, focus and the week's
/// signature workouts); the member's own plan is saved and comes back on pause, leave or finish.
extension AppModel {
    /// Explore → Programmes, from any tab (#345).
    func openExploreProgrammes() {
        exploreJump = .programmes
        tab = .explore
    }

    var activeProgramme: ActiveProgramme? { state.synced?.programme }

    /// The programme shaping the plan now; nil when none or paused.
    var runningProgramme: Programme? {
        guard let a = activeProgramme, !a.paused else { return nil }
        return a.programme
    }

    /// Programme week today (1…weeks).
    var programmeWeek: Int? {
        guard let a = activeProgramme, let p = a.programme else { return nil }
        return min(p.weeks, a.week(on: .now))
    }

    var programmeHistory: [ProgrammeRecord] { state.synced?.programmeHistory ?? [] }

    /// Programmes the member made or copied (#269), newest last.
    var myProgrammes: [Programme] { state.synced?.customProgrammes ?? [] }

    /// A programme by id at its standard length: the member's own, the catalog's, or the one running (kept even when
    /// the member deleted their copy).
    func findProgramme(_ id: String) -> Programme? {
        myProgrammes.first { $0.id == id } ?? Programme.find(id)
            ?? [activeProgramme?.custom].compactMap { $0 }.first { $0.id == id }
    }

    /// Saves a programme the member made or edited. Running: the new version runs from now (this week stays as built).
    func saveProgramme(_ programme: Programme) {
        guard programme.mine else { return }
        var list = myProgrammes
        if let i = list.firstIndex(where: { $0.id == programme.id }) { list[i] = programme } else { list.append(programme) }
        state.synced?.customProgrammes = list
        if activeProgramme?.programmeId == programme.id {
            state.synced?.programme?.custom = programme
            if let l = activeProgramme?.length, !programme.lengths.contains(where: { $0.weeks == l }) {
                state.synced?.programme?.length = nil
            }
        }
        persistProgrammeChange()
    }

    func deleteProgramme(_ id: String) {
        state.synced?.customProgrammes = myProgrammes.filter { $0.id != id }
        if state.synced?.customProgrammes?.isEmpty == true { state.synced?.customProgrammes = nil }
        persistProgrammeChange()
    }

    /// Starts `programme` this week at `length` weeks (nil = standard). Another one in progress is left first; the
    /// member's own plan stays saved.
    func startProgramme(_ programme: Programme, length: Int? = nil, firstDay: Date? = nil, now: Date = .now) {
        guard let sp = state.synced else { return }
        var saved = ActiveProgramme.SavedPlan(profile: sp.profile, seed: sp.seed, week: sp.week)
        if let old = sp.programme {
            if !old.paused { saved = old.saved }
            record(old, finished: false, now: now)
        }
        state.synced?.programme = ActiveProgramme(
            programmeId: programme.id, start: Progression.weekStart(now, Progression.calendar()),
            seed: UInt32.random(in: 0...UInt32.max), saved: saved,
            length: length == programme.weeks ? nil : length, custom: programme.mine ? programme : nil)
        state.synced?.programme?.firstDay = firstDay
        syncProgramme(now: now, starting: true)
    }

    /// New length for the programme in progress (#268). This week stays as built; the phases from next week follow
    /// the new length, so nothing done this week is lost.
    func setProgrammeLength(_ weeks: Int) {
        guard var a = activeProgramme, let standard = a.custom ?? Programme.find(a.programmeId) else { return }
        a.length = weeks == standard.weeks ? nil : weeks
        state.synced?.programme = a
        persistProgrammeChange()
    }

    /// Builds the plan for this programme week when the week changed, finishes the programme once it is over.
    /// Called on Train and whenever the app comes to the front.
    func syncProgramme(now: Date = .now, starting: Bool = false) {
        guard let a = activeProgramme, !a.paused, let prog = a.programme, let sp = state.synced else { return }
        if a.finished(on: now) { return finishProgramme(now: now) }
        let week = a.week(on: now)
        guard starting || a.appliedWeek != week || !prog.isApplied(to: sp.profile) else { return }
        if a.appliedWeek != week { state.synced?.planInserts = [] }
        applyProfile(prog.profile(from: sp.profile, starting: starting), seed: Programme.seed(a.seed, week: week),
                     week: prog.cycleWeek(week: week))
        state.synced?.programme?.appliedWeek = week
        placeSignatures()
    }

    /// Places this programme week's signature workouts into the plan (replacing any earlier placement).
    func placeSignatures() {
        guard let a = activeProgramme, !a.paused, let prog = a.programme, var sp = state.synced, let base = state.plan else { return }
        let week = a.appliedWeek ?? a.week(on: .now)
        let sigs = prog.signatureInserts(week: week, plan: base, profile: sp.planProfile)
        let ours = Set(prog.signatures.map { Programme.insertId(programme: prog.id, signature: $0.id, week: week) })
        var list = (sp.planInserts ?? []).filter { !ours.contains($0.id) }
        list.removeAll { ins in ins.replacing != nil && sigs.contains { $0.replacing == ins.replacing } }
        list += sigs
        sp.planInserts = list.isEmpty ? nil : list
        state.synced = sp
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    /// Back to the member's own plan; the programme waits at this week.
    func pauseProgramme(now: Date = .now) {
        guard var a = activeProgramme, !a.paused else { return }
        a.pausedAt = Progression.weekStart(now, Progression.calendar())
        state.synced?.programme = a
        restoreOwnPlan(a.saved)
    }

    /// Picks the programme up at the week it was paused; the member's plan as it is now is what comes back later.
    func resumeProgramme(now: Date = .now) {
        guard var a = activeProgramme, a.paused, let sp = state.synced else { return }
        a.saved = ActiveProgramme.SavedPlan(profile: sp.profile, seed: sp.seed, week: sp.week)
        state.synced?.programme = a.resumed(on: now, calendar: Progression.calendar())
        syncProgramme(now: now, starting: true)
    }

    /// Stops the programme and restores the member's own plan.
    func leaveProgramme(now: Date = .now) {
        guard let a = activeProgramme else { return }
        record(a, finished: false, now: now)
        state.synced?.programme = nil
        if a.paused { return persistProgrammeChange() }
        restoreOwnPlan(a.saved)
    }

    private func finishProgramme(now: Date) {
        guard let a = activeProgramme else { return }
        finishedProgramme = record(a, finished: true, now: now)
        state.synced?.programme = nil
        restoreOwnPlan(a.saved)
    }

    @discardableResult
    private func record(_ a: ActiveProgramme, finished: Bool, now: Date) -> ProgrammeRecord {
        let weeks = finished ? (a.programme?.weeks ?? 0) : max(0, min(a.programme?.weeks ?? 0, a.week(on: now)) - 1)
        let r = ProgrammeRecord(programmeId: a.programmeId, start: a.start, end: now, finished: finished, weeks: weeks,
                                length: a.length, custom: a.custom)
        state.synced?.programmeHistory = (state.synced?.programmeHistory ?? []) + [r]
        return r
    }

    private func restoreOwnPlan(_ saved: ActiveProgramme.SavedPlan) {
        state.synced?.planInserts = nil
        // Gym and equipment edited during the programme are kept.
        let current = state.synced?.profile ?? saved.profile
        applyProfile(saved.restoring(onto: current), seed: saved.seed, week: saved.week)
    }

    private func persistProgrammeChange() {
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    /// Start vs now on the programme's lifts.
    func programmeLifts(_ programme: Programme, start: Date, end: Date = .distantFuture) -> [ProgrammeLift] {
        ProgrammeLift.compare(programme.lifts, logs: setLogs, attempts: state.prAttempts ?? [], start: start, end: end)
    }
}

extension AppModel {
    /// Coming weeks of a running programme for the calendar: its phases, then the member's own plan once it ends.
    func programmeWeeks(_ sp: SyncedProfile) -> ((Int) -> (profile: Profile, week: Int, seed: UInt32))? {
        guard let a = sp.programme, !a.paused, let prog = a.programme else { return nil }
        let now = a.appliedWeek ?? a.week(on: .now)
        return { offset in
            let w = now + offset
            if w <= prog.weeks { return (profile: sp.profile, week: prog.cycleWeek(week: w), seed: Programme.seed(a.seed, week: w)) }
            return (profile: a.saved.profile, week: PlanCalendar.cycleWeek(current: a.saved.week, offset: w - prog.weeks - 1),
                    seed: a.saved.seed)
        }
    }
}
