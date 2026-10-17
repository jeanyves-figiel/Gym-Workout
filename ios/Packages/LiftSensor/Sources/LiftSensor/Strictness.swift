import Foundation

/// How strict rep counting is (#410), from -2 (counts the smallest pushes) to +2 (only clear, full reps).
/// 0 is the normal level. The member's setting (Relaxed -1, Normal 0, Strict +1) plus what the Watch learned
/// for the exercise from Crown corrections.
public enum Strictness {
    public static let lowest = -2.0
    public static let highest = 2.0
    /// What corrections can add or take away for one exercise.
    public static let learnedLimit = 1.5
    /// One correction moves the exercise's level this much.
    public static let learnStep = 0.5

    /// Scale of the minimum range and minimum mean speed a rep needs.
    public static func factor(_ level: Double) -> Double {
        interpolate(level, [0.7, 0.85, 1, 1.25, 1.5])
    }

    /// Share of the set's median range a rep needs once there are 3 reps: drops unracking and fidgeting.
    public static func rangeShare(_ level: Double) -> Double {
        interpolate(level, [0, 0.2, 0.35, 0.45, 0.55])
    }

    /// `config` with the minimums of this level (from the config's normal values).
    public static func apply(_ level: Double, to config: SetAnalyzer.Config) -> SetAnalyzer.Config {
        var c = config
        let f = factor(level)
        c.minRange *= f
        c.minMeanVelocity *= f
        c.minRangeShare = rangeShare(level)
        return c
    }

    /// Level used for a set: the member's setting plus the exercise's learned part.
    public static func level(setting: Double, learned: Double) -> Double {
        min(highest, max(lowest, setting + learned))
    }

    /// The exercise's learned part after a set the member corrected: counted more than logged → stricter.
    public static func learn(_ learned: Double, counted: Int, logged: Int) -> Double {
        guard counted != logged, counted > 0 else { return learned }
        let next = learned + (counted > logged ? learnStep : -learnStep)
        return min(learnedLimit, max(-learnedLimit, next))
    }

    /// Linear between 5 values at levels -2…2.
    static func interpolate(_ level: Double, _ v: [Double]) -> Double {
        let x = min(highest, max(lowest, level)) - lowest
        let i = min(3, Int(x.rounded(.down)))
        let t = x - Double(i)
        return v[i] + (v[i + 1] - v[i]) * t
    }
}
