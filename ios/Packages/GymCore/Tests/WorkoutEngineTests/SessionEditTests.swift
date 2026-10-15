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
        let added0 = blocks.add(Exercise.get("cable-fly"), to: .strength, sessionId: "w1s0")
        let uid = try #require(added0)
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

    @Test func splitTurnsASupersetIntoStraightSets() {
        func item(_ uid: String, _ group: String?, note: String? = nil) -> PlannedExercise {
            var p = PlannedExercise(uid: uid, exerciseId: "bench-press", slot: .hPush,
                                    prescription: Prescription(sets: 4, reps: "10-15", restSec: 60, note: note), estSec: 300)
            p.group = group
            return p
        }
        var drill = item("d", nil)
        drill.supersetWith = "y"
        let a1 = item("x", "A1", note: "Superset: 2 exercises back to back, rest after the round · Slow negatives")
        let b = [Block(kind: .strength, title: "Strength", targetMin: 20,
                       items: [a1, item("y", "A2"), drill, item("p", "B1"), item("q", "B2")])]
        var blocks = b
        blocks.split("y")
        #expect(blocks[0].items.map(\.uid) == ["x", "y", "d", "p", "q"])
        #expect(blocks[0].items.map(\.group) == [nil, nil, nil, "A1", "A2"])
        #expect(blocks[0].items[0].prescription.note == "Slow negatives")
        #expect(blocks[0].items[2].supersetWith == "y")
        // Straight sets rest between sets, so each takes longer than as a superset member.
        #expect(blocks[0].items[0].estSec > a1.estSec)
        // Split from the second member: its sets come first.
        var fromA2 = b
        fromA2.split("q")
        #expect(fromA2[0].items.map(\.uid) == ["x", "y", "d", "q", "p"])
        #expect(fromA2[0].items.map(\.group) == ["A1", "A2", nil, nil, nil])
        // Straight exercise: nothing to split.
        var straight = blocks
        straight.split("x")
        #expect(straight == blocks)
    }

    @Test func splitPlannedSuperset() throws {
        let p = Profile(goal: .build, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0, grouping: .supersets)
        let s = try #require(Generator.generateWeek(p, seed: 42).sessions.first { strength($0.blocks).contains { $0.group != nil } })
        let grouped = try #require(strength(s.blocks).first { $0.group != nil })
        var blocks = s.blocks
        blocks.split(grouped.uid)
        let after = try #require(strength(blocks).first { $0.uid == grouped.uid })
        #expect(after.group == nil && after.prescription.note?.hasPrefix("Superset") != true)
        #expect(blocks.flatMap(\.items).map(\.uid) == s.blocks.flatMap(\.items).map(\.uid))
    }

    @Test func removingFromAPairDropsTheSupersetNote() {
        var a = PlannedExercise(uid: "a", exerciseId: "bench-press", slot: .hPush,
                                prescription: Prescription(sets: 3, reps: "8", restSec: 90,
                                                           note: "Superset: 2 exercises back to back, rest after the round"),
                                estSec: 300)
        a.group = "A1"
        var b = a
        b.uid = "b"; b.group = "A2"; b.prescription.note = nil
        var blocks = [Block(kind: .strength, title: "Strength", targetMin: 20, items: [a, b])]
        blocks.remove("b")
        #expect(blocks[0].items[0].group == nil && blocks[0].items[0].prescription.note == nil)
    }

    @Test func editRoundTrips() throws {
        let s = plan.sessions[0]
        let edit = SessionEdit(sessionId: s.id, week: 2, base: s.editBase, blocks: s.blocks)
        let back = try JSONDecoder().decode(SessionEdit.self, from: JSONEncoder().encode(edit))
        #expect(back == edit)
    }
}
