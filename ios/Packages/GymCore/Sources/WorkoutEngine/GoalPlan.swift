/// What each goal recommends for the week, shown when picking a goal.
extension Goal {
    /// Sensible gym sessions per week for this goal.
    public var sessionRange: ClosedRange<Int> {
        switch self {
        case .balanced: 3...4
        case .build: 4...5
        case .strength: 3...4
        case .climbing: 2...3
        case .endurance: 3...5
        case .athletic: 3...4
        }
    }

    /// Default gym sessions per week; climbing keeps gym work light around climbing days.
    public var recommendedSessions: Int {
        switch self {
        case .balanced, .build, .endurance: 4
        case .strength, .athletic: 3
        case .climbing: 2
        }
    }

    /// Only the climbing goal schedules around climbing days.
    public var usesClimbing: Bool { self == .climbing }

    /// Training mix shares (power, strength, mobility, cardio), summing to 1.
    public var mixShares: (power: Double, strength: Double, mobility: Double, cardio: Double) {
        let m = config.mix.normalised
        return (m.power, m.strength, m.mobility, m.cardio)
    }
}

extension Profile {
    /// Picks a goal and applies its recommended week: sessions per week, and climbing only for the climbing goal.
    public mutating func applyGoal(_ g: Goal) {
        goal = g
        sessionsPerWeek = g.recommendedSessions
        if g.usesClimbing {
            if climbingDaysPerWeek == 0 { climbingDaysPerWeek = 2 }
        } else {
            clearClimbing()
        }
    }

    /// Drops climbing days when the goal does not use them.
    public mutating func normalizeForGoal() {
        if !goal.usesClimbing { clearClimbing() }
    }

    mutating func clearClimbing() {
        climbingDaysPerWeek = 0
        climbingWeekdays = nil
    }

    /// Session minutes this profile would get with `goal` at its recommended frequency.
    public func recommendedMinutes(for g: Goal) -> Int {
        var p = self
        p.applyGoal(g)
        return Generator.sessionMinutes(p)
    }
}
