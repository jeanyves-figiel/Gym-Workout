import Foundation
import WorkoutEngine

/// Game layer (#227): XP, level and badges from the whole history, the same numbers the Watch shows.
extension AppModel {
    var gameTarget: Int { profile?.sessionsPerWeek ?? 3 }

    var game: GameProgress { GameProgress.evaluate(records: state.history, targetPerWeek: gameTarget) }

    var badges: [Badge] { Achievements.evaluate(records: state.history, weights: weightEntries, targetPerWeek: gameTarget) }

    /// XP a planned session earns with every set done.
    func xp(for session: Session) -> Int {
        GameProgress.xp(sets: session.blocks.reduce(0) { $0 + $1.items.reduce(0) { $0 + max(1, $1.prescription.sets) } })
    }
}
