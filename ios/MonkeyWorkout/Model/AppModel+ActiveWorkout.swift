import Foundation
import WorkoutEngine

/// Pause / resume of the workout player (#57). Exercises only complete inside the player.
extension AppModel {
    /// Paused workout for this session, if any.
    func activeWorkout(_ sessionId: String) -> ActiveWorkout? {
        state.activeWorkout.flatMap { $0.sessionId == sessionId ? $0 : nil }
    }

    /// Fresh start: forget earlier completion of this session's exercises and any other paused workout.
    func beginWorkout(_ session: Session) {
        for b in session.blocks { for it in b.items { state.ticked[it.uid] = nil } }
        state.activeWorkout = ActiveWorkout(sessionId: session.id, index: 0, setsDone: [:], elapsed: 0, updatedAt: Date())
        persist()
    }

    func saveActiveWorkout(_ w: ActiveWorkout) {
        guard state.activeWorkout != w else { return }
        state.activeWorkout = w
        persist()
    }

    func clearActiveWorkout(_ sessionId: String) {
        guard state.activeWorkout?.sessionId == sessionId else { return }
        state.activeWorkout = nil
        persist()
    }
}
