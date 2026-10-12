import Foundation
import Testing
@testable import WorkoutEngine

private let bench = Exercise.get("bench-press")
private let curl = Exercise.get("barbell-curl")
private let squat = Exercise.get("back-squat")

private func rx(_ reps: String) -> Prescription { Prescription(sets: 3, reps: reps, restSec: 90, intensity: "RPE 8") }

private func day(_ n: Double) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + n * 86_400) }

@Suite struct BodyMeasurementTests {
    @Test func sidesAverageAndSingleValueWins() {
        var m = BodyMeasurement(date: day(0))
        m.setGirth(.upperArm, side: .left, 35)
        m.setGirth(.upperArm, side: .right, 36)
        #expect(m.girth(.upperArm) == 35.5)
        m.setGirth(.upperArm, 37)
        #expect(m.girth(.upperArm) == 37)
        m.setGirth(.upperArm, nil)
        m.setGirth(.upperArm, side: .left, nil)
        #expect(m.girth(.upperArm) == 36)
        #expect(m.count == 1)
    }

    @Test func leanMassNeedsWeightAndFat() {
        #expect(BodyMeasurement(date: day(0), weightKg: 80).leanKg == nil)
        #expect(BodyMeasurement(date: day(0), weightKg: 80, bodyFatPct: 20).leanKg == 64)
    }

    @Test func roundTripsThroughJSON() throws {
        var m = BodyMeasurement(date: Date(timeIntervalSince1970: 1_790_000_000), weightKg: 80.5, bodyFatPct: 18)
        m.setGirth(.thigh, side: .right, 58)
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let back = try d.decode(BodyMeasurement.self, from: e.encode(m))
        #expect(back == m)
        #expect(String(decoding: try e.encode(m), as: UTF8.self).contains(#""thighR":58"#))
    }

    @Test func seriesMergesHealthWithoutDoubleCounting() {
        let list = [BodyMeasurement(date: day(0), weightKg: 80), BodyMeasurement(date: day(10), weightKg: 79)]
        let health = [BodyMeasurements.Point(date: day(10).addingTimeInterval(60), value: 79.0),
                      BodyMeasurements.Point(date: day(5), value: 79.6)]
        let s = BodyMeasurements.series(.weight, in: list, extra: health)
        #expect(s.map(\.value) == [80, 79.6, 79])
        #expect(BodyMeasurements.change(s) == -1)
        #expect(BodyMeasurements.change(Array(s.prefix(1))) == nil)
        #expect(BodyMeasurements.series(.girth(.waist), in: list).isEmpty)
    }

    @Test func leanMassRaisesOrLowersFirstTimeEstimateWithinCap() throws {
        let base = Athlete(bodyKg: 80, sex: .male, age: 30, experience: .intermediate)
        var lean = base
        lean.leanKg = 72 // 10 % fat: leaner than typical → more
        var soft = base
        soft.leanKg = 56 // 30 % fat → less
        let b = try #require(StartingLoad.estimate(exercise: bench, prescription: rx("5–8"), athlete: base))
        let l = try #require(StartingLoad.estimate(exercise: bench, prescription: rx("5–8"), athlete: lean))
        let s = try #require(StartingLoad.estimate(exercise: bench, prescription: rx("5–8"), athlete: soft))
        #expect(l.kg > b.kg)
        #expect(s.kg < b.kg)
        #expect(l.kg <= b.kg * 1.15 + 2.5)
        #expect(s.kg >= b.kg * 0.85 - 2.5)
        #expect(l.reason.contains("lean mass"))
        #expect(!b.reason.contains("lean mass"))
    }

    @Test func girthOnlyTouchesItsBodyRegion() throws {
        let base = Athlete(bodyKg: 78, sex: .male, age: 30, experience: .intermediate)
        var big = base
        big.upperArmCm = 42
        big.thighCm = 40 // implausibly small → capped −8 %
        let curlBase = try #require(StartingLoad.estimate(exercise: curl, prescription: rx("8–10"), athlete: base))
        let curlBig = try #require(StartingLoad.estimate(exercise: curl, prescription: rx("8–10"), athlete: big))
        #expect(curlBig.kg >= curlBase.kg)
        #expect(curlBig.reason.contains("arm girth"))
        let benchBase = try #require(StartingLoad.estimate(exercise: bench, prescription: rx("8–10"), athlete: base))
        let benchBig = try #require(StartingLoad.estimate(exercise: bench, prescription: rx("8–10"), athlete: big))
        #expect(benchBig == benchBase)
        let f = StartingLoad.bodyFactors(big, bodyKg: 78, pattern: squat.pattern)
        #expect(abs(f.factor - (1 - StartingLoad.maxGirthShift)) < 1e-9)
    }

    @Test func noBodyDataKeepsTheOldEstimate() {
        let f = StartingLoad.bodyFactors(Athlete(bodyKg: 80), bodyKg: 80, pattern: .hPush)
        #expect(f.factor == 1)
        #expect(f.used.isEmpty)
    }

    @Test func everyLoggedMetricHasAGuide() {
        for metric in [BodyMetric.weight, .bodyFat] + GirthSite.allCases.map({ BodyMetric.girth($0) }) {
            #expect(metric.guide.steps.count == 3, "\(metric.label)")
            #expect(!metric.guide.tip.isEmpty)
        }
        #expect(BodyMetric.girth(.waist).guide.tip.hasSuffix(BodyMetric.tapeTip))
    }

    @Test(arguments: BodyMapLayout.Figure.allCases)
    func everySiteHasATapeBand(figure: BodyMapLayout.Figure) throws {
        for site in GirthSite.allCases {
            let band = try #require(BodyMapLayout.tapeBand(site, figure: figure), "\(site)")
            #expect(band.width > 8 && band.width < 130, "\(site) \(band)")
        }
        // Chest sits under the armpits, so the arms aren't in the tape.
        let chest = try #require(BodyMapLayout.tapeBand(.chest, figure: figure))
        let shoulders = try #require(BodyMapLayout.tapeBand(.shoulders, figure: figure))
        #expect(chest.width < shoulders.width)
        // Member's left arm is on the viewer's right.
        let left = try #require(BodyMapLayout.tapeBand(.upperArm, side: .left, figure: figure))
        let right = try #require(BodyMapLayout.tapeBand(.upperArm, side: .right, figure: figure))
        #expect(left.minX > BodyMapLayout.width / 2 && right.maxX < BodyMapLayout.width / 2)
    }
}
