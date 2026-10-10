import ActivityKit
import Foundation
import UserNotifications
import WorkoutEngine

/// Lock screen / Dynamic Island Live Activity and the "rest over" notification for the workout player.
@MainActor
final class LiveWorkout {
    private var activity: Activity<WorkoutActivityAttributes>?
    private static let restNotificationId = "workout.rest.end"

    func start(title: String, startedAt: Date, state: WorkoutActivityAttributes.ContentState) {
        #if DEBUG
        let ask = !Demo.enabled  // no permission prompt in demo/screenshot runs
        #else
        let ask = true
        #endif
        if ask { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return update(state) }
        // A previous run killed mid-workout can leave one behind.
        for a in Activity<WorkoutActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        activity = try? Activity.request(
            attributes: WorkoutActivityAttributes(sessionTitle: title, startedAt: startedAt),
            content: ActivityContent(state: state, staleDate: nil))
    }

    func update(_ state: WorkoutActivityAttributes.ContentState) {
        scheduleRestEnd(state)
        guard let activity else { return }
        Task { await activity.update(ActivityContent(state: state, staleDate: state.restEnd)) }
    }

    func end() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.restNotificationId])
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Buzz when rest is over while the phone is locked or in a pocket (shown as a banner only in the background).
    private func scheduleRestEnd(_ state: WorkoutActivityAttributes.ContentState) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.restNotificationId])
        guard let end = state.restEnd, end.timeIntervalSinceNow > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = "Next: \(state.next)"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: end.timeIntervalSinceNow, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.restNotificationId, content: content, trigger: trigger))
    }
}

extension WorkoutEngine.Category {
    /// First gradient colour as hex, for the Live Activity (the widget extension has no access to the app's theme).
    var tintHex: UInt32 {
        switch self {
        case .warmup: 0xFF8A00
        case .power: 0xFF2D55
        case .strength: 0x2F6BFF
        case .mobility: 0xA64DFF
        case .cardio: 0x00C9A7
        case .stretch: 0x1ED98A
        }
    }
}
