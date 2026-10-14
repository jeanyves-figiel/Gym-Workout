import Foundation

/// Member-steered variation of one week (#98): exercise swaps on top of the generated plan, keyed by item uid.
/// Belongs to the plan it was made for (`week` + `seed`); a new week or seed drops it.
public struct PlanVariation: Codable, Hashable, Sendable {
    public var week: Int
    public var seed: UInt32
    /// uid → replacement exercise id.
    public var swaps: [String: String]

    public init(week: Int, seed: UInt32, swaps: [String: String] = [:]) {
        self.week = week
        self.seed = seed
        self.swaps = swaps
    }

    public func applies(to plan: WeekPlan) -> Bool { plan.week == week && plan.seed == seed }
}

/// What a variation may change. Cool-down stretches follow the session's load and never change on their own.
public enum VaryPart: String, Codable, CaseIterable, Sendable, Identifiable {
    case accessories, mainLifts, warmup, power, cardio
    public var id: String { rawValue }

    public static let defaults: Set<VaryPart> = [.accessories, .warmup]
}

public struct VaryRequest: Sendable {
    /// Session ids to vary.
    public var sessions: Set<String>
    public var parts: Set<VaryPart>
    /// Item uids that keep their current exercise.
    public var keep: Set<String>
    /// Shuffle seed: same request + seed → same result.
    public var seed: UInt32

    public init(sessions: Set<String>, parts: Set<VaryPart> = VaryPart.defaults, keep: Set<String> = [], seed: UInt32) {
        self.sessions = sessions
        self.parts = parts
        self.keep = keep
        self.seed = seed
    }
}

extension Block {
    /// Which `VaryPart` an item at `index` belongs to; nil = never varied (cool-down).
    func varyPart(at index: Int) -> VaryPart? {
        switch kind {
        case .warmup, .mobility: .warmup
        case .power: .power
        case .cardio: .cardio
        case .cooldown: nil
        // First item of a (non-circuit) strength block is the main lift.
        case .strength: index == 0 && !title.lowercased().contains("circuit") ? .mainLifts : .accessories
        }
    }
}

extension WeekPlan {
    /// The plan with `variation`'s swaps (ignored when it was made for another week or seed). Superset notes
    /// that name a swapped host follow it.
    public func applying(_ variation: PlanVariation?) -> WeekPlan {
        guard let variation, variation.applies(to: self), !variation.swaps.isEmpty else { return self }
        var p = self
        for s in p.sessions.indices {
            var renamed: [String: (String, String)] = [:]
            for b in p.sessions[s].blocks.indices {
                for i in p.sessions[s].blocks[b].items.indices {
                    let item = p.sessions[s].blocks[b].items[i]
                    guard let to = variation.swaps[item.uid], to != item.exerciseId, let new = Exercise.find(to),
                          let old = Exercise.find(item.exerciseId) else { continue }
                    renamed[item.uid] = (old.name, new.name)
                    p.sessions[s].blocks[b].items[i].exerciseId = to
                }
            }
            guard !renamed.isEmpty else { continue }
            // Cool-down flush stays on the session's cardio machine.
            if let machine = p.sessions[s].blocks.first(where: { $0.kind == .cardio })?.items.first?.exerciseId,
               let cd = p.sessions[s].blocks.firstIndex(where: { $0.kind == .cooldown }) {
                for i in p.sessions[s].blocks[cd].items.indices where p.sessions[s].blocks[cd].items[i].uid.hasSuffix("-flush") {
                    p.sessions[s].blocks[cd].items[i].exerciseId = machine
                }
            }
            for b in p.sessions[s].blocks.indices {
                for i in p.sessions[s].blocks[b].items.indices {
                    guard let host = p.sessions[s].blocks[b].items[i].supersetWith, let names = renamed[host],
                          let note = p.sessions[s].blocks[b].items[i].prescription.note else { continue }
                    p.sessions[s].blocks[b].items[i].prescription.note = note.replacingOccurrences(of: names.0, with: names.1)
                }
            }
        }
        return p
    }

    /// Swaps for `request` on top of `current` (this plan's existing variation swaps): requested sessions get
    /// new picks for the requested parts; everything else, and every kept uid, stays as it is now.
    /// A swap keeps the movement role (same pattern, regions or muscles), unit, unilateral and level, and never
    /// brings in heavy grip work where the original had none, so each day keeps its muscle focus.
    public func varied(_ request: VaryRequest, profile: Profile, current: [String: String] = [:]) -> [String: String] {
        var swaps = current
        let base = self
        let now = applying(PlanVariation(week: week, seed: seed, swaps: current))
        // Exercises elsewhere in the week: avoided so the week stays varied.
        var weekIds = Set(now.sessions.flatMap { $0.blocks.flatMap { $0.items.map(\.exerciseId) } })
        for (si, session) in base.sessions.enumerated() where request.sessions.contains(session.id) {
            var sessionIds = Set(now.sessions[si].blocks.flatMap { $0.items.map(\.exerciseId) })
            for block in session.blocks {
                for (i, item) in block.items.enumerated() {
                    guard let part = block.varyPart(at: i), request.parts.contains(part), !request.keep.contains(item.uid),
                          let original = Exercise.find(item.exerciseId) else { continue }
                    let currentId = swaps[item.uid] ?? item.exerciseId
                    var pool = original.alternatives(for: profile).filter { e in
                        e.unit == original.unit && e.unilateral == original.unilateral
                            && (original.gripHeavy || !e.gripHeavy)
                            && e.id != currentId && !sessionIds.contains(e.id)
                    }
                    if original.id != currentId, !sessionIds.contains(original.id) { pool.append(original) }
                    if original.main, pool.contains(where: \.main) { pool = pool.filter(\.main) }
                    let fresh = pool.filter { !weekIds.contains($0.id) }
                    if !fresh.isEmpty { pool = fresh }
                    // Exercises the member dislikes (#299) only when nothing else fits.
                    let welcome = pool.filter { !profile.dislikes($0.id) }
                    if !welcome.isEmpty { pool = welcome }
                    guard !pool.isEmpty else { continue }
                    var rng = Rng(seed: request.seed ^ Self.stableHash(item.uid))
                    let pick = rng.pick(pool.sorted { $0.id < $1.id })
                    sessionIds.remove(currentId)
                    sessionIds.insert(pick.id)
                    weekIds.insert(pick.id)
                    swaps[item.uid] = pick.id == item.exerciseId ? nil : pick.id
                }
            }
        }
        return swaps
    }

    /// FNV-1a: stable across launches (unlike `hashValue`).
    static func stableHash(_ s: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        return h
    }
}
