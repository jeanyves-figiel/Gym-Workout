import Foundation

// MARK: - Train around pain (#870)

/// Where it hurts. Joints, not muscles: the guard reads each move's pattern, equipment and muscles to know what loads it.
public enum PainArea: String, Codable, CaseIterable, Sendable, Identifiable {
    case neck, shoulder, elbow, wrist
    case lowerBack = "lower-back"
    case hip, knee, ankle

    public var id: String { rawValue }
    public var label: String { self == .lowerBack ? "lower back" : rawValue }
    /// "Knee-friendly plan".
    public var friendly: String { "\(self == .lowerBack ? "Back" : rawValue.capitalized)-friendly plan" }
    /// One side or the middle of the body.
    public var sided: Bool { ![.neck, .lowerBack].contains(self) }
}

public enum PainSide: String, Codable, CaseIterable, Sendable {
    case left, right, both
}

/// How bad: a niggle, hurts when loaded, sharp. Each level swaps more.
public enum PainLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case mild, loaded, sharp

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .mild: "Mild"
        case .loaded: "Sore when I load it"
        case .sharp: "Sharp"
        }
    }
}

/// A spot being protected, from the body figure or Ask Coach, until the member says it feels better. Stored with the profile.
public struct PainProtect: Codable, Hashable, Sendable {
    public var area: PainArea
    public var side: PainSide
    public var level: PainLevel
    public var since: Date
    /// Red flags were mentioned (Ask Coach): the "see a doctor" line stays on.
    public var seeDoctor: Bool

    public init(area: PainArea, side: PainSide = .both, level: PainLevel, since: Date = Date(), seeDoctor: Bool = false) {
        self.area = area
        self.side = area.sided ? side : .both
        self.level = level
        self.since = since
        self.seeDoctor = seeDoctor
    }

    /// "right knee", "lower back".
    public var spot: String { area.sided && side != .both ? "\(side.rawValue) \(area.label)" : area.label }

    /// Day 1 is the day it started.
    public func day(now: Date = Date(), calendar: Calendar = .current) -> Int {
        (calendar.dateComponents([.day], from: calendar.startOfDay(for: since), to: calendar.startOfDay(for: now)).day ?? 0) + 1
    }

    /// Two weeks in and still on: time to get it looked at.
    public func longRunning(now: Date = Date(), calendar: Calendar = .current) -> Bool { day(now: now, calendar: calendar) > 14 }

    public static let notAdvice = "Not medical advice. Sharp pain, swelling or numbness: see a doctor."

    // MARK: What loads the spot

    private static let impactCardio: Set<String> = ["treadmill-run", "jump-rope", "burpee", "jumping-jacks", "high-knees", "sled-sprint", "bear-crawl"]
    private static let standingCardio: Set<String> = ["stair-climber", "elliptical", "incline-walk", "ski-erg"]
    private static let overhead: Set<String> = ["push-press", "kb-snatch", "db-snatch", "barbell-thruster", "db-thruster", "kb-thruster",
                                                "overhead-squat", "kb-overhead-squat", "overhead-carry", "turkish-get-up"]
    /// Machine squats that keep the knee in a short, guided range: fine for a knee that only hurts loaded deep.
    private static let kneeGuided: Set<String> = ["leg-press", "single-leg-press", "wall-sit"]

    /// Whether `e` loads the spot at this level. Each level includes the ones below.
    public func risky(_ e: Exercise) -> Bool {
        let p = e.pattern
        let eq = Set(e.equipment)
        let mus = Set(e.primary)
        func pat(_ ps: Pattern...) -> Bool { ps.contains(p) }
        func hits(_ ms: Muscle...) -> Bool { ms.contains { mus.contains($0) } }
        let impact = p == .jump || Self.impactCardio.contains(e.id)
        let standing = Self.standingCardio.contains(e.id)
        let barbell = eq.contains(.barbell)
        let overhead = Self.overhead.contains(e.id)
        let guided = Self.kneeGuided.contains(e.id)
        let tiers: [Bool]
        switch area {
        case .knee:
            tiers = [impact,
                     pat(.singleLeg, .kneeExt) || (p == .squat && !guided),
                     pat(.squat, .kneeFlex, .ballistic) || standing]
        case .ankle:
            tiers = [impact,
                     pat(.singleLeg, .calves, .ballistic, .carry),
                     p == .squat || standing]
        case .hip:
            tiers = [impact,
                     pat(.singleLeg, .ballistic) || (p == .squat && !guided),
                     pat(.squat, .hinge) || hits(.hipFlexors, .adductors)]
        case .lowerBack:
            tiers = [p == .ballistic || (p == .hinge && barbell),
                     impact || pat(.hinge, .carry, .coreFlex) || (p == .squat && barbell) || hits(.lowerBack),
                     pat(.squat, .singleLeg, .throw) || (p == .hPull && barbell)]
        case .shoulder:
            tiers = [pat(.upperPlyo, .vPush, .throw) || overhead,
                     pat(.hPush, .lateralRaise, .ballistic) || eq.contains(.dipStation),
                     pat(.vPull, .hPull, .carry, .armsExt) || hits(.frontDelts, .sideDelts, .rearDelts, .rotatorCuff)]
        case .elbow:
            tiers = [p == .armsExt,
                     pat(.armsFlex, .upperPlyo) || eq.contains(.dipStation) || hits(.brachialis, .forearms),
                     pat(.hPush, .vPush, .vPull, .hPull, .carry)]
        case .wrist:
            tiers = [pat(.upperPlyo, .forearmAntagonist) || hits(.forearms, .forearmExtensors),
                     pat(.hPush, .carry, .ballistic, .armsFlex) || e.gripHeavy || e.id == "burpee",
                     pat(.vPush, .vPull, .hPull, .armsExt, .coreAntiExt)]
        case .neck:
            tiers = [p == .upperPlyo || hits(.traps),
                     pat(.vPush, .carry, .coreFlex) || overhead || (p == .squat && barbell),
                     pat(.hPull, .vPull, .ballistic) || (p == .hinge && barbell) || impact]
        }
        return tiers.prefix(Self.order(level) + 1).contains(true)
    }

    private static func order(_ l: PainLevel) -> Int { PainLevel.allCases.firstIndex(of: l) ?? 0 }

    // MARK: The plan around it

    /// One change: a move swapped (`to`) or removed (`to` nil).
    public struct Change: Hashable, Sendable {
        public let from: String
        public let to: String?

        public var line: String {
            let a = Exercise.find(from)?.name ?? from
            guard let to else { return "\(a) removed" }
            return "\(a) → \(Exercise.find(to)?.name ?? to)"
        }
    }

    /// What the guard did to a plan: each distinct change, and the swapped items' uids (marked 🛡).
    public struct Result: Sendable {
        public var plan: WeekPlan
        public var changes: [Change]
        public var swapped: Set<String>
        public var workouts: Int
    }

    /// Note on a swapped move.
    public var swapNote: String { "Protecting your \(spot): pain-free range only" }

    /// Every move that loads the spot swaps to the closest one that doesn't (same role, best muscle overlap, the
    /// member's equipment, from the catalog), or goes when nothing fits. Swapped items keep their uid.
    public func guarded(_ plan: WeekPlan, profile: Profile) -> Result {
        var out = plan
        var changes: [Change] = []
        var swapped = Set<String>()
        var workouts = 0
        for k in out.sessions.indices {
            var s = out.sessions[k]
            var used = Set(s.blocks.flatMap(\.items).map(\.exerciseId))
            var removed = Set<String>()
            var touched = false
            for b in s.blocks.indices {
                var lines: [String] = []
                var kept: [PlannedExercise] = []
                for var it in s.blocks[b].items {
                    if let p = it.pairedWith, let pe = Exercise.find(p), risky(pe) { it.pairedWith = nil }
                    guard let e = Exercise.find(it.exerciseId), risky(e) else { kept.append(it); continue }
                    let option = e.swapOptions(for: profile, excluding: used).first { !risky($0) }
                    let c = Change(from: e.id, to: option?.id)
                    if !changes.contains(c) { changes.append(c) }
                    if !lines.contains(c.line) { lines.append(c.line) }
                    touched = true
                    if let option {
                        used.insert(option.id)
                        it.exerciseId = option.id
                        it.prescription.note = swapNote
                        swapped.insert(it.uid)
                        kept.append(it)
                    } else {
                        removed.insert(it.uid)
                    }
                }
                s.blocks[b].items = kept
                if !lines.isEmpty {
                    s.blocks[b].note = (["🛡 " + lines.joined(separator: " · ")] + [s.blocks[b].note].compactMap { $0 }).joined(separator: " ")
                }
            }
            guard touched else { continue }
            workouts += 1
            // A removed move's superset partner is done on its own.
            for b in s.blocks.indices {
                for i in s.blocks[b].items.indices where s.blocks[b].items[i].supersetWith.map({ removed.contains($0) }) == true {
                    s.blocks[b].items[i].supersetWith = nil
                }
            }
            s.blocks.removeAll { $0.items.isEmpty }
            s.estMin = Int(s.blocks.reduce(0) { $0 + $1.estMin }.rounded())
            out.sessions[k] = s
        }
        return Result(plan: out, changes: changes, swapped: swapped, workouts: workouts)
    }
}
