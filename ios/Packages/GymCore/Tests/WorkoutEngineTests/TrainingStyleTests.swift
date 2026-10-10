import Foundation
import Testing
@testable import WorkoutEngine

private func profile(_ goal: Goal, rest: RestStyle? = nil, grouping: Grouping? = nil, sessions: Int = 3) -> Profile {
    Profile(goal: goal, sessionsPerWeek: sessions, experience: .intermediate, climbingDaysPerWeek: 0,
            restStyle: rest, grouping: grouping)
}

private func strengthBlocks(_ p: Profile, seed: UInt32 = 5) -> [Block] {
    Generator.generateWeek(p, seed: seed).sessions.flatMap { $0.blocks.filter { $0.kind == .strength && $0.title == "Strength" } }
}

private func nx(_ b: Block, after uid: String, setsDone: [String: Int]) -> String {
    b.next(after: uid, setsDone: setsDone).map { "\($0.uid)/\($0.restSec)" } ?? "done"
}

@Suite struct TrainingStyleTests {
    @Test func goalDefaults() {
        #expect(profile(.strength).rest == .long)
        #expect(profile(.strength).group == .straight)
        #expect(profile(.build).rest == .long)
        #expect(profile(.build).group == .supersets)
        #expect(profile(.endurance).rest == .short)
        #expect(profile(.endurance).group == .circuits)
        #expect(profile(.balanced).rest == .standard)
        #expect(profile(.climbing).group == .straight)
    }

    @Test func userChoiceOverridesGoal() {
        let p = profile(.strength, rest: .short, grouping: .circuits)
        #expect(p.rest == .short)
        #expect(p.group == .circuits)
    }

    @Test func olderProfilesDecodeWithoutStyle() throws {
        let json = #"{"goal":"build","sessionsPerWeek":4,"experience":"beginner","climbingDaysPerWeek":0,"equipment":["dumbbells"]}"#
        let p = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        #expect(p.restStyle == nil && p.grouping == nil)
        #expect(p.rest == .long && p.group == .supersets)
    }

    @Test func plannedExerciseDecodesWithoutGroup() throws {
        let item = Generator.generateWeek(profile(.balanced), seed: 1).sessions[0].blocks[0].items[0]
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as! [String: Any]
        obj.removeValue(forKey: "group")
        let back = try JSONDecoder().decode(PlannedExercise.self, from: JSONSerialization.data(withJSONObject: obj))
        #expect(back.group == nil)
    }

    @Test func standardRestKeepsGoalRest() {
        let p = profile(.balanced, rest: .standard, grouping: .straight)
        let main = strengthBlocks(p).map { $0.items[0] }
        #expect(main.allSatisfy { $0.prescription.restSec == Goal.balanced.config.main.restSec })
    }

    @Test func longRestsLongerThanShort() {
        let long = strengthBlocks(profile(.balanced, rest: .long, grouping: .straight))
        let short = strengthBlocks(profile(.balanced, rest: .short, grouping: .straight))
        for b in long { #expect(b.items[0].prescription.restSec >= 180) }
        for b in short {
            #expect(b.items[0].prescription.restSec >= 90, "main lifts keep ≥ 90 s")
            for it in b.items.dropFirst() { #expect(it.prescription.restSec <= 45) }
        }
    }

    @Test func straightSetsHaveNoGroups() {
        let items = strengthBlocks(profile(.balanced, grouping: .straight)).flatMap(\.items)
        #expect(items.allSatisfy { $0.group == nil })
    }

    @Test(arguments: [Grouping.supersets, .circuits])
    func groupsShareMuscleGroupAndRest(grouping: Grouping) {
        var found = false
        for n in 2...6 {
            for b in strengthBlocks(profile(.balanced, grouping: grouping, sessions: n)) {
                #expect(b.items.first?.group == nil, "main lift stays straight sets")
                let labelled = b.items.filter { $0.group != nil }
                let byLetter = Dictionary(grouping: labelled) { $0.group!.first! }
                for (_, members) in byLetter {
                    found = true
                    #expect(members.count >= 2)
                    #expect(members.count <= (grouping == .supersets ? 2 : 5))
                    let groups = Set(members.map { $0.slot.muscleGroup!.rawValue })
                    let areas = Set(members.map { $0.slot.muscleGroup!.area })
                    if grouping == .supersets { #expect(groups.count == 1, "\(members.map(\.exerciseId))") }
                    else { #expect(areas.count == 1, "\(members.map(\.exerciseId))") }
                    #expect(Set(members.map(\.prescription.restSec)).count == 1)
                    #expect(members.allSatisfy { $0.supersetWith == nil })
                    // Members sit next to each other (attached prehab may follow a member).
                    let idx = members.map { m in b.items.firstIndex { $0.uid == m.uid }! }
                    let between = b.items[idx.min()!...idx.max()!].filter { $0.group == nil && $0.supersetWith == nil }
                    #expect(between.isEmpty)
                }
            }
        }
        #expect(found, "some session groups exercises")
    }

    @Test func noExerciseLostWhenGrouping() {
        for b in strengthBlocks(profile(.build, grouping: .circuits)) {
            #expect(Set(b.items.map(\.uid)).count == b.items.count)
        }
    }

    @Test func groupedPlayOrder() {
        func item(_ uid: String, sets: Int, group: String?) -> PlannedExercise {
            PlannedExercise(uid: uid, exerciseId: "db-curl", slot: .armsFlex,
                            prescription: Prescription(sets: sets, reps: "10", restSec: 60),
                            pairedWith: nil, supersetWith: nil, group: group, estSec: 60)
        }
        let b = Block(kind: .strength, title: "Strength", targetMin: 10,
                      items: [item("m", sets: 2, group: nil), item("a1", sets: 2, group: "A1"), item("a2", sets: 3, group: "A2")])
        // Straight item: same exercise until done, with rest.
        #expect(nx(b, after: "m", setsDone: ["m": 1]) == "m/60")
        #expect(nx(b, after: "m", setsDone: ["m": 2]) == "done")
        // A1 → A2 without rest, then rest back to A1.
        #expect(nx(b, after: "a1", setsDone: ["a1": 1]) == "a2/0")
        #expect(nx(b, after: "a2", setsDone: ["a1": 1, "a2": 1]) == "a1/60")
        #expect(nx(b, after: "a1", setsDone: ["a1": 2, "a2": 1]) == "a2/0")
        // A1 finished: A2's extra set after the rest.
        #expect(nx(b, after: "a2", setsDone: ["a1": 2, "a2": 2]) == "a2/60")
        #expect(nx(b, after: "a2", setsDone: ["a1": 2, "a2": 3]) == "done")
    }

    @Test(arguments: Goal.allCases)
    func styledPlansFitTargetTime(goal: Goal) {
        for g in Grouping.allCases {
            for r in RestStyle.allCases {
                let plan = Generator.generateWeek(profile(goal, rest: r, grouping: g, sessions: 4), seed: 9)
                for s in plan.sessions {
                    #expect(Double(abs(s.estMin - s.targetMin)) <= max(10, Double(s.targetMin) * 0.2), "\(goal) \(r) \(g) \(s.focus)")
                }
            }
        }
    }
}
