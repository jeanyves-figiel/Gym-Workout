import APIClient
import Foundation
import WorkoutEngine

/// Custom workouts (#28): local create/edit/delete with an offline queue, synced like workout history.
extension AppModel {
    /// Oldest first, so new workouts land at the bottom of "My workouts".
    var customWorkouts: [CustomWorkout] {
        (state.customWorkoutList ?? []).sorted { ($0.createdAt, $0.name) < ($1.createdAt, $1.name) }
    }

    func customWorkout(_ id: UUID) -> CustomWorkout? {
        state.customWorkoutList?.first { $0.id == id }
    }

    func customWorkout(sessionId: String) -> CustomWorkout? {
        state.customWorkoutList?.first { $0.sessionId == sessionId }
    }

    /// Creates or replaces a custom workout; returns what was stored.
    @discardableResult
    func saveCustomWorkout(_ workout: CustomWorkout) -> CustomWorkout {
        let w = workout.sanitized
        var list = state.customWorkoutList ?? []
        if let i = list.firstIndex(where: { $0.id == w.id }) { list[i] = w } else { list.append(w) }
        state.customWorkoutList = list
        var pending = state.pendingCustomWorkoutIds ?? []
        pending.insert(w.id)
        state.pendingCustomWorkoutIds = pending
        state.deletedCustomWorkoutIds?.remove(w.id)
        persist()
        Task { await sync() }
        return w
    }

    func deleteCustomWorkout(_ id: UUID) {
        guard let w = customWorkout(id) else { return }
        state.customWorkoutList?.removeAll { $0.id == id }
        state.pendingCustomWorkoutIds?.remove(id)
        var deleted = state.deletedCustomWorkoutIds ?? []
        deleted.insert(id)
        state.deletedCustomWorkoutIds = deleted
        state.done[w.sessionId] = nil
        for b in w.session.blocks { for it in b.items { state.ticked[it.uid] = nil } }
        persist()
        Task { await sync() }
    }

    /// Pushes queued deletes and edits, then pulls the full list (small) so deletes made on other devices apply too.
    /// Called from `sync()`, which guarantees a single sync at a time.
    func syncCustomWorkouts() async throws {
        for id in state.deletedCustomWorkoutIds ?? [] {
            try await api.deleteCustomWorkout(id)
            state.deletedCustomWorkoutIds?.remove(id)
        }

        let pendingIds = state.pendingCustomWorkoutIds ?? []
        let pending = (state.customWorkoutList ?? []).filter { pendingIds.contains($0.id) }
        // Ids without a local workout (deleted meanwhile) need no push.
        state.pendingCustomWorkoutIds = Set(pending.map(\.id))
        if !pending.isEmpty {
            // Failure keeps them queued (offline at the gym); `sync()` surfaces the error.
            try await api.pushCustomWorkouts(pending)
            // Only clear what is unchanged since the push started (an edit made meanwhile stays queued).
            for w in pending where customWorkout(w.id) == w { state.pendingCustomWorkoutIds?.remove(w.id) }
        }

        let remote = try await api.fetchCustomWorkouts(CustomWorkout.self)
        let stillPending = state.pendingCustomWorkoutIds ?? []
        let deleted = state.deletedCustomWorkoutIds ?? []
        let local = state.customWorkoutList ?? []
        // Server copy wins unless a local edit is still queued; ids gone from the server were deleted elsewhere.
        var merged = remote.filter { !stillPending.contains($0.id) && !deleted.contains($0.id) }
        merged += local.filter { stillPending.contains($0.id) }
        var seen = Set<UUID>()
        state.customWorkoutList = merged.filter { seen.insert($0.id).inserted }
    }
}
