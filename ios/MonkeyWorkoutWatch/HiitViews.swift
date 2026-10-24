import Foundation
import HealthKit
import Observation
import SwiftUI
import WatchConnectivity
import WatchKit

// HIIT on the Watch (#693, design C): while the iPhone plays a HIIT session, the Watch shows the same step full
// screen (phase colour, clock, move, round, heart rate), double tap pauses, and a HIIT workout session measures heart
// rate, sends it to the iPhone every 10 s and saves the workout to Apple Health when the iPhone logs it.

/// Heart-rate workout behind the iPhone's HIIT player.
@MainActor @Observable
final class HiitMirror: NSObject {
    static let shared = HiitMirror()

    private(set) var heartRate: Double?
    private(set) var running = false
    private var title = "HIIT"
    private var done = false
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var sentAt = Date.distantPast
    /// Last step from the iPhone, and the check that ends a workout the iPhone went silent on (#720).
    private var heardAt = Date()
    private var watchdog: Task<Void, Never>?
    /// No step for this long (the iPhone player was closed out of reach, or the app was killed): the workout ends.
    /// Longer than any sensible pause, so a paused HIIT isn't dropped.
    private static let silentLimit: TimeInterval = 60 * 60

    /// Each step from the iPhone: starts the workout on the first running one.
    func update(_ live: WHiitLive, name: String) {
        title = name
        done = live.done
        heardAt = Date()
        guard !running, live.endsAt != nil || live.startedAt != nil, !live.done else { return }
        guard !WorkoutManager.shared.running, !WodTracker.shared.running, !SportTracker.shared.running, !HyroxTracker.shared.running,
              !SwimTracker.shared.running, HKHealthStore.isHealthDataAvailable() else { return }
        running = true
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, self.running else { return }
                if Date().timeIntervalSince(self.heardAt) > HiitMirror.silentLimit {
                    self.end()
                    return
                }
            }
        }
        Task { await start() }
    }

    private func start() async {
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        try? await store.requestAuthorization(toShare: share, read: read)
        let config = HKWorkoutConfiguration()
        config.activityType = .highIntensityIntervalTraining
        config.locationType = .indoor
        guard let s = try? HKWorkoutSession(healthStore: store, configuration: config) else {
            running = false
            return
        }
        let b = s.associatedWorkoutBuilder()
        b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        b.delegate = self
        session = s
        builder = b
        let now = Date()
        s.startActivity(with: now)
        try? await b.beginCollection(at: now)
        try? await b.addMetadata(["MonkeyWorkoutTitle": title])
    }

    /// The iPhone closed its player: saved when it logged the workout, else thrown away.
    func end() {
        guard running else { return }
        running = false
        watchdog?.cancel()
        watchdog = nil
        let keep = done
        let s = session, b = builder
        session = nil
        builder = nil
        heartRate = nil
        s?.end()
        Task {
            if keep {
                try? await b?.endCollection(at: Date())
                _ = try? await b?.finishWorkout()
            } else {
                b?.discardWorkout()
            }
        }
    }

    fileprivate func collect(_ stats: HKStatistics) {
        guard stats.quantityType == HKQuantityType(.heartRate),
              let v = stats.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) else { return }
        heartRate = v
        if Date().timeIntervalSince(sentAt) >= 10, WCSession.default.isReachable {
            sentAt = Date()
            WCSession.default.sendMessage([WatchKeys.heartRate: Int(v.rounded())], replyHandler: nil, errorHandler: nil)
        }
    }
}

extension HiitMirror: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let stats = collectedTypes.compactMap { $0 as? HKQuantityType }.compactMap { workoutBuilder.statistics(for: $0) }
        Task { @MainActor in stats.forEach(self.collect) }
    }
}

/// The iPhone's HIIT step: phase colour, clock, move, round and heart rate; double tap pauses.
struct HiitRemoteView: View {
    let live: WHiitLive
    @Environment(WatchStore.self) private var store
    @Environment(\.isLuminanceReduced) private var dimmed

    private var colors: (UInt32, UInt32) {
        (live.tint.first ?? 0x3D4BD6, live.tint.count > 1 ? live.tint[1] : (live.tint.first ?? 0x5A2FA0))
    }

    var body: some View {
        // Wrist down: once a minute; paused on the iPhone: the clock stands still (#720).
        TimelineView(.animation(minimumInterval: dimmed ? 60 : 0.5, paused: live.endsAt == nil && live.startedAt == nil)) { ctx in
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: live.detail, color: .white.opacity(0.9))
                Text(clock(ctx.date)).font(W.display(40)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(live.title).font(W.label(14)).lineLimit(2).minimumScaleFactor(0.7)
                if let bpm = HiitMirror.shared.heartRate {
                    Text("♥ \(Int(bpm.rounded()))").font(W.label(13)).foregroundStyle(W.color(0xFF3D8B))
                }
                Spacer(minLength: 0)
                Button { store.sendTimerToggle() } label: {
                    Text(live.endsAt != nil || live.startedAt != nil ? "👌 pause" : "👌 start").font(W.label(14)).foregroundStyle(W.ink)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(W.lime))
                }
                .buttonStyle(.plain)
                .handGestureShortcut(.primaryAction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .watchMargins()
            .background(W.gradient(colors.0, colors.1).ignoresSafeArea())
        }
    }

    private func clock(_ now: Date) -> String {
        let s: Int
        if live.countUp, let from = live.startedAt {
            s = Int(now.timeIntervalSince(from))
        } else if let end = live.endsAt {
            s = Int(end.timeIntervalSince(now).rounded(.up))
        } else {
            s = live.remaining
        }
        let t = max(0, s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
