import APIClient
import Foundation
import WorkoutEngine

/// Per-set history and load suggestions derived from the synced weight logs.
extension AppModel {
    /// Logs with a weight, as engine set logs.
    var setLogs: [SetLog] {
        state.logs.compactMap { l in
            l.weightKg.map { SetLog(date: l.date, exerciseId: l.exerciseId, sessionId: l.sessionId, setIndex: l.setIndex, kg: $0, reps: l.reps, rir: l.rir) }
        }
    }

    /// Every session in which `exerciseId` was logged, oldest first.
    func exerciseSessions(_ exerciseId: String) -> [ExerciseSession] {
        LoadAdvisor.sessions(setLogs, exerciseId: exerciseId, records: state.history)
    }

    /// Planned item + the session it belongs to (this week's plan or an example workout).
    func plannedItem(uid: String) -> (item: PlannedExercise, sessionId: String)? {
        for s in plan?.sessions ?? [] {
            for b in s.blocks {
                if let it = b.items.first(where: { $0.uid == uid }) { return (it, s.id) }
            }
        }
        return nil
    }

    /// Suggested load for a planned exercise. Today's sets of the same session are ignored so the
    /// suggestion stays stable while the workout is being logged.
    func loadSuggestion(for item: PlannedExercise, sessionId: String) -> LoadSuggestion? {
        // PR attempts (single heavy sets) say nothing about the working-set rep range.
        let history = exerciseSessions(item.exerciseId).filter {
            !($0.sessionId == sessionId && Calendar.current.isDateInToday($0.date)) && !PRPlanner.isPRSession($0.sessionId)
        }
        let inPlan = plan?.sessions.contains { $0.id == sessionId } ?? false
        return LoadAdvisor.suggest(
            exercise: Exercise.get(item.exerciseId), prescription: item.prescription,
            week: plan?.week ?? 1, deload: inPlan && (plan?.deload ?? false), history: history)
    }

    /// Sets already logged today for this exercise in this session, by set index.
    func todaysSets(exerciseId: String, sessionId: String) -> [Int: LogEntry] {
        var out: [Int: LogEntry] = [:]
        for l in state.logs where l.exerciseId == exerciseId && l.sessionId == sessionId && Calendar.current.isDateInToday(l.date) {
            if let i = l.setIndex { out[i] = l }
        }
        return out
    }
}
