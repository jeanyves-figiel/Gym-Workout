import Foundation

// MARK: - Variation rotation (#182)

extension Profile {
    /// Accessories cycle through their variations week to week (#182); nil = off, so plans stay as generated.
    /// Has no effect with `.same` variety, which repeats week 1 on purpose.
    public var rotatesVariations: Bool { rotateVariations == true && planVariety != .same }
}

extension WeekPlan {
    /// Accessory exercises swapped for another member of their family each week: week 1 keeps the generated pick,
    /// later weeks step through the family (base and variations the member's equipment and level allow, same
    /// category and unit). Main lifts stay put for progression; exercises with a kept swap on that day are left
    /// for the swap. Deterministic per item, so the same week always gets the same picks.
    public func rotatingVariations(for profile: Profile, swaps: [ExerciseSwap] = []) -> WeekPlan {
        guard profile.rotatesVariations, week > 1 else { return self }
        var p = self
        for s in p.sessions.indices where !p.sessions[s].isPlanInsert {
            let kept = Set(swaps.filter { $0.matches(p.sessions[s]) }.map(\.from))
            var used = Set(p.sessions[s].blocks.flatMap(\.items).map(\.exerciseId))
            for b in p.sessions[s].blocks.indices where [.strength, .power].contains(p.sessions[s].blocks[b].kind) {
                for i in p.sessions[s].blocks[b].items.indices {
                    let item = p.sessions[s].blocks[b].items[i]
                    guard !kept.contains(item.exerciseId), let e = Exercise.find(item.exerciseId), !e.main else { continue }
                    let options = e.rotationFamily(for: profile)
                    guard options.count > 1, let start = options.firstIndex(where: { $0.id == e.id }) else { continue }
                    let offset = item.uid.unicodeScalars.reduce(0) { $0 + Int($1.value) } % options.count
                    var pick = options[(start + offset + week - 1) % options.count]
                    if pick.id != e.id, used.contains(pick.id) { pick = e }
                    guard pick.id != e.id else { continue }
                    used.insert(pick.id)
                    p.sessions[s].blocks[b].items[i].exerciseId = pick.id
                }
            }
        }
        return p
    }
}

extension Exercise {
    /// Family members a rotation may use for this exercise, in family order.
    func rotationFamily(for profile: Profile) -> [Exercise] {
        let equipment = Set(profile.equipment)
        return family.filter { m in
            m.id == id || (m.category == category && m.unit == unit && m.unilateral == unilateral
                && m.level <= profile.experience.level && Selector.isAvailable(m, equipment))
        }
    }
}
