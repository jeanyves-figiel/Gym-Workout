import Foundation

/// Weekly challenge room (#626 C): one AMRAP 12′ for everyone all week, kit-free so it works anywhere. The week key
/// is the ISO 8601 week ("2026-W43"), the same string the server ranks scores by.
public enum WeeklyChallenge {
    /// Time cap of every challenge.
    public static let minutes = 12

    /// The rotation, one per week; moves read on the big-screen timer.
    public static let wods: [(name: String, moves: [String])] = [
        ("Monkey Mile", ["10 burpees", "15 air squats", "20 mountain climbers"]),
        ("Banana Split", ["8 push-ups", "12 lunges", "16 sit-ups"]),
        ("Jungle Gym", ["5 burpees", "10 jump squats", "15 V-ups"]),
        ("Silverback", ["10 push-ups", "20 walking lunges", "30″ plank"]),
        ("Vine Swing", ["12 jumping lunges", "12 pike push-ups", "12 tuck-ups"]),
        ("Canopy Climb", ["6 burpee broad jumps", "12 squats", "18 bicycle crunches"]),
        ("Treetop", ["10 skater jumps", "10 hand-release push-ups", "10 hollow rocks"]),
        ("Big Ape", ["7 burpees", "14 squat jumps", "21 flutter kicks"]),
    ]

    /// ISO week of `date` in the member's time zone.
    public static func key(for date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    /// The week's WOD as a timer: AMRAP 12′ with its moves.
    public static func wod(for key: String) -> WodTimer {
        let parts = key.split(separator: "-W")
        let n = (Int(parts.first ?? "") ?? 0) * 53 + (Int(parts.last ?? "") ?? 0)
        let w = wods[((n % wods.count) + wods.count) % wods.count]
        return WodTimer(id: "challenge-\(key)", name: w.name, kind: .amrap, work: minutes * 60, moves: w.moves)
    }

    /// Server score order: rounds first, then extra reps.
    public static func score(rounds: Int, reps: Int) -> Int { rounds * 1000 + reps }
}
