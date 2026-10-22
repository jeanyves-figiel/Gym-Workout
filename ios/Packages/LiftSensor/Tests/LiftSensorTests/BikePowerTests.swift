import Foundation
import Testing
@testable import LiftSensor

/// Cycling with sensors (#623).
@Suite struct BikePowerTests {
    @Test func zonesFollowFTP() {
        #expect(BikePower.zone(watts: 200, ftp: nil) == nil)
        #expect(BikePower.zone(watts: 100, ftp: 250)?.index == 1)
        #expect(BikePower.zone(watts: 214, ftp: 246)?.name == "Tempo")
        #expect(BikePower.zone(watts: 246, ftp: 246)?.index == 4)
        #expect(BikePower.zone(watts: 900, ftp: 246)?.index == 7)
        let r = BikePower.range(BikePower.zones[2], ftp: 200)
        #expect(r == 151...180)
    }

    @Test func ftpTestPhasesAndResult() {
        #expect(BikePower.testPhase(elapsed: 0).phase == .warmUp)
        #expect(BikePower.testPhase(elapsed: 15 * 60).phase == .allOut)
        #expect(BikePower.testPhase(elapsed: 15 * 60 + 60).left == 19 * 60)
        #expect(BikePower.testPhase(elapsed: 35 * 60).phase == .coolDown)
        #expect(BikePower.testPhase(elapsed: 46 * 60).phase == .done)
        #expect(BikePower.ftp(twentyMinuteAverage: 259) == 246)
        let now = Date()
        #expect(BikePower.retestDue(lastTest: nil, now: now))
        #expect(!BikePower.retestDue(lastTest: now.addingTimeInterval(-30 * 86_400), now: now))
        #expect(BikePower.retestDue(lastTest: now.addingTimeInterval(-43 * 86_400), now: now))
    }

    @Test func rollingAverage() {
        var r = BikePower.Rolling(window: 3)
        #expect(r.average == nil)
        r.add(200, at: 0)
        r.add(220, at: 1)
        r.add(240, at: 2)
        #expect(r.average == 220)
        r.add(300, at: 5)
        #expect(r.average == 270)
    }

    @Test func parsesBluetoothPackets() {
        // Power: flags 0x20 (crank data), 214 W, 1000 revs, time 2048.
        let p = BikePower.parsePower([0x20, 0x00, 0xD6, 0x00, 0xE8, 0x03, 0x00, 0x08])
        #expect(p?.watts == 214)
        #expect(p?.crank == BikePower.CrankReading(revs: 1000, time: 2048))
        // No crank data.
        #expect(BikePower.parsePower([0x00, 0x00, 0x10, 0x01])?.crank == nil)
        #expect(BikePower.parsePower([0x00]) == nil)
        // CSC with wheel + crank.
        let c = BikePower.parseCadence([0x03, 1, 0, 0, 0, 0, 0, 0x0A, 0x00, 0x00, 0x04])
        #expect(c == BikePower.CrankReading(revs: 10, time: 1024))
        // Heart rate 8-bit and 16-bit.
        #expect(BikePower.parseHeartRate([0x00, 148]) == 148)
        #expect(BikePower.parseHeartRate([0x01, 0x2C, 0x01]) == 300)
    }

    @Test func cadenceHandlesWraparound() {
        let a = BikePower.CrankReading(revs: 65_535, time: 64_000)
        let b = BikePower.CrankReading(revs: 1, time: 64_000 &+ 1336) // 2 revs in 1.3 s
        let rpm = BikePower.cadence(from: a, to: b)
        #expect(rpm != nil)
        #expect(abs((rpm ?? 0) - 92) < 1)
        #expect(BikePower.cadence(from: b, to: b) == nil)
    }
}
