import Foundation
import Testing
@testable import WorkoutEngine

/// Piste map (#1132): runs matched to their piste, lift rides to their lift, labels and colours.
@Suite struct PisteMapTests {
    private let t0 = Date(timeIntervalSince1970: 0)

    /// A straight line of points from (lat0, lon) going south, 10 s apart.
    private func points(_ lat0: Double, lon: Double, count: Int, alt0: Double, drop: Double) -> [SportTrack.Point] {
        (0..<count).map { i in
            SportTrack.Point(lat: lat0 - Double(i) * 0.0005, lon: lon, alt: alt0 - Double(i) * drop, speed: 8, time: t0.addingTimeInterval(Double(i) * 10))
        }
    }

    private let map = PisteMap(
        pistes: [
            .init(name: "Standard", ref: "12", difficulty: "intermediate", pts: [46.52, 7.90, 46.50, 7.90]),
            .init(name: "Wall", ref: "7", difficulty: "advanced", pts: [46.52, 7.905, 46.50, 7.905]),
        ],
        lifts: [.init(name: "Alpha", kind: "gondola", pts: [46.50, 7.902, 46.52, 7.902])])

    @Test func runFollowsItsPiste() {
        // 15 m east of the red, 370 m west of the black.
        let track = SportTrack(points: points(46.52, lon: 7.9002, count: 30, alt0: 2400, drop: 10))
        let run = SportTrack.Run(from: 0, to: 29, drop: 290, topKmh: 40)
        #expect(map.piste(for: run, in: track)?.ref == "12")
        #expect(map.piste(for: run, in: track)?.label == "Red 12 · Standard")
        // Off every piste (2 km away): no name.
        let off = SportTrack(points: points(46.52, lon: 7.93, count: 30, alt0: 2400, drop: 10))
        #expect(map.piste(for: run, in: off) == nil)
    }

    @Test func liftByItsEnds() {
        let a = SportTrack.Point(lat: 46.5001, lon: 7.9021, alt: 1800, speed: 4, time: t0)
        let b = SportTrack.Point(lat: 46.5199, lon: 7.9019, alt: 2400, speed: 4, time: t0)
        #expect(map.lift(from: a, to: b)?.label == "Gondola Alpha")
        let far = SportTrack.Point(lat: 46.6, lon: 8.0, alt: 0, speed: 0, time: t0)
        #expect(map.lift(from: far, to: far) == nil)
    }

    @Test func labelsAndColours() {
        #expect(PisteMap.Line(difficulty: "easy", pts: []).colour == .blue)
        #expect(PisteMap.Line(difficulty: "expert", pts: []).colour == .black)
        #expect(PisteMap.Line(pts: []).label == "Piste")
        #expect(PisteMap.Line(name: "Chair Bravo", kind: "chair_lift", pts: []).label == "Chair Bravo")
        #expect(PisteMap.Line(kind: "t-bar", pts: []).label == "Drag lift")
    }

    @Test func decodesTheServer() throws {
        let json = #"{"pistes":[{"name":"Standard","difficulty":"intermediate","pts":[46.5,7.9,46.51,7.9]}],"lifts":[{"kind":"gondola","pts":[46.5,7.9,46.52,7.9]}],"attribution":"© OpenStreetMap contributors (ODbL)"}"#
        let m = try PisteMap.decode(Data(json.utf8))
        #expect(m.pistes.first?.coordinates.count == 2)
        #expect(m.lifts.first?.kind == "gondola")
    }

    @Test func boxHasAMargin() {
        let track = SportTrack(points: points(46.52, lon: 7.9, count: 3, alt0: 2000, drop: 10))
        let b = PisteMap.box(track)!
        #expect(b.s < 46.519 && b.n > 46.52 && b.w < 7.9 && b.e > 7.9)
    }
}
