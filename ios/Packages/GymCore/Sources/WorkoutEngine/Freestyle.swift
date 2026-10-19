import Foundation

/// Build as I go (#490): a workout that starts empty and grows one exercise at a time in the player. Every exercise
/// lands in one block, in the order added; the Coach offers the next picks.
public enum Freestyle {
    public static let idPrefix = "free-"
    public static let title = "Freestyle"
    /// Picks the Coach offers after each exercise.
    public static let pickCount = 3

    public static func isFreestyle(_ sessionId: String) -> Bool { sessionId.hasPrefix(idPrefix) }

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

    /// Muscle groups the workout already trains as a primary mover.
    public static func groupsHit(_ blocks: [Block]) -> Set<MuscleGroup> {
        Set(blocks.flatMap(\.items).compactMap { Exercise.find($0.exerciseId) }.flatMap { $0.primary.map(\.group) })
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
