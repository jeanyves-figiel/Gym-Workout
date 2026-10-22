import CoreMotion
import Foundation
import LiftSensor
import Observation
import WatchKit

/// High-rate motion (#611): the batched sensors (accelerometer 800 Hz, device motion 200 Hz) count punches during
/// boxing rounds (C) and racket or club swings during padel, tennis and golf (B). watchOS only delivers them while a
/// workout session runs, so the timer and sport trackers start this after their session.
@MainActor @Observable
final class ImpactTracker {
    private(set) var punches = PunchCounter(hz: 800)
    private(set) var swings = SwingCounter(hz: 200)
    /// Punches in each finished round, and the round being counted.
    private(set) var rounds: [Int] = []
    private(set) var roundStart = 0
    private(set) var running = false
    /// Punches per minute over the last few seconds, for the live rate.
    private(set) var rate = 0
    private var stamps: [Date] = []
    private var task: Task<Void, Never>?

    var roundPunches: Int { punches.count - roundStart }

    static var punchesAvailable: Bool { CMBatchedSensorManager.isAccelerometerSupported }
    static var swingsAvailable: Bool { CMBatchedSensorManager.isDeviceMotionSupported }

    func startPunches() {
        stop()
        guard Self.punchesAvailable else { return }
        let manager = CMBatchedSensorManager()
        let hz = Double(manager.accelerometerDataFrequency)
        punches = PunchCounter(hz: hz > 0 ? hz : 800)
        rounds = []
        roundStart = 0
        stamps = []
        rate = 0
        running = true
        task = Task { [weak self] in
            do {
                for try await batch in manager.accelerometerUpdates() {
                    guard let self, !Task.isCancelled else { return }
                    var c = self.punches
                    let before = c.count
                    for d in batch { c.append(Vec3(d.acceleration.x, d.acceleration.y, d.acceleration.z)) }
                    self.punches = c
                    self.counted(c.count - before)
                }
            } catch {}
        }
    }

    /// `lever`: shoulder to racket head (padel / tennis 1.2 m, golf 1.6 m).
    func startSwings(lever: Double) {
        stop()
        guard Self.swingsAvailable else { return }
        let manager = CMBatchedSensorManager()
        let hz = Double(manager.deviceMotionDataFrequency)
        swings = SwingCounter(hz: hz > 0 ? hz : 200, lever: lever)
        running = true
        task = Task { [weak self] in
            do {
                for try await batch in manager.deviceMotionUpdates() {
                    guard let self, !Task.isCancelled else { return }
                    var c = self.swings
                    let before = c.total
                    for m in batch {
                        let r = m.rotationRate, g = m.gravity
                        c.append(rotation: Vec3(r.x, r.y, r.z), gravity: Vec3(g.x, g.y, g.z))
                    }
                    self.swings = c
                    if c.total > before { WKInterfaceDevice.current().play(.click) }
                }
            } catch {}
        }
    }

    /// Boxing: closes the round's count when its bell rings.
    func endRound() {
        rounds.append(roundPunches)
        roundStart = punches.count
    }

    func stop() {
        task?.cancel()
        task = nil
        running = false
    }

    private func counted(_ n: Int) {
        guard n > 0 else { return }
        let now = Date()
        stamps.append(contentsOf: Array(repeating: now, count: n))
        stamps.removeAll { now.timeIntervalSince($0) > 10 }
        rate = stamps.count * 6
    }

    #if DEBUG
    /// CI screenshots.
    func demo(punches n: Int, rate: Int, rounds: [Int]) {
        var c = PunchCounter(hz: 100)
        for _ in 0..<n {
            c.append(Vec3(0, 0, 8))
            for _ in 0..<40 { c.append(Vec3(0, 0, 1)) }
        }
        punches = c
        self.rate = rate
        self.rounds = rounds
        roundStart = 0
    }

    func demo(swings fh: Int, _ bh: Int, _ smash: Int, top: Double) {
        var c = SwingCounter(hz: 100, lever: top / 3.6 / 20)
        func swing(_ r: Vec3, _ g: Vec3) {
            for _ in 0..<80 { c.append(rotation: .zero, gravity: Vec3(0, -1, 0)) }
            for _ in 0..<5 { c.append(rotation: r, gravity: g) }
        }
        for _ in 0..<fh { swing(Vec3(0, 0, 20), Vec3(0, -1, 0)) }
        for _ in 0..<bh { swing(Vec3(0, 0, -20), Vec3(0, -1, 0)) }
        for _ in 0..<smash { swing(Vec3(0, 0, 20), Vec3(-1, 0, 0)) }
        for _ in 0..<80 { c.append(rotation: .zero, gravity: Vec3(0, -1, 0)) }
        swings = c
    }
    #endif
}
