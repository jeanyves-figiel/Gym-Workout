import CoreMotion
import Foundation
import LiftSensor
import Observation
import WatchKit

/// Lift sensor (#383): device motion at 100 Hz during the workout session, fed to `SetTracker`.
/// On the wrist it measures lifts where the wrist moves with the load; in machine mode the Watch is strapped on
/// the machine's moving part and a slow test rep teaches it the axis and which way is the push.
@MainActor @Observable
final class LiftTracker {
    enum Mode: Equatable {
        case idle
        /// Machine mode: waiting for the member to strap the Watch on.
        case strap
        /// Machine mode: learning the axis from one slow test rep.
        case testRep
        /// Measuring a set.
        case tracking
    }

    private(set) var mode: Mode = .idle
    /// What is measured: exercise uid + set number, so a new set starts fresh.
    private(set) var key: String?
    private(set) var machine = false
    private(set) var reps: [LiftRep] = []
    private(set) var velocityLoss = 0.0
    /// Set when the velocity-loss limit was reached in this set ("Rack it").
    private(set) var lossReached = false
    /// Changes when the set looks over (bar racked), so views can react once.
    private(set) var endedAt: Date?
    /// Machine mode: the test rep found the push (shown briefly).
    private(set) var calibratedAt: Date?
    /// Practice mode (#410): counting for the iPhone's Try it screen, not a set.
    private(set) var practicing = false

    var lastVelocity: Double? { reps.last?.meanVelocity }
    var best: Double? { reps.map(\.meanVelocity).max() }
    var count: Int { reps.count }

    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()
    nonisolated private let box = Box()
    /// Machine mode axis per exercise, learned once per strapping (device frame).
    private var machineAxis: [String: (axis: Vec3, sign: Int)] = [:]

    /// Thread-safe holder of the tracker the motion queue feeds.
    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var tracker: SetTracker?
        var calibration: [MotionSample]?
    }

    nonisolated static let available = CMMotionManager().isDeviceMotionAvailable

    /// Starts measuring a set on the wrist (no-op when this set is already measured).
    /// `strictness`: counting level (#410), see `Strictness`.
    func track(key: String, profile: LiftProfile, lossLimit: Double?, strictness: Double = 0) {
        guard key != self.key || mode == .idle else { return }
        reset(key: key, machine: false)
        begin(SetTracker(profile: profile, lossLimit: lossLimit, strictness: strictness))
    }

    /// Practice mode (#410): counts any lift on the wrist at `level` until stopped; `recount` changes the level.
    func practice(level: Double) {
        reset(key: "practice", machine: false)
        practicing = true
        begin(SetTracker(profile: LiftProfile(direction: .up, family: .bench), lossLimit: nil, strictness: level))
    }

    /// Practice mode: the same movements counted at another level.
    func recount(level: Double) {
        box.lock.lock()
        let update = box.tracker?.setStrictness(level)
        box.lock.unlock()
        if let update { apply(update) }
    }

    /// Practice mode: what the iPhone shows (trace at 20 values a second, reps placed on it).
    func practiceState() -> WLiftPracticeState? {
        box.lock.lock()
        defer { box.lock.unlock() }
        guard practicing, let t = box.tracker else { return nil }
        let trace = t.trace(seconds: 6, every: 5)
        let reps = t.reps
        let marks = reps.compactMap { r -> Int? in
            let i = (r.endIndex - trace.start) / 5
            return i >= 0 && i < trace.values.count ? i : nil
        }
        return WLiftPracticeState(level: t.strictness, reps: reps.count, velocities: reps.map(\.meanVelocity), ranges: reps.map(\.range),
                                  trace: trace.values, marks: marks)
    }

    /// Machine mode for a lift the wrist can't measure: ask to strap the Watch on, then a test rep (once per exercise).
    func trackMachine(key: String, exercise: String, family: LiftProfile.Family, lossLimit: Double?, strictness: Double = 0) {
        guard key != self.key || mode == .idle else { return }
        reset(key: key, machine: true)
        if let known = machineAxis[exercise] {
            begin(SetTracker(machineAxis: known.axis, sign: known.sign, family: family, lossLimit: lossLimit, strictness: strictness))
        } else {
            mode = .strap
        }
    }

    /// The member strapped the Watch on: learn the axis from one slow push.
    func strapped(exercise: String, family: LiftProfile.Family, lossLimit: Double?, strictness: Double = 0) {
        guard mode == .strap else { return }
        mode = .testRep
        box.lock.lock()
        box.calibration = []
        box.tracker = nil
        box.lock.unlock()
        let box = self.box
        startMotion { [weak self] sample in
            box.lock.lock()
            box.calibration?.append(sample)
            if (box.calibration?.count ?? 0) > 6000 { box.calibration?.removeFirst(1000) }
            let samples = box.calibration ?? []
            box.lock.unlock()
            // Try every 0.25 s.
            guard samples.count % 25 == 0, let found = MachineCalibration.find(samples) else { return }
            Task { @MainActor [weak self] in
                self?.calibrated(found, exercise: exercise, family: family, lossLimit: lossLimit, strictness: strictness)
            }
        }
    }

    private func calibrated(_ found: (axis: Vec3, sign: Int), exercise: String, family: LiftProfile.Family, lossLimit: Double?, strictness: Double) {
        guard mode == .testRep else { return }
        machineAxis[exercise] = found
        calibratedAt = Date()
        WKInterfaceDevice.current().play(.success)
        motion.stopDeviceMotionUpdates()
        box.lock.lock()
        box.calibration = nil
        box.lock.unlock()
        begin(SetTracker(machineAxis: found.axis, sign: found.sign, family: family, lossLimit: lossLimit, strictness: strictness))
    }

    #if DEBUG
    /// CI screenshots: a set in progress.
    func demo(_ velocities: [Double], machine: Bool = false, stop: Bool = false, mode: Mode = .tracking) {
        self.mode = mode
        self.machine = machine
        reps = velocities.enumerated().map { LiftRep(meanVelocity: $1, peakVelocity: $1 * 1.6, range: 0.42, concentricSec: 0.6, eccentricSec: 1.4, endIndex: $0) }
        velocityLoss = LiftStats.velocityLoss(reps)
        lossReached = stop
    }
    #endif

    func clearCalibrated() {
        calibratedAt = nil
    }

    /// The member put the Watch somewhere else: learn the axis again next time.
    func forgetMachine(_ exercise: String) {
        machineAxis[exercise] = nil
    }

    /// Stops measuring and returns the set's reps (treating the set as over).
    @discardableResult
    func stop() -> [LiftRep] {
        motion.stopDeviceMotionUpdates()
        box.lock.lock()
        let final = box.tracker?.finish() ?? []
        box.tracker = nil
        box.calibration = nil
        box.lock.unlock()
        let out = final.count >= reps.count ? final : reps
        mode = .idle
        key = nil
        practicing = false
        return out
    }

    /// Undo of an automatic log: the set goes on.
    func resume() {
        endedAt = nil
        box.lock.lock()
        box.tracker?.resume()
        box.lock.unlock()
    }

    private func reset(key: String, machine: Bool) {
        motion.stopDeviceMotionUpdates()
        box.lock.lock()
        box.tracker = nil
        box.calibration = nil
        box.lock.unlock()
        self.key = key
        self.machine = machine
        practicing = false
        reps = []
        velocityLoss = 0
        lossReached = false
        endedAt = nil
        calibratedAt = nil
    }

    private func begin(_ tracker: SetTracker) {
        mode = .tracking
        box.lock.lock()
        box.tracker = tracker
        box.lock.unlock()
        let box = self.box
        startMotion { [weak self] sample in
            box.lock.lock()
            let update = box.tracker?.append(sample)
            box.lock.unlock()
            if let update { Task { @MainActor [weak self] in self?.apply(update) } }
        }
    }

    private func startMotion(_ handler: @escaping @Sendable (MotionSample) -> Void) {
        guard motion.isDeviceMotionAvailable else { return }
        motion.stopDeviceMotionUpdates()
        motion.deviceMotionUpdateInterval = 0.01
        motion.startDeviceMotionUpdates(to: queue) { m, _ in
            guard let m else { return }
            let u = m.userAcceleration
            let g = m.gravity
            let r = m.rotationRate
            handler(MotionSample(userAcceleration: Vec3(u.x, u.y, u.z), gravity: Vec3(g.x, g.y, g.z),
                                 rotationRate: (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()))
        }
    }

    private func apply(_ u: SetTracker.Update) {
        guard mode == .tracking else { return }
        if u.reps.count > reps.count { WKInterfaceDevice.current().play(.click) }
        reps = u.reps
        velocityLoss = u.velocityLoss
        if u.lossReached {
            lossReached = true
            // Strong double buzz: stop the set.
            WKInterfaceDevice.current().play(.retry)
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                WKInterfaceDevice.current().play(.retry)
            }
        }
        if u.ended { endedAt = Date() }
    }
}

/// Machine mode test rep (#383): after strapping, the Watch rests on the machine (1 s still), then the first
/// clear movement gives the axis and its direction is the push. Strapping movements before that are ignored.
enum MachineCalibration {
    static func find(_ samples: [MotionSample]) -> (axis: Vec3, sign: Int)? {
        var run = 0
        for (i, m) in samples.enumerated() {
            run = m.userAcceleration.length < 0.02 && m.rotationRate < 0.5 ? run + 1 : 0
            guard run == 100, let found = pair(Array(samples[(i - 99)...])) else { continue }
            return found
        }
        return nil
    }

    /// A clean push and return of similar range after a still second (strapping movements are not).
    private static func pair(_ after: [MotionSample]) -> (axis: Vec3, sign: Int)? {
        let moving = after.map(\.userAcceleration).filter { $0.length > 0.05 }
        guard moving.count >= 20, let axis = SetAnalyzer.principalAxis(moving) else { return nil }
        var config = SetAnalyzer.Config()
        config.minRange = 0.05
        let phases = SetAnalyzer.phases(after.map { $0.userAcceleration.dot(axis) }, rotation: nil, config: config)
        guard phases.count >= 2, phases[0].sign != phases[1].sign,
              abs(phases[0].range - phases[1].range) <= 0.4 * max(phases[0].range, phases[1].range) else { return nil }
        return (axis, phases[0].sign)
    }
}

extension SetTracker {
    /// Machine mode tracker: fixed axis and push direction from the test rep.
    convenience init(machineAxis: Vec3, sign: Int, family: LiftProfile.Family, lossLimit: Double?, strictness: Double = 0) {
        // Floor of the machine's family (#424): leg press 15 cm, hip thrust 12 cm, calf raise and the rest 6 cm.
        self.init(profile: LiftProfile(direction: .axis, family: family), lossLimit: lossLimit, strictness: strictness)
        fixAxis(sign > 0 ? machineAxis : machineAxis * -1)
    }
}
