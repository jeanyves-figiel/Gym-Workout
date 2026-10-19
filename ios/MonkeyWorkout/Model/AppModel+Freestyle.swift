import Foundation
import WorkoutEngine

/// Build as I go (#490): a workout started empty, built one exercise at a time in the player. Kept on this device until
/// the next one starts; its record goes to history like any other workout.
extension AppModel {
    func freestyleSession(_ id: String) -> Session? {
        state.freestyle.flatMap { $0.id == id ? $0 : nil }
    }

    /// The freestyle workout paused in the player, to resume instead of starting another.
    var freestyleInProgress: Session? {
        guard let s = state.freestyle, activeWorkout(s.id) != nil, state.done[s.id] != true else { return nil }
        return s
    }

    /// A new empty workout to open in the player.
    func startFreestyle() -> Session {
        let s = Freestyle.session()
        if let old = state.freestyle, state.activeWorkout?.sessionId == old.id { state.activeWorkout = nil }
        state.freestyle = s
        persist()
        return s
    }

    /// Saves the freestyle workout's list (adds, swaps, removes); its time estimate follows.
    func saveFreestyle(_ id: String, blocks: [Block]) {
        guard var s = freestyleSession(id) else { return }
        s.blocks = blocks
        s.estMin = max(1, Int((Double(blocks.estSec) / 60).rounded()))
        state.freestyle = s
        persist()
    }

    /// Adds `exercise` at the end of the freestyle workout; returns its uid. `id` gives the uid, so a finish-early
    /// fit in the player can add the same item.
    @discardableResult
    func addToFreestyle(_ sessionId: String, _ exercise: Exercise, id: UUID = UUID()) -> String? {
        guard let s = freestyleSession(sessionId) else { return nil }
        let added = Freestyle.adding(exercise, to: s.blocks, sessionId: sessionId, id: id)
        saveFreestyle(sessionId, blocks: added.blocks)
        return added.uid
    }

    /// Exercises the member logged lately, newest first, without repeats.
    func recentExerciseIds(limit: Int = 20) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for l in state.logs.sorted(by: { $0.date > $1.date }) where seen.insert(l.exerciseId).inserted {
            out.append(l.exerciseId)
            if out.count == limit { break }
        }
        return out
    }

    /// The Coach's next picks for the freestyle workout: the gym's equipment, muscles not trained yet, lifts done before.
    func freestylePicks(_ sessionId: String) -> [Exercise] {
        guard let s = freestyleSession(sessionId), let p = profile else { return [] }
        return Freestyle.suggest(after: s.blocks, profile: p, recent: recentExerciseIds())
    }
}
