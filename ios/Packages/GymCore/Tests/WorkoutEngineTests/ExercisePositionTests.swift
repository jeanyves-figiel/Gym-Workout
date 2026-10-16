import Foundation
import Testing
@testable import WorkoutEngine

/// Position guide data (#399): 3D key positions lifted from the animation's key poses.
@Suite struct ExercisePositionTests {
    @Test func everyIllustratedExerciseHasThreeKeyPositions() {
        #expect(!ExercisePosition.ids.isEmpty)
        for id in ExerciseIllustrations.ids {
            guard let p = ExercisePosition.of(id) else {
                Issue.record("\(id) has no 3D position")
                continue
            }
            #expect(p.keys.count == 3, "\(id)")
            for k in p.keys {
                for j in ["hip", "shoulder", "head", "kneeN", "ankleF", "elbowN", "wristF", "toeN"] {
                    #expect(k[j] != nil, "\(id) misses \(j)")
                }
                // standing on (or above) the floor
                #expect(k.joints.values.allSatisfy { $0.y > -12 }, "\(id) sinks into the floor")
            }
        }
    }

    @Test func squatChecksKneeAndHipAtTheBottom() throws {
        let p = try #require(Exercise.get("back-squat").position)
        #expect(p.view == .side)
        let bottom = p.mainKey
        #expect(bottom > 0)
        let checks = p.checks(at: bottom)
        #expect(Set(checks.map(\.joint)) == [.knee, .hip])
        for c in checks {
            #expect(c.range.contains(c.degrees))
            #expect(c.degrees < 120, "a deep squat at the bottom")
        }
        // standing tall at the start: knees nearly straight
        #expect(try #require(p.keys[0].angle(.knee)) > 160)
        // feet about shoulder-width apart for a squat
        let feet = try #require(p.keys[0]["ankleN"]).z - (try #require(p.keys[0]["ankleF"]).z)
        #expect(feet > 25)
    }

    @Test func barbellGripIsWiderThanShoulders() throws {
        let k = try #require(Exercise.get("bench-press").position).keys[0]
        let grip = abs(try #require(k["wristN"]).z - (try #require(k["wristF"]).z))
        let shoulders = abs(try #require(k["shoulderN"]).z - (try #require(k["shoulderF"]).z))
        #expect(grip > shoulders)
        #expect(k.props.contains { if case .disc = $0 { true } else { false } }, "plates on the bar")
    }

    @Test func mistakeIsPickedFromTheAvoidList() {
        #expect(PositionMistake.pick(["Knees caving in"])?.kind == .kneesIn)
        #expect(PositionMistake.pick(["Rounding the lower back"])?.kind == .roundedBack)
        #expect(PositionMistake.pick(["Letting the hips sag"])?.kind == .hipsSag)
        #expect(PositionMistake.pick(["Elbows flared to 90°"])?.kind == .elbowsFlared)
        #expect(PositionMistake.pick(["Holding your breath the whole set"]) == nil)
        let text = "Something odd, then knees cave in"
        #expect(PositionMistake.pick(["Holding your breath", text])?.text == text)
    }

    @Test func ghostMovesTheRightJoints() throws {
        let p = try #require(Exercise.get("back-squat").position)
        let bottom = p.keys[p.mainKey]
        let knees = try #require(PositionMistake(kind: .kneesIn, text: "").apply(to: bottom, view: p.view, start: p.keys[0]))
        #expect(abs(try #require(knees["kneeN"]).z) < abs(try #require(bottom["kneeN"]).z))
        #expect(knees["hip"] == bottom["hip"])
        let half = try #require(PositionMistake(kind: .halfRange, text: "").apply(to: bottom, view: p.view, start: p.keys[0]))
        #expect(try #require(half["hip"]).y > (try #require(bottom["hip"]).y))
    }

    @Test func mostExercisesShowAMistakeAndAngles() {
        let all = Exercise.catalog.filter { $0.position != nil }
        let withMistake = all.filter { PositionMistake.pick($0.technique?.mistakes ?? []) != nil }
        let withChecks = all.filter { p in p.position.map { !$0.checks(at: $0.mainKey).isEmpty } ?? false }
        #expect(Double(withMistake.count) / Double(all.count) > 0.5)
        #expect(Double(withChecks.count) / Double(all.count) > 0.8)
    }
}
