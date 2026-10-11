import Foundation
import WorkoutEngine

/// What Undo restores after applying a variation.
struct VariationUndo: Equatable {
    var previous: PlanVariation?
    var days: Int
}

/// Member-steered "New variation" (#98): swaps chosen in a sheet, stored with the week, undoable.
extension AppModel {
    /// Swaps currently applied to this week's plan.
    var currentSwaps: [String: String] {
        guard let base = state.plan, let v = state.synced?.variation, v.applies(to: base) else { return [:] }
        return v.swaps
    }

    /// Generated sessions that may still change: not done and not replaced by a library workout.
    var variableSessions: [Session] {
        (plan?.sessions ?? []).filter { !(state.done[$0.id] ?? false) && !$0.isPlanInsert }
    }

    /// Swaps `request` would produce, for the preview.
    func previewVariation(_ request: VaryRequest) -> [String: String] {
        guard let base = state.plan, let profile else { return currentSwaps }
        return base.varied(request, profile: profile, current: currentSwaps)
    }

    /// The generated plan with `swaps` applied (no library inserts), for the preview.
    func plan(with swaps: [String: String]) -> WeekPlan? {
        guard let base = state.plan else { return nil }
        return base.applying(PlanVariation(week: base.week, seed: base.seed, swaps: swaps))
    }

    func applyVariation(_ swaps: [String: String], days: Int) {
        guard var sp = state.synced, let base = state.plan else { return }
        let previous = sp.variation.flatMap { $0.applies(to: base) ? $0 : nil }
        variationUndo = VariationUndo(previous: previous, days: days)
        // Ticks belong to the exercise that was ticked.
        let touched = Set(swaps.keys).union(previous.map { Array($0.swaps.keys) } ?? [])
        for uid in touched where swaps[uid] != previous?.swaps[uid] {
            state.ticked[uid] = nil
        }
        sp.variation = swaps.isEmpty ? nil : PlanVariation(week: base.week, seed: base.seed, swaps: swaps)
        save(sp)
    }

    func undoVariation() {
        guard let undo = variationUndo, var sp = state.synced else { return }
        variationUndo = nil
        sp.variation = undo.previous
        save(sp)
    }

    /// Back to the generated plan.
    func resetVariation() {
        applyVariation([:], days: 0)
    }

    private func save(_ sp: SyncedProfile) {
        state.synced = sp
        state.profileDirty = true
        persist()
        Task { await sync() }
    }
}
