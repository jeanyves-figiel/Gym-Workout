import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct MuscleWorkoutTests {
    private let profile = Profile(goal: .balanced, experience: .intermediate, climbingDaysPerWeek: 0)

    private func generate(_ groups: Set<MuscleGroup>, minutes: Int = 45, rest: RestStyle = .standard,
                          grouping: Grouping = .straight, profile: Profile? = nil, seed: UInt32 = 7) -> CustomWorkout {
        CustomWorkout.generate(MuscleWorkoutOptions(groups: groups, minutes: minutes, rest: rest, grouping: grouping),
                               profile: profile ?? self.profile, seed: seed)
    }

    @Test func noGroupsGivesEmptyWorkout() {
        #expect(generate([]).items.isEmpty)
    }

    @Test func picksOnlyChosenMusclesWithProfileEquipment() throws {
        for g in MuscleGroup.allCases {
            let w = generate([g])
            #expect(!w.items.isEmpty, "\(g)")
            for it in w.items {
                let e = try #require(it.exercise)
                #expect(e.category == .strength)
                #expect(e.primary.contains { $0.group == g }, "\(e.id) for \(g)")
                #expect(e.equipment.allSatisfy { profile.equipment.contains($0) })
                #expect(e.level <= profile.experience.level)
            }
            #expect(Set(w.items.map(\.exerciseId)).count == w.items.count)
        }
    }

    @Test func everyChosenGroupGetsAnExercise() {
        let groups: Set<MuscleGroup> = [.chest, .back, .arms]
        let w = generate(groups, minutes: 20)
        let hit = Set(w.items.compactMap(\.exercise).flatMap { $0.primary.map(\.group) })
        #expect(groups.isSubset(of: hit))
        #expect(w.name == "Chest + Arms + Back")
    }

    @Test func sizeFollowsDuration() {
        let short = generate([.legs, .hips], minutes: 30)
        let long = generate([.legs, .hips], minutes: 75)
        #expect(long.items.count > short.items.count)
        #expect(abs(short.session.estMin - 30) <= 10)
        #expect(long.items.count <= MuscleWorkoutOptions.maxExercises)
    }

    @Test func sameSeedSameWorkoutNewSeedVaries() {
        let a = generate([.chest, .back], seed: 1).items.map(\.exerciseId)
        #expect(a == generate([.chest, .back], seed: 1).items.map(\.exerciseId))
        let others = (2...6).map { generate([.chest, .back], seed: $0).items.map(\.exerciseId) }
        #expect(others.contains { $0 != a })
    }

    @Test func restFollowsStyle() {
        let long = generate([.chest], rest: .long)
        let short = generate([.chest], rest: .short)
        #expect(long.items.map(\.restSec).max()! > short.items.map(\.restSec).max()!)
        // Main lifts keep at least 90 s.
        #expect(short.items.first!.restSec >= 90 || short.items.first!.exercise?.main == false)
    }

    @Test func supersetsPairSameMuscleGroup() {
        let w = generate([.chest, .back], minutes: 60, grouping: .supersets)
        let labels = w.groupLabels
        #expect(!labels.isEmpty)
        let byLetter = Dictionary(grouping: w.items.filter { labels[$0.id] != nil }, by: { labels[$0.id]!.first! })
        for (_, members) in byLetter {
            #expect(members.count == 2)
            let groupsOf = members.map { m in Set(m.exercise!.primary.map(\.group)) }
            #expect(!groupsOf[0].intersection(groupsOf[1]).isEmpty)
            #expect(Set(members.map(\.restSec)).count == 1)
        }
        // Grouped members sit next to each other.
        let order = w.items.compactMap { labels[$0.id]?.first }
        for l in Set(order) {
            let idx = order.indices.filter { order[$0] == l }
            #expect(idx.last! - idx.first! == idx.count - 1)
        }
    }

    @Test func straightHasNoGroups() {
        #expect(generate([.chest, .back], minutes: 60).groupLabels.isEmpty)
    }

    @Test func groupsReachThePlayerSession() throws {
        let w = generate([.legs, .hips], minutes: 60, grouping: .circuits)
        let block = try #require(w.session.blocks.first)
        let grouped = block.items.filter { $0.group != nil }
        #expect(!grouped.isEmpty)
        #expect(block.note != nil)
        let members = block.groupMembers(of: grouped[0].uid)
        #expect(members.count >= 2)
        // First set of A1 → A2 with no rest.
        let next = block.next(after: members[0].uid, setsDone: [members[0].uid: 1])
        #expect(next?.uid == members[1].uid && next?.restSec == 0)
    }

    @Test func groupOfOneAfterEditPlaysStraight() throws {
        var w = generate([.chest, .back], minutes: 60, grouping: .supersets)
        let labels = w.groupLabels
        let pair = try #require(w.items.first { labels[$0.id] == "A1" })
        let partner = try #require(w.items.first { labels[$0.id] == "A2" })
        w.items.removeAll { $0.id == partner.id }
        #expect(w.groupLabels[pair.id] == nil)
        let item = try #require(w.session.blocks[0].items.first { $0.uid.hasSuffix(pair.id.uuidString.lowercased()) })
        #expect(item.group == nil)
    }

    @Test func groupSurvivesCodableAndDuplicate() throws {
        let w = generate([.chest, .back], minutes: 60, grouping: .supersets)
        let back = try JSONDecoder().decode(CustomWorkout.self, from: JSONEncoder().encode(w))
        #expect(back == w)
        #expect(w.duplicated().items.map(\.group) == w.items.map(\.group))
    }

    @Test func defaultsFromProfile() {
        let build = Profile(goal: .build, climbingDaysPerWeek: 0)
        let o = MuscleWorkoutOptions(profile: build)
        #expect(o.rest == build.goal.defaultRest && o.grouping == build.goal.defaultGrouping)
        #expect(MuscleWorkoutOptions.durations.contains(o.minutes))
        var custom = build
        custom.restStyle = .short
        #expect(MuscleWorkoutOptions(profile: custom).rest == .short)
    }

    @Test func homeEquipmentStillWorks() {
        let home = Profile(goal: .balanced, climbingDaysPerWeek: 0, equipment: [.dumbbells])
        let w = generate([.chest, .legs], profile: home)
        #expect(!w.items.isEmpty)
        #expect(w.items.allSatisfy { $0.exercise!.equipment.allSatisfy { $0 == .dumbbells } })
    }
}
