import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct FreestyleTests {
    private let profile = Profile(goal: .balanced, experience: .intermediate, climbingDaysPerWeek: 0)

    @Test func newSessionIsEmptyAndFreestyle() {
        let s = Freestyle.session()
        #expect(Freestyle.isFreestyle(s.id))
        #expect(s.blocks.flatMap(\.items).isEmpty)
        #expect(Freestyle.session().id != s.id)
    }

    @Test func settingSetsChangesOnlyThatExerciseAndItsTime() throws {
        let s = Freestyle.session()
        let a = try #require(Exercise.find("back-squat"))
        let b = try #require(Exercise.find("bench-press"))
        var blocks = Freestyle.adding(a, to: s.blocks, sessionId: s.id).blocks
        let added = Freestyle.adding(b, to: blocks, sessionId: s.id)
        blocks = added.blocks
        let uid = try #require(added.uid)
        let before = try #require(blocks.flatMap(\.items).first { $0.uid == uid })
        let more = Freestyle.settingSets(before.prescription.sets + 1, of: uid, in: blocks)
        let after = try #require(more.flatMap(\.items).first { $0.uid == uid })
        #expect(after.prescription.sets == before.prescription.sets + 1)
        #expect(after.estSec > before.estSec)
        #expect(more.flatMap(\.items).first?.prescription == blocks.flatMap(\.items).first?.prescription)
        #expect(Freestyle.settingSets(0, of: uid, in: blocks).flatMap(\.items).last?.prescription.sets == 1)
        #expect(Freestyle.settingSets(99, of: uid, in: blocks).flatMap(\.items).last?.prescription.sets == Freestyle.maxSets)
    }

    @Test func coachNamesAreKnownStrengthMovesWithinTheLimit() throws {
        let names = Freestyle.coachNames(profile: profile)
        #expect(!names.isEmpty)
        #expect(names.count <= Freestyle.coachNameLimit)
        #expect(names == names.sorted())
        #expect(names.contains(try #require(Exercise.find("back-squat")).name))
        #expect(names.allSatisfy { Exercise.named($0) != nil })
    }

    @Test func namedFreestyleNotByFocus() {
        #expect(Freestyle.session().displayTitle == Freestyle.title)
    }

    @Test func addingKeepsOrderAndBringsTheBlockBack() throws {
        let s = Freestyle.session()
        let a = try #require(Exercise.find("back-squat"))
        let b = try #require(Exercise.find("bench-press"))
        var blocks = Freestyle.adding(a, to: s.blocks, sessionId: s.id).blocks
        blocks = Freestyle.adding(b, to: blocks, sessionId: s.id).blocks
        #expect(blocks.flatMap(\.items).map(\.exerciseId) == ["back-squat", "bench-press"])
        let uids = blocks.flatMap(\.items).map(\.uid)
        for uid in uids { blocks.remove(uid) }
        #expect(blocks.isEmpty)
        let again = Freestyle.adding(a, to: blocks, sessionId: s.id)
        #expect(again.uid != nil)
        #expect(again.blocks.flatMap(\.items).count == 1)
    }

    @Test func emptyWorkoutStartsBigOnDifferentMuscles() {
        let picks = Freestyle.suggest(after: [], profile: profile)
        #expect(picks.count == Freestyle.pickCount)
        #expect(picks.contains { $0.main })
        #expect(Set(picks.compactMap { $0.primary.first?.group }).count == picks.count)
        for e in picks {
            #expect(e.category == .strength)
            #expect(e.equipment.allSatisfy { profile.equipment.contains($0) })
            #expect(e.level <= profile.experience.level)
        }
        #expect(Freestyle.suggest(after: [], profile: profile).map(\.id) == picks.map(\.id))
    }

    @Test func nextPicksSkipWhatIsDoneAndItsMuscles() throws {
        let s = Freestyle.session()
        let first = try #require(Freestyle.suggest(after: s.blocks, profile: profile).first)
        let blocks = Freestyle.adding(first, to: s.blocks, sessionId: s.id).blocks
        let next = Freestyle.suggest(after: blocks, profile: profile)
        #expect(!next.contains { $0.id == first.id })
        let hit = Freestyle.groupsHit(blocks)
        #expect(next.first.map { !Set($0.primary.map(\.group)).isSubset(of: hit) } == true)
    }

    @Test func doneBeforeRanksHigher() throws {
        let base = Freestyle.suggest(after: [], profile: profile, count: 40)
        let late = try #require(base.last)
        let picks = Freestyle.suggest(after: [], profile: profile, recent: [late.id], count: 40)
        let before = try #require(base.firstIndex { $0.id == late.id })
        let after = try #require(picks.firstIndex { $0.id == late.id })
        #expect(after <= before)
    }

    @Test func resumeLineSaysWhatIsKept() {
        #expect(Freestyle.resumeLine(exercises: 3, setsDone: 4) == "3 exercises · 4 sets done")
        #expect(Freestyle.resumeLine(exercises: 1, setsDone: 1) == "1 exercise · 1 set done")
        #expect(Freestyle.resumeLine(exercises: 2, setsDone: 0) == "2 exercises · none done yet")
    }
}
