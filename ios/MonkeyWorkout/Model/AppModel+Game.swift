import Foundation
import WorkoutEngine

/// Game layer (#227): XP, level and badges from the whole history, the same numbers the Watch shows.
extension AppModel {
    var gameTarget: Int { profile?.sessionsPerWeek ?? 3 }

    /// Walking and stairs (Daily Move, #454) add their XP on top of the workouts.
    var game: GameProgress {
        let version = observedStateVersion
        let moveXP = MoveStore.shared.xp + FuelStore.shared.xp
        if let c = derived.game, c.key == version, c.moveXP == moveXP { return c.value }
        let g = GameProgress.evaluate(records: state.history, targetPerWeek: gameTarget, moveXP: moveXP)
        derived.game = (version, moveXP, g)
        return g
    }

    /// Rank on the level ladder (#242).
    var rank: GameRank { .of(level: game.level) }

    var badges: [Badge] {
        let version = observedStateVersion
        if let c = derived.badges, c.key == version { return c.value }
        let b = Achievements.evaluate(records: state.history, weights: weightEntries, targetPerWeek: gameTarget)
        derived.badges = (version, b)
        return b
    }

    /// XP a planned session earns with every set done.
    func xp(for session: Session) -> Int {
        GameProgress.xp(sets: session.blocks.reduce(0) { $0 + $1.items.reduce(0) { $0 + max(1, $1.prescription.sets) } })
    }
}

// MARK: - Week chest reveal (#476)

/// The chest opens whichever way the goal-meeting workout was saved (player, Watch, logged later).
/// Only the iPhone player showed it, so Train reveals a chest the member hasn't seen open yet.
extension AppModel {
    private static let chestSeenKey = "game.chestSeenWeek"

    private var thisWeekStart: Date { Progression.weekStart(Date(), Progression.calendar()) }

    /// This week's session goal is met.
    var weekChestOpen: Bool {
        Progression.stats(records: state.history, weights: [], targetPerWeek: gameTarget).thisWeek >= max(1, gameTarget)
    }

    /// This week's chest opened but its reveal hasn't been shown on this device.
    var chestRevealPending: Bool {
        guard weekChestOpen else { return false }
        let seen = UserDefaults.standard.double(forKey: Self.chestSeenKey)
        return seen != thisWeekStart.timeIntervalSince1970
    }

    func markChestSeen() {
        UserDefaults.standard.set(thisWeekStart.timeIntervalSince1970, forKey: Self.chestSeenKey)
    }
}

// MARK: - Kind streaks + Wins you missed (#501)

extension AppModel {
    /// "Welcome back" after a break, or the Comeback quest still running.
    var comeback: Comeback? { Comeback.current(records: state.history) }

    func feel(of id: UUID) -> Feel? { state.feels?[id].flatMap(Feel.init(rawValue:)) }

    func setFeel(_ f: Feel, for id: UUID) {
        var all = state.feels ?? [:]
        all[id] = f.rawValue
        state.feels = all
        persist()
    }

    /// Three personal wins for a finished workout.
    func wins(for r: WorkoutRecord) -> [Win] {
        let feels = state.history.filter { $0.id != r.id && $0.startedAt < r.startedAt }
            .sorted { $0.startedAt < $1.startedAt }
            .compactMap { feel(of: $0.id) }
        return Wins.find(record: r, history: state.history, weights: weightEntries, targetPerWeek: gameTarget, feels: feels)
    }
}
