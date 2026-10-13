import Testing
@testable import WorkoutEngine

/// #225: 3D body map built from the 2D sheets; taps on the mesh resolve through the 2D hit test.
@Suite struct BodyMeshTests {
    @Test(arguments: BodyMapLayout.Figure.allCases)
    func meshIsClosedAndInRange(figure: BodyMapLayout.Figure) {
        let mesh = BodyMesh.build(figure)
        for (s, front) in [(mesh.front, true), (mesh.back, false)] {
            #expect(s.positions.count > 3000)
            #expect(s.positions.count == s.normals.count && s.positions.count == s.uvs.count)
            #expect(s.indices.count % 3 == 0 && s.indices.count > s.positions.count)
            #expect(s.indices.allSatisfy { Int($0) < s.positions.count })
            #expect(s.positions.allSatisfy { front ? $0.z >= 0 : $0.z <= 0 })
            #expect(s.positions.allSatisfy { abs($0.x) <= 101 && $0.y >= -1 && $0.y <= 411 })
            #expect(s.uvs.allSatisfy { $0.x >= -0.01 && $0.x <= 1.01 && $0.y >= -0.01 && $0.y <= 1.01 })
        }
        // Both surfaces share the contour (same grid), so the figure has no gap at the sides.
        #expect(mesh.front.positions.count == mesh.back.positions.count)
        // A rounded body: the torso is several units deep.
        #expect((mesh.front.positions.map(\.z).max() ?? 0) > 15)
    }

    @Test(arguments: BodyMapLayout.Figure.allCases)
    func modelPointsHitTheSameMuscleAsTheSheet(figure: BodyMapLayout.Figure) {
        for side in BodyMapLayout.Side.allCases {
            for shape in BodyMapLayout.shapes(side, figure: figure) {
                guard BodyMapLayout.muscle(at: shape.midX, shape.midY, side: side, figure: figure) == shape.muscle else { continue }
                let x = side == .front ? shape.midX - 100 : 100 - shape.midX
                let p = SIMD3(Float(x), Float(410 - shape.midY), side == .front ? 8 : -8)
                #expect(BodyMesh.muscle(atModel: p, figure: figure, tolerance: 0) == shape.muscle, "\(figure) \(side) \(shape.muscle)")
            }
        }
    }

    @Test func backOfTheFigureShowsBackMuscles() {
        // Behind the right buttock (design x 82 on the back sheet = model x 18).
        #expect(BodyMesh.muscle(atModel: SIMD3(18, 410 - 208, -12), figure: .male) == .glutes)
        #expect(BodyMesh.muscle(atModel: SIMD3(-19, 410 - 95, 12), figure: .male) == .chest)
        #expect(BodyMesh.centre(of: .glutes, figure: .male)?.side == .back)
        #expect(BodyMesh.centre(of: .chest, figure: .male)?.side == .front)
    }
}
