import APIClient
import Foundation
import WorkoutEngine

/// Custom exercises (#52): local create/edit/archive with an offline queue, synced like custom workouts.
extension AppModel {
    /// Not archived, by name.
    var customExercises: [CustomExercise] {
        (state.customExerciseList ?? []).filter { !$0.archived }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func customExercise(_ id: UUID) -> CustomExercise? {
        state.customExerciseList?.first { $0.id == id }
    }

    /// Creates or replaces a custom exercise; returns what was stored.
    @discardableResult
    func saveCustomExercise(_ exercise: CustomExercise) -> CustomExercise {
        let e = exercise.sanitized
        var list = state.customExerciseList ?? []
        if let i = list.firstIndex(where: { $0.id == e.id }) { list[i] = e } else { list.append(e) }
        state.customExerciseList = list
        var pending = state.pendingCustomExerciseIds ?? []
        pending.insert(e.id)
        state.pendingCustomExerciseIds = pending
        persist()
        Task { await sync() }
        return e
    }

    /// Hides it from the picker; workouts and history that use it keep working.
    func archiveCustomExercise(_ id: UUID) {
        guard var e = customExercise(id) else { return }
        e.archived = true
        saveCustomExercise(e)
    }

    /// Pushes queued edits, then pulls the full list. Called from `sync()` (one sync at a time).
    func syncCustomExercises() async throws {
        let pendingIds = state.pendingCustomExerciseIds ?? []
        let pending = (state.customExerciseList ?? []).filter { pendingIds.contains($0.id) }
        state.pendingCustomExerciseIds = Set(pending.map(\.id))
        if !pending.isEmpty {
            // Failure keeps them queued (offline at the gym); `sync()` surfaces the error.
            try await api.pushCustomExercises(pending)
            for e in pending where customExercise(e.id) == e { state.pendingCustomExerciseIds?.remove(e.id) }
        }

        let remote = try await api.fetchCustomExercises(CustomExercise.self)
        let stillPending = state.pendingCustomExerciseIds ?? []
        let local = state.customExerciseList ?? []
        // Server copy wins unless a local edit is still queued. Local-only records are kept (never deleted).
        var byId = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        for r in remote where !stillPending.contains(r.id) { byId[r.id] = r }
        let merged = byId.values.sorted { $0.createdAt < $1.createdAt }
        if merged != local { state.customExerciseList = merged }
    }
}
