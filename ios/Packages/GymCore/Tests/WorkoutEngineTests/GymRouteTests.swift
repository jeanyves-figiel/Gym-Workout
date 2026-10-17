import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct GymRouteTests {
    @Test func stopsMergeSameZoneAndCarryAnywhereExercises() {
        let r = GymLayout.starter.route(["push-up", "bench-press", "push-up", "leg-press", "rower"])
        #expect(r.stops.map(\.zone.id) == ["freeWeights", "machines", "cardio"])
        #expect(r.stops[0].exerciseIds == ["push-up", "bench-press", "push-up"])
        #expect(r.walks == 2)
        #expect(r.metres == nil)
    }

    @Test func metresFromTheEntranceWithAPlan() {
        var l = GymLayout.starter
        l.zones[0].rect = .init(x: 0, y: 0, w: 0.5, h: 0.5)   // free weights, centre (0.25, 0.25)
        l.zones[1].rect = .init(x: 0.5, y: 0, w: 0.5, h: 0.5) // machines, centre (0.75, 0.25)
        l.door = .init(x: 0.25, y: 1)
        let r = l.route(["bench-press", "leg-press"])
        // 0.75 of 37.5 m up, then 0.5 of 30 m across.
        #expect(r.metres == Int((0.75 * GymLayout.planHeightM + 0.5 * GymLayout.planWidthM).rounded()))
        // A scanned room: 20 × 10 m.
        l.sizeM = .init(x: 20, y: 10)
        #expect(l.route(["bench-press", "leg-press"]).metres == Int((0.75 * 10 + 0.5 * 20).rounded()))
    }

    @Test func oldLayoutsDecodeWithoutADoor() throws {
        let json = #"{"zones":[{"id":"a","name":"A","color":0,"items":["bench"]}]}"#
        let l = try JSONDecoder().decode(GymLayout.self, from: Data(json.utf8))
        #expect(l.door == nil)
        #expect(l.entrance == .init(x: 0.5, y: 1))
    }

    @Test func busyAroundTheSameTimeOfDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_760_000_000) // fixed instant
        let day: TimeInterval = 86_400
        let taps = [
            BusyTap(zoneId: "fw", at: now - 7 * day + 600),  // same weekday, 10 min later in the day → 2
            BusyTap(zoneId: "fw", at: now - 2 * day - 1800), // other day, 30 min earlier → 1
            BusyTap(zoneId: "fw", at: now - 3 * day + 3 * 3600), // 3 h off → 0
            BusyTap(zoneId: "fw", at: now - 70 * day),       // too old → 0
            BusyTap(zoneId: "m", at: now - day),             // other zone
        ]
        #expect(GymBusy.score(taps, zone: "fw", at: now, calendar: cal) == 3)
        #expect(GymBusy.usuallyBusy(taps, zone: "fw", at: now, calendar: cal))
        #expect(!GymBusy.usuallyBusy(taps, zone: "m", at: now, calendar: cal))
    }
}
