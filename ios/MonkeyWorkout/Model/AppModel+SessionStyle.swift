import Foundation
import WorkoutEngine

/// Per-workout rest between sets and grouping (#106): overrides the training profile's style for one session of
/// this week; synced with the profile, dropped on a week change.
extension AppModel {
    /// The session's override; empty when it follows the plan.
    func sessionStyle(_ sessionId: String) -> SessionStyle {
        state.synced?.sessionStyles?[sessionId] ?? SessionStyle()
    }

    /// Whether the workout can take its own style: a generated plan session with a strength block, not done or started.
    func canStyle(_ session: Session) -> Bool {
        guard state.plan?.sessions.contains(where: { $0.id == session.id }) == true, session.stylable else { return false }
        return !(state.done[session.id] ?? false) && activeWorkout(session.id) == nil
    }

    /// Sets (or with an empty style clears) the override and regenerates that session; the other sessions stay as they are.
    func setSessionStyle(_ sessionId: String, _ style: SessionStyle) {
        guard var sp = state.synced, var plan = state.plan,
              let i = plan.sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        var styles = sp.sessionStyles ?? [:]
        styles[sessionId] = style.isEmpty ? nil : style
        sp.sessionStyles = styles.isEmpty ? nil : styles
        state.synced = sp
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
}

/// Session flow (#198): one workout's blocks and time split, or the plan-wide default from a workout.
extension AppModel {
    /// Whether this workout's flow can change: a generated plan session or a generated extra (#590), not done or started.
    func canEditFlow(_ session: Session) -> Bool {
        if session.isPlanInsert {
            guard generatedExtra(session.id) != nil else { return false }
        } else if state.plan?.sessions.contains(where: { $0.id == session.id }) != true {
            return false
        }
        return !(state.done[session.id] ?? false) && activeWorkout(session.id) == nil
    }

    /// This workout only; a flow equal to the plan's clears the override.
    func setSessionFlow(_ sessionId: String, _ flow: SessionFlow) {
        var style = sessionStyle(sessionId)
        let f = flow.sanitized
        style.flow = f == (profile?.sessionFlow ?? SessionFlow()) ? nil : f
        if generatedExtra(sessionId) != nil { return setExtraFlow(sessionId, style) }
        setSessionStyle(sessionId, style)
    }

    /// The quick extra (#113) behind a session of this week, when it was generated rather than a library workout.
    func generatedExtra(_ sessionId: String) -> PlanInsert? {
        state.synced?.planInserts?.first { $0.sessionId == sessionId && $0.generated != nil }
    }

    /// A generated extra regenerated with the flow (#590): same focus and length, exercises picked again.
    private func setExtraFlow(_ sessionId: String, _ style: SessionStyle) {
        guard var sp = state.synced, let i = sp.planInserts?.firstIndex(where: { $0.sessionId == sessionId }),
              let old = sp.planInserts?[i].generated else { return }
        var p = sp.tasteProfile
        p.sessionFlow = style.flow ?? p.sessionFlow
        let u = sp.planInserts![i].id.uuid
        let seed = sp.seed &+ (UInt32(u.0) << 24 | UInt32(u.1) << 16 | UInt32(u.2) << 8 | UInt32(u.3))
        guard let fresh = Generator.quickSession(p, focus: old.focus, week: sp.week, seed: seed, minutes: old.targetMin) else { return }
        sp.planInserts?[i].generated = fresh
        var styles = sp.sessionStyles ?? [:]
        styles[sessionId] = style.isEmpty ? nil : style
        sp.sessionStyles = styles.isEmpty ? nil : styles
        state.synced = sp
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    /// Every workout: becomes the plan's flow (Edit plan), and `sessionId` drops its own.
    func setPlanFlow(_ flow: SessionFlow, clearing sessionId: String) {
        guard var sp = state.synced else { return }
        if var style = sp.sessionStyles?[sessionId] {
            style.flow = nil
            sp.sessionStyles?[sessionId] = style.isEmpty ? nil : style
            if sp.sessionStyles?.isEmpty == true { sp.sessionStyles = nil }
            state.synced = sp
        }
        var p = sp.profile
        p.sessionFlow = flow.isAuto ? nil : flow.sanitized
        updateProfile(p)
    }
}

/// My picks per block (#204): exercises the member always wants in a block, set from a workout's exercise menu.
extension AppModel {
    /// Blocks that take picks, once a training profile exists.
    func canPick(_ kind: BlockKind) -> Bool { profile != nil && BlockPicks.kinds.contains(kind) }

    func isPicked(_ exerciseId: String, in kind: BlockKind) -> Bool {
        profile?.picks(kind)?.items.contains { $0.exerciseId == exerciseId } ?? false
    }

    /// Pins the exercise to every workout's `kind` block with `minutes`, or unpins it; the week is re-planned.
    func togglePick(_ exerciseId: String, in kind: BlockKind, minutes: Int) {
        guard var p = profile else { return }
        var picks = p.blockPicks?[kind.rawValue] ?? BlockPicks()
        if let i = picks.items.firstIndex(where: { $0.exerciseId == exerciseId }) {
            picks.items.remove(at: i)
        } else {
            let range = BlockPick.minutesRange
            picks.items.append(BlockPick(exerciseId: exerciseId, minutes: min(range.upperBound, max(range.lowerBound, minutes))))
        }
        p.setPicks(picks, for: kind)
        updateProfile(p)
    }
}
