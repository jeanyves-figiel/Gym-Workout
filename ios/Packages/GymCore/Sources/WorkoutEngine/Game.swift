import Foundation

/// Game layer shared by the iPhone and the Watch (#219, #227): XP, level and weeks cleared, from history.
/// Badges are `Achievements` (one set on both devices). Pure and deterministic.
public struct GameProgress: Sendable, Equatable {
    public static let perLevel = 500
    /// XP for one workout: 50 + 5 per set done.
    public static let perWorkout = 50
    public static let perSet = 5
    /// Extra XP the first time a week's session goal is met (quest chest).
    public static let weekBonus = 200

    public var xp = 0
    public var workouts = 0
    public var totalSets = 0
    /// Weeks where the session goal was met.
    public var weeksCleared = 0

    public init(xp: Int = 0, workouts: Int = 0, totalSets: Int = 0, weeksCleared: Int = 0) {
        self.xp = xp
        self.workouts = workouts
        self.totalSets = totalSets
        self.weeksCleared = weeksCleared
    }

    public static func xp(sets: Int) -> Int { perWorkout + perSet * max(0, sets) }

    public var level: Int { xp / Self.perLevel + 1 }
    public var xpInLevel: Int { xp % Self.perLevel }
    public var xpToNext: Int { Self.perLevel - xpInLevel }
    public var levelProgress: Double { Double(xpInLevel) / Double(Self.perLevel) }

    /// Rank names of the level ladder (#242); same thresholds as `GameRank` in WatchShared.
    public var rank: String {
        switch level {
        case ..<3: "Rookie"
        case ..<8: "Regular"
        case ..<15: "Iron"
        case ..<25: "Steel"
        case ..<40: "Titan"
        default: "Legend"
        }
    }

    public static func evaluate(records: [WorkoutRecord], targetPerWeek: Int,
                                calendar cal: Calendar = Progression.calendar()) -> GameProgress {
        var g = GameProgress()
        var perWeek: [Date: Int] = [:]
        for r in records {
            g.workouts += 1
            g.totalSets += r.totalSets
            g.xp += xp(sets: r.totalSets)
            perWeek[Progression.weekStart(r.startedAt, cal), default: 0] += 1
        }
        g.weeksCleared = perWeek.values.filter { $0 >= max(1, targetPerWeek) }.count
        g.xp += weekBonus * g.weeksCleared
        return g
    }
}

/// What one finished workout earned: compare the game before and after recording it.
public struct GameReward: Sendable, Equatable {
    public var xp: Int
    public var levelUp: Int?
    /// The week's session goal was met by this workout (+`GameProgress.weekBonus`).
    public var weekCleared: Bool
    public var badges: [Badge]

    public init(xp: Int, levelUp: Int? = nil, weekCleared: Bool = false, badges: [Badge] = []) {
        self.xp = xp
        self.levelUp = levelUp
        self.weekCleared = weekCleared
        self.badges = badges
    }

    public init(before: GameProgress, after: GameProgress, badgesBefore: [Badge], badgesAfter: [Badge]) {
        let had = Set(badgesBefore.filter(\.unlocked).map(\.id))
        self.init(xp: max(0, after.xp - before.xp),
                  levelUp: after.level > before.level ? after.level : nil,
                  weekCleared: after.weeksCleared > before.weeksCleared,
                  badges: badgesAfter.filter { $0.unlocked && !had.contains($0.id) })
    }
}
