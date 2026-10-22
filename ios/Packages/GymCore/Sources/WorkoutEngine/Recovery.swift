import Foundation

/// Mobility & recovery days (#619, designs A + B + C from `apple-tech-radar/x2.png`): a short routine for the
/// areas trained hardest this week on rest days, and a 5′ cool-down finisher for workouts that have none.
public enum Recovery {
    /// Area a rest-day routine works on, picked from this week's load.
    public enum Area: String, CaseIterable, Sendable {
        case hipsBack, legs, upper, full

        public var label: String {
            switch self {
            case .hipsBack: "Hips & back"
            case .legs: "Legs"
            case .upper: "Shoulders & chest"
            case .full: "Full body"
            }
        }

        /// Muscle groups whose load points to this area.
        public var groups: Set<MuscleGroup> {
            switch self {
            case .hipsBack: [.hips, .back, .core]
            case .legs: [.legs]
            case .upper: [.shoulders, .chest, .arms]
            case .full: Set(MuscleGroup.allCases)
            }
        }
    }

    /// The rest-day routine for an area (about 12 minutes, mat only).
    public static func routine(_ area: Area) -> WorkoutTemplate { routines[area]! }

    /// Every routine, so `WorkoutTemplate.find(sessionId:)` resolves them (session view, player, history).
    public static let templates: [WorkoutTemplate] = Area.allCases.map { routines[$0]! }

    /// Area with the most load this week; full body when nothing stands out (no group set above 40 % of the total).
    public static func area(_ load: [Muscle: Double]) -> Area {
        var byGroup: [MuscleGroup: Double] = [:]
        for (m, v) in load { byGroup[m.group, default: 0] += v }
        let total = byGroup.values.reduce(0, +)
        guard total > 0 else { return .full }
        let scored = [Area.hipsBack, .legs, .upper].map { a in (a, a.groups.reduce(0) { $0 + (byGroup[$1] ?? 0) }) }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 / total >= 0.4 else { return .full }
        return best.0
    }

    /// Days of `records` (start, load) whose biggest group belongs to `area`, in order, one per day.
    public static func hardDays(_ records: [(start: Date, load: [Muscle: Double])], area: Area, calendar: Calendar) -> [Date] {
        guard area != .full else { return [] }
        var days: [Date] = []
        for r in records.sorted(by: { $0.start < $1.start }) {
            var byGroup: [MuscleGroup: Double] = [:]
            for (m, v) in r.load { byGroup[m.group, default: 0] += v }
            guard let top = byGroup.max(by: { $0.value < $1.value })?.key, area.groups.contains(top) else { continue }
            let day = calendar.startOfDay(for: r.start)
            if days.last != day { days.append(day) }
        }
        return days
    }

    // MARK: Cool-down finisher (C)

    /// A workout without a cool-down (examples, own and shared workouts) gets a 5′ one for its most-loaded muscles:
    /// 4 mat stretches. Mobility, warm-up and cool-down-only workouts are left as they are.
    public static func withFinisher(_ s: Session) -> Session {
        guard !s.blocks.contains(where: { $0.kind == .cooldown }),
              s.blocks.contains(where: { [.power, .strength, .cardio].contains($0.kind) }) else { return s }
        var out = s
        let block = finisher(Generator.muscleLoad(s.blocks), uid: "\(s.id)-fin")
        out.blocks.append(block)
        out.estMin += Int(block.estMin.rounded())
        return out
    }

    static func finisher(_ load: [Muscle: Double], uid: String) -> Block {
        let stretches = Exercise.catalog.filter { e in
            e.category == .stretch && e.id != "breathing" && e.equipment.allSatisfy { $0 == .mat }
        }
        var remaining = load
        var chosen: [Exercise] = []
        while chosen.count < finisherCount {
            let pick = stretches.filter { e in !chosen.contains { $0.id == e.id } }
                .max { a, b in
                    let sa = a.primary.reduce(0) { $0 + (remaining[$1] ?? 0) }, sb = b.primary.reduce(0) { $0 + (remaining[$1] ?? 0) }
                    return sa != sb ? sa < sb : a.id > b.id
                }
            guard let e = pick else { break }
            chosen.append(e)
            for m in e.primary { remaining[m] = (remaining[m] ?? 0) * 0.25 }
        }
        let items = chosen.enumerated().map { i, e in
            PlannedExercise(uid: "\(uid)-\(i)", exerciseId: e.id, slot: .general,
                            prescription: Prescription(sets: 1, reps: "45 s\(Generator.perSide(e))", restSec: 0,
                                                       intensity: "Relaxed · long exhales"),
                            estSec: e.unilateral ? 90 : 60)
        }
        return Block(kind: .cooldown, title: "Cool-down", targetMin: 5, items: items,
                     note: "Auto-added: 4 stretches for what this workout loaded most.")
    }

    public static let finisherCount = 4

    // MARK: Routines (A)

    typealias Item = WorkoutTemplate.Item

    private static func drill(_ id: String, _ reps: Int) -> Item { Item(id, sets: 1, reps: reps, rest: 0, block: .mobility) }
    private static func hold(_ id: String, _ sec: Int = 45) -> Item { Item(id, sets: 1, reps: sec, rest: 0, block: .cooldown) }

    private static func make(_ area: Area, _ focus: Focus, _ items: [Item]) -> WorkoutTemplate {
        WorkoutTemplate(id: "recover-\(area.rawValue)", name: "Recover · \(area.label)", focus: focus, goal: .mobility,
                        kit: "Mat", level: 1, main: .mobility, items: items)
    }

    static let routines: [Area: WorkoutTemplate] = [
        .hipsBack: make(.hipsBack, .lower, [
            drill("cat-cow", 8), drill("hip-car", 5), drill("windshield-wipers", 8), drill("open-book", 6),
            hold("pigeon"), hold("half-kneeling-hf"), hold("childs-pose-reach"), hold("supine-twist"),
        ]),
        .legs: make(.legs, .lower, [
            drill("knee-to-wall", 10), drill("hip-car", 5), drill("adductor-rock-back", 8),
            hold("standing-quad-stretch"), hold("seated-forward-fold"), hold("calf-wall"), hold("figure-4"), hold("butterfly"),
        ]),
        .upper: make(.upper, .upper, [
            drill("shoulder-car", 5), drill("thread-needle", 6), drill("open-book", 6), drill("wall-slide", 10),
            hold("pec-stretch"), hold("cross-body"), hold("triceps-stretch"), hold("sphinx"),
        ]),
        .full: make(.full, .fullLower, [
            drill("cat-cow", 8), drill("worlds-greatest", 5), drill("thread-needle", 6), drill("hip-car", 5),
            hold("downward-dog"), hold("pigeon"), hold("childs-pose-reach"), hold("breathing", 60),
        ]),
    ]
}
