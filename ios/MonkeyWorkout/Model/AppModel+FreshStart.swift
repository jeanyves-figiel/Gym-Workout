import Foundation
import WorkoutEngine

/// What Undo puts back after a fresh start (#492).
struct FreshStartUndo {
    var synced: SyncedProfile
    var plan: WeekPlan?
    var ticked: [String: Bool]
}

/// Start fresh (#492, design A + B from `fresh-start/proposals.png`): a brand new plan from the training profile.
/// Plan customisations go (swaps, edited plan days, own split days, added and moved days, per-workout styles and
/// types, a running programme); history, PRs, XP, profile, gyms, learned tastes and library workout edits stay.
extension AppModel {
    /// What a fresh start would clear, for the sheet; empty = the plan is already as generated.
    var freshStartClears: [String] {
        guard let sp = state.synced else { return [] }
        var out: [String] = []
        if !(sp.exerciseSwaps ?? []).isEmpty || !(sp.variation?.swaps ?? [:]).isEmpty { out.append("Exercise swaps") }
        if (sp.sessionEdits ?? []).contains(where: { $0.week != nil }) { out.append("Edited workouts") }
        if sp.profile.splitDays != nil { out.append("Own split days") }
        if !(sp.planInserts ?? []).isEmpty { out.append("Added workouts") }
        if !(sp.moves ?? []).isEmpty { out.append("Moved days") }
        if !(sp.sessionStyles ?? [:]).isEmpty || !(sp.sessionFoci ?? [:]).isEmpty { out.append("Per-workout changes") }
        if activeProgramme != nil { out.append("Programme") }
        return out
    }

    /// Profile a fresh start begins from: the member's own (outside a programme), without per-day split picks.
    var freshStartProfile: Profile? {
        guard let sp = state.synced else { return nil }
        var p = activeProgramme.map { $0.saved.restoring(onto: sp.profile) } ?? sp.profile
        p.splitDays = nil
        return p
    }

    /// Leaves any programme, drops plan customisations and builds a new plan (new seed) from `profile`
    /// (nil = the current answers). Sessions done this week and the one in progress keep their content.
    @discardableResult
    func startFresh(_ profile: Profile? = nil, now: Date = .now) -> FreshStartUndo? {
        guard let before = state.synced else { return nil }
        let undo = FreshStartUndo(synced: before, plan: state.plan, ticked: state.ticked)
        if activeProgramme != nil { leaveProgramme(now: now) }
        guard var sp = state.synced else { return nil }
        var p = profile ?? sp.profile
        // Answered again (B): the member's own day picks stand.
        if profile == nil { p.splitDays = nil }
        sp.exerciseSwaps = nil
        sp.variation = nil
        sp.planInserts = nil
        sp.moves = nil
        sp.sessionStyles = nil
        sp.sessionFoci = nil
        // Library workout edits are the member's own workouts, not the plan's.
        sp.sessionEdits = sp.sessionEdits?.filter { $0.week == nil }
        if sp.sessionEdits?.isEmpty == true { sp.sessionEdits = nil }
        // A new seed with the same week: a different plan, while this week's done sessions stay done.
        var seed = UInt32.random(in: 0...UInt32.max)
        if seed == before.seed { seed &+= 1 }
        sp.seed = seed
        state.synced = sp
        applyProfile(p, seed: seed, week: sp.week)
        return undo
    }

    func undoFreshStart(_ undo: FreshStartUndo) {
        state.synced = undo.synced
        state.plan = undo.plan
        state.ticked = undo.ticked
        replanCurrentWeek()
        state.profileDirty = true
        persist()
        Task { await sync() }
    }
}
