import APIClient
import Foundation
import WorkoutEngine

/// Personal-record attempts (#60): stored locally with an offline queue and synced, so a community feed can share them.
extension AppModel {
    /// Newest first.
    func prAttempts(_ exerciseId: String) -> [PRAttempt] {
        (state.prAttempts ?? []).filter { $0.exerciseId == exerciseId }.sorted { $0.date > $1.date }
    }

    /// Every record set, newest first (for sharing / a community feed).
    var personalRecords: [PRAttempt] {
        (state.prAttempts ?? []).filter { $0.success && $0.isRecord }.sorted { $0.date > $1.date }
    }

    /// Plan for an attempt from this exercise's logs and earlier attempts.
    func prPlan(_ exercise: Exercise, kind: PRKind, reps: Int, kg: Double? = nil) -> PRPlan {
        PRPlanner.plan(exercise: exercise, kind: kind, reps: reps, kg: kg, logs: prLogs(exercise.id), attempts: prAttempts(exercise.id))
    }

    /// Best before an attempt, for record detection.
    func prBest(_ exerciseId: String, kind: PRKind, reps: Int, kg: Double) -> Double? {
        PRPlanner.best(kind, reps: reps, kg: kg, logs: prLogs(exerciseId), attempts: prAttempts(exerciseId))
    }

    /// Logged sets of an exercise, excluding the copies of attempt sets (attempts are counted from `prAttempts`).
    private func prLogs(_ exerciseId: String) -> [SetLog] {
        setLogs.filter { $0.exerciseId == exerciseId && !PRPlanner.isPRSession($0.sessionId) }
    }

    /// Stores a finished attempt; made attempt sets are also logged so they show in the exercise history.
    func savePRAttempt(_ attempt: PRAttempt) {
        var list = state.prAttempts ?? []
        list.removeAll { $0.id == attempt.id }
        list.append(attempt)
        state.prAttempts = list
        var pending = state.pendingPRAttemptIds ?? []
        pending.insert(attempt.id)
        state.pendingPRAttemptIds = pending
        for (i, set) in attempt.sets.filter({ !$0.warmup && $0.made && $0.reps > 0 }).enumerated() {
            let entry = LogEntry(date: attempt.date, exerciseId: attempt.exerciseId, sessionId: attempt.sessionId,
                                 weightKg: set.kg, reps: set.reps, setIndex: i)
            state.logs.append(entry)
            state.pendingLogIds.insert(entry.id)
        }
        persist()
        Task { await sync() }
    }

    /// Removes the attempt and the logged copies of its sets (best effort on the server).
    func deletePRAttempt(_ id: UUID) {
        guard let attempt = state.prAttempts?.first(where: { $0.id == id }) else { return }
        let logIds = state.logs.filter { $0.sessionId == attempt.sessionId }.map(\.id)
        state.logs.removeAll { $0.sessionId == attempt.sessionId }
        state.pendingLogIds.subtract(logIds)
        Task { [api] in for l in logIds { try? await api.deleteLog(l) } }
        state.prAttempts?.removeAll { $0.id == id }
        state.pendingPRAttemptIds?.remove(id)
        var deleted = state.deletedPRAttemptIds ?? []
        deleted.insert(id)
        state.deletedPRAttemptIds = deleted
        persist()
        Task { await sync() }
    }

    /// Pushes queued deletes and new attempts, then pulls the full list. Called from `sync()`.
    func syncPRAttempts() async throws {
        for id in state.deletedPRAttemptIds ?? [] {
            try await api.deletePRAttempt(id)
            state.deletedPRAttemptIds?.remove(id)
        }
        let pendingIds = state.pendingPRAttemptIds ?? []
        let pending = (state.prAttempts ?? []).filter { pendingIds.contains($0.id) }
        if !pending.isEmpty {
            try await api.pushPRAttempts(pending)
            state.pendingPRAttemptIds?.subtract(pending.map(\.id))
        }
        let remote = try await api.fetchPRAttempts(PRAttempt.self)
        let stillPending = state.pendingPRAttemptIds ?? []
        let deleted = state.deletedPRAttemptIds ?? []
        var merged = remote.filter { !stillPending.contains($0.id) && !deleted.contains($0.id) }
        merged += (state.prAttempts ?? []).filter { stillPending.contains($0.id) }
        var seen = Set<UUID>()
        state.prAttempts = merged.filter { seen.insert($0.id).inserted }
    }
}
