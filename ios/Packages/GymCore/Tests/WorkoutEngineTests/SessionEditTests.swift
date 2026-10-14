import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct SessionEditTests {
    private let profile = Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0)

    private var plan: WeekPlan { Generator.generateWeek(profile, seed: 42) }

    private func strength(_ blocks: [Block]) -> [PlannedExercise] { blocks.first { $0.kind == .strength }?.items ?? [] }

    @Test func editAppliesToItsSessionOnly() throws {
        let p = plan
        let s = p.sessions[0]
        var blocks = s.blocks
        let gone = try #require(strength(blocks).last)
        blocks.remove(gone.uid)
        let edit = SessionEdit(sessionId: s.id, week: p.week, base: s.editBase, blocks: blocks)
        let edited = p.applying(edits: [edit])
        #expect(!edited.sessions[0].blocks.flatMap(\.items).contains { $0.uid == gone.uid })
        #expect(edited.sessions[0].estMin <= s.estMin)
        for i in p.sessions.indices.dropFirst() { #expect(edited.sessions[i] == p.sessions[i]) }
    }

    @Test func replannedSessionDropsTheEdit() {
        let s = plan.sessions[0]
        var other = s
        other.blocks[0].items[0].exerciseId = "something-else"
        let edit = SessionEdit(sessionId: s.id, week: 1, base: s.editBase, blocks: [])
        #expect(other.applying(edit) == other)
        #expect(s.applying(edit).blocks.isEmpty)
    }

    @Test func swapKeepsPlaceAndPrescription() throws {
        var blocks = plan.sessions[0].blocks
        let item = try #require(strength(blocks).first)
        let to = try #require(Exercise.get(item.exerciseId).swapOptions(for: profile).first)
        blocks.swap(item.uid, to: to.id)
        let after = try #require(strength(blocks).first)
        #expect(after.uid == item.uid && after.exerciseId == to.id && after.prescription == item.prescription)
    }

    @Test func addedExerciseLandsInItsBlockWithAStartingPrescription() throws {
        var blocks = plan.sessions[0].blocks
        let before = blocks.itemCount
        let uid = try #require(blocks.add(Exercise.get("cable-fly"), to: .strength, sessionId: "w1s0"))
        #expect(blocks.itemCount == before + 1)
        let added = try #require(strength(blocks).last)
        #expect(added.uid == uid && added.exerciseId == "cable-fly" && added.prescription.sets == 3 && added.estSec > 0)
    }

    @Test func setsChangeScalesTheEstimate() throws {
        var blocks = plan.sessions[0].blocks
        let item = try #require(strength(blocks).first)
        blocks.setSets(item.uid, item.prescription.sets * 2)
        let after = try #require(strength(blocks).first)
        #expect(after.prescription.sets == item.prescription.sets * 2)
        #expect(after.estSec > item.estSec)
        blocks.setSets(item.uid, 99)
        #expect(strength(blocks).first?.prescription.sets == CustomWorkout.setsRange.upperBound)
    }

    @Test func removingFromAPairEndsTheGroup() {
        let a = PlannedExercise(uid: "a", exerciseId: "bench-press", slot: .hPush,
                                prescription: Prescription(sets: 3, reps: "8", restSec: 90), estSec: 300)
        var b1 = a, b2 = a, drill = a
        b1.uid = "b"; b1.group = "A1"
        b2.uid = "c"; b2.group = "A2"
        drill.uid = "d"; drill.supersetWith = "c"
        var blocks = [Block(kind: .strength, title: "Strength", targetMin: 20, items: [a, b1, b2, drill])]
        blocks.remove("c")
        #expect(blocks[0].items.map(\.uid) == ["a", "b"])
        #expect(blocks[0].items[1].group == nil)
    }

    @Test func moveRenumbersGroups() {
        func item(_ uid: String, _ group: String?) -> PlannedExercise {
            var p = PlannedExercise(uid: uid, exerciseId: "bench-press", slot: .hPush,
                                    prescription: Prescription(sets: 3, reps: "8", restSec: 90), estSec: 300)
            p.group = group
            return p
        }
        var blocks = [Block(kind: .strength, title: "Strength", targetMin: 20, items: [item("x", "A1"), item("y", "A2"), item("z", nil)])]
        blocks.move(in: .strength, from: [1], to: 0)
        #expect(blocks[0].items.map(\.uid) == ["y", "x", "z"])
        #expect(blocks[0].items.map(\.group) == ["A1", "A2", nil])
        blocks.move(in: .strength, from: [0], to: 3)
        #expect(blocks[0].items.map(\.uid) == ["x", "z", "y"])
    }

    @Test func emptiedBlockGoes() {
        var blocks = plan.sessions[0].blocks
        let first = blocks[0]
        for it in first.items { blocks.remove(it.uid) }
        #expect(!blocks.contains { $0.kind == first.kind })
    }

    @Test func editRoundTrips() throws {
        let s = plan.sessions[0]
        let edit = SessionEdit(sessionId: s.id, week: 2, base: s.editBase, blocks: s.blocks)
        let back = try JSONDecoder().decode(SessionEdit.self, from: JSONEncoder().encode(edit))
        #expect(back == edit)
    }
}
