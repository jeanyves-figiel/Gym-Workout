import Foundation

/// Finish a workout early (#300): re-fits what is left of a workout in progress to the minutes the member has left.
/// Done sets and the current exercise stay; the main lift goes last; the cool-down always stays (shortened at most to
/// `minCooldownSec`, keeping its first stretches and the closing breathing).
public enum FinishEarly {
    /// Cool-down kept at least this long when there is one to keep.
    public static let minCooldownSec = 180
    /// Cardio left in the plan is shortened to no less than this before it is skipped.
    public static let minCardioSec = 300
    /// Rest between remaining sets is tightened to no less than this.
    public static let minRestSec = 45

    /// What happened to one item that was still to do.
    public enum Change: Hashable, Sendable {
        case kept
        case fewerSets(from: Int, to: Int)
        case shorter(fromSec: Int, toSec: Int)
        case restTighter(fromSec: Int, toSec: Int)
        case skipped
    }

    public struct Line: Hashable, Sendable, Identifiable {
        public var uid: String
        public var exerciseId: String
        public var kind: BlockKind
        public var change: Change
        public var id: String { uid }
    }

    public struct Fit: Hashable, Sendable {
        /// The whole workout with the trimmed rest; done items are unchanged so player positions still match by uid.
        public var blocks: [Block]
        /// Estimated seconds still to do before and after the fit.
        public var beforeSec: Int
        public var leftSec: Int
        /// Every item that was still to do, in workout order.
        public var lines: [Line]
        /// Whether `leftSec` is within the minutes asked for (false when even the protected work takes longer).
        public var fits: Bool

        public var skipped: Int { lines.filter { $0.change == .skipped }.count }
        public var setsCut: Int {
            lines.reduce(0) { n, l in if case let .fewerSets(a, b) = l.change { n + a - b } else { n } }
        }
        public var changed: Bool { lines.contains { $0.change != .kept } }
    }

    /// Estimated seconds still to do: the unfinished share of every item.
    public static func remainingSec(_ blocks: [Block], setsDone: [String: Int]) -> Int {
        blocks.reduce(0) { $0 + $1.items.reduce(0) { $0 + left($1, setsDone) } }
    }

    /// Trims the remaining work to `minutes`. `current` is the item on screen: never skipped, its done sets kept.
    /// Items before it (outside its superset / circuit) are behind the member and count as done.
    public static func fit(_ blocks: [Block], setsDone done: [String: Int], current: String?, minutes: Int) -> Fit {
        let budget = max(0, minutes) * 60
        let original = blocks
        let setsDone = behind(blocks, setsDone: done, current: current)
        var t = Trim(blocks: blocks, setsDone: setsDone, current: current, budget: budget)
        let steps: [(inout Trim) -> Void] = [
            { $0.dropAll(.mobility) },
            { $0.shortenCardio() },
            { $0.dropAll(.cardio) },
            { $0.trimWarmup() },
            { $0.tightenRest() },
            { $0.cutAccessorySets(to: 2) },
            { $0.shortenCooldown() },
            { $0.dropAccessories() },
            { $0.cutAccessorySets(to: 1) },
            { $0.cutMainSets(to: 2) },
            { $0.dropAll(.warmup) },
            { $0.cutMainSets(to: 1) },
            { $0.dropMain() },
        ]
        for step in steps where !t.fits { step(&t) }
        let lines = original.flatMap { b in
            b.items.compactMap { it -> Line? in
                guard left(it, setsDone) > 0 || it.uid == current else { return nil }
                return Line(uid: it.uid, exerciseId: it.exerciseId, kind: b.kind, change: change(it, t.blocks))
            }
        }
        return Fit(blocks: t.blocks, beforeSec: remainingSec(original, setsDone: setsDone), leftSec: t.left, lines: lines, fits: t.fits)
    }

    /// The fit's whole workout as a session (same id), estimate updated.
    public static func session(_ s: Session, _ fit: Fit) -> Session {
        var out = s
        let before = s.blocks.estSec, after = fit.blocks.estSec
        out.blocks = fit.blocks
        out.estMin = max(1, s.estMin + Int((Double(after - before) / 60).rounded()))
        return out
    }

    /// Sets done with the items behind `current` counted as finished.
    public static func behind(_ blocks: [Block], setsDone: [String: Int], current: String?) -> [String: Int] {
        guard let current else { return setsDone }
        let group = Set(blocks.first { b in b.items.contains { $0.uid == current } }?.groupMembers(of: current).map(\.uid) ?? [])
        var out = setsDone
        for it in blocks.flatMap(\.items) {
            if it.uid == current { break }
            if !group.contains(it.uid) { out[it.uid] = max(out[it.uid] ?? 0, sets(it)) }
        }
        return out
    }

    // MARK: Helpers

    static func sets(_ it: PlannedExercise) -> Int { max(1, it.prescription.sets) }

    static func left(_ it: PlannedExercise, _ done: [String: Int]) -> Int {
        let d = min(done[it.uid] ?? 0, sets(it))
        return it.estSec * (sets(it) - d) / sets(it)
    }

    /// Leading "<n> min" of a single timed piece ("10 min", "2 min"); nil otherwise.
    static func minutes(_ p: Prescription) -> Int? {
        let t = p.reps.trimmingCharacters(in: .whitespaces)
        guard p.sets == 1, !t.contains("/"), let m = t.firstMatch(of: #/^(\d+)\s*min\b/#) else { return nil }
        return Int(m.1)
    }

    static func change(_ it: PlannedExercise, _ blocks: [Block]) -> Change {
        guard let now = blocks.lazy.flatMap(\.items).first(where: { $0.uid == it.uid }) else { return .skipped }
        if now.prescription.sets != it.prescription.sets { return .fewerSets(from: it.prescription.sets, to: now.prescription.sets) }
        if now.prescription.reps != it.prescription.reps { return .shorter(fromSec: it.estSec, toSec: now.estSec) }
        if now.prescription.restSec != it.prescription.restSec {
            return .restTighter(fromSec: it.prescription.restSec, toSec: now.prescription.restSec)
        }
        return .kept
    }
}

/// One fit in progress: blocks being trimmed and what may not be touched.
private struct Trim {
    var blocks: [Block]
    let setsDone: [String: Int]
    let current: String?
    let budget: Int

    var left: Int { FinishEarly.remainingSec(blocks, setsDone: setsDone) }
    var fits: Bool { left <= budget }
    var over: Int { left - budget }

    func done(_ uid: String) -> Int { setsDone[uid] ?? 0 }
    /// Started or on screen: may lose sets still to do, never be skipped.
    func started(_ it: PlannedExercise) -> Bool { it.uid == current || done(it.uid) > 0 }
    func finished(_ it: PlannedExercise) -> Bool { done(it.uid) >= FinishEarly.sets(it) }

    /// The main lift: the strength block's first exercise.
    var mainUid: String? { blocks.first { $0.kind == .strength }?.items.first { $0.supersetWith == nil }?.uid }

    /// Item and the members of its superset / circuit, which change together.
    func unit(_ uid: String) -> [String] {
        for b in blocks where b.items.contains(where: { $0.uid == uid }) {
            let members = b.groupMembers(of: uid).map(\.uid)
            return members.count > 1 ? members : [uid]
        }
        return [uid]
    }

    func item(_ uid: String) -> PlannedExercise? { blocks.lazy.flatMap(\.items).first { $0.uid == uid } }

    /// Removes not-started items in `candidates`, last first, while over budget.
    mutating func drop(_ candidates: [String]) {
        for uid in candidates.reversed() where !fits {
            let members = unit(uid).compactMap { item($0) }
            guard !members.isEmpty, !members.contains(where: { started($0) }) else { continue }
            for m in members { blocks.remove(m.uid) }
        }
    }

    func uids(_ kinds: Set<BlockKind>) -> [String] {
        blocks.filter { kinds.contains($0.kind) }.flatMap(\.items).filter { $0.supersetWith == nil }.map(\.uid)
    }

    /// Strength and power items other than the main lift and its superset partners.
    var accessories: [String] {
        let main = mainUid.map { Set(unit($0)) } ?? []
        return uids([.strength, .power]).filter { !main.contains($0) }
    }

    mutating func dropAll(_ kind: BlockKind) { drop(uids([kind])) }

    mutating func dropAccessories() { drop(accessories) }

    mutating func dropMain() {
        guard let main = mainUid else { return }
        drop([main])
    }

    /// Single timed cardio pieces lose minutes (not below `minCardioSec`); interval pieces lose rounds.
    mutating func shortenCardio() {
        for b in blocks.indices where blocks[b].kind == .cardio {
            for i in blocks[b].items.indices.reversed() where !fits {
                let it = blocks[b].items[i]
                guard !finished(it), done(it.uid) == 0 || it.uid == current else { continue }
                if let m = FinishEarly.minutes(it.prescription) {
                    let target = max(FinishEarly.minCardioSec / 60, m - (over + 59) / 60)
                    guard target < m else { continue }
                    blocks[b].items[i].prescription.reps = it.prescription.reps.replacingOccurrences(of: "\(m)", with: "\(target)", options: .anchored)
                    blocks[b].items[i].estSec = max(60, it.estSec * target / m)
                } else {
                    let floor = max(2, done(it.uid) + 1)
                    let per = max(1, it.estSec / FinishEarly.sets(it))
                    let target = max(floor, FinishEarly.sets(it) - (over + per - 1) / per)
                    if target < FinishEarly.sets(it) { blocks.setSets(it.uid, target) }
                }
            }
        }
    }

    /// A warm-up not started yet keeps its pulse raiser and first two drills; the raiser drops to 3 min.
    mutating func trimWarmup() {
        guard let b = blocks.firstIndex(where: { $0.kind == .warmup }) else { return }
        for it in blocks[b].items.dropFirst(3).reversed() where !fits && !started(it) && !finished(it) { blocks.remove(it.uid) }
        guard !fits, let b2 = blocks.firstIndex(where: { $0.kind == .warmup }), let first = blocks[b2].items.first,
              !started(first), let m = FinishEarly.minutes(first.prescription), m > 3 else { return }
        blocks[b2].items[0].prescription.reps = first.prescription.reps.replacingOccurrences(of: "\(m)", with: "3", options: .anchored)
        blocks[b2].items[0].estSec = 180
    }

    /// Rest between the sets still to do drops by a quarter (not below `minRestSec`).
    mutating func tightenRest() {
        for b in blocks.indices where blocks[b].kind == .strength || blocks[b].kind == .power {
            for i in blocks[b].items.indices where !finished(blocks[b].items[i]) {
                let it = blocks[b].items[i]
                let rest = it.prescription.restSec
                let to = max(FinishEarly.minRestSec, rest * 3 / 4 / 5 * 5)
                guard to < rest else { continue }
                let gaps = max(0, FinishEarly.sets(it) - max(1, done(it.uid)))
                blocks[b].items[i].prescription.restSec = to
                blocks[b].items[i].estSec = max(30, it.estSec - gaps * (rest - to))
            }
        }
    }

    /// Accessories (every strength / power item but the main lift), last first, lose sets down to `floor`.
    mutating func cutAccessorySets(to floor: Int) {
        for uid in accessories.reversed() where !fits { cutSets(uid, to: floor) }
    }

    mutating func cutMainSets(to floor: Int) {
        guard let main = mainUid, !fits else { return }
        cutSets(main, to: floor)
    }

    /// Lowers the set count of an item (and its group) one set at a time while over budget; done sets stay.
    mutating func cutSets(_ uid: String, to floor: Int) {
        let members = unit(uid)
        while !fits {
            let items = members.compactMap { item($0) }
            guard let it = items.first else { return }
            let n = FinishEarly.sets(it)
            let least = max(floor, items.map { done($0.uid) }.max() ?? 0, 1)
            guard n > least else { return }
            for m in items { blocks.setSets(m.uid, min(FinishEarly.sets(m), n - 1)) }
        }
    }

    /// Cool-down down to `minCooldownSec`: the cardio flush goes first, then stretches from the end; the closing
    /// breathing and the first two stretches stay.
    mutating func shortenCooldown() {
        guard let b = blocks.firstIndex(where: { $0.kind == .cooldown }) else { return }
        let items = blocks[b].items.filter { !started($0) && !finished($0) }
        var cool = FinishEarly.remainingSec([blocks[b]], setsDone: setsDone)
        let flush = items.filter { $0.uid.hasSuffix("-flush") }
        let breathing = items.last { $0.exerciseId == "breathing" }
        let stretches = items.filter { !$0.uid.hasSuffix("-flush") && $0.uid != breathing?.uid }
        for it in flush + stretches.dropFirst(2).reversed() where !fits {
            guard cool - it.estSec >= FinishEarly.minCooldownSec else { continue }
            blocks.remove(it.uid)
            cool -= it.estSec
        }
    }
}
