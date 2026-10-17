import Foundation

// MARK: - Snow ready: pre-season ski / snowboard programme (#428)

/// What the member rides; picks the Snow ready variant.
public enum SnowRide: String, Codable, CaseIterable, Sendable, Identifiable {
    case ski, snowboard, both

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .ski: "Ski"
        case .snowboard: "Snowboard"
        case .both: "Both"
        }
    }

    public var programmeId: String {
        switch self {
        case .ski: "snow-ready-ski"
        case .snowboard: "snow-ready-board"
        case .both: "snow-ready"
        }
    }

    /// The ride a member's sports point to: ski and snowboard → both; nil when they do neither.
    public static func from(_ sports: [SportPlan]?) -> SnowRide? {
        let s = Set((sports ?? []).map(\.sport))
        switch (s.contains(.ski), s.contains(.snowboard)) {
        case (true, true): return .both
        case (true, false): return .ski
        case (false, true): return .snowboard
        default: return nil
        }
    }
}

extension Programme {
    /// Snow ready family: the catalog card (both) and its ski / snowboard variants.
    public var snowRide: SnowRide? { SnowRide.allCases.first { $0.programmeId == id } }

    public static func snowReady(_ ride: SnowRide) -> Programme {
        switch ride {
        case .ski: snowReadySki
        case .snowboard: snowReadyBoard
        case .both: snowReadyBoth
        }
    }

    /// Weeks from this week to the week before `firstDay` (the programme ends just before the first day on snow),
    /// clamped to what the programme can shrink or grow to.
    public static func snowWeeks(until firstDay: Date, now: Date, calendar cal: Calendar = Progression.calendar()) -> Int {
        let from = Progression.weekStart(now, cal), to = Progression.weekStart(firstDay, cal)
        let weeks = cal.dateComponents([.weekOfYear], from: from, to: to).weekOfYear ?? 0
        return min(snowMaxWeeks, max(snowMinWeeks, weeks))
    }

    /// Shortest Snow ready: Base and Build one week each, plus Peak, Test and Ease.
    public static let snowMinWeeks = 5
    public static let snowMaxWeeks = 16

    /// Default first day on snow: the start of the member's ski / snowboard season if set and still ahead, else the
    /// Saturday 8 weeks out.
    public static func defaultSnowDay(sports: [SportPlan]?, now: Date, calendar cal: Calendar = Progression.calendar()) -> Date {
        let months = (sports ?? []).filter { $0.sport == .ski || $0.sport == .snowboard }.flatMap { $0.seasonMonths ?? [] }
        let today = cal.startOfDay(for: now)
        let year = cal.component(.year, from: now)
        let starts = Set(months).flatMap { m in [year, year + 1].compactMap { cal.date(from: DateComponents(year: $0, month: m, day: 1)) } }
            .filter { $0 > today.addingTimeInterval(14 * 86_400) }
        // A season over the new year (Dec–Apr) starts in its first month after a gap, not in January.
        let seasonStart = starts.filter { d in
            let prev = cal.component(.month, from: cal.date(byAdding: .month, value: -1, to: d)!)
            return !months.contains(prev)
        }.min()
        if let s = seasonStart { return s }
        let out = cal.date(byAdding: .weekOfYear, value: 8, to: today)!
        let wd = cal.component(.weekday, from: out) // 7 = Saturday
        return cal.date(byAdding: .day, value: (7 - wd + 7) % 7, to: out)!
    }

    /// Season nudge (#428 C): the ride to suggest Snow ready for, when the member skis or snowboards, it is autumn
    /// (September – December), no programme runs and they have not looked at it this season.
    public static func snowNudge(sports: [SportPlan]?, running: Bool, seenSeason: Int?, now: Date,
                                 calendar cal: Calendar = Progression.calendar()) -> SnowRide? {
        guard !running, let ride = SnowRide.from(sports) else { return nil }
        let month = cal.component(.month, from: now)
        guard (9...12).contains(month), seenSeason != cal.component(.year, from: now) else { return nil }
        return ride
    }

    private typealias Item = ProgrammeSignature.Item
    private typealias Dose = ProgrammeSignature.Dose

    private static let snowPhases = [
        ProgrammePhase(kind: .base, weeks: 3, note: "Legs and knee armour: squats, single leg, Nordic, Copenhagen"),
        ProgrammePhase(kind: .build, weeks: 2, note: "Heavier legs, sideways jumps, landing control"),
        ProgrammePhase(kind: .peak, weeks: 1, note: "Long-run legs: longer sets, longer wall sits"),
        ProgrammePhase(kind: .test, weeks: 1, note: "Test your squat and split squat"),
        ProgrammePhase(kind: .ease, weeks: 1, note: "Easy week, fresh legs for day 1"),
    ]

    private static func snowLegs(_ id: String, finisher: Item) -> ProgrammeSignature {
        ProgrammeSignature(
            id: id, name: "Snow legs", replaces: [.fullLower, .lower, .legs, .fullPower],
            phases: [.base, .build, .peak, .ease],
            items: [
                Item("back-squat", Dose(4, "6"), rest: 150, [.build: Dose(5, "4"), .peak: Dose(3, "12"), .ease: Dose(2, "6")]),
                Item("bulgarian-split-squat", Dose(3, "8"), [.peak: Dose(3, "12"), .ease: Dose(2, "8")]),
                Item("nordic-curl", Dose(3, "5"), rest: 120, [.ease: Dose(2, "4")]),
                Item("wall-sit", Dose(3, "45 s"), rest: 60, [.build: Dose(3, "60 s"), .peak: Dose(3, "90 s"), .ease: Dose(2, "45 s")]),
                finisher,
            ])
    }

    private static func edge(_ id: String, name: String, items: [Item]) -> ProgrammeSignature {
        ProgrammeSignature(id: id, name: name, replaces: [.conditioning, .fullPower, .fullUpper, .upper], phases: [.base, .build, .peak],
                           items: items)
    }

    static let snowReadyBoth = Programme(
        id: "snow-ready", name: "Snow ready",
        tagline: "Legs, balance, knees · 3× a week",
        summary: "Eight weeks to get your legs ready for the slopes: strong quads for long runs, single-leg balance and sideways power for edging, Nordic and Copenhagen work to protect knees, then an easy week before your first day.",
        symbol: "snowflake", palette: .cardio,
        goal: .athletic, sessionsPerWeek: 3, split: .hybrid, method: .undulating, focusMuscles: [.legs, .core],
        phases: snowPhases,
        signatures: [
            Programme.snowLegs("snow-legs", finisher: Item("standing-calf-raise", Dose(3, "12"), rest: 60)),
            Programme.edge("edge-balance", name: "Edge + balance", items: [
                Item("lateral-bound", Dose(4, "6"), rest: 90, [.build: Dose(5, "6")]),
                Item("skater-squat", Dose(3, "6"), [.build: Dose(3, "8")]),
                Item("single-leg-rdl", Dose(3, "8")),
                Item("copenhagen-plank", Dose(3, "20 s"), rest: 60, [.build: Dose(3, "30 s"), .peak: Dose(3, "40 s")]),
                Item("pallof-press", Dose(3, "10"), rest: 60),
            ]),
        ],
        lifts: ["back-squat", "bulgarian-split-squat"])

    static let snowReadySki: Programme = {
        var p = Programme.snowReadyBoth
        p.id = "snow-ready-ski"
        p.tagline = "Ski · legs, balance, knees · 3× a week"
        p.symbol = "figure.skiing.downhill"
        p.summary = "Eight weeks to get your legs ready for skiing: strong quads for long runs, single-leg balance and sideways power for carving, Nordic and Copenhagen work to protect knees, then an easy week before your first day."
        p.signatures = [
            Programme.snowLegs("snow-legs", finisher: Item("standing-calf-raise", Dose(3, "12"), rest: 60)),
            Programme.edge("edge-balance", name: "Edge + balance", items: [
                Item("lateral-bound", Dose(4, "6"), rest: 90, [.build: Dose(5, "6")]),
                Item("skater-squat", Dose(3, "6"), [.build: Dose(3, "8")]),
                Item("lateral-lunge", Dose(3, "8")),
                Item("copenhagen-plank", Dose(3, "20 s"), rest: 60, [.build: Dose(3, "30 s"), .peak: Dose(3, "40 s")]),
                Item("side-plank", Dose(3, "30 s"), rest: 60),
            ]),
        ]
        return p
    }()

    static let snowReadyBoard: Programme = {
        var p = Programme.snowReadyBoth
        p.id = "snow-ready-board"
        p.tagline = "Snowboard · legs, balance, rotation · 3× a week"
        p.symbol = "figure.snowboarding"
        p.summary = "Eight weeks to get ready for snowboarding: strong legs for a low stance, soft landings, rotation and core for turns, Nordic and Copenhagen work to protect knees, then an easy week before your first day."
        p.signatures = [
            Programme.snowLegs("snow-legs", finisher: Item("squat-jump", Dose(3, "6"), rest: 90)),
            Programme.edge("edge-rotation", name: "Edge + rotation", items: [
                Item("lateral-bound", Dose(4, "6"), rest: 90, [.build: Dose(5, "6")]),
                Item("cossack-squat", Dose(3, "6"), [.build: Dose(3, "8")]),
                Item("rotational-throw", Dose(3, "6"), rest: 60),
                Item("copenhagen-plank", Dose(3, "20 s"), rest: 60, [.build: Dose(3, "30 s"), .peak: Dose(3, "40 s")]),
                Item("pallof-press", Dose(3, "10"), rest: 60),
            ]),
        ]
        return p
    }()
}
