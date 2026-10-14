import Foundation
import Testing
@testable import WorkoutEngine

private func profile(_ grouping: Grouping, layout: GymLayout?, sessions: Int = 4) -> Profile {
    var p = Profile(goal: .balanced, sessionsPerWeek: sessions, experience: .intermediate, climbingDaysPerWeek: 0, grouping: grouping)
    p.gymLayout = layout
    return p
}

private func strengthBlocks(_ p: Profile, seed: UInt32 = 5) -> [Block] {
    Generator.generateWeek(p, seed: seed).sessions.flatMap { $0.blocks.filter { $0.kind == .strength && $0.title == "Strength" } }
}

/// Every item in one zone: zones change nothing.
private var oneZone: GymLayout { GymLayout(zones: [.init(id: "all", name: "All", color: 0, items: Equipment.allCases)]) }

@Suite struct GymLayoutTests {
    @Test func starterPlacesEveryItemOnce() {
        let l = GymLayout.starter
        for e in Equipment.allCases { #expect(l.zones.filter { $0.items.contains(e) }.count == 1, "\(e)") }
    }

    @Test func plainChunkingWithoutZones() {
        let g = GymLayout.chunk(Array(1...7), size: 2) { _, _ in true }
        #expect(g == [[1, 2], [3, 4], [5, 6], [7]])
        let odd = GymLayout.chunk(Array(1...5), size: 2) { a, b in a % 2 == b % 2 }
        #expect(odd == [[1, 3], [2, 4], [5]])
    }

    @Test(arguments: [Grouping.supersets, .circuits])
    func oneZoneKeepsPlansUnchanged(grouping: Grouping) {
        for n in 2...6 {
            let plain = Generator.generateWeek(profile(grouping, layout: nil, sessions: n), seed: 3)
            let zoned = Generator.generateWeek(profile(grouping, layout: oneZone, sessions: n), seed: 3)
            #expect(plain.sessions == zoned.sessions)
        }
    }

    @Test(arguments: [Grouping.supersets, .circuits])
    func groupsStayInOneZone(grouping: Grouping) {
        let layout = GymLayout.starter
        var found = false
        for n in 2...6 {
            for b in strengthBlocks(profile(grouping, layout: layout, sessions: n)) {
                let byLetter = Dictionary(grouping: b.items.filter { $0.group != nil }) { $0.group!.first! }
                for (_, members) in byLetter {
                    found = true
                    #expect(members.count >= 2)
                    let ex = members.map { Exercise.get($0.exerciseId) }
                    for a in ex { for c in ex { #expect(layout.near(a, c), "\(a.id) / \(c.id)") } }
                    let idx = members.map { m in b.items.firstIndex { $0.uid == m.uid }! }
                    let between = b.items[idx.min()!...idx.max()!].filter { $0.group == nil && $0.supersetWith == nil }
                    #expect(between.isEmpty)
                }
                // Letters run A, B, C… in order after the room order.
                let letters = b.items.compactMap { $0.group?.first }.reduce(into: [Character]()) { if $0.last != $1 { $0.append($1) } }
                #expect(letters == letters.indices.map { Character(Unicode.Scalar(UInt8(65 + $0))) })
            }
        }
        #expect(found)
    }

    @Test func zonedPlanKeepsEveryExercise() {
        for n in 2...6 {
            let plain = strengthBlocks(profile(.supersets, layout: nil, sessions: n))
            let zoned = strengthBlocks(profile(.supersets, layout: .starter, sessions: n))
            #expect(plain.map { Set($0.items.map(\.exerciseId)) } == zoned.map { Set($0.items.map(\.exerciseId)) })
            #expect(zip(plain, zoned).allSatisfy { $0.items.first?.uid == $1.items.first?.uid }, "main lift first")
        }
    }

    @Test func floorPlanNeighbours() {
        var l = GymLayout.starter
        #expect(!l.near(l.zones[0], l.zones[1]))
        l.zones[0].rect = .init(x: 0, y: 0, w: 0.5, h: 0.4)
        l.zones[1].rect = .init(x: 0.5, y: 0, w: 0.5, h: 0.4)
        l.zones[3].rect = .init(x: 0, y: 0.8, w: 1, h: 0.2)
        #expect(l.near(l.zones[0], l.zones[1]))
        #expect(!l.near(l.zones[0], l.zones[3]))
        #expect(l.hasPlan)
    }

    @Test func exerciseZoneIgnoresPortableItems() {
        let l = GymLayout.starter
        let bench = Exercise.catalog.first { !$0.equipment.isEmpty && $0.equipment.allSatisfy { $0.zone == .freeWeights } }!
        #expect(l.zone(of: bench)?.id == GymZone.freeWeights.rawValue)
        if let mat = Exercise.catalog.first(where: { !$0.equipment.isEmpty && Set($0.equipment).isSubset(of: GymLayout.portable) }) {
            #expect(l.zone(of: mat) == nil)
        }
    }

    @Test func moveAndRemoveZone() {
        var l = GymLayout.starter
        let z = GymLayout.Zone(id: "corner", name: "Corner", color: l.nextColor, items: [])
        l.zones.append(z)
        l.move(.kettlebells, to: "corner")
        #expect(l.zone(of: .kettlebells)?.id == "corner")
        #expect(l.zones.filter { $0.items.contains(.kettlebells) }.count == 1)
        l.remove("corner")
        #expect(l.zone(of: .kettlebells)?.id == GymZone.functional.rawValue)
        #expect(l.zone(id: "corner") == nil)
    }

    /// No zone (#289): an unassigned item belongs to no zone, so its exercises fit next to any other.
    @Test func unassignedItemFitsAnyZone() {
        var l = GymLayout.starter
        l.unassign(.barbell)
        #expect(l.zone(of: .barbell) == nil)
        #expect(l.zones.allSatisfy { !$0.items.contains(.barbell) })
        let bar = Exercise.catalog.first { $0.equipment == [.barbell] }
        let cardio = Exercise.catalog.first { !$0.equipment.isEmpty && $0.equipment.allSatisfy { $0.zone == .cardio } }!
        if let bar { #expect(l.near(bar, cardio)) }
        l.move(.barbell, to: GymZone.machines.rawValue)
        #expect(l.zone(of: .barbell)?.id == GymZone.machines.rawValue)
    }

    @Test func olderProfilesAndSavedGymsDecode() throws {
        let p = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(Profile()))
        #expect(p.gymLayout == nil)
        var q = Profile()
        q.gymLayout = .starter
        #expect(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(q)).gymLayout == .starter)
        let g = SavedGym(ref: SavedGym.customRef(name: "Home"), equipment: [.dumbbells], layout: .starter)
        #expect(try JSONDecoder().decode(SavedGym.self, from: JSONEncoder().encode(g)).layout == .starter)
    }
}
