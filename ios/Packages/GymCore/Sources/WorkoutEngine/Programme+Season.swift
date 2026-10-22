import Foundation

// MARK: - Sport season blocks (#620 A): "Get ready for…" a sport, fitted to the season's first day

/// Sports with a pre-season block. Ski and climbing use the programmes they already had (Snow ready, Climber's power).
public enum SeasonSport: String, Codable, CaseIterable, Sendable, Identifiable {
    case ski, padel, climb, run, surf, football

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .ski: "Ski"
        case .padel: "Padel"
        case .climb: "Climb"
        case .run: "Run"
        case .surf: "Surf"
        case .football: "Football"
        }
    }

    public var emoji: String {
        switch self {
        case .ski: "⛷"
        case .padel: "🎾"
        case .climb: "🧗"
        case .run: "🏃"
        case .surf: "🏄"
        case .football: "⚽"
        }
    }

    public var programmeId: String {
        switch self {
        case .ski: "snow-ready"
        case .climb: "climbers-power"
        default: "season-\(rawValue)"
        }
    }

    /// Sports a member plays that point to this block.
    public var sports: Set<Sport> {
        switch self {
        case .ski: [.ski, .snowboard, .crossCountrySki]
        case .padel: [.padel, .tennis, .squash]
        case .climb: [.climbing]
        case .run: [.run, .trailRun]
        case .surf: [.surf]
        case .football: [.football, .basketball, .volleyball]
        }
    }

    public static func of(_ sport: Sport) -> SeasonSport? { allCases.first { $0.sports.contains(sport) } }
}

extension Programme {
    /// A sport season block (not Snow ready, which has its own ride picker).
    public var isSeason: Bool { id.hasPrefix("season-") }

    /// Weeks from this week to the week before the season's first day, clamped to what a season block can fit.
    public static func seasonWeeks(until firstDay: Date, now: Date, calendar cal: Calendar = Progression.calendar()) -> Int {
        let from = Progression.weekStart(now, cal), to = Progression.weekStart(firstDay, cal)
        let weeks = cal.dateComponents([.weekOfYear], from: from, to: to).weekOfYear ?? 0
        return min(seasonMaxWeeks, max(seasonMinWeeks, weeks))
    }

    public static let seasonMinWeeks = 5
    public static let seasonMaxWeeks = 12

    private typealias Item = ProgrammeSignature.Item
    private typealias Dose = ProgrammeSignature.Dose

    private static func seasonPhases(_ base: String, _ build: String, _ peak: String) -> [ProgrammePhase] {
        [
            ProgrammePhase(kind: .base, weeks: 3, note: base),
            ProgrammePhase(kind: .build, weeks: 2, note: build),
            ProgrammePhase(kind: .peak, weeks: 1, note: peak),
            ProgrammePhase(kind: .test, weeks: 1, note: "Test your main lifts"),
            ProgrammePhase(kind: .ease, weeks: 1, note: "Easy week, fresh for the season"),
        ]
    }

    private static func season(_ sport: SeasonSport, name: String, tagline: String, summary: String, symbol: String,
                               focus: [MuscleGroup], phases: [ProgrammePhase], signatures: [ProgrammeSignature],
                               lifts: [String]) -> Programme {
        Programme(id: sport.programmeId, name: name, tagline: tagline, summary: summary, symbol: symbol, palette: .power,
                  goal: .athletic, sessionsPerWeek: 3, split: .hybrid, method: .undulating, focusMuscles: focus,
                  phases: phases, signatures: signatures, lifts: lifts)
    }

    static let seasonPadel = season(
        .padel, name: "Padel ready", tagline: "Shoulders, wrists, lateral legs · 3× a week",
        summary: "Eight weeks before the season: rotator cuff and wrist armour for the smash and bandeja, lateral lunges and bounds for court movement, rotation power from the hips, then an easy week.",
        symbol: "figure.racquetball", focus: [.shoulders, .legs, .core],
        phases: seasonPhases("Shoulder and wrist armour, lateral legs", "Heavier legs, rotation power", "Fast feet: bounds and throws"),
        signatures: [
            ProgrammeSignature(id: "court-legs", name: "Court legs", replaces: [.fullLower, .lower, .legs, .fullPower],
                               phases: [.base, .build, .peak, .ease], items: [
                Item("goblet-squat", Dose(3, "8"), [.build: Dose(4, "6"), .ease: Dose(2, "8")]),
                Item("lateral-lunge", Dose(3, "8"), [.peak: Dose(3, "10")]),
                Item("lateral-bound", Dose(3, "6"), rest: 90, [.build: Dose(4, "6")]),
                Item("copenhagen-plank", Dose(3, "20 s"), rest: 60, [.build: Dose(3, "30 s")]),
            ]),
            ProgrammeSignature(id: "racket-shoulders", name: "Racket shoulders", replaces: [.fullUpper, .upper, .push, .pull],
                               phases: [.base, .build, .peak], items: [
                Item("cable-external-rotation", Dose(3, "12"), rest: 60),
                Item("face-pull", Dose(3, "15"), rest: 60),
                Item("landmine-press", Dose(3, "8"), [.build: Dose(4, "6")]),
                Item("rotational-throw", Dose(3, "6"), rest: 60, [.peak: Dose(4, "6")]),
                Item("pronation-supination", Dose(2, "15"), rest: 45),
            ]),
        ],
        lifts: ["goblet-squat", "landmine-press"])

    static let seasonRun = season(
        .run, name: "Run ready", tagline: "Calves, single leg, hips · 3× a week",
        summary: "Eight weeks of strength for runners: calves and soleus for the miles, single-leg work and glute med for knees and hips, a little plyometric spring, then an easy week before race season.",
        symbol: "figure.run", focus: [.legs, .hips],
        phases: seasonPhases("Calves, single leg, hip stability", "Heavier single leg, first hops", "Spring: bounds and pogo-style hops"),
        signatures: [
            ProgrammeSignature(id: "runner-legs", name: "Runner legs", replaces: [.fullLower, .lower, .legs, .fullPower],
                               phases: [.base, .build, .peak, .ease], items: [
                Item("bulgarian-split-squat", Dose(3, "8"), [.build: Dose(4, "6"), .ease: Dose(2, "8")]),
                Item("single-leg-rdl", Dose(3, "8")),
                Item("seated-calf-raise", Dose(3, "15"), rest: 60),
                Item("standing-calf-raise", Dose(3, "12"), rest: 60),
                Item("side-lying-hip-abduction", Dose(2, "15"), rest: 45),
            ]),
            ProgrammeSignature(id: "runner-spring", name: "Spring + core", replaces: [.conditioning, .fullUpper, .upper],
                               phases: [.build, .peak], items: [
                Item("box-jump", Dose(4, "4"), rest: 90),
                Item("lateral-bound", Dose(3, "6"), rest: 90),
                Item("tib-raise", Dose(3, "15"), rest: 45),
                Item("dead-bug", Dose(3, "10"), rest: 45),
            ]),
        ],
        lifts: ["bulgarian-split-squat", "single-leg-rdl"])

    static let seasonSurf = season(
        .surf, name: "Surf ready", tagline: "Paddle back, pop-up, balance · 3× a week",
        summary: "Eight weeks before your surf trip: pulling endurance and shoulder health for paddling, push-ups and hip mobility for fast pop-ups, single-leg balance for riding, then an easy week.",
        symbol: "figure.surfing", focus: [.back, .shoulders, .core],
        phases: seasonPhases("Paddle endurance, shoulder health", "Stronger pulls, explosive pop-ups", "Long paddle sets"),
        signatures: [
            ProgrammeSignature(id: "paddle-back", name: "Paddle back", replaces: [.fullUpper, .upper, .pull, .backBi],
                               phases: [.base, .build, .peak, .ease], items: [
                Item("lat-pulldown", Dose(3, "12"), [.build: Dose(4, "8"), .peak: Dose(3, "20")]),
                Item("prone-ytw", Dose(3, "8"), rest: 60),
                Item("band-pull-apart", Dose(3, "15"), rest: 45),
                Item("plyo-push-up", Dose(3, "5"), rest: 90, [.peak: Dose(4, "5")]),
            ]),
            ProgrammeSignature(id: "ride-balance", name: "Ride + balance", replaces: [.fullLower, .lower, .legs],
                               phases: [.base, .build, .peak], items: [
                Item("cossack-squat", Dose(3, "6")),
                Item("skater-squat", Dose(3, "6")),
                Item("landmine-rotation", Dose(3, "8"), rest: 60),
                Item("side-plank", Dose(3, "30 s"), rest: 45),
            ]),
        ],
        lifts: ["lat-pulldown", "cossack-squat"])

    static let seasonFootball = season(
        .football, name: "Match ready", tagline: "Speed, hamstrings, groin · 3× a week",
        summary: "Eight weeks of pre-season for team sports: Nordic curls and Copenhagen planks for hamstrings and groin, strong legs for sprints and duels, jumps for speed, then an easy week before the first match.",
        symbol: "figure.soccer", focus: [.legs, .hips, .core],
        phases: seasonPhases("Hamstring and groin armour, strong legs", "Heavier legs, sprint power", "Speed: jumps and bounds"),
        signatures: [
            ProgrammeSignature(id: "match-legs", name: "Match legs", replaces: [.fullLower, .lower, .legs, .fullPower],
                               phases: [.base, .build, .peak, .ease], items: [
                Item("trap-bar-deadlift", Dose(4, "5"), rest: 150, [.build: Dose(5, "3"), .ease: Dose(2, "5")]),
                Item("nordic-curl", Dose(3, "5"), rest: 120),
                Item("copenhagen-plank", Dose(3, "20 s"), rest: 60, [.build: Dose(3, "30 s")]),
                Item("reverse-lunge", Dose(3, "8")),
            ]),
            ProgrammeSignature(id: "match-speed", name: "Speed + core", replaces: [.conditioning, .fullUpper, .upper],
                               phases: [.build, .peak], items: [
                Item("broad-jump", Dose(4, "4"), rest: 90),
                Item("lateral-bound", Dose(3, "6"), rest: 90),
                Item("pallof-press", Dose(3, "10"), rest: 45),
                Item("hanging-knee-raise", Dose(3, "10"), rest: 45),
            ]),
        ],
        lifts: ["trap-bar-deadlift", "reverse-lunge"])

    static let seasonBlocks: [Programme] = [seasonPadel, seasonRun, seasonSurf, seasonFootball]
}
