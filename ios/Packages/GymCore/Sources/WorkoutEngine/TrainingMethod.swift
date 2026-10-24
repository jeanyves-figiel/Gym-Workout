import Foundation

/// How a plan progresses (#156), chosen in the training profile, separate from the goal: the goal picks what is
/// trained (mix, rep zones), the method how load and volume change over the cycle. Nil = `.block` (plans before #156).
public enum TrainingMethod: String, Codable, CaseIterable, Sendable, Identifiable {
    /// 4-week block: Base → Build → Peak → Deload, double progression.
    case block
    /// Daily undulating: each main lift rotates Heavy / Moderate / Light days across the week.
    case undulating
    /// Load set from logged reps in reserve each session; readiness eases today's session.
    case autoregulated
    /// Weekly hard sets per muscle climb through the cycle (MEV → MAV), then deload.
    case volume
    /// Few hard sets near failure, short sessions.
    case minimal
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .block: "Block periodization"
        case .undulating: "Daily undulating"
        case .autoregulated: "RIR autoregulated"
        case .volume: "Volume progression"
        case .minimal: "Minimal dose"
        }
    }

    public var blurb: String {
        switch self {
        case .block: "Base → Build → Peak → Deload, reps then load go up"
        case .undulating: "Heavy, moderate and light days for each lift"
        case .autoregulated: "Reps left in the tank set the load · readiness eases the day"
        case .volume: "Sets per muscle rise each week, then deload · hypertrophy"
        case .minimal: "2 hard sets per exercise · 40 min max"
        }
    }

    /// Plain-language detail and the main sources, shown under the cards.
    public var detail: String {
        switch self {
        case .block:
            "Intensity rises over three weeks, then a lighter week lets fatigue drop. Periodized plans beat non-periodized ones for strength (Williams 2017, Sports Med); deloads per Bell 2023 (Sports Med Open)."
        case .undulating:
            "Main lifts change rep zone from day to day: Heavy 3–5, your goal's Moderate range, Light 10–12. Similar or better strength gains than linear plans, especially for trained lifters (Rhea 2002, JSCR; Moesgaard 2022, Sports Med)."
        case .autoregulated:
            "Log reps left after each set: more than planned → load goes up, fewer → it comes down. On a low-readiness day today's session drops 1 RPE and an accessory set. RIR-based loading matched or beat fixed loading (Helms 2018, Front Physiol; Graham & Cleather 2021, JSCR)."
        case .volume:
            "Weekly hard sets per major muscle start near 10, climb to about 16, then deload. More weekly sets give more growth up to a point (Schoenfeld 2017, J Sports Sci; Baz-Valle 2022, J Hum Kinet); sets end 1–3 reps short of failure (Refalo 2023, Sports Med)."
        case .minimal:
            "Sessions capped at 40 min: up to 4 strength exercises, 2 hard sets each, supersets by default. Low-volume training near failure still builds strength and muscle (Iversen 2021, Sports Med; Androulakis-Korakakis 2020, Sports Med)."
        }
    }
}

extension Profile {
    /// Method in effect: the user's choice, else block periodization.
    public var trainingMethod: TrainingMethod { method ?? .block }

    /// Grouping recommended for this profile: minimal-dose plans superset by default, otherwise the goal's.
    public var defaultGrouping: Grouping { trainingMethod == .minimal ? .supersets : goal.defaultGrouping }
}

// MARK: - Daily undulating

/// Day type of a session in a daily-undulating plan.
public enum DayZone: Int, CaseIterable, Sendable {
    case heavy, moderate, light

    public var label: String {
        switch self {
        case .heavy: "Heavy day"
        case .moderate: "Moderate day"
        case .light: "Light day"
        }
    }

    /// Zone of the `occurrence`-th session (0-based) of a focus that first appears at `firstIndex` in the week:
    /// each repeat of a session type moves to the next zone, and different session types start on different zones.
    static func of(firstIndex: Int, occurrence: Int) -> DayZone {
        DayZone(rawValue: (firstIndex + occurrence) % 3) ?? .moderate
    }

    /// The goal's dose moved to this day's rep zone. Moderate keeps the goal's own dose.
    func dose(_ d: Dose, main: Bool) -> Dose {
        var d = d
        switch self {
        case .moderate: break
        case .heavy:
            if main { d.reps = "3–5"; d.repsMid = 4; d.restSec = max(d.restSec, 180) }
            else { d.reps = "6–8"; d.repsMid = 7; d.restSec = max(d.restSec, 90) }
            d.rpe = 8
        case .light:
            if main { d.reps = "10–12"; d.repsMid = 11; d.restSec = max(90, min(d.restSec, 120)); d.rpe = 7 }
            else { d.reps = "12–15"; d.repsMid = 13; d.restSec = min(d.restSec, 60); d.rpe = 8 }
        }
        return d
    }
}

// MARK: - Volume progression

/// Weekly hard-set targets per major muscle for `.volume` plans (#156).
public enum VolumeTargets {
    /// Muscles with a weekly target; others follow the plan.
    public static let tracked: [Muscle] = [.chest, .lats, .upperBack, .sideDelts, .biceps, .triceps, .quads, .hamstrings, .glutes]
    /// Hard sets per muscle per week by phase (Base, Build, Peak, Deload), intermediate.
    static let byPhase = [10, 13, 16, 6]
    /// Above target + this, accessory sets are trimmed.
    static let slack = 4.0
    /// Hard sets one muscle may get in one session.
    static let perSessionCap = 10.0
    static let maxSetsPerExercise = 5
    static let minSetsPerExercise = 2

    public static func target(week: Int, experience: Experience) -> Int {
        let base = byPhase[Generator.phaseIndex(week)]
        switch experience {
        case .beginner: return Int((Double(base) * 0.8).rounded())
        case .intermediate: return base
        case .advanced: return base + 2
        }
    }

    /// Hard sets per muscle in strength blocks: primary muscles count a full set, secondary half a set.
    public static func sets(_ sessions: [Session]) -> [Muscle: Double] {
        var out: [Muscle: Double] = [:]
        for s in sessions { for (m, v) in sets(s) { out[m, default: 0] += v } }
        return out
    }

    static func sets(_ s: Session) -> [Muscle: Double] {
        var out: [Muscle: Double] = [:]
        for b in s.blocks where b.kind == .strength {
            for it in b.items {
                guard let e = Exercise.find(it.exerciseId) else { continue }
                let n = Double(it.prescription.sets)
                for m in e.primary { out[m, default: 0] += n }
                for m in e.secondary { out[m, default: 0] += n * 0.5 }
            }
        }
        return out
    }

    /// Location of an accessory that may get more or fewer sets: not the main lift, not light prehab/core,
    /// not a superset partner riding another exercise's rest, counted in reps.
    struct Slot { let s: Int, b: Int, i: Int }

    static func adjustable(_ sessions: [Session], primary m: Muscle) -> [Slot] {
        var out: [Slot] = []
        for (si, s) in sessions.enumerated() {
            for (bi, b) in s.blocks.enumerated() where b.kind == .strength && b.title == "Strength" {
                for (ii, it) in b.items.enumerated() where ii > 0 && it.supersetWith == nil
                    && !Rules.lightPatterns.contains(it.slot) && it.prescription.repRange != nil {
                    guard let e = Exercise.find(it.exerciseId), e.primary.contains(m) else { continue }
                    out.append(Slot(s: si, b: bi, i: ii))
                }
            }
        }
        return out
    }

    /// Adds or removes accessory sets so each tracked muscle lands near this week's target, within the session
    /// time (≤ 115 % of the target length) and the per-session cap.
    static func balance(_ sessions: [Session], week: Int, experience: Experience) -> [Session] {
        var out = sessions
        let target = Double(self.target(week: week, experience: experience))
        func change(_ c: Slot, by delta: Int) {
            var it = out[c.s].blocks[c.b].items[c.i]
            let sets = it.prescription.sets
            let perSet = Double(max(0, it.estSec - Int(Generator.transitionSec))) / Double(max(1, sets))
            it.prescription.sets = sets + delta
            it.estSec = max(0, it.estSec + Int((perSet * Double(delta)).rounded()))
            out[c.s].blocks[c.b].items[c.i] = it
            out[c.s].estMin = Int(out[c.s].blocks.reduce(0) { $0 + $1.estMin }.rounded())
        }
        for m in tracked {
            var steps = 0
            while (sets(out)[m] ?? 0) < target - 0.25, steps < 40 {
                steps += 1
                let ok = adjustable(out, primary: m).filter { c in
                    let s = out[c.s]
                    return s.blocks[c.b].items[c.i].prescription.sets < maxSetsPerExercise
                        && (sets(s)[m] ?? 0) + 1 <= perSessionCap
                        && Double(s.estMin) < Double(s.targetMin) * 1.15
                }
                guard let c = ok.min(by: { out[$0.s].blocks[$0.b].items[$0.i].prescription.sets < out[$1.s].blocks[$1.b].items[$1.i].prescription.sets })
                else { break }
                change(c, by: 1)
            }
            steps = 0
            while (sets(out)[m] ?? 0) > target + slack, steps < 40 {
                steps += 1
                let ok = adjustable(out, primary: m).filter { out[$0.s].blocks[$0.b].items[$0.i].prescription.sets > minSetsPerExercise }
                guard let c = ok.max(by: { out[$0.s].blocks[$0.b].items[$0.i].prescription.sets < out[$1.s].blocks[$1.b].items[$1.i].prescription.sets })
                else { break }
                change(c, by: -1)
            }
        }
        return out
    }
}

// MARK: - Readiness

extension Session {
    /// Low-readiness version of this session (#156, RIR-autoregulated plans): 1 RPE lower on strength work,
    /// one set less on accessories and explosive work. The main lift keeps its sets; uids are unchanged.
    public func easedForReadiness() -> Session {
        // HIIT (#693): fewer intervals, a little more rest.
        if let h = hiit { return withHiit(h.eased()) }
        var s = self
        for b in s.blocks.indices where s.blocks[b].kind == .strength || s.blocks[b].kind == .power {
            let kind = s.blocks[b].kind
            for i in s.blocks[b].items.indices {
                var it = s.blocks[b].items[i]
                let isMain = kind == .strength && i == 0 && s.blocks[b].title == "Strength"
                let floor = kind == .power ? 2 : 1
                if !isMain && it.prescription.sets > floor {
                    let perSet = Double(it.estSec) / Double(it.prescription.sets)
                    it.prescription.sets -= 1
                    it.estSec = max(0, it.estSec - Int(perSet.rounded()))
                }
                if let rpe = it.prescription.rpeValue, kind == .strength {
                    it.prescription.intensity = it.prescription.intensity?
                        .replacingOccurrences(of: "RPE \(rpe)", with: "RPE \(max(5, rpe - 1))")
                }
                s.blocks[b].items[i] = it
            }
            if kind == .strength {
                s.blocks[b].note = ["Low readiness today: 1 RPE lower, one set less on accessories.", s.blocks[b].note]
                    .compactMap { $0 }.joined(separator: " ")
            }
        }
        s.estMin = Int(s.blocks.reduce(0) { $0 + $1.estMin }.rounded())
        return s
    }
}

extension WeekPlan {
    /// The plan with the sessions in `ids` eased for low readiness.
    public func easedForReadiness(_ ids: Set<String>) -> WeekPlan {
        guard !ids.isEmpty else { return self }
        var p = self
        p.sessions = p.sessions.map { ids.contains($0.id) ? $0.easedForReadiness() : $0 }
        return p
    }
}

extension Prescription {
    /// "RPE 8" → 8.
    var rpeValue: Int? { targetRIR.map { 10 - $0 } }
}

// MARK: - Sources

/// A peer-reviewed reference behind a training method (#156), shown on the method's Sources page.
public struct MethodSource: Hashable, Sendable, Identifiable {
    public let authors: String
    public let year: Int
    public let title: String
    /// Journal, volume(issue):pages.
    public let journal: String
    public var id: String { title }

    /// "Rhea MR et al. (2002)".
    public var short: String { "\(authors) (\(year))" }

    /// PubMed search for the exact title: stable without hard-coding DOIs.
    public var url: URL? {
        var c = URLComponents(string: "https://pubmed.ncbi.nlm.nih.gov/")
        c?.queryItems = [URLQueryItem(name: "term", value: "\"\(title)\"")]
        return c?.url
    }
}

extension TrainingMethod {
    public var sources: [MethodSource] {
        switch self {
        case .block: [
            MethodSource(authors: "Williams TD et al.", year: 2017,
                         title: "Comparison of periodized and non-periodized resistance training on maximal strength: a meta-analysis",
                         journal: "Sports Med 47(10):2083–2100"),
            MethodSource(authors: "Bell L et al.", year: 2023,
                         title: "Integrating deloading into strength and physique sports training programmes: an international Delphi consensus approach",
                         journal: "Sports Med Open 9:87"),
        ]
        case .undulating: [
            MethodSource(authors: "Rhea MR et al.", year: 2002,
                         title: "A comparison of linear and daily undulating periodized programs with equated volume and intensity for strength",
                         journal: "J Strength Cond Res 16(2):250–255"),
            MethodSource(authors: "Moesgaard L et al.", year: 2022,
                         title: "Effects of periodization on strength and muscle hypertrophy in volume-equated resistance training programs: a systematic review and meta-analysis",
                         journal: "Sports Med 52(7):1647–1666"),
            MethodSource(authors: "Harries SK et al.", year: 2015,
                         title: "Systematic review and meta-analysis of linear and undulating periodized resistance training programs on muscular strength",
                         journal: "J Strength Cond Res 29(4):1113–1125"),
        ]
        case .autoregulated: [
            MethodSource(authors: "Helms ER et al.", year: 2018,
                         title: "RPE vs. percentage 1RM loading in periodized programs matched for sets and repetitions",
                         journal: "Front Physiol 9:247"),
            MethodSource(authors: "Graham T, Cleather DJ", year: 2021,
                         title: "Autoregulation by \"repetitions in reserve\" leads to greater improvements in strength over a 12-week training program than fixed loading",
                         journal: "J Strength Cond Res 35(9):2451–2456"),
            MethodSource(authors: "Larsen S et al.", year: 2021,
                         title: "Effects of subjective and objective autoregulation methods for intensity and volume on enhancing maximal strength during resistance-training interventions: a systematic review",
                         journal: "PeerJ 9:e10663"),
        ]
        case .volume: [
            MethodSource(authors: "Schoenfeld BJ et al.", year: 2017,
                         title: "Dose-response relationship between weekly resistance training volume and increases in muscle mass: a systematic review and meta-analysis",
                         journal: "J Sports Sci 35(11):1073–1082"),
            MethodSource(authors: "Baz-Valle E et al.", year: 2022,
                         title: "A systematic review of the effects of different resistance training volumes on muscle hypertrophy",
                         journal: "J Hum Kinet 81:199–210"),
            MethodSource(authors: "Refalo MC et al.", year: 2023,
                         title: "Influence of resistance training proximity-to-failure on skeletal muscle hypertrophy: a systematic review with meta-analysis",
                         journal: "Sports Med 53(3):649–665"),
        ]
        case .minimal: [
            MethodSource(authors: "Iversen VM et al.", year: 2021,
                         title: "No time to lift? Designing time-efficient training programs for strength and hypertrophy: a narrative review",
                         journal: "Sports Med 51(10):2079–2095"),
            MethodSource(authors: "Androulakis-Korakakis P et al.", year: 2020,
                         title: "The minimum effective training dose required to increase 1RM strength in resistance-trained men: a systematic review and meta-analysis",
                         journal: "Sports Med 50(4):751–765"),
        ]
        }
    }
}
