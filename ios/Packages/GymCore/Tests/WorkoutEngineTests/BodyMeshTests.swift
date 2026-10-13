import Testing
@testable import WorkoutEngine

/// #225: sculpted 3D body for the 3D body map; taps on the mesh resolve through the 2D hit test.
@Suite struct BodyMeshTests {
    @Test(arguments: BodyMapLayout.Figure.allCases)
    func meshLoadsAndIsInRange(figure: BodyMapLayout.Figure) {
        let mesh = BodyMesh.of(figure)
        for s in [mesh.front, mesh.back] {
            #expect(s.positions.count > 10_000)
            #expect(s.positions.count == s.normals.count && s.positions.count == s.uvs.count)
            #expect(s.indices.count % 3 == 0 && s.indices.count > s.positions.count)
            #expect(s.indices.allSatisfy { Int($0) < s.positions.count })
            #expect(s.positions.allSatisfy { abs($0.x) <= 101 && $0.y >= -1 && $0.y <= 411 && abs($0.z) < 50 })
            #expect(s.uvs.allSatisfy { $0.x >= -0.01 && $0.x <= 1.01 && $0.y >= -0.01 && $0.y <= 1.01 })
        }
        // Front surface faces the front view, back surface the back.
        #expect(mesh.front.normals.allSatisfy { $0.z >= -0.9 })
        #expect(mesh.back.normals.allSatisfy { $0.z <= 0.9 })
        // A body, not a cut-out: the torso has depth.
        #expect((mesh.front.positions.map(\.z).max() ?? 0) - (mesh.back.positions.map(\.z).min() ?? 0) > 35)
        // Feet at the bottom, head at the top.
        #expect((mesh.front.positions.map(\.y).min() ?? 99) < 12)
        #expect((mesh.front.positions.map(\.y).max() ?? 0) > 395)
    }

    @Test(arguments: BodyMapLayout.Figure.allCases)
    func modelPointsHitTheSameMuscleAsTheSheet(figure: BodyMapLayout.Figure) {
        for side in BodyMapLayout.Side.allCases {
            for shape in BodyMapLayout.shapes(side, figure: figure) {
                guard BodyMapLayout.muscle(at: shape.midX, shape.midY, side: side, figure: figure) == shape.muscle else { continue }
                let x = side == .front ? shape.midX - 100 : 100 - shape.midX
                let p = SIMD3(Float(x), Float(410 - shape.midY), side == .front ? 8 : -8)
                #expect(BodyMesh.muscle(atModel: p, side: side, figure: figure, tolerance: 0) == shape.muscle, "\(figure) \(side) \(shape.muscle)")
            }
        }
    }

    @Test func backOfTheFigureShowsBackMuscles() {
        // Behind the right buttock (design x 82 on the back sheet = model x 18).
        #expect(BodyMesh.muscle(atModel: SIMD3(18, 410 - 208, -12), side: .back, figure: .male) == .glutes)
        #expect(BodyMesh.muscle(atModel: SIMD3(-19, 410 - 95, 12), side: .front, figure: .male) == .chest)
    }
}
