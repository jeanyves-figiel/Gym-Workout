import Foundation

/// Build as I go (#490): a workout that starts empty and grows one exercise at a time in the player. Every exercise
/// lands in one block, in the order added; the Coach offers the next picks.
public enum Freestyle {
    public static let idPrefix = "free-"
    public static let title = "Custom gym session"
    /// Picks the Coach offers after each exercise.
    public static let pickCount = 3

    public static func isFreestyle(_ sessionId: String) -> Bool { sessionId.hasPrefix(idPrefix) }

    /// A paused workout's contents for its Resume tile and "Workout kept" bar (#997): "3 exercises · 4 sets done".
    public static func resumeLine(exercises: Int, setsDone: Int) -> String {
        let ex = exercises == 1 ? "1 exercise" : "\(exercises) exercises"
        guard setsDone > 0 else { return ex + " · none done yet" }
        return ex + " · " + (setsDone == 1 ? "1 set done" : "\(setsDone) sets done")
    }

    /// A new empty workout with its own id, so its sets, history and Watch link never mix with another run.
    public static func session(id: UUID = UUID()) -> Session {
        Session(id: idPrefix + String(id.uuidString.lowercased().prefix(8)), index: 0, focus: .fullUpper, title: title,
                targetMin: 0, estMin: 1, blocks: [emptyBlock])
    }

    static var emptyBlock: Block {
        Block(kind: .strength, title: title, targetMin: 0, items: [], note: nil)
    }

    /// `blocks` with `exercise` added at the end (the block comes back if the last exercise was removed); the new uid.
    public static func adding(_ exercise: Exercise, to blocks: [Block], sessionId: String, id: UUID = UUID()) -> (blocks: [Block], uid: String?) {
        var out = blocks.contains { $0.kind == .strength } ? blocks : blocks + [emptyBlock]
        let uid = out.add(exercise, to: .strength, sessionId: sessionId, id: id)
        return (out, uid)
    }

    /// Most sets one exercise takes in a freestyle workout (#795: + set while doing it).
    public static let maxSets = 12

    /// `blocks` with the exercise `uid` set to `sets` sets (1…`maxSets`); its time estimate follows.
    public static func settingSets(_ sets: Int, of uid: String, in blocks: [Block]) -> [Block] {
        let n = min(maxSets, max(1, sets))
        return blocks.map { b in
            var b = b
            b.items = b.items.map { it in
                guard it.uid == uid, it.prescription.sets != n else { return it }
                var it = it
                let old = max(1, it.prescription.sets)
                it.estSec = max(1, it.estSec * n / old)
                it.prescription.sets = n
                return it
            }
            return b
        }
    }

    /// Muscle groups the workout already trains as a primary mover.
    public static func groupsHit(_ blocks: [Block]) -> Set<MuscleGroup> {
        Set(blocks.flatMap(\.items).compactMap { Exercise.find($0.exerciseId) }.flatMap { $0.primary.map(\.group) })
    }

    /// Most names sent to Coach (#856), the server's limit.
    public static let coachNameLimit = 400

    /// Exercise names Ask Coach may hand back on the freestyle screen (#856): strength and power moves at the member's
    /// level with any equipment (the machine in front of them may not be in their gym list), no climbing. A–Z.
    public static func coachNames(profile: Profile) -> [String] {
        let climbing = Set(Exercise.climbingCatalog.map(\.id))
        let level = profile.experience.level
        let names = Exercise.catalog
            .filter { ($0.category == .strength || $0.category == .power) && $0.level <= level && !climbing.contains($0.id) && !$0.primary.isEmpty }
            .map(\.name)
        return Array(Set(names)).sorted().prefix(coachNameLimit).map { $0 }
    }

    /// The Coach's next picks: strength exercises the member's gym and level allow, not yet in the workout. Empty
    /// workout → a big main lift first; then muscle groups not trained yet; exercises the member has done before
    /// (`recent`, newest first) rank higher. Each pick trains a different muscle group when it can. Same input →
    /// same picks.
    public static func suggest(after blocks: [Block], profile: Profile, recent: [String] = [], count: Int = pickCount) -> [Exercise] {
        let used = Set(blocks.flatMap(\.items).map(\.exerciseId))
        let hit = groupsHit(blocks)
        let empty = used.isEmpty
        let level = profile.experience.level
        let equipment = Set(profile.equipment)
        let known = Dictionary(recent.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a })
        let pool = Exercise.catalog.filter { e in
            e.category == .strength && e.level <= level && Selector.isAvailable(e, equipment)
                && !Exercise.libraryOnlyIds.contains(e.id) && !used.contains(e.id) && !e.primary.isEmpty
        }
        func score(_ e: Exercise) -> Double {
            let groups = Set(e.primary.map(\.group))
            var s = 3 * Double(groups.subtracting(hit).count) - 2 * Double(groups.intersection(hit).count)
            if e.main { s += empty ? 4 : 1 }
            if !Rules.lightPatterns.contains(e.pattern) { s += empty ? 1.5 : 0.5 }
            if let i = known[e.id] { s += 2 - min(1.5, Double(i) * 0.1) }
            if e.generator { s += 0.5 }
            return s
        }
        let ranked = pool.map { (e: $0, s: score($0)) }.sorted { ($0.s, $1.e.name) > ($1.s, $0.e.name) }.map(\.e)
        var picks: [Exercise] = []
        var groups: Set<MuscleGroup> = []
        for e in ranked where picks.count < count {
            guard let g = e.primary.first?.group, !groups.contains(g) else { continue }
            picks.append(e)
            groups.insert(g)
        }
        for e in ranked where picks.count < count && !picks.contains(where: { $0.id == e.id }) { picks.append(e) }
        return picks
    }
}
