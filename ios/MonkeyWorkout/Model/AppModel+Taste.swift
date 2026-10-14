import Foundation
import WorkoutEngine

/// Learning the member's exercise likes and dislikes (#299): swaps, edits before starting and finished workouts
/// feed `MemberTaste`; the plan uses it from the next new week (`SyncedProfile.weekTaste`). What Monkey learned
/// (Training profile) shows and corrects it; the coach's new-week card says what it changed.
extension AppModel {
    var memberTaste: MemberTaste { state.synced?.taste ?? MemberTaste() }

    var learningOn: Bool { state.synced?.tasteOff != true }

    /// Records signals; the caller persists and syncs.
    func learnTaste(_ change: (inout MemberTaste) -> Void) {
        guard state.synced != nil, learningOn else { return }
        var t = memberTaste
        change(&t)
        state.synced?.taste = t.isEmpty ? nil : t
        state.profileDirty = true
    }

    /// Affinities a new week's plan is made with; nil when learning is off or nothing was learned.
    var freshWeekTaste: [String: Double]? {
        guard learningOn, let t = state.synced?.taste else { return nil }
        let a = t.affinities(at: Date())
        return a.isEmpty ? nil : a
    }

    /// After a new week's plan: what learned tastes changed in it, for the coach's card.
    func makeTasteRecap() {
        guard let sp = state.synced, let taste = sp.weekTaste, let plan = state.plan else { return }
        var plainProfile = sp.planProfile
        plainProfile.learnedTaste = nil
        let plain = Generator.generateWeek(plainProfile, week: sp.week, seed: sp.seed)
        let changes = plan.tasteChanges(from: plain, taste: taste)
        state.synced?.tasteRecap = changes.isEmpty ? nil : TasteRecap(week: sp.week, changes: changes)
    }

    /// The coach's new-week card, while the member hasn't closed it.
    var tasteRecap: TasteRecap? {
        guard learningOn, let r = state.synced?.tasteRecap, r.week == state.synced?.week, !r.changes.isEmpty else { return nil }
        return r
    }

    func dismissTasteRecap() {
        state.synced?.tasteRecap = nil
        saveTaste()
    }

    /// Undo on the coach's card: forgets what the change was about and puts this week back.
    func undoTasteChange(_ c: TasteChange) {
        state.synced?.tasteRecap?.changes.removeAll { $0.id == c.id }
        if state.synced?.tasteRecap?.changes.isEmpty == true { state.synced?.tasteRecap = nil }
        forgetTaste(c.subject)
    }

    // MARK: What Monkey learned

    func forgetTaste(_ id: String) {
        guard state.synced != nil else { return }
        var t = memberTaste
        t.forget(id)
        state.synced?.taste = t.isEmpty ? nil : t
        applyTasteNow(id)
    }

    func markTaste(_ id: String, _ mark: TasteMark) {
        guard state.synced != nil else { return }
        var t = memberTaste
        t.mark(id, mark, at: Date())
        state.synced?.taste = t
        applyTasteNow(id)
    }

    /// Reset: everything learned goes; returns it for Undo.
    func resetTaste() -> MemberTaste? {
        let old = state.synced?.taste
        state.synced?.taste = nil
        state.synced?.tasteRecap = nil
        replanForTaste(nil)
        return old
    }

    func restoreTaste(_ t: MemberTaste) {
        state.synced?.taste = t
        replanForTaste(freshWeekTaste)
    }

    func setLearning(_ on: Bool) {
        state.synced?.tasteOff = on ? nil : true
        // Off: this week's plan drops learned tastes at once. On: they apply from the next new week.
        if on { saveTaste() } else { replanForTaste(nil) }
    }

    /// The member's own word on one exercise applies to the rest of this week straight away.
    private func applyTasteNow(_ id: String) {
        guard learningOn else { return saveTaste() }
        var week = state.synced?.weekTaste ?? [:]
        let a = memberTaste.affinity(id, at: Date())
        week[id] = a == 0 ? nil : a
        replanForTaste(week.isEmpty ? nil : week)
    }

    /// Re-plans the rest of this week (done and started sessions keep theirs) with `week` affinities.
    private func replanForTaste(_ week: [String: Double]?) {
        guard let sp = state.synced else { return }
        state.synced?.weekTaste = week
        if runningProgramme == nil {
            applyProfile(sp.profile, seed: sp.seed, week: sp.week)
        } else {
            saveTaste()
        }
    }

    private func saveTaste() {
        state.profileDirty = true
        persist()
        Task { await sync() }
    }
}

#if DEBUG
extension AppModel {
    /// Demo screens `taste` / `train-taste`: two accessories swapped away (one never again), two alternatives
    /// picked and finished, then the week made with that, so the coach has changes to show.
    func applyDemoTaste() {
        guard let plan = state.plan, let profile = state.synced?.profile else { return }
        let now = Date()
        let picked = Set(plan.sessions.flatMap { $0.blocks.flatMap(\.items) }.map(\.exerciseId))
        let accessories = plan.sessions.flatMap { s in s.blocks.filter { $0.kind == .strength }.flatMap(\.items) }
            .map(\.exerciseId).filter { !Exercise.get($0).main }
        var seen = Set<String>()
        let ids = accessories.filter { seen.insert($0).inserted }
        var t = MemberTaste()
        for (i, id) in ids.prefix(3).enumerated() {
            t.record(id, .swappedOut(kept: false), at: now)
            t.record(id, .swappedOut(kept: false), at: now)
            if i == 1 { t.record(id, .skipped, at: now) }
            if i == 2 { t.mark(id, .never, at: now) }
        }
        let liked = ids.prefix(2).compactMap { id in Exercise.get(id).alternatives(for: profile).first { !picked.contains($0.id) }?.id }
        for id in liked {
            for _ in 0..<3 { t.record(id, .swappedIn(kept: false), at: now) }
            for _ in 0..<5 { t.record(id, .finished, at: now) }
        }
        state.synced?.taste = t
        state.synced?.weekTaste = freshWeekTaste
        if let sp = state.synced { state.plan = Generator.generateWeek(sp.planProfile, week: sp.week, seed: sp.seed) }
        makeTasteRecap()
    }
}
#endif
