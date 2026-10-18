import Foundation
import WorkoutEngine

/// Customisable Progress page (#444): the member's widget board, synced with the profile.
extension AppModel {
    /// What Progress shows: the member's board, else the default.
    var progressBoard: ProgressBoard { state.synced?.progressBoard ?? .classic }

    var progressBoardCustomised: Bool { state.synced?.progressBoard != nil }

    /// The member's sports for sport widgets, most important first: climbing for climbers, My sports,
    /// then sports with sessions.
    var progressSports: [Sport] {
        var out = (profile?.otherSports ?? []).map(\.sport)
        if profile.map(Generator.isClimber) ?? false || !climbLogs.isEmpty { out.insert(.climbing, at: 0) }
        for log in sportLogs where !out.contains(log.sport) { out.append(log.sport) }
        var seen = Set<Sport>()
        return out.filter { seen.insert($0).inserted }
    }

    func progressPreset(_ p: ProgressBoard.Preset) -> ProgressBoard { .preset(p, sports: progressSports) }

    /// Preset the current board matches, if any.
    var progressBoardPreset: ProgressBoard.Preset? {
        guard progressBoardCustomised else { return .classic }
        return ProgressBoard.Preset.allCases.first { progressBoard.matches(progressPreset($0)) }
    }

    /// Saves the board; the default one is stored as nil.
    func setProgressBoard(_ board: ProgressBoard?) {
        guard state.synced != nil else { return }
        let stored = board.flatMap { $0.matches(.classic) ? nil : $0 }
        guard state.synced?.progressBoard != stored else { return }
        state.synced?.progressBoard = stored
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    func editProgressBoard(_ change: (inout ProgressBoard) -> Void) {
        var b = progressBoard
        change(&b)
        setProgressBoard(b)
    }
}
