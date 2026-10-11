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
