import Foundation
import WorkoutEngine

/// Learning the member's exercise likes and dislikes (#299): swaps, edits before starting and finished workouts
/// feed `MemberTaste`; the plan uses it from the next new week (`SyncedProfile.weekTaste`).
extension AppModel {
    var memberTaste: MemberTaste { state.synced?.taste ?? MemberTaste() }

    /// Records signals; the caller persists and syncs.
    func learnTaste(_ change: (inout MemberTaste) -> Void) {
        guard state.synced != nil else { return }
        var t = memberTaste
        change(&t)
        state.synced?.taste = t.isEmpty ? nil : t
        state.profileDirty = true
    }
}
