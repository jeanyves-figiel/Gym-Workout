/// Training style (#78): rest between sets and how strength accessories are grouped.
/// Defaults follow the goal (long rests for mass and strength, short rests and grouping for a toned, lean look);
/// the user can override both in the training profile.

public enum RestStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Full recovery, heavier loads: mass and strength.
    case long
    /// The goal's own rest times (plans before #78).
    case standard
    /// Denser sessions: toned and lean.
    case short
    public var id: String { rawValue }
}

public enum Grouping: String, Codable, CaseIterable, Sendable, Identifiable {
    /// All sets of one exercise, then the next.
    case straight
    /// Accessories in pairs that train the same muscle group, rest after the pair.
    case supersets
    /// Accessories in rounds of up to 4 for the same body area, rest after the round.
    case circuits
    public var id: String { rawValue }
}

/// Muscle group used to group exercises "of the same category".
public enum SetGroup: String, Sendable {
    case push, pull, arms, legs, core

    /// Coarser area used by circuits: upper body, lower body, core.
    var area: String {
        switch self {
        case .push, .pull, .arms: "upper"
        case .legs: "legs"
        case .core: "core"
        }
    }

    public var label: String {
        switch self {
        case .push: "Push"
        case .pull: "Pull"
        case .arms: "Arms"
        case .legs: "Legs"
        case .core: "Core"
        }
    }
}

extension Pattern {
    /// Muscle group of a strength slot; nil for power/general patterns.
    public var setGroup: SetGroup? {
        switch self {
        case .squat, .hinge, .singleLeg, .kneeFlex, .kneeExt, .calves: .legs
        case .hPush, .vPush, .lateralRaise: .push
        case .hPull, .vPull, .shoulderHealth, .forearmAntagonist: .pull
        case .armsFlex, .armsExt: .arms
        case .coreAntiExt, .coreAntiRot, .coreFlex, .carry: .core
        case .jump, .throw, .ballistic, .upperPlyo, .general: nil
        }
    }
}

extension RestStyle {
    public var label: String {
        switch self {
        case .long: "Long rests"
        case .standard: "Standard"
        case .short: "Short rests"
        }
    }

    public var blurb: String {
        switch self {
        case .long: "Full recovery · heavier loads · mass"
        case .standard: "Balanced recovery and pace"
        case .short: "More density · toned & lean"
        }
    }

    /// Range shown on the setting card.
    public var range: (value: String, unit: String) {
        switch self {
        case .long: ("2–3", "MIN")
        case .standard: ("60–120", "SEC")
        case .short: ("30–60", "SEC")
        }
    }

    /// Rest for a strength exercise. Main lifts never drop below 90 s; light prehab/core stays short.
    func restSec(_ base: Int, main: Bool, light: Bool) -> Int {
        switch self {
        case .standard: base
        case .long: light ? 60 : max(base, main ? 180 : 120)
        case .short: light ? 30 : (main ? 90 : min(base, 45))
        }
    }
}

extension Grouping {
    public var label: String {
        switch self {
        case .straight: "Straight sets"
        case .supersets: "Supersets"
        case .circuits: "Circuits"
        }
    }

    public var blurb: String {
        switch self {
        case .straight: "All sets of one exercise, then the next"
        case .supersets: "Accessories in pairs of the same muscle group"
        case .circuits: "Up to 4 accessories for one body area, in rounds"
        }
    }

    /// Big number + caption shown on the setting card.
    public var size: (value: String, unit: String) {
        switch self {
        case .straight: ("1", "AT A TIME")
        case .supersets: ("2", "PER GROUP")
        case .circuits: ("2–4", "PER ROUND")
        }
    }
}

extension Goal {
    /// Rest style this goal recommends.
    public var defaultRest: RestStyle {
        switch self {
        case .strength, .athletic, .build: .long
        case .balanced, .climbing: .standard
        case .endurance: .short
        }
    }

    /// Grouping this goal recommends.
    public var defaultGrouping: Grouping {
        switch self {
        case .strength, .athletic, .balanced, .climbing: .straight
        case .build: .supersets
        case .endurance: .circuits
        }
    }
}

extension Profile {
    /// Rest style in effect: the user's choice, else the goal's default.
    public var rest: RestStyle { restStyle ?? goal.defaultRest }
    /// Grouping in effect: the user's choice, else the goal's default.
    public var group: Grouping { grouping ?? goal.defaultGrouping }
}

// MARK: Grouping a strength block

extension Generator {
    /// Groups the strength block's accessories per the profile's grouping. The main lift stays straight sets;
    /// prehab supersetted into another exercise's rest stays attached to it. Members are moved next to each other,
    /// get the same rest (taken after the round) and a label: "A1", "A2", "B1", …
    static func applyGrouping(_ block: Block, _ grouping: Grouping) -> Block {
        guard grouping != .straight, block.kind == .strength else { return block }
        var b = block
        let attached = Dictionary(grouping: b.items.filter { $0.supersetWith != nil }, by: { $0.supersetWith! })
        // Candidates: non-main, standalone strength exercises (not a prehab partner riding another's rest).
        let mainUid = b.items.first?.uid
        let free = b.items.filter { $0.uid != mainUid && $0.supersetWith == nil && $0.slot.setGroup != nil }
        let key: (PlannedExercise) -> String = { item in
            let g = item.slot.setGroup!
            return grouping == .supersets ? g.rawValue : g.area
        }
        let size = grouping == .supersets ? 2 : 4
        var buckets: [String: [PlannedExercise]] = [:]
        var order: [String] = []
        for item in free {
            let k = key(item)
            if buckets[k] == nil { order.append(k) }
            buckets[k, default: []].append(item)
        }
        var groups: [[PlannedExercise]] = []
        for k in order {
            let members = buckets[k]!
            var i = 0
            while i < members.count {
                let chunk = Array(members[i..<min(i + size, members.count)])
                // A trailing single can't group: it joins the previous group of that area (circuits) or stays straight.
                if chunk.count == 1 {
                    if grouping == .circuits, !groups.isEmpty, key(groups[groups.count - 1][0]) == k {
                        groups[groups.count - 1].append(chunk[0])
                    }
                } else {
                    groups.append(chunk)
                }
                i += size
            }
        }
        guard !groups.isEmpty else { return b }

        // Rebuild the item list: each group at its first member's position, followed by attached prehab.
        let grouped = Set(groups.flatMap { $0.map(\.uid) })
        var out: [PlannedExercise] = []
        var letter = 0
        for item in b.items where item.supersetWith == nil {
            if let g = groups.first(where: { $0.first?.uid == item.uid }) {
                let label = String(Character(Unicode.Scalar(UInt8(65 + letter % 26))))
                letter += 1
                let rest = g.map(\.prescription.restSec).max() ?? 0
                let rounds = g.map(\.prescription.sets).max() ?? 1
                for (n, var m) in g.enumerated() {
                    m.group = "\(label)\(n + 1)"
                    m.prescription.restSec = rest
                    m.pairedWith = n == g.count - 1 ? m.pairedWith ?? g.compactMap(\.pairedWith).first : nil
                    let first = n == 0
                    let note = first ? (g.count == 2 ? "Superset" : "Circuit") + ": \(g.count) exercises back to back, rest after the round" : nil
                    if let note { m.prescription.note = [note, m.prescription.note].compactMap { $0 }.joined(separator: " · ") }
                    m.estSec = groupedSec(m, rounds: rounds, rest: rest, last: n == g.count - 1)
                    out.append(m)
                    out += attached[m.uid] ?? []
                }
            } else if !grouped.contains(item.uid) {
                out.append(item)
                out += attached[item.uid] ?? []
            }
        }
        b.items = out
        let style = grouping == .supersets ? "Supersets" : "Circuits"
        b.note = [b.note, "\(style): same-letter exercises back to back (A1 → A2), rest after the round."].compactMap { $0 }.joined(separator: " ")
        return b
    }

    /// Grouping can leave the block short when the focus has no more slots to fill: add a round to the groups
    /// (up to 5 sets) until the block is within a minute of its target.
    static func fillGroupedTime(_ block: Block, targetMin: Int) -> Block {
        var b = block
        var deficit = Double(targetMin * 60) - Double(b.items.reduce(0) { $0 + $1.estSec })
        let letters = Array(Set(b.items.compactMap { $0.group?.first })).sorted()
        var progress = true
        while deficit > 60 && progress {
            progress = false
            for letter in letters where deficit > 60 {
                let idx = b.items.indices.filter { b.items[$0].group?.first == letter }
                guard let lastIdx = idx.last, idx.allSatisfy({ b.items[$0].prescription.sets < 5 }) else { continue }
                let rest = b.items[lastIdx].prescription.restSec
                var added = 0
                for i in idx {
                    let m = b.items[i]
                    let rounds = m.prescription.sets
                    let restPart = i == lastIdx ? max(0, rounds - 1) * rest : 0
                    let perSet = (m.estSec - restPart) / max(1, rounds)
                    b.items[i].prescription.sets += 1
                    let extra = perSet + (i == lastIdx ? rest : 0)
                    b.items[i].estSec += extra
                    added += extra
                }
                deficit -= Double(added)
                progress = true
            }
        }
        return b
    }

    /// Time of one member in a group: its work sets plus a short move to the next exercise; the round's rest is
    /// carried by the last member.
    static func groupedSec(_ item: PlannedExercise, rounds: Int, rest: Int, last: Bool) -> Int {
        let p = item.prescription
        let restIn = max(0, p.sets - 1) * p.restSec
        let work = max(0, item.estSec - restIn - Int(transitionSec))
        let move = 15 * p.sets
        return work + move + (last ? max(0, rounds - 1) * rest : 0)
    }
}

// MARK: Playing a grouped block

extension Block {
    /// Members of the group `uid` belongs to, in order; just the item when it isn't grouped.
    public func groupMembers(of uid: String) -> [PlannedExercise] {
        guard let item = items.first(where: { $0.uid == uid }) else { return [] }
        guard let g = item.group, let letter = g.first else { return [item] }
        return items.filter { $0.group?.first == letter && $0.supersetWith == nil }
    }

    /// Where to go after finishing a set of `uid`, given sets done so far per uid (including the one just done).
    /// Straight sets: the same exercise until its sets are done. Grouped: the next member with sets left in this
    /// round (no rest, just move), or after the round's last member the first member with sets left, after the rest.
    /// nil when the exercise (or the whole group) is finished.
    public func next(after uid: String, setsDone: [String: Int]) -> (uid: String, restSec: Int)? {
        let members = groupMembers(of: uid)
        guard let i = members.firstIndex(where: { $0.uid == uid }) else { return nil }
        let left: (PlannedExercise) -> Bool = { setsDone[$0.uid, default: 0] < $0.prescription.sets }
        if members.count == 1 {
            return left(members[0]) ? (uid, members[0].prescription.restSec) : nil
        }
        let round = setsDone[uid, default: 0]
        // Later members still owe a set this round.
        if let n = members[(i + 1)...].first(where: { left($0) && setsDone[$0.uid, default: 0] < round }) {
            return (n.uid, 0)
        }
        guard let first = members.first(where: left) else { return nil }
        return (first.uid, members[i].prescription.restSec)
    }
}
