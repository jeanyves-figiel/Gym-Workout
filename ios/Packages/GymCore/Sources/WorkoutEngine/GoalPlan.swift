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

    /// Training mix shares (power, strength, mobility, cardio), summing to 1.
    public var mixShares: (power: Double, strength: Double, mobility: Double, cardio: Double) {
        let m = config.mix.normalised
        return (m.power, m.strength, m.mobility, m.cardio)
    }
}

extension Profile {
    /// Picks a goal and applies its recommended sessions per week. Climbing days are kept;
    /// the climbing goal switches climbing on.
    public mutating func applyGoal(_ g: Goal) {
        goal = g
        sessionsPerWeek = g.recommendedSessions
        if g == .climbing && !climbs { climbs = true }
    }

    /// Whether the user climbs, independent of the goal. Off clears climbing days and weekdays;
    /// on starts at 2 days / week. Same signal as `Generator.isClimber` minus the goal.
    public var climbs: Bool {
        get { climbingDaysPerWeek > 0 || !climbingDays.isEmpty }
        set {
            if newValue {
                if climbingDaysPerWeek == 0 { climbingDaysPerWeek = 2 }
            } else {
                climbingDaysPerWeek = 0
                climbingWeekdays = nil
            }
        }
    }

    /// Session minutes this profile would get with `goal` at its recommended frequency.
    public func recommendedMinutes(for g: Goal) -> Int {
        var p = self
        p.applyGoal(g)
        return Generator.sessionMinutes(p)
    }
}
