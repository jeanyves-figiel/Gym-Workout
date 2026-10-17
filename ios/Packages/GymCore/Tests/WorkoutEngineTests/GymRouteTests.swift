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

@Suite struct GymMapEditTests {
    private func plan() -> GymLayout {
        var l = GymLayout.starter
        let rects = [GymLayout.Rect(x: 0, y: 0, w: 0.45, h: 0.3), .init(x: 0.55, y: 0, w: 0.45, h: 0.3),
                     .init(x: 0, y: 0.35, w: 0.45, h: 0.3), .init(x: 0.55, y: 0.35, w: 0.45, h: 0.3),
                     .init(x: 0, y: 0.7, w: 0.45, h: 0.2)]
        for i in l.zones.indices { l.zones[i].rect = rects[i] }
        return l
    }

    private func noOverlaps(_ l: GymLayout) -> Bool {
        let r = l.zones.compactMap(\.rect)
        return !r.indices.contains { i in r.indices.contains { j in i < j && r[i].overlaps(r[j]) } }
    }

    @Test func growingPushesNeighboursAside() {
        var l = plan()
        l.zones[2].rect?.w = 0.7 // functional grows into cardio
        #expect(!noOverlaps(l))
        l.settle(l.zones[2].id)
        #expect(noOverlaps(l))
        #expect(l.zones[2].rect?.w == 0.7)
    }

    @Test func blocksKeepTheEntranceClear() {
        var l = plan()
        l.door = .init(x: 0.3, y: 1)
        l.zones[4].rect = .init(x: 0, y: 0.75, w: 0.45, h: 0.25) // stretch over the door
        l.settle(l.zones[4].id)
        #expect(!(l.zones[4].rect!.overlaps(l.doorClearance)))
        #expect(noOverlaps(l))
    }

    @Test func swapTradesSpotsAndFindsBlocks() {
        var l = plan()
        let a = l.zones[0], b = l.zones[3]
        #expect(l.zone(at: .init(x: 0.7, y: 0.5))?.id == b.id)
        l.swapPlaces(a.id, b.id)
        #expect(l.zones[0].rect == b.rect)
        #expect(l.zones[3].rect == a.rect)
    }
}
