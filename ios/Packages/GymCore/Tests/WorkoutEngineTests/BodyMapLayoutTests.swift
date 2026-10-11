import Testing
@testable import WorkoutEngine

/// #79: every tap on the Explore body map opened Calves. #110: anatomical polygons, M and F figures.
/// #112: muscle audit (traps, serratus, deep core, lower abs, glute med, tibialis, soleus, brachialis, extensors).
@Suite struct BodyMapLayoutTests {
    @Test(arguments: BodyMapLayout.Side.allCases, BodyMapLayout.Figure.allCases)
    func centreOfEveryShapeHitsItsOwnMuscle(side: BodyMapLayout.Side, figure: BodyMapLayout.Figure) {
        for shape in BodyMapLayout.shapes(side, figure: figure) {
            #expect(BodyMapLayout.muscle(at: shape.midX, shape.midY, side: side, figure: figure) == shape.muscle, "\(figure) \(side) \(shape.muscle)")
        }
    }

    @Test(arguments: BodyMapLayout.Figure.allCases)
    func tapsResolveToDifferentMuscles(figure: BodyMapLayout.Figure) {
        func hit(_ x: Double, _ y: Double, _ side: BodyMapLayout.Side) -> Muscle? {
            BodyMapLayout.muscle(at: x, y, side: side, figure: figure)
        }
        #expect(hit(81, 95, .front) == .chest)
        #expect(hit(100, 152, .front) == .abs)
        #expect(hit(79, 264, .front) == .quads)
        #expect(hit(78, 357, .front) == .tibialis)
        #expect(hit(87, 345, .front) == .calves)
        #expect(hit(100, 190, .front) == .lowerAbs)
        #expect(hit(72, 198, .back) == .gluteMed)
        #expect(hit(79, 378, .back) == .soleus)
        #expect(hit(100, 66, .back) == .traps)
        #expect(hit(100, 90, .back) == .upperBack)
        #expect(hit(82, 208, .back) == .glutes)
        #expect(hit(120, 270, .back) == .hamstrings) // mirrored twin
        let hits = Set(BodyMapLayout.shapes(.front, figure: figure).compactMap { hit($0.midX, $0.midY, .front) })
        #expect(hits.count == BodyMapLayout.muscles(.front).count)
    }

    @Test func outsideMusclesHitsNothing() {
        #expect(BodyMapLayout.muscle(at: 2, 2, side: .front) == nil)
        #expect(BodyMapLayout.muscle(at: 100, 30, side: .back) == nil) // head
    }

    @Test func everyMuscleIsOnTheMap() {
        let shown = Set(BodyMapLayout.muscles(.front) + BodyMapLayout.muscles(.back))
        #expect(shown == Set(Muscle.allCases))
    }

    @Test(arguments: BodyMapLayout.Figure.allCases)
    func musclesSitInsideTheSilhouette(figure: BodyMapLayout.Figure) {
        for side in BodyMapLayout.Side.allCases {
            let body = BodyMapLayout.Shape(muscle: .abs, points: BodyMapLayout.outline(side, figure: figure)[1])
            for shape in BodyMapLayout.shapes(side, figure: figure) {
                #expect(body.contains(x: shape.midX, y: shape.midY), "\(figure) \(side) \(shape.muscle)")
            }
        }
    }

    @Test func femaleFigureIsNarrowerAtTheWaistWiderAtTheHips() {
        func span(_ f: BodyMapLayout.Figure, _ y: Double) -> Double {
            let pts = BodyMapLayout.outline(.front, figure: f)[1].filter { abs($0.y - y) < 12 && $0.x > 50 && $0.x < 100 }
            return 100 - (pts.map(\.x).min() ?? 100)
        }
        #expect(span(.female, 166) < span(.male, 166))
        #expect(span(.female, 214) > span(.male, 214))
    }
}

/// #112: every muscle on the map has at least one exercise that trains it directly.
@Suite struct MuscleAuditTests {
    @Test(arguments: Muscle.allCases)
    func everyMuscleHasADirectExercise(muscle: Muscle) {
        #expect(Exercise.catalog.contains { $0.primary.contains(muscle) }, "\(muscle)")
    }

    @Test func newMusclesDecodeAndOldOnesStayStable() throws {
        #expect(Muscle(rawValue: "upper-back") == .upperBack)
        #expect(Muscle(rawValue: "deep-core") == .deepCore)
        #expect(Muscle(rawValue: "glute-med") == .gluteMed)
        #expect(Muscle.allCases.count == 28)
    }
}

/// Explore muscle cards: each muscle gets a close-up thumbnail of the figure.
@Suite struct BodyMapFocusTests {
    @Test(arguments: Muscle.allCases, BodyMapLayout.Figure.allCases)
    func everyMuscleHasACloseUpAroundIt(muscle: Muscle, figure: BodyMapLayout.Figure) throws {
        let f = try #require(BodyMapLayout.focus(muscle, figure: figure), "\(muscle)")
        #expect(f.size >= 64 && f.size < 200, "\(muscle) \(f.size)")
        let hit = BodyMapLayout.shapes(f.side, figure: figure).filter { $0.muscle == muscle }
            .contains { $0.midX > f.x && $0.midX < f.x + f.size && $0.midY > f.y && $0.midY < f.y + f.size }
        #expect(hit, "\(muscle)")
    }

    @Test func pairedLimbMusclesFrameOneSide() throws {
        let biceps = try #require(BodyMapLayout.focus(.biceps))
        #expect(biceps.side == .front)
        #expect(biceps.x + biceps.size / 2 < BodyMapLayout.width / 2)
        #expect(try #require(BodyMapLayout.focus(.lats)).side == .back)
    }
}
