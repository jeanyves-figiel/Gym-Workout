import APIClient
import Foundation
import WorkoutEngine

/// Per-set history and load suggestions derived from the synced weight logs.
extension AppModel {
    /// Logs with a weight, as engine set logs.
    var setLogs: [SetLog] {
        let version = observedStateVersion
        if let c = derived.setLogs, c.key == version { return c.value }
        let logs = state.logs.compactMap { l in
            l.weightKg.map { SetLog(date: l.date, exerciseId: l.exerciseId, sessionId: l.sessionId, setIndex: l.setIndex, kg: $0, reps: l.reps, rir: l.rir) }
        }
        derived.setLogs = (version, logs)
        return logs
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

    /// Suggested load for a planned exercise. This workout's sets (today's, or since it began past midnight)
    /// are ignored so the suggestion stays stable while the workout is being logged.
    func loadSuggestion(for item: PlannedExercise, sessionId: String) -> LoadSuggestion? {
        let from = workoutWindowStart(sessionId)
        // PR attempts (single heavy sets) say nothing about the working-set rep range.
        let history = exerciseSessions(item.exerciseId).filter {
            !($0.sessionId == sessionId && $0.date >= from) && !PRPlanner.isPRSession($0.sessionId)
        }
        let inPlan = plan?.sessions.contains { $0.id == sessionId } ?? false
        let exercise = Exercise.get(item.exerciseId)
        if let s = LoadAdvisor.suggest(
            exercise: exercise, prescription: item.prescription,
            week: plan?.week ?? 1, deload: inPlan && (plan?.deload ?? false), history: history,
            method: profile?.trainingMethod ?? .block, now: Date()) {
            return s
        }
        // Never logged (#115): start from a related logged lift, else from body data and experience.
        let related = Set(setLogs.map(\.exerciseId)).subtracting([item.exerciseId]).compactMap { id in
            Exercise.find(id).map { e in (exercise: e, sessions: exerciseSessions(id).filter { !PRPlanner.isPRSession($0.sessionId) }) }
        }
        return StartingLoad.fromRelated(exercise: exercise, prescription: item.prescription, related: related)
            ?? StartingLoad.estimate(exercise: exercise, prescription: item.prescription, athlete: athlete)
    }

    /// Body data for first-time load estimates: the newest of Apple Health and logged measurements (#185),
    /// then what was entered in the app. Body fat gives lean mass; arm and thigh girth refine arm and leg work.
    var athlete: Athlete {
        let snap = health?.snapshot
        let sex: Athlete.Sex = switch body.sex ?? snap?.sex {
        case .female: .female
        case .male: .male
        default: .unspecified
        }
        let year = body.birthYear ?? snap?.birthYear
        let weight = measurementSeries(.weight).last?.value ?? snap?.weightKg ?? body.weightKg
        let fat = measurementSeries(.bodyFat).last?.value
        let lean = weight.flatMap { w in fat.map { w * (1 - $0 / 100) } } ?? snap?.leanKg
        let recent = measurements.filter { $0.date > Date().addingTimeInterval(-365 * 86_400) }
        return Athlete(
            bodyKg: weight, sex: sex,
            age: year.map { Calendar.current.component(.year, from: Date()) - $0 },
            experience: profile?.experience ?? .beginner,
            leanKg: lean,
            upperArmCm: recent.last { $0.girth(.upperArm) != nil }?.girth(.upperArm),
            thighCm: recent.last { $0.girth(.thigh) != nil }?.girth(.thigh))
    }

    /// Sets already logged in this workout (today, or since it began past midnight) for this exercise, by set index.
    func todaysSets(exerciseId: String, sessionId: String) -> [Int: LogEntry] {
        let from = workoutWindowStart(sessionId)
        var out: [Int: LogEntry] = [:]
        for l in state.logs where l.exerciseId == exerciseId && l.sessionId == sessionId && l.date >= from {
            if let i = l.setIndex { out[i] = l }
        }
        return out
    }
}
