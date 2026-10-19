import Foundation
import Observation
import WorkoutEngine

/// kg × reps · RIR rows for the exercise on screen in the player, shared by the current-set card (the only
/// place sets are entered, #206) and the effort picker. Reload with `load` whenever the player moves to another exercise.
@MainActor @Observable
final class SetLogState {
    struct Row: Equatable {
        var kg = ""
        var reps = ""
        var rir = ""
        var logged = false
    }

    struct Values: Equatable {
        var kg: Double
        var reps: Int
        var rir: Int?
    }

    private(set) var item: PlannedExercise?
    private(set) var sessionId = ""
    var rows: [Row] = []
    private(set) var suggestion: LoadSuggestion?
    /// Lift Focus block or Pro Sets style sets (#499), one per row; nil = straight sets.
    private(set) var planned: [PlannedSet]?

    /// Weight step of the kg stepper (equipment-aware: 2.5 barbell, 1 dumbbell, …).
    var kgStep: Double {
        guard let item else { return 2.5 }
        let kg = rows.first.flatMap { Self.parseKg($0.kg) } ?? 20
        return LoadAdvisor.steps(for: Exercise.get(item.exerciseId), kg: kg).granularity
    }

    func load(item: PlannedExercise, sessionId: String, model: AppModel) {
        self.item = item
        self.sessionId = sessionId
        let s = model.loadSuggestion(for: item, sessionId: sessionId)
        suggestion = s
        let logged = model.todaysSets(exerciseId: item.exerciseId, sessionId: sessionId)
        let kg = s.map { LoadAdvisor.formatKg($0.kg) } ?? model.lastWeight(item.exerciseId).map { LoadAdvisor.formatKg($0) } ?? ""
        var reps = ""
        if let r = s?.reps ?? item.prescription.repRange?.low { reps = String(r) }
        let sets = model.plannedSets(for: item, sessionId: sessionId, workingKg: Self.parseKg(kg))
        planned = sets
        rows = (0..<max(1, item.prescription.sets)).map { i in
            let p = sets?.indices.contains(i) == true ? sets?[i] : nil
            let rowKg = p?.kg.map { LoadAdvisor.formatKg($0) } ?? kg
            let rowReps = p?.reps.map { String($0) } ?? reps
            guard let l = logged[i] else { return Row(kg: rowKg, reps: rowReps) }
            return Row(
                kg: l.weightKg.map { LoadAdvisor.formatKg($0) } ?? rowKg,
                reps: l.reps.map { String($0) } ?? rowReps,
                rir: l.rir.map { String($0) } ?? "",
                logged: true)
        }
    }

    static func parseKg(_ s: String) -> Double? {
        guard let kg = Double(s.replacingOccurrences(of: ",", with: ".")), kg >= 0, kg <= 1000 else { return nil }
        return kg
    }

    func values(_ i: Int) -> Values? {
        guard rows.indices.contains(i), let kg = Self.parseKg(rows[i].kg),
              let reps = Int(rows[i].reps), reps >= 0, reps <= 1000 else { return nil }
        return Values(kg: kg, reps: reps, rir: Int(rows[i].rir).map { min(10, max(0, $0)) })
    }

    /// Saves row `i` and carries its load forward to the sets not logged yet. Returns false when the row is incomplete.
    @discardableResult
    func log(_ i: Int, model: AppModel) -> Bool {
        guard let item, let v = values(i) else { return false }
        model.logSet(exerciseId: item.exerciseId, sessionId: sessionId, setIndex: i, kg: v.kg, reps: v.reps, rir: v.rir)
        rows[i].logged = true
        if let planned {
            // Pro Sets: later sets keep their own loads; back-offs follow the top set's weight and effort.
            if planned.indices.contains(i), planned[i].role == .top {
                let e = Exercise.get(item.exerciseId)
                for j in rows.indices where j > i && !rows[j].logged && planned.indices.contains(j) && planned[j].role == .backoff {
                    let kg = ProSets.backoffKg(topKg: v.kg, topReps: v.reps, topRIR: v.rir,
                                               backoffReps: planned[j].reps ?? v.reps, exercise: e)
                    rows[j].kg = LoadAdvisor.formatKg(kg)
                }
            }
        } else {
            for j in rows.indices where j > i && !rows[j].logged { rows[j].kg = rows[i].kg }
        }
        return true
    }

    /// Planned set of row `i` (#499).
    func plannedSet(_ i: Int) -> PlannedSet? {
        guard let planned, planned.indices.contains(i) else { return nil }
        return planned[i]
    }

    /// Rest after row `i`: the planned set's own (drops and minis are short), else `fallback`.
    func restAfter(_ i: Int, fallback: Int) -> Int { plannedSet(i)?.restSec ?? fallback }

    /// Warm-up ramp toward the first working set of a heavy barbell lift (#499).
    var warmups: [RampStep] {
        guard let item, let first = rows.first, let kg = Self.parseKg(first.kg) else { return [] }
        return ProSets.warmups(to: kg, exercise: Exercise.get(item.exerciseId))
    }

    /// One-tap effort for a set: stores RIR and re-saves the row.
    func setRIR(_ i: Int, _ rir: Int, model: AppModel) {
        guard rows.indices.contains(i) else { return }
        rows[i].rir = String(rir)
        log(i, model: model)
    }

    func stepKg(_ i: Int, by sign: Double) {
        guard rows.indices.contains(i) else { return }
        let step = kgStep
        let now = Self.parseKg(rows[i].kg) ?? 0
        rows[i].kg = LoadAdvisor.formatKg(LoadAdvisor.round(max(0, now + sign * step), to: step))
    }

    /// Weight said to the player mic (#412).
    func setKg(_ i: Int, _ kg: Double) {
        guard rows.indices.contains(i) else { return }
        rows[i].kg = LoadAdvisor.formatKg(min(1000, max(0, kg)))
    }

    func setReps(_ i: Int, _ reps: Int) {
        guard rows.indices.contains(i) else { return }
        rows[i].reps = String(min(1000, max(0, reps)))
    }

    func stepReps(_ i: Int, by delta: Int) {
        guard rows.indices.contains(i) else { return }
        rows[i].reps = String(min(1000, max(0, (Int(rows[i].reps) ?? 0) + delta)))
    }
}
