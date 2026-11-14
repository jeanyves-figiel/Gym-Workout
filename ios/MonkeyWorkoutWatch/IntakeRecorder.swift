import CoreMotion
import Foundation
import LiftSensor
import WatchConnectivity
import WatchKit

/// Invisible Monkey (#1087): while the member has sips or meals on, the Watch keeps its accelerometer recording in the
/// background (`CMSensorRecorder`, kept by watchOS for up to 3 days), and every background refresh or app open reads
/// what was recorded since last time, finds sips and bites (`IntakeGestures`) and sends only their times to the
/// iPhone. The motion itself never leaves the Watch.
@MainActor
final class IntakeRecorder {
    static let shared = IntakeRecorder()

    private let recorder = CMSensorRecorder()
    private let defaults = UserDefaults.standard
    private var busy = false

    private enum Key {
        static let on = "intake.on"
        static let recordedUntil = "intake.recordedUntil"
        static let readUntil = "intake.readUntil"
    }

    /// One recording request runs this long; it is renewed when less than `renewBefore` is left.
    private static let span: TimeInterval = 12 * 3600
    private static let renewBefore: TimeInterval = 4 * 3600
    /// Read at most this much at once (a long-unopened Watch catches up over a few refreshes).
    private static let chunk: TimeInterval = 3 * 3600
    /// The recorder makes data available a few minutes late.
    private static let lag: TimeInterval = 4 * 60

    var available: Bool { CMSensorRecorder.isAccelerometerRecordingAvailable() }

    /// Follows the phone's setting from the snapshot.
    func apply(_ sense: WIntakeSense?) {
        let on = sense?.on ?? false
        let was = defaults.bool(forKey: Key.on)
        defaults.set(on, forKey: Key.on)
        guard on, available else { return }
        if !was { defaults.set(Date().timeIntervalSince1970, forKey: Key.readUntil) }
        renew()
        Self.scheduleRefresh()
    }

    private func renew(now: Date = Date()) {
        let until = defaults.double(forKey: Key.recordedUntil)
        guard until - now.timeIntervalSince1970 < Self.renewBefore else { return }
        recorder.recordAccelerometer(forDuration: Self.span)
        defaults.set(now.timeIntervalSince1970 + Self.span, forKey: Key.recordedUntil)
    }

    /// Reads what was recorded since last time and sends what it found. Safe to call often.
    func process(now: Date = Date()) async {
        guard defaults.bool(forKey: Key.on), available, !busy else { return }
        busy = true
        defer { busy = false }
        renew(now: now)
        let last = defaults.double(forKey: Key.readUntil)
        let from = Date(timeIntervalSince1970: last > 0 ? last : now.timeIntervalSince1970 - 3600)
        let to = min(now.addingTimeInterval(-Self.lag), from.addingTimeInterval(Self.chunk))
        guard to.timeIntervalSince(from) > 60 else { return }
        let device = WKInterfaceDevice.current()
        let sign = IntakeGestures.handSign(leftWrist: device.wristLocation == .left, crownRight: device.crownOrientation == .right)
        let recorder = recorder
        // Reading and the maths run off the main thread: a 3 h chunk is ~540k samples.
        let found = await Task.detached(priority: .utility) { () -> ([IntakeGestures.Gesture], [IntakeGestures.MealWindow], TimeInterval) in
            guard let list = recorder.accelerometerData(from: from, to: to) else { return ([], [], 0) }
            var samples: [IntakeGestures.Sample] = []
            samples.reserveCapacity(Int(to.timeIntervalSince(from) * 50))
            let base = from.timeIntervalSince1970
            var it = NSFastEnumerationIterator(list)
            while let item = it.next() {
                guard let d = item as? CMRecordedAccelerometerData else { continue }
                let a = d.acceleration
                samples.append(.init(t: d.startDate.timeIntervalSince1970 - base, a: Vec3(a.x, a.y, a.z)))
            }
            let gestures = IntakeGestures.detect(samples, handSign: sign)
            return (gestures, IntakeGestures.meals(gestures), base)
        }.value
        defaults.set(to.timeIntervalSince1970, forKey: Key.readUntil)
        let (gestures, meals, base) = found
        guard !gestures.isEmpty || !meals.isEmpty else { return }
        let date = { (t: TimeInterval) in Date(timeIntervalSince1970: base + t) }
        let batch = WIntakeBatch(
            from: from, to: to,
            sips: gestures.filter { $0.kind == .sip }.map { .init(date: date($0.start), confidence: $0.confidence) },
            meals: meals.map { .init(start: date($0.start), end: date($0.end), bites: $0.bites, confidence: $0.confidence) })
        guard WCSession.isSupported(), let data = try? JSONEncoder.watch.encode(batch) else { return }
        WCSession.default.transferUserInfo([WatchKeys.intake: data])
    }

    /// Next background refresh in about an hour (watchOS decides the exact time).
    static func scheduleRefresh() {
        guard UserDefaults.standard.bool(forKey: Key.on) else { return }
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: Date().addingTimeInterval(3600), userInfo: nil) { _ in }
    }
}
