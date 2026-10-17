import Foundation
import simd
import Testing
@testable import WorkoutEngine

/// The position guide's skinned body (#399 follow-up): the resource loads and poses land on the figure's joints.
@Suite struct BodyRigTests {
    @Test func bodyResourceLoads() throws {
        let rig = try #require(BodyRig.shared)
        #expect(rig.vertexCount > 20_000)
        #expect(rig.triangles.count % 3 == 0 && rig.triangles.count / 3 > rig.vertexCount)
        #expect(rig.boneNames.contains("wrist.L") && rig.boneNames.contains("upperleg01.R"))
        #expect(rig.cavity.count == rig.vertexCount && rig.phase.count == rig.vertexCount)
        // standing ~2.24 m tall on the floor in the rest pose, feet at y = 0
        let ys = rig.rest.map(\.y)
        let lo = try #require(ys.min()), hi = try #require(ys.max())
        #expect(lo > -1 && lo < 2)
        #expect(hi > 200 && hi < 240)
        // every highlighted muscle name is one the catalog uses
        for name in BodyRig.muscleNames.dropFirst() {
            #expect(Muscle(rawValue: name) != nil, "\(name)")
        }
        #expect(rig.shorts.contains(true) && rig.muscle.contains(where: { $0 > 0 }))
    }

    @Test func malformedDataIsRejected() {
        #expect(BodyRig(data: Data()) == nil)
        #expect(BodyRig(data: Data("MWB2".utf8) + Data(repeating: 0, count: 16)) == nil)
    }

    @Test func squatPoseLandsOnTheFigure() throws {
        let rig = try #require(BodyRig.shared)
        let p = try #require(Exercise.get("back-squat").position)
        let bottom = p.keys[p.mainKey]
        let pose = rig.pose(bottom, mush: 0)
        #expect(pose.positions.count == rig.vertexCount)
        #expect(pose.normals.count == rig.vertexCount)
        // on the floor, not through it; lower than standing
        let ys = pose.positions.map(\.y)
        let lo = try #require(ys.min()), hi = try #require(ys.max())
        #expect(lo > -4)
        let standing = rig.pose(p.keys[0], mush: 0).positions.map(\.y).max() ?? 0
        #expect(hi < standing - 20)
        // the hands end up near the figure's hands (the bar on the back)
        for side in ["N", "F"] {
            let hand = try #require(pose.hands[side])
            let target = try #require(bottom["hand" + side])
            #expect(simd_length(hand - target) < 30, "\(side) hand \(hand) vs \(target)")
        }
        // the bar is held: both hands are fists
        #expect(pose.fists == ["N", "F"])
    }

    @Test func freeHandsStayOpenAndMushKeepsTheShape() throws {
        let rig = try #require(BodyRig.shared)
        let k = ExercisePosition.Key(joints: try #require(Exercise.get("back-squat").position).keys[0].joints, props: [])
        let plain = rig.pose(k, mush: 0)
        #expect(plain.fists.isEmpty)
        let mushed = rig.pose(k)
        var moved = 0.0, maxMove = 0.0
        for (a, b) in zip(plain.positions, mushed.positions) {
            let d = Double(simd_length(a - b))
            moved += d
            maxMove = max(maxMove, d)
        }
        // the mush only irons creases: small average change, nothing flies off
        #expect(moved / Double(rig.vertexCount) < 1.5)
        #expect(maxMove < 20)
    }

    @Test func bodyOffsetAndDumbbellAxisAreRead() throws {
        let k = ExercisePosition.Key(joints: [:], props: [], dy: -3)
        #expect(k.dy == -3)
        let curl = try #require(Exercise.get("db-curl").position).keys[0]
        let axes = curl.props.compactMap { p -> SIMD3<Double>? in
            if case let .weight(kind, _, _, axis) = p, kind == "db" { return axis }
            return nil
        }
        #expect(axes.allSatisfy { abs(simd_length($0) - 1) < 1e-6 }, "unit handle axes")
        // hanging at the sides: neutral grip, handle front-back
        #expect(BodyRig.dumbbellAxis(curl.joints, "N") == SIMD3(1, 0, 0))
    }

    @Test func workedMusclesFeatherIntoTheSkin() throws {
        let rig = try #require(BodyRig.shared)
        let w = rig.work([.chest])
        #expect(w.count == rig.vertexCount)
        #expect(w.contains(where: { $0 > 0.95 }) && w.contains(where: { $0 == 0 }))
        #expect(w.contains(where: { $0 > 0.1 && $0 < 0.9 }), "soft edge")
        #expect(rig.work([]).allSatisfy { $0 == 0 })
    }
}
