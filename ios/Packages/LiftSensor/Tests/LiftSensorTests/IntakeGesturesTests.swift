import XCTest
@testable import LiftSensor

/// Invisible Monkey (#1087): synthetic wrist traces (left wrist, crown right: hand up = gravity along −x).
final class IntakeGesturesTests: XCTestCase {
    /// Builds 50 Hz samples from (seconds, elevation degrees) segments; elevation ramps linearly inside a segment.
    private func trace(_ parts: [(seconds: Double, from: Double, to: Double)], shake: Double = 0) -> [IntakeGestures.Sample] {
        var out: [IntakeGestures.Sample] = []
        var t = 0.0
        for p in parts {
            let n = Int(p.seconds * 50)
            for i in 0..<n {
                let e = (p.from + (p.to - p.from) * Double(i) / Double(max(1, n - 1))) * .pi / 180
                let wobble = shake == 0 ? 0 : shake * sin(Double(out.count) * 1.7)
                out.append(.init(t: t, a: Vec3(-sin(e) * (1 + wobble), 0, -cos(e) * (1 + wobble))))
                t += 0.02
            }
        }
        return out
    }

    private let sign = IntakeGestures.handSign(leftWrist: true, crownRight: true)

    func testHandSign() {
        XCTAssertEqual(IntakeGestures.handSign(leftWrist: true, crownRight: true), -1)
        XCTAssertEqual(IntakeGestures.handSign(leftWrist: false, crownRight: true), 1)
        XCTAssertEqual(IntakeGestures.handSign(leftWrist: false, crownRight: false), -1)
    }

    func testElevationFollowsForearm() {
        let el = IntakeGestures.elevations(trace([(seconds: 3, from: 70, to: 70)]), handSign: sign)
        XCTAssertEqual(el.last ?? 0, 70, accuracy: 1)
    }

    func testSipFromTableIsFound() {
        let s = trace([(5, -5, -5), (0.6, -5, 75), (2.5, 75, 78), (0.6, 78, -5), (5, -5, -5)])
        let g = IntakeGestures.detect(s, handSign: sign)
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g.first?.kind, .sip)
        XCTAssertGreaterThanOrEqual(g.first?.confidence ?? 0, 0.85)
    }

    func testBiteIsShortAndLow() {
        let s = trace([(4, 0, 0), (0.4, 0, 50), (0.8, 50, 52), (0.4, 52, 0), (4, 0, 0)])
        let g = IntakeGestures.detect(s, handSign: sign)
        XCTAssertEqual(g.map(\.kind), [.bite])
    }

    func testHandAlreadyUpIsIgnored() {
        // Starts raised (reading the phone held high): no rise from below, nothing found.
        let s = trace([(6, 60, 60), (1, 60, 0), (3, 0, 0)])
        XCTAssertTrue(IntakeGestures.detect(s, handSign: sign).isEmpty)
    }

    func testLongHoldIsNotASip() {
        let s = trace([(3, 0, 0), (0.5, 0, 70), (20, 70, 70), (0.5, 70, 0), (3, 0, 0)])
        XCTAssertTrue(IntakeGestures.detect(s, handSign: sign).isEmpty)
    }

    func testShakyRaiseIsIgnored() {
        let s = trace([(3, 0, 0), (0.5, 0, 70), (2, 70, 70), (0.5, 70, 0), (3, 0, 0)], shake: 0.6)
        XCTAssertTrue(IntakeGestures.detect(s, handSign: sign).isEmpty)
    }

    func testRightWristFlipsSign() {
        // Right wrist, crown right: hand up = gravity along +x. The left-wrist sign sees the hand going down.
        let s = trace([(3, 0, 0), (0.5, 0, 70), (2, 70, 70), (0.5, 70, 0), (3, 0, 0)])
            .map { IntakeGestures.Sample(t: $0.t, a: Vec3(-$0.a.x, $0.a.y, $0.a.z)) }
        XCTAssertTrue(IntakeGestures.detect(s, handSign: sign).isEmpty)
        XCTAssertEqual(IntakeGestures.detect(s, handSign: IntakeGestures.handSign(leftWrist: false, crownRight: true)).count, 1)
    }

    func testRunOfBitesIsAMeal() {
        var parts: [(seconds: Double, from: Double, to: Double)] = [(5, 0, 0)]
        for _ in 0..<12 { parts += [(0.4, 0, 50), (0.8, 50, 50), (0.4, 50, 0), (20, 0, 0)] }
        let g = IntakeGestures.detect(trace(parts), handSign: sign)
        XCTAssertEqual(g.filter { $0.kind == .bite }.count, 12)
        let meals = IntakeGestures.meals(g)
        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals.first?.bites, 12)
        XCTAssertGreaterThan(meals.first?.confidence ?? 0, 0.5)
    }

    func testFewBitesAreNotAMeal() {
        let bites = (0..<4).map { IntakeGestures.Gesture(kind: .bite, start: Double($0) * 60, duration: 1, peak: 50, confidence: 0.7) }
        XCTAssertTrue(IntakeGestures.meals(bites).isEmpty)
    }

    func testLongGapSplitsMeals() {
        let lunch = (0..<8).map { IntakeGestures.Gesture(kind: .bite, start: Double($0) * 30, duration: 1, peak: 50, confidence: 0.7) }
        let dinner = (0..<8).map { IntakeGestures.Gesture(kind: .bite, start: 20_000 + Double($0) * 30, duration: 1, peak: 50, confidence: 0.7) }
        XCTAssertEqual(IntakeGestures.meals(lunch + dinner).count, 2)
    }
}
