import Foundation

/// The member's own exercise list for one workout (#295): swapped, removed, added, reordered exercises and set counts,
/// edited before starting. Applies to plan days, extras, quick sessions and library workouts alike, this workout only.
public struct SessionEdit: Codable, Hashable, Sendable {
    public var sessionId: String
    /// Plan week the session belongs to; nil for a library / example workout started on its own.
    public var week: Int?
    /// `Session.editBase` of the session the edit was made on: a re-planned session drops the edit.
    public var base: [String]
    public var blocks: [Block]

    public init(sessionId: String, week: Int?, base: [String], blocks: [Block]) {
        self.sessionId = sessionId
        self.week = week
        self.base = base
        self.blocks = blocks
    }
}

extension Session {
    /// What an edit was made on: every item's uid and exercise, in order.
    public var editBase: [String] { blocks.flatMap(\.items).map { "\($0.uid)=\($0.exerciseId)" } }

    /// The session with the member's edit, when it was made on this exact session; otherwise unchanged.
    public func applying(_ edit: SessionEdit?) -> Session {
        guard let edit, edit.sessionId == id, edit.base == editBase else { return self }
        var s = self
        let before = blocks.reduce(0) { $0 + $1.items.reduce(0) { $0 + $1.estSec } }
        let after = edit.blocks.reduce(0) { $0 + $1.items.reduce(0) { $0 + $1.estSec } }
        s.blocks = edit.blocks
        s.estMin = max(1, estMin + Int((Double(after - before) / 60).rounded()))
        return s
    }
}

extension WeekPlan {
    /// Plan with the member's per-workout edits (#295).
    public func applying(edits: [SessionEdit]) -> WeekPlan {
        guard !edits.isEmpty else { return self }
        var p = self
        p.sessions = sessions.map { s in s.applying(edits.first { $0.sessionId == s.id }) }
        return p
    }
}

/// Edits on a list of blocks; every change keeps supersets and circuits consistent.
extension [Block] {
    public var itemCount: Int { reduce(0) { $0 + $1.items.count } }
    public var estSec: Int { reduce(0) { $0 + $1.items.reduce(0) { $0 + $1.estSec } } }

    /// Replaces an exercise, keeping its place, prescription and group.
    public mutating func swap(_ uid: String, to exerciseId: String) {
        for b in indices {
            for i in self[b].items.indices where self[b].items[i].uid == uid {
                self[b].items[i].exerciseId = exerciseId
                if let e = Exercise.find(exerciseId) { self[b].items[i].slot = e.pattern }
            }
        }
    }

    /// Removes an exercise; drills done in its rest go with it, and a group left with one exercise ends.
    public mutating func remove(_ uid: String) {
        for b in indices {
            self[b].items.removeAll { $0.uid == uid || $0.supersetWith == uid }
            self[b].regroup()
        }
        removeAll { $0.items.isEmpty }
    }

    /// Moves exercises within a block (List `onMove`).
    public mutating func move(in kind: BlockKind, from: IndexSet, to: Int) {
        guard let b = firstIndex(where: { $0.kind == kind }) else { return }
        let moving = from.sorted().map { self[b].items[$0] }
        var rest = self[b].items.enumerated().filter { !from.contains($0.offset) }.map(\.element)
        let at = to - from.filter { $0 < to }.count
        rest.insert(contentsOf: moving, at: Swift.min(Swift.max(0, at), rest.count))
        self[b].items = rest
        self[b].regroup()
    }

    /// Sets an exercise's set count (1…20); its time estimate follows.
    public mutating func setSets(_ uid: String, _ sets: Int) {
        let n = Swift.min(Swift.max(sets, CustomWorkout.setsRange.lowerBound), CustomWorkout.setsRange.upperBound)
        for b in indices {
            for i in self[b].items.indices where self[b].items[i].uid == uid {
                let old = Swift.max(1, self[b].items[i].prescription.sets)
                self[b].items[i].estSec = Swift.max(30, self[b].items[i].estSec * n / old)
                self[b].items[i].prescription.sets = n
            }
        }
    }

    /// Adds an exercise at the end of the block of `kind` with a starting prescription; returns its uid.
    @discardableResult
    public mutating func add(_ exercise: Exercise, to kind: BlockKind, sessionId: String, id: UUID = UUID()) -> String? {
        guard let b = firstIndex(where: { $0.kind == kind }) else { return nil }
        let it = CustomWorkout.Item(adding: exercise)
        let measure = CustomWorkout.Measure(exercise)
        let perSet: Double = switch measure {
        case .reps: Double(it.reps) * (exercise.secPerRep ?? 3) * (exercise.unilateral ? 2 : 1)
        case .seconds: Double(it.reps) * (exercise.unilateral ? 2 : 1)
        case .minutes: Double(it.reps) * 60
        }
        let uid = "\(sessionId)-add-\(id.uuidString.lowercased().prefix(8))"
        self[b].items.append(PlannedExercise(
            uid: uid, exerciseId: exercise.id, slot: exercise.pattern,
            prescription: Prescription(sets: it.sets, reps: measure.text(it.reps), restSec: it.restSec),
            estSec: Int(perSet * Double(it.sets)) + (it.sets - 1) * it.restSec + 60))
        return uid
    }
}

extension Block {
    /// Renumbers groups in list order ("A1", "A2"…); a group left with one exercise ends, rest-time drills lose a missing host.
    mutating func regroup() {
        let uids = Set(items.map(\.uid))
        for i in items.indices where items[i].supersetWith.map({ !uids.contains($0) }) == true { items[i].supersetWith = nil }
        var counts: [Character: Int] = [:]
        for it in items where it.supersetWith == nil { if let l = it.group?.first { counts[l, default: 0] += 1 } }
        var seen: [Character: Int] = [:]
        for i in items.indices where items[i].supersetWith == nil {
            guard let l = items[i].group?.first else { continue }
            if counts[l, default: 0] < 2 {
                items[i].group = nil
            } else {
                seen[l, default: 0] += 1
                items[i].group = "\(l)\(seen[l]!)"
            }
        }
    }
}
