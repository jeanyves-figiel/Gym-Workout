import Foundation

// MARK: - Hyrox ready: race prep across a season of races (#431)

extension Programme {
    public static let hyroxId = "hyrox-ready"
    public var isHyrox: Bool { id == Programme.hyroxId }

    private typealias Item = ProgrammeSignature.Item
    private typealias Dose = ProgrammeSignature.Dose

    /// One race block, standard length: Base, Build, Peak, a sim week, then race week.
    static let hyroxReady = Programme(
        id: hyroxId, name: "Hyrox ready",
        tagline: "Run + 8 stations · 4× a week",
        summary: "Nine weeks to race day: station strength, compromised runs and an engine day, paced from your goal time and loaded for your division. A half sim on your Watch shows where you stand, then a light race week.",
        symbol: "flag.checkered", palette: .warmup,
        goal: .athletic, sessionsPerWeek: 4, split: .hybrid, method: .undulating, focusMuscles: [.legs, .core],
        phases: [
            ProgrammePhase(kind: .base, weeks: 3, note: Note.base),
            ProgrammePhase(kind: .build, weeks: 3, note: Note.build),
            ProgrammePhase(kind: .peak, weeks: 1, note: Note.peak),
            ProgrammePhase(kind: .test, weeks: 1, note: Note.sim),
            ProgrammePhase(kind: .ease, weeks: 1, note: Note.race),
        ],
        signatures: [
            ProgrammeSignature(
                id: "station-strength", name: "Station strength", replaces: [.fullLower, .lower, .legs, .fullPower],
                phases: [.base, .build, .peak],
                items: [
                    Item("sled-sprint", Dose(4, "30 s"), rest: 120, [.build: Dose(5, "30 s"), .peak: Dose(4, "40 s")]),
                    Item("sled-drag", Dose(3, "30 s"), rest: 120, [.build: Dose(4, "30 s")]),
                    Item("sandbag-lunge", Dose(3, "16"), [.build: Dose(4, "20"), .peak: Dose(3, "24")]),
                    Item("kb-thruster", Dose(3, "15"), [.build: Dose(4, "20"), .peak: Dose(3, "25")]),
                    Item("farmer-carry", Dose(3, "45 s"), rest: 60, [.build: Dose(3, "60 s")]),
                ]),
            ProgrammeSignature(
                id: "compromised-run", name: "Compromised run", replaces: [.conditioning, .fullPower, .fullUpper],
                phases: [.base, .build, .peak],
                items: [
                    Item("treadmill-run", Dose(3, "1000 m"), rest: 0, [.build: Dose(4, "1000 m"), .peak: Dose(5, "1000 m")]),
                    Item("burpee", Dose(3, "40 s"), rest: 0, [.build: Dose(4, "45 s"), .peak: Dose(5, "45 s")]),
                    Item("kb-thruster", Dose(3, "15"), rest: 60, [.build: Dose(4, "20"), .peak: Dose(5, "20")]),
                ]),
            ProgrammeSignature(
                id: "engine", name: "Engine", replaces: [.conditioning, .upper, .fullUpper, .pull],
                phases: [.base, .build, .peak],
                items: [
                    Item("ski-erg", Dose(5, "500 m"), rest: 60, [.build: Dose(6, "500 m"), .peak: Dose(4, "1000 m")]),
                    Item("rower", Dose(5, "500 m"), rest: 60, [.build: Dose(6, "500 m"), .peak: Dose(4, "1000 m")]),
                    Item("plank", Dose(3, "45 s"), rest: 45),
                ]),
        ],
        lifts: [])

    private enum Note {
        static let base = "Station strength and an aerobic base"
        static let build = "Race pace: compromised runs, heavier sleds"
        static let peak = "Sharpest week: race-pace runs and stations"
        static let sim = "Sim week: a half Hyrox on your Watch, compared to your plan"
        static let race = "Race week: light, sharp, rested"
        static let recover = "Recovery after the race: easy runs and mobility"
    }

    /// Hyrox ready built around every race ahead (#431): the first block fits the first race (Base, Build, Peak, sim,
    /// race week); each gap to the next race gets its own block: 6+ weeks recovery, Build, Peak; 3–5 weeks recovery and
    /// a short Build; less, recovery then a sharpening week. The programme ends after the last race week.
    /// Races before this week are dropped; none ahead gives the standard programme.
    public static func hyroxSeason(races: [Date], now: Date, calendar cal: Calendar = Progression.calendar()) -> Programme {
        let monday = Progression.weekStart(now, cal)
        let weeks = Set(races.compactMap { d -> Int? in
            let w = cal.dateComponents([.weekOfYear], from: monday, to: Progression.weekStart(d, cal)).weekOfYear ?? -1
            return w >= 0 ? w : nil
        }).sorted()
        guard let first = weeks.first else { return hyroxReady }
        var phases: [ProgrammePhase] = []
        func add(_ kind: ProgrammePhaseKind, _ n: Int, _ note: String) {
            if n > 0 { phases.append(ProgrammePhase(kind: kind, weeks: n, note: note)) }
        }
        func raceWeek(_ w: Int) {
            let day = cal.date(byAdding: .weekOfYear, value: w, to: monday)!
            add(.ease, 1, Note.race + " (week of \(day.formatted(.dateTime.day().month(.abbreviated))))")
        }
        // First block: `first` weeks before the first race week.
        switch first {
        case 6...:
            let base = (first - 1) / 2
            add(.base, base, Note.base)
            add(.build, first - 2 - base, Note.build)
            add(.peak, 1, Note.peak)
            add(.test, 1, Note.sim)
        case 3...5:
            add(.build, first - 1, Note.build)
            add(.test, 1, Note.sim)
        default:
            add(.peak, first, Note.peak)
        }
        raceWeek(first)
        for (prev, next) in zip(weeks, weeks.dropFirst()) {
            let gap = next - prev - 1
            switch gap {
            case 6...:
                add(.ease, 1, Note.recover)
                add(.build, gap - 2, Note.build)
                add(.peak, 1, Note.peak)
            case 3...5:
                add(.ease, 1, Note.recover)
                add(.build, gap - 1, Note.build)
            default:
                add(.ease, min(1, gap), Note.recover)
                add(.peak, gap - 1, Note.peak)
            }
            raceWeek(next)
        }
        var p = hyroxReady
        p.phases = phases
        let n = weeks.count
        p.summary = n == 1
            ? "\(p.weeks) weeks fitted to race day: station strength, compromised runs and an engine day, paced from your goal time and loaded for your division, then a light race week."
            : "A \(p.weeks)-week season for your \(n) races: a full build to the first one, then each gap gets its own block (recovery, build, sharpen) so you peak again for every race."
        return p
    }

    /// The programme with each signature exercise's target (pace, load) set from `target` (#431 C).
    public func targeting(_ target: (String) -> String?) -> Programme {
        var p = self
        p.signatures = signatures.map { sig in
            var s = sig
            s.items = sig.items.map { it in
                var i = it
                i.target = target(it.exerciseId)
                return i
            }
            return s
        }
        return p
    }
}
