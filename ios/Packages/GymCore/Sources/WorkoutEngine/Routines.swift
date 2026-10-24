import Foundation

/// Daily routines (#689, designs A + B from `daily-routines/proposals.png`): short routines to do any day, each in a
/// few lengths. A: two of them as daily tiles under Next up on Train; B: all of them in Explore → Routines.
/// The routine scales to the length picked: more moves, then longer holds or a second round.
public enum Routine: String, CaseIterable, Codable, Sendable, Identifiable {
    case stretch, hangs, morning, desk, bedtime
    /// More built-ins (#732), all from existing stretch and mobility moves.
    case hips, shoulders, rollout, legs, wrists, splits

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .stretch: "Full-body stretch"
        case .hangs: "Daily hangs"
        case .morning: "Morning mobility"
        case .desk: "Desk reset"
        case .bedtime: "Before bed"
        case .hips: "Hip opener"
        case .shoulders: "Shoulder care"
        case .rollout: "Roll out"
        case .legs: "Runner's legs"
        case .wrists: "Wrists & fingers"
        case .splits: "Splits & straddle"
        }
    }

    /// Tile title on Train.
    public var short: String {
        switch self {
        case .stretch: "Stretch"
        case .hangs: "Hangboard"
        case .morning: "Mobility"
        case .desk: "Desk reset"
        case .bedtime: "Before bed"
        case .hips: "Hips"
        case .shoulders: "Shoulders"
        case .rollout: "Roll out"
        case .legs: "Legs"
        case .wrists: "Wrists"
        case .splits: "Splits"
        }
    }

    public var tag: String {
        switch self {
        case .stretch: "No kit · calm"
        case .hangs: "Low load · every day"
        case .morning: "Wake up"
        case .desk: "Neck · hips"
        case .bedtime: "Slow · breathe"
        case .hips: "Pigeon · frog · lizard"
        case .shoulders: "CARs · sleeper · slides"
        case .rollout: "Foam roller · ball"
        case .legs: "Calves · quads · ankles"
        case .wrists: "Climb · desk · calm"
        case .splits: "Deep · flexibility"
        }
    }

    public var symbol: String {
        switch self {
        case .stretch: "figure.flexibility"
        case .hangs: "hand.raised.fill"
        case .morning: "sun.max.fill"
        case .desk: "laptopcomputer"
        case .bedtime: "moon.stars.fill"
        case .hips: "figure.cooldown"
        case .shoulders: "figure.arms.open"
        case .rollout: "cylinder.fill"
        case .legs: "figure.run"
        case .wrists: "hand.raised.fingers.spread.fill"
        case .splits: "figure.gymnastics"
        }
    }

    /// Lengths offered, in minutes.
    public var lengths: [Int] {
        switch self {
        case .stretch: [5, 10, 15, 20, 30]
        case .hangs: [5, 10, 15, 20]
        case .morning, .bedtime, .shoulders, .rollout, .legs: [5, 10, 15]
        case .hips: [5, 10, 15, 20]
        case .splits: [10, 15, 20, 30]
        case .desk, .wrists: [5, 10]
        }
    }

    public var defaultLength: Int {
        switch self {
        case .desk, .wrists: 5
        case .splits: 15
        default: 10
        }
    }

    /// Explore → Routines filter.
    public enum Kind: String, CaseIterable, Sendable { case stretch, hang, mobility, recovery }

    public var kind: Kind {
        switch self {
        case .stretch, .bedtime, .hips, .legs, .splits: .stretch
        case .hangs: .hang
        case .morning, .desk, .shoulders, .wrists: .mobility
        case .rollout: .recovery
        }
    }

    /// Daily tiles on Train before the member picks: hangboard for climbers, else morning mobility.
    public static func dailyDefaults(climber: Bool) -> [Routine] { climber ? [.stretch, .hangs] : [.stretch, .morning] }

    /// Starter pack on Train (#732 A): three routines to add in one tap.
    public static func starters(climber: Bool) -> [Routine] { climber ? [.stretch, .hangs, .hips] : [.stretch, .morning, .hips] }

    /// Coach pick of the day (#732 C): one routine matched to today. `focus` nil = rest day.
    public static func coachPick(focus: Focus?, climbing: Bool) -> (routine: Routine, why: String) {
        if climbing { return (.wrists, "Climb day · fingers and wrists") }
        guard let focus else { return (.rollout, "Rest day · roll it out") }
        switch focus {
        case .pull, .backBi, .chestBack: return (.shoulders, "Pull day · opens up after pulling")
        case .push, .chestTri, .shouldersArms: return (.shoulders, "Push day · shoulders and chest")
        case .upper, .fullUpper: return (.shoulders, "Upper day · shoulders")
        case .lower, .legs, .fullLower, .posterior, .fullPower: return (.hips, "Leg day · open the hips")
        case .conditioning: return (.legs, "Cardio day · calves and quads")
        }
    }

    /// Session ids are `example-routine-<routine>-<minutes>`; every length of a routine shares the prefix.
    public var sessionPrefix: String { WorkoutTemplate.idPrefix + "routine-\(rawValue)-" }

    public static func of(sessionId: String) -> Routine? { allCases.first { sessionId.hasPrefix($0.sessionPrefix) } }

    /// The routine at `minutes` (snapped to the nearest offered length).
    public func template(minutes: Int) -> WorkoutTemplate {
        let m = lengths.min { abs($0 - minutes) < abs($1 - minutes) } ?? defaultLength
        return Self.built[self]![m]!
    }

    /// Every routine at every length, so `WorkoutTemplate.find(sessionId:)` resolves them (session view, player, history).
    public static let templates: [WorkoutTemplate] = allCases.flatMap { r in r.lengths.map { built[r]![$0]! } }

    /// Days in a row, up to today, with this routine done (today not done yet keeps yesterday's streak).
    public func streak(_ days: Set<Date>, today: Date, calendar: Calendar) -> Int {
        Self.streak(days, today: today, calendar: calendar)
    }

    /// Same count for any routine's done days, own ones too (#732).
    public static func streak(_ days: Set<Date>, today: Date, calendar: Calendar) -> Int {
        var d = calendar.startOfDay(for: today)
        if !days.contains(d) { d = calendar.date(byAdding: .day, value: -1, to: d)! }
        var n = 0
        while days.contains(d) {
            n += 1
            d = calendar.date(byAdding: .day, value: -1, to: d)!
        }
        return n
    }

    // MARK: Building

    typealias Item = WorkoutTemplate.Item

    private static let built: [Routine: [Int: WorkoutTemplate]] = Dictionary(uniqueKeysWithValues: allCases.map { r in
        (r, Dictionary(uniqueKeysWithValues: r.lengths.map { ($0, r.make($0)) }))
    })

    private func wrap(_ minutes: Int, _ items: [Item]) -> WorkoutTemplate {
        WorkoutTemplate(id: "routine-\(rawValue)-\(minutes)", name: "\(label) · \(minutes)′",
                        focus: self == .hangs ? .pull : .fullLower, goal: .mobility,
                        kit: kit,
                        level: 1, main: self == .hangs ? .strength : .mobility, items: items)
    }

    private var kit: String {
        switch self {
        case .hangs: "Hangboard"
        case .rollout: "Foam roller"
        case .desk, .wrists: "No kit"
        default: "Mat"
        }
    }

    private func est(_ items: [Item]) -> Int { wrap(0, items).session.estMin }

    /// A move of a stretch or mobility routine: a drill (reps) or a hold (seconds, set by the length).
    private enum Move {
        case drill(String, Int)
        case hold(String)
    }

    private var pool: [Move] {
        switch self {
        case .stretch:
            [.drill("cat-cow", 8), .hold("downward-dog"), .hold("pigeon"), .hold("half-kneeling-hf"), .hold("hamstring-stretch"),
             .hold("pec-stretch"), .hold("childs-pose-reach"), .hold("supine-twist"), .hold("butterfly"), .hold("cross-body"),
             .hold("calf-wall"), .hold("lizard-stretch"), .hold("triceps-stretch"), .hold("figure-4"), .hold("sphinx"),
             .hold("side-bend"), .hold("seated-forward-fold"), .hold("forearm-flexor")]
        case .morning:
            [.drill("cat-cow", 8), .drill("worlds-greatest", 5), .drill("hip-car", 5), .drill("shoulder-car", 5),
             .drill("thread-needle", 6), .drill("open-book", 6), .drill("knee-to-wall", 10), .drill("windshield-wipers", 8),
             .drill("wall-slide", 10), .drill("adductor-rock-back", 8), .hold("downward-dog")]
        case .desk:
            [.hold("upper-trap"), .drill("shoulder-car", 5), .hold("pec-stretch"), .hold("half-kneeling-hf"),
             .drill("open-book", 6), .drill("wrist-car", 6), .hold("figure-4")]
        case .bedtime:
            [.hold("childs-pose-reach"), .hold("supine-twist"), .hold("figure-4"), .hold("butterfly"), .hold("hamstring-stretch"),
             .hold("sphinx"), .hold("seated-forward-fold"), .hold("breathing")]
        case .hips:
            [.drill("hip-car", 5), .hold("pigeon"), .hold("lizard-stretch"), .hold("frog-stretch"), .drill("windshield-wipers", 8),
             .hold("butterfly"), .hold("half-kneeling-hf"), .hold("figure-4"), .drill("frog-rockback", 8), .hold("deep-squat-pry"),
             .hold("warrior-2"), .hold("brettzel")]
        case .shoulders:
            [.drill("shoulder-car", 5), .drill("wall-slide", 10), .hold("sleeper-stretch"), .hold("cross-body"), .drill("thread-needle", 6),
             .hold("pec-stretch"), .drill("open-book", 6), .hold("behind-back-clasp"), .hold("side-delt-stretch"), .hold("triceps-stretch"),
             .hold("upper-trap")]
        case .rollout:
            [.hold("foam-roll-upper-back"), .hold("foam-roll-lats"), .hold("foam-roll-glutes"), .hold("foam-roll-hamstrings"),
             .hold("foam-roll-quads"), .hold("foam-roll-calves"), .hold("foam-roll-adductors"), .hold("massage-ball-foot"),
             .hold("massage-ball-glute"), .hold("massage-ball-chest")]
        case .legs:
            [.drill("knee-to-wall", 10), .hold("calf-wall"), .hold("standing-quad-stretch"), .hold("half-kneeling-hf"), .hold("hamstring-stretch"),
             .hold("pigeon"), .drill("hip-car", 5), .hold("figure-4"), .hold("massage-ball-foot"), .hold("butterfly"), .hold("supine-twist")]
        case .wrists:
            [.drill("wrist-car", 6), .hold("forearm-flexor"), .hold("forearm-extensor"), .hold("wrist-flexor-floor"),
             .drill("shoulder-car", 5), .hold("upper-trap"), .hold("cross-body")]
        case .splits:
            [.hold("butterfly"), .hold("straddle-stretch"), .drill("pancake-gm", 8), .hold("frog-stretch"), .hold("lizard-stretch"),
             .drill("bw-cossack", 6), .hold("half-kneeling-hf"), .hold("seated-forward-fold"), .hold("pigeon"), .hold("hamstring-stretch"),
             .hold("brettzel"), .hold("warrior-2")]
        case .hangs:
            []
        }
    }

    private func item(_ m: Move, hold: Int, sets: Int = 1) -> Item {
        switch m {
        case .drill(let id, let reps): Item(id, sets: sets, reps: reps, rest: 0, block: .mobility)
        case .hold(let id): Item(id, sets: sets, reps: hold, rest: 0, block: kind == .stretch ? .cooldown : .mobility,
                                 intensity: self == .rollout ? "Slow · pause on tight spots" : "Relaxed · long exhales")
        }
    }

    private func make(_ minutes: Int) -> WorkoutTemplate {
        if self == .hangs { return wrap(minutes, hangs(minutes)) }
        let hold = minutes <= 5 ? 30 : minutes >= 20 ? 60 : 45
        var items: [Item] = []
        for m in pool {
            let next = items + [item(m, hold: hold)]
            guard abs(est(next) - minutes) <= abs(est(items) - minutes) else { break }
            items = next
        }
        // Pool used up short of the length: a second round of the moves, in order.
        var i = 0
        while est(items) < minutes && i < items.count {
            let it = items[i]
            var next = items
            next[i] = Item(it.exerciseId, sets: 2, reps: it.reps, rest: 15, block: it.block, intensity: it.intensity)
            guard abs(est(next) - minutes) <= abs(est(items) - minutes) else { break }
            items = next
            i += 1
        }
        return wrap(minutes, items)
    }

    /// Daily low-load hangs (Abrahangs-style): 10 s on, 50 s off on a 20 mm edge, feet on a chair or a pulley so the
    /// fingers carry 40–60 % bodyweight. Effort 3–4/10, never to failure; the length sets the number of hangs.
    public static let hangIntensity = "Easy: 40–60 % bodyweight (feet on a chair or pulley) · effort 3–4/10 · 20 mm edge, half crimp and open hand in turn"

    private func hangs(_ minutes: Int) -> [Item] {
        func build(_ n: Int) -> [Item] {
            var items = [Item("finger-ramp", sets: 1, reps: 60, rest: 0, block: .warmup)]
            if minutes >= 10 { items.append(Item("hang-ramp", sets: 2, reps: 10, rest: 30, block: .warmup)) }
            items.append(Item("open-hand-hang", sets: n, reps: 10, rest: 50, block: .strength, intensity: Self.hangIntensity))
            if minutes >= 15 { items.append(Item("forearm-extensor", sets: 1, reps: 30, rest: 0, block: .cooldown)) }
            return items
        }
        let best = (2...30).min { abs(est(build($0)) - minutes) < abs(est(build($1)) - minutes) } ?? 6
        return build(best)
    }
}
