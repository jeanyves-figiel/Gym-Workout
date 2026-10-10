import APIClient
import Foundation
import WorkoutEngine

/// Workout library (#62): my workouts, built-in examples and workouts other members shared;
/// any of them can be started on its own or placed into the week plan.
extension AppModel {
    enum SharedLibraryLoad: Equatable {
        case loaded
        /// Browsing and sharing need a community profile (guidelines accepted, #61).
        case needsCommunityProfile
        case failed(String)
    }

    func sharedWorkout(sessionId: String) -> SharedWorkout? {
        sharedLibrary.first { $0.workout.sessionId == sessionId }
    }

    func loadSharedLibrary(query: String? = nil) async -> SharedLibraryLoad {
        #if DEBUG
        if demo {
            sharedLibrary = Demo.sharedWorkouts
            return .loaded
        }
        #endif
        do {
            sharedLibrary = try await api.fetchSharedWorkouts(SharedWorkout.self, query: query)
            return .loaded
        } catch let APIError.server(_, code, _) where code == "community_profile_required" {
            sharedLibrary = []
            return .needsCommunityProfile
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Adds an editable private copy to "My workouts".
    @discardableResult
    func saveCopy(of shared: SharedWorkout) -> CustomWorkout {
        let w = saveCustomWorkout(shared.copy())
        if !demo { Task { try? await api.countSharedWorkoutSave(shared.id) } }
        return w
    }

    func setVisibility(_ id: UUID, _ visibility: WorkoutVisibility) {
        guard var w = customWorkout(id), w.visibility != visibility else { return }
        w.visibility = visibility
        saveCustomWorkout(w)
    }

    /// Reports a member's workout; it disappears from this device's library right away.
    func report(_ shared: SharedWorkout, reason: String, details: String?) async throws {
        if !demo { try await api.reportSharedWorkout(shared.id, reason: reason, details: details) }
        sharedLibrary.removeAll { $0.id == shared.id }
    }

    /// Blocks the author: none of their workouts (or community posts) show any more, either way.
    func block(_ author: SharedWorkout.Author) async throws {
        if !demo { try await api.blockMember(author.userId) }
        sharedLibrary.removeAll { $0.author.userId == author.userId }
    }

    // MARK: Plan

    /// The library workout behind a standalone session (example, mine, shared or already planned), as a snapshot to plan.
    func libraryWorkout(for session: Session) -> CustomWorkout? {
        if let id = session.planInsertId { return state.synced?.planInserts?.first { $0.id == id }?.workout }
        if let w = customWorkout(sessionId: session.id) { return w }
        if let s = sharedWorkout(sessionId: session.id) { return s.workout }
        if let t = WorkoutTemplate.find(sessionId: session.id) {
            var w = CustomWorkout(duplicating: t)
            w.name = t.name
            return w
        }
        return nil
    }

    /// Generated sessions of this week (the ones a library workout can replace), with any current replacement.
    var replaceableSessions: [(generated: Session, current: Session)] {
        guard let base = state.plan, let current = plan else { return [] }
        return base.sessions.enumerated().map { i, s in (s, current.sessions.indices.contains(i) ? current.sessions[i] : s) }
    }

    /// Places `workout` into this week: replaces session `replacing` (any earlier replacement of it goes) or adds an extra session.
    @discardableResult
    func insertIntoPlan(_ workout: CustomWorkout, replacing: Int?, weekday: Int? = nil) -> PlanInsert? {
        guard var sp = state.synced, let base = state.plan else { return nil }
        var snapshot = workout.sanitized
        snapshot.visibility = .private
        snapshot.hidden = false
        let insert = PlanInsert(week: base.week, replacing: replacing, weekday: replacing == nil ? weekday : nil, workout: snapshot)
        var list = sp.planInserts ?? []
        if let r = replacing {
            for old in list where old.week == base.week && old.replacing == r { forgetProgress(old.sessionId) }
            list.removeAll { $0.week == base.week && $0.replacing == r }
            if base.sessions.indices.contains(r) { forgetProgress(base.sessions[r].id) }
        }
        list.append(insert)
        sp.planInserts = list
        state.synced = sp
        state.profileDirty = true
        persist()
        Task { await sync() }
        return insert
    }

    /// Takes a library workout back out of the plan; a replaced day returns to its generated session.
    func removePlanInsert(_ id: UUID) {
        guard var sp = state.synced, let ins = sp.planInserts?.first(where: { $0.id == id }) else { return }
        forgetProgress(ins.sessionId)
        sp.planInserts?.removeAll { $0.id == id }
        state.synced = sp
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    private func forgetProgress(_ sessionId: String) {
        guard state.done[sessionId] != true, let s = plan?.sessions.first(where: { $0.id == sessionId }) else { return }
        state.done[sessionId] = nil
        for b in s.blocks { for it in b.items { state.ticked[it.uid] = nil } }
    }
}
