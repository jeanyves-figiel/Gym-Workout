import Foundation
import WorkoutEngine

/// Editing a workout's exercise list before starting it (#295): plan days, extras, quick sessions and library workouts.
extension AppModel {
    /// The session as planned or as the library has it, before the member's edit.
    func uneditedSession(_ id: String) -> Session? {
        uneditedPlan?.sessions.first { $0.id == id } ?? standaloneSession(id)
    }

    /// The member's edit of `id`, when it still fits the session it was made on.
    func sessionEdit(_ id: String) -> SessionEdit? {
        guard let edit = state.synced?.sessionEdits?.first(where: { $0.sessionId == id }),
              let base = uneditedPlan?.sessions.first(where: { $0.id == id }) ?? standaloneSession(id),
              edit.base == base.editBase else { return nil }
        return edit
    }

    /// The list the edit sheet starts from: planned, with the member's edit, without today's readiness easing.
    func editableBlocks(_ id: String) -> [Block]? {
        uneditedSession(id).map { $0.applying(sessionEdit(id)).blocks }
    }

    /// A freestyle workout (#490) is all the member's own: Undo puts its list back as it was.
    func isEdited(_ id: String) -> Bool { sessionEdit(id) != nil || freestyleSession(id) != nil }

    /// Exercises can change until the workout starts; a finished one stays as it was done.
    func canEditExercises(_ s: Session) -> Bool {
        activeWorkout(s.id) == nil && state.done[s.id] != true && uneditedSession(s.id) != nil
    }

    /// Saves the edited exercise list; the unedited list back clears the edit.
    func saveSessionEdit(_ id: String, blocks: [Block]) {
        if freestyleSession(id) != nil { return saveFreestyle(id, blocks: blocks) }
        guard let base = uneditedSession(id) else { return }
        if let before = editableBlocks(id) { learnTaste { $0.learn(edit: before, blocks, at: Date()) } }
        guard var sp = state.synced else { return }
        var list = (sp.sessionEdits ?? []).filter { $0.sessionId != id }
        if blocks != base.blocks {
            let week = uneditedPlan?.sessions.contains { $0.id == id } == true ? uneditedPlan?.week : nil
            list.append(SessionEdit(sessionId: id, week: week, base: base.editBase, blocks: blocks))
        }
        sp.sessionEdits = list.isEmpty ? nil : list
        state.synced = sp
        // Ticks of exercises no longer in the workout go.
        let kept = Set(blocks.flatMap(\.items).map(\.uid))
        for it in base.blocks.flatMap(\.items) where !kept.contains(it.uid) { state.ticked[it.uid] = nil }
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    /// Back to the workout as planned.
    func resetSessionEdit(_ id: String) {
        guard let base = uneditedSession(id) else { return dropSessionEdit(id) }
        saveSessionEdit(id, blocks: base.blocks)
    }

    func dropSessionEdit(_ id: String) {
        guard state.synced?.sessionEdits?.contains(where: { $0.sessionId == id }) == true else { return }
        state.synced?.sessionEdits?.removeAll { $0.sessionId == id }
        if state.synced?.sessionEdits?.isEmpty == true { state.synced?.sessionEdits = nil }
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    /// Swap from the session page (#295): a library workout or an already edited one changes its own list.
    func swapInSession(_ id: String, uid: String, to exerciseId: String) {
        guard var blocks = editableBlocks(id) else { return }
        blocks.swap(uid, to: exerciseId)
        saveSessionEdit(id, blocks: blocks)
    }

    /// Removes one exercise (#391), from the session page's menu or the player's Change sheet. Returns what Undo puts back:
    /// the edit before (nil = the workout as planned).
    @discardableResult
    func removeFromSession(_ id: String, uid: String) -> [Block]? {
        guard var blocks = editableBlocks(id) else { return nil }
        let before = isEdited(id) ? blocks : nil
        blocks.remove(uid)
        saveSessionEdit(id, blocks: blocks)
        return before
    }

    /// Undo of a removal: the edit as it was, or back to the plan.
    func restoreSessionEdit(_ id: String, to blocks: [Block]?) {
        if let blocks { saveSessionEdit(id, blocks: blocks) } else { resetSessionEdit(id) }
    }

    /// Whether the session page's Swap goes through the plan (kept swaps, variation) rather than the edit.
    func swapsThroughPlan(_ s: Session, uid: String) -> Bool {
        canSwap(uid: uid) && !isEdited(s.id)
    }
}
