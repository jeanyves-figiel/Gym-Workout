/// Exercise families (#174): a base exercise and its variations (`Exercise.variationOf`), so long lists stay
/// short — the base shows once with "+N variations" and the exercise page lists the rest.
extension Exercise {
    /// Ids of the library-only catalog extensions (#174, #182, #366); never generated, only picked by members.
    public static let libraryOnlyIds: Set<String> = Set((variationCatalog + gymAppCatalog + climbingCatalog).map(\.id))

    /// Base exercise id when this is a variation, else nil.
    public var baseId: String? { Exercise.variationOf[id] }

    /// Id of the family this exercise belongs to (its base, or itself).
    public var familyId: String { baseId ?? id }

    private static let variationsByBase: [String: [Exercise]] = Dictionary(grouping: catalog.filter { variationOf[$0.id] != nil }) {
        variationOf[$0.id]!
    }.mapValues { $0.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }

    /// Base first, then its variations by name (just this exercise when it has no family).
    public var family: [Exercise] {
        let base = Exercise.find(familyId) ?? self
        return [base] + (Exercise.variationsByBase[base.id] ?? [])
    }

    /// The other members of this exercise's family.
    public var relatives: [Exercise] { family.filter { $0.id != id } }

    /// Folds variations under their base when the base is in the same list; a variation whose base isn't
    /// listed stays a row of its own. Keeps the list's order.
    public static func folded(_ list: [Exercise]) -> [(exercise: Exercise, variations: [Exercise])] {
        let ids = Set(list.map(\.id))
        var under: [String: [Exercise]] = [:]
        for e in list { if let b = e.baseId, ids.contains(b) { under[b, default: []].append(e) } }
        return list.compactMap { e in
            if let b = e.baseId, ids.contains(b) { return nil }
            return (e, under[e.id] ?? [])
        }
    }

    /// Family members for the swap sheet: same family, the member's equipment and level.
    public func variationOptions(for profile: Profile, excluding: Set<String> = []) -> [Exercise] {
        let equipment = Set(profile.equipment)
        return relatives.filter { e in
            !excluding.contains(e.id) && e.level <= profile.experience.level && Selector.isAvailable(e, equipment)
        }
    }
}
