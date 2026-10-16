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

    /// Lock screen card left by a run iOS closed mid-workout, when that workout isn't reopened (#359).
    static func endLeftovers() {
        for a in Activity<WorkoutActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
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

    /// Finished (#371): the card turns into the workout summary and stays on the lock screen for 15 minutes.
    func finish(_ state: WorkoutActivityAttributes.ContentState) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.restNotificationId])
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil),
                               dismissalPolicy: .after(Date().addingTimeInterval(15 * 60)))
        }
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

    /// Second gradient colour as hex (Watch).
    var tintHex2: UInt32 {
        switch self {
        case .warmup: 0xFFC93D
        case .power: 0xFF6FB5
        case .strength: 0x8A4DFF
        case .mobility: 0xFF4DD8
        case .cardio: 0x2EC5FF
        case .stretch: 0xB6FF6B
        }
    }
}

extension AppModel {
    /// kg × reps logged in this workout, and how many exercises beat their heaviest weight from before it (#371).
    func liveLifts(sessionId: String, since: Date) -> (volumeKg: Double, prs: Int) {
        let logs = setLogs
        let mine = logs.filter { $0.sessionId == sessionId && $0.date >= since }
        let volume = mine.reduce(0) { $0 + $1.kg * Double($1.reps ?? 0) }
        var prs = 0
        for (id, sets) in Dictionary(grouping: mine, by: \.exerciseId) {
            // A first log of an exercise is not a record.
            let before = logs.filter { $0.exerciseId == id && $0.date < since }.map(\.kg).max()
            if let before, let top = sets.map(\.kg).max(), top > before { prs += 1 }
        }
        return (volume, prs)
    }
}
