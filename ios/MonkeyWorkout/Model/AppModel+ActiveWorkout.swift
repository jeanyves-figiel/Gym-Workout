import Foundation
import WorkoutEngine

/// Pause / resume of the workout player (#57). Exercises only complete inside the player.
extension AppModel {
    /// Paused workout for this session, if any.
    func activeWorkout(_ sessionId: String) -> ActiveWorkout? {
        state.activeWorkout.flatMap { $0.sessionId == sessionId ? $0 : nil }
    }

    /// How long after going to the background a closed-by-iOS workout still counts as running (#359).
    static let interruptedWindow: TimeInterval = 3 * 3600

    /// Workout the player was running when iOS closed the app in the background, still within the window.
    func interruptedWorkout(now: Date = Date()) -> Session? {
        guard let w = state.activeWorkout, w.interrupted == true,
              now.timeIntervalSince(w.updatedAt) < Self.interruptedWindow else { return nil }
        return session(w.sessionId)
    }

    /// Fresh start: forget earlier completion of this session's exercises and any other paused workout.
    func beginWorkout(_ session: Session) {
        for b in session.blocks { for it in b.items { state.ticked[it.uid] = nil } }
        state.activeWorkout = ActiveWorkout(sessionId: session.id, index: 0, setsDone: [:], elapsed: 0, updatedAt: Date(), startedAt: Date())
        persist()
    }

    func saveActiveWorkout(_ w: ActiveWorkout) {
        var w = w
        // The player doesn't carry the start; the run it saves over does.
        if w.startedAt == nil, let cur = state.activeWorkout, cur.sessionId == w.sessionId { w.startedAt = cur.startedAt }
        guard state.activeWorkout != w else { return }
        state.activeWorkout = w
        persist()
    }

    func clearActiveWorkout(_ sessionId: String) {
        guard state.activeWorkout?.sessionId == sessionId else { return }
        state.activeWorkout = nil
        persist()
    }

    /// Start of the window a session's sets belong to (#716): the running workout's start (a workout past midnight
    /// keeps its sets, and a second run of the same session today never edits the first run's sets, #817), else the
    /// start of today. Runs saved before `startedAt` existed keep the start-of-today floor.
    func workoutWindowStart(_ sessionId: String, now: Date = Date()) -> Date {
        let today = Calendar.current.startOfDay(for: now)
        guard let w = activeWorkout(sessionId) else { return today }
        guard let start = w.startedAt else { return min(today, w.updatedAt.addingTimeInterval(-w.elapsed)) }
        return start.addingTimeInterval(-60)
    }

    /// A discarded run's sets go too (#817), as Undo workout does, so they don't sync, prefill the next run or count
    /// as records. Only logs of `sessionId` from the run's start; a run without a start keeps them.
    func dropRunLogs(_ run: ActiveWorkout) {
        guard let start = run.startedAt else { return }
        let from = start.addingTimeInterval(-60)
        let ids = Set(state.logs.filter { $0.sessionId == run.sessionId && $0.date >= from }.map(\.id))
        guard !ids.isEmpty else { return }
        state.logs.removeAll { ids.contains($0.id) }
        state.pendingLogIds.subtract(ids)
        state.deletedLogIds = (state.deletedLogIds ?? []).union(ids)
        persist()
        Task { await sync() }
    }

    /// Gym zones set during a workout (#352): re-plans once the player closed with no workout left running.
    func replanAfterWorkoutIfDone() {
        guard replanAfterWorkout, state.activeWorkout == nil, let p = profile else { return }
        replanAfterWorkout = false
        updateProfile(p)
    }
}
