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

    /// What the paused freestyle workout holds (#997), for its Resume tile: "3 exercises · 4 sets done".
    var freestyleResumeLine: String? {
        guard let s = freestyleInProgress, let run = activeWorkout(s.id) else { return nil }
        return Freestyle.resumeLine(exercises: s.blocks.flatMap(\.items).count, setsDone: run.setsDone.values.reduce(0, +))
    }

    /// A new empty workout to open in the player.
    func startFreestyle() -> Session {
        let s = Freestyle.session()
        if let old = state.freestyle, state.activeWorkout?.sessionId == old.id { state.activeWorkout = nil }
        state.freestyle = s
        persist()
        return s
    }

    /// A discarded freestyle workout once its Undo bar is gone (#903): its paused run and list go, so Train offers a new
    /// custom gym session instead of Resume. One with a run (Undo kept it) stays.
    func dropFreestyle(_ id: String) {
        guard state.freestyle?.id == id, activeWorkout(id) == nil else { return }
        state.freestyle = nil
        persist()
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

    /// One more (or one less) set on a freestyle exercise while doing it (#795).
    func setFreestyleSets(_ sessionId: String, uid: String, sets: Int) {
        guard let s = freestyleSession(sessionId) else { return }
        saveFreestyle(sessionId, blocks: Freestyle.settingSets(sets, of: uid, in: s.blocks))
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

    /// Film my workout (#952): the filmed moves become a custom gym session, every set logged and the workout saved to
    /// history at once. A custom session paused in the player is left alone. Nil when nothing was filmed.
    @discardableResult
    func recordFilmed(_ moves: [FilmedMove], startedAt: Date, endedAt: Date = Date()) -> WorkoutRecord? {
        let moves = moves.filter { !$0.sets.isEmpty }
        guard !moves.isEmpty else { return nil }
        var s = Freestyle.session()
        var done: [String: Int] = [:]
        for m in moves {
            let added = Freestyle.adding(Exercise.get(m.exerciseId), to: s.blocks, sessionId: s.id)
            guard let uid = added.uid else { continue }
            s.blocks = Freestyle.settingSets(m.sets.count, of: uid, in: added.blocks)
            done[uid] = m.sets.count
            for (i, set) in m.sets.enumerated() {
                logSet(exerciseId: m.exerciseId, sessionId: s.id, setIndex: i, kg: set.kg, reps: set.reps, rir: nil)
            }
        }
        s.estMin = max(1, Int((Double(s.blocks.estSec) / 60).rounded()))
        if freestyleInProgress == nil {
            state.freestyle = s
            persist()
        }
        return recordWorkout(session: s, setsDone: done, startedAt: startedAt, endedAt: endedAt, bodyMassKg: body.weightKg)
    }
}
