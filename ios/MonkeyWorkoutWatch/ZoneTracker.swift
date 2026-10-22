import HealthKit
import Observation
import SwiftUI
import WatchKit

// Heart-rate zones (#609, designs A + B from `apple-tech-radar/t7.png`): five square tiles with the current zone big and
// lit, a buzz on zone change, and a target lock that turns the screen when out of the session's zone.
// watchOS 27 sends Apple's own zone changes (Health settings zones, or ours set on the workout); before that the zone
// comes from the heart rate and the zones the iPhone sent.

/// Live zone of the running workout (sport, run, Hyrox or gym): one at a time, fed by the tracker that owns the session.
@MainActor @Observable
final class ZoneTracker {
    static let shared = ZoneTracker()

    /// 1…5; nil before the first heart rate.
    private(set) var zone: Int?
    /// Seconds in zone 1…5 this workout.
    private(set) var seconds: [Double] = Array(repeating: 0, count: 5)
    /// In the current zone since.
    private(set) var since: Date?
    /// Session target zone (design B): a planned run's zone, or the one picked before the start.
    var target: Int?
    private(set) var bpm: Double?
    private var last: Date?
    /// Apple's zone updates arrived (watchOS 27): they decide the zone, the heart rate only adds time.
    private var appleDriven = false

    var zones: WZones {
        if let z = WatchStore.current?.snapshot.zones, z.valid { return z }
        return .standard
    }

    func start(target: Int?) {
        zone = nil
        seconds = Array(repeating: 0, count: 5)
        since = nil
        bpm = nil
        last = nil
        appleDriven = false
        self.target = target
    }

    /// bpm under (negative) or over (positive) the target; 0 inside it or with no target.
    var off: Int {
        guard let target, let bpm else { return 0 }
        return zones.off(bpm, target: target)
    }

    var zone2Seconds: Double { seconds[1] }

    func heart(_ v: Double, at now: Date = Date()) {
        if let last, let zone { seconds[zone - 1] += min(max(now.timeIntervalSince(last), 0), 30) }
        last = now
        bpm = v
        if !appleDriven { change(to: zones.zone(v), at: now) }
    }

    /// watchOS 27 zone update: position 1…count among Apple's zones. Only five-zone setups drive the tiles.
    func apple(_ position: Int, count: Int) {
        guard count == 5 else { return }
        appleDriven = true
        change(to: position, at: Date())
    }

    private func change(to z: Int, at now: Date) {
        guard z != zone else { return }
        let was = zone
        let wasOff = off
        zone = z
        since = now
        guard let was, zones.buzz else { return }
        // Target lock: a stronger tap when leaving or coming back into the target zone.
        if target != nil, (wasOff == 0) != (off == 0) {
            WKInterfaceDevice.current().play(off == 0 ? .success : .retry)
        } else {
            WKInterfaceDevice.current().play(z > was ? .directionUp : .directionDown)
        }
    }
}

/// watchOS 27 HealthKit zones (verified against the HealthKit reference: `HKWorkoutZoneConfiguration`,
/// `HKLiveWorkoutBuilderDelegate.workoutBuilder(_:didUpdateWorkoutZone:)`).
@available(watchOS 27, *)
enum AppleZones {
    /// Before `beginCollection`: keep the member's Health zones when set, else ours for this workout.
    static func prepare(_ builder: HKLiveWorkoutBuilder, zones: WZones) async {
        let hr = HKQuantityType(.heartRate)
        if (try? await builder.zoneConfiguration(for: hr)) != nil { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let bounds = zones.starts.map { HKQuantity(unit: unit, doubleValue: Double($0)) }
        guard let config = try? HKWorkoutZoneConfiguration(quantityType: hr, zoneBoundaries: bounds) else { return }
        try? await builder.setCustomZoneConfiguration(config, for: hr)
    }

    /// Current zone as position 1…count, and the count.
    static func position(_ update: HKLiveWorkoutZoneUpdate) -> (zone: Int, count: Int)? {
        guard let group = update.zoneGroup, let current = update.currentZoneDuration?.zone,
              group.configuration.quantityType == HKQuantityType(.heartRate),
              let i = group.configuration.zones.firstIndex(where: { $0.index == current.index }) else { return nil }
        return (i + 1, group.configuration.zones.count)
    }
}

/// Before `beginCollection` on any of the Watch's workout builders.
@MainActor func prepareZones(_ builder: HKLiveWorkoutBuilder, target: Int?) async {
    ZoneTracker.shared.start(target: target)
    if #available(watchOS 27, *) { await AppleZones.prepare(builder, zones: ZoneTracker.shared.zones) }
}

/// Zone tiles (design A): five squares, the current one wide and lit with its number.
struct ZoneTiles: View {
    var height: CGFloat = 22
    @State private var tracker = ZoneTracker.shared

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { z in
                let on = tracker.zone == z
                let tint = WZones.tints[z - 1]
                Text("\(z)")
                    .font(W.label(on ? 13 : 10))
                    .foregroundStyle(on ? W.ink : .white.opacity(0.85))
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(RoundedRectangle(cornerRadius: 5).fill(on ? AnyShapeStyle(W.gradient(tint.0, tint.1)) : AnyShapeStyle(W.color(tint.0).opacity(0.3))))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(tracker.target == z ? Color.white : Color.clear, lineWidth: 1.5))
                    .layoutPriority(on ? 2 : 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tracker.zone.map { "Heart rate zone \($0)" } ?? "Heart rate zone unknown")
    }
}

/// Target lock line (design B): "Slow down ↓ 10 bpm" / "Speed up ↑ 6 bpm" / "In Zone 2 · 18:40".
struct ZoneTargetLine: View {
    @State private var tracker = ZoneTracker.shared

    var body: some View {
        if let target = tracker.target {
            let off = tracker.off
            Text(off > 0 ? "Slow down ↓ \(off) bpm" : off < 0 ? "Speed up ↑ \(-off) bpm"
                 : "In Zone \(target) · \(SportTrackView.clock(tracker.seconds[target - 1]))")
                .font(W.label(11))
                .foregroundStyle(off == 0 ? W.lime : .white)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

extension View {
    /// Out of the target zone: the screen washes orange (over) or blue (under), design B.
    func zoneLockWash() -> some View { modifier(ZoneLockWash()) }
}

private struct ZoneLockWash: ViewModifier {
    @State private var tracker = ZoneTracker.shared

    func body(content: Content) -> some View {
        let off = tracker.off
        content.background((off > 0 ? W.color(0xFF5A1F) : W.color(0x1E6BFF)).opacity(off == 0 ? 0 : 0.55).ignoresSafeArea())
    }
}
