import APIClient
import SwiftUI
import UIKit
import UserNotifications
import WorkoutEngine

/// Where a tapped notification takes the user.
enum NotificationRoute: Identifiable, Equatable {
    case session(String)
    /// Missed-session check-in: the session and the day it was planned on.
    case reschedule(sessionId: String, day: Date)
    /// Badge just unlocked (#76).
    case badge(String)
    /// Someone you follow achieved something: their community page.
    case member(userId: String, nickname: String)

    var id: String {
        switch self {
        case let .session(s): "session|\(s)"
        case let .reschedule(s, d): "reschedule|\(s)|\(d.timeIntervalSince1970)"
        case let .badge(b): "badge|\(b)"
        case let .member(u, _): "member|\(u)"
        }
    }
}

/// Notifications (#69).
/// - Local: reminder on the morning of each planned session, check-in the day after a missed one
///   (actions: train today / pick another day). Rebuilt from the plan whenever it, history or prefs change.
/// - Remote: APNs token registered with the backend, which pushes followed users' achievements.
@MainActor @Observable
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    enum Category {
        static let upcoming = "SESSION_UPCOMING"
        static let missed = "SESSION_MISSED"
        static let follow = "FOLLOW_ACHIEVEMENT"
        static let badge = "BADGE_UNLOCKED"
    }

    enum Action {
        static let trainToday = "TRAIN_TODAY"
        static let reschedule = "RESCHEDULE"
    }

    private static let prefsKey = "notifications.prefs"

    var prefs: NotificationPrefs {
        didSet {
            guard prefs != oldValue else { return }
            save(prefs, Self.prefsKey)
            prefsDirty = true
        }
    }

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// Set when a notification is tapped; the main tab view presents it.
    var route: NotificationRoute?
    private(set) var pendingCount = 0

    private var deviceToken: String?
    private var registeredFor: String?
    private var prefsDirty = true
    private let center = UNUserNotificationCenter.current()

    override private init() {
        prefs = Self.load(NotificationPrefs.self, Self.prefsKey) ?? NotificationPrefs()
        super.init()
    }

    /// Once at launch, before any notification response can arrive.
    func configure() {
        center.delegate = self
        let train = UNNotificationAction(identifier: Action.trainToday, title: "Train today", options: [.foreground])
        let move = UNNotificationAction(identifier: Action.reschedule, title: "Pick another day", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.upcoming, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.missed, actions: [train, move], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.follow, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.badge, actions: [], intentIdentifiers: []),
        ])
    }

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Asks once; later calls just report the current state.
    @discardableResult
    func requestAuthorization() async -> Bool {
        await refreshAuthorization()
        if authorization == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
        }
        return [.authorized, .provisional, .ephemeral].contains(authorization)
    }

    var allowed: Bool { [.authorized, .provisional, .ephemeral].contains(authorization) }

    // MARK: Local reminders

    /// Rebuilds pending session reminders and check-ins from the current plan.
    func reschedule(_ model: AppModel, now: Date = Date()) async {
        await refreshAuthorization()
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter(Self.isOurs)
        center.removePendingNotificationRequests(withIdentifiers: ours)
        guard allowed, model.phase == .signedIn, !model.demo else {
            pendingCount = 0
            return
        }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let from = cal.date(byAdding: .day, value: -1, to: today) ?? today
        let through = cal.date(byAdding: .day, value: 8, to: today) ?? today
        let source = CalendarSessionSource(model: model, from: from, through: through)
        let reminders = ReminderPlanner.plan(source.plannedSessions(from: from, through: through, calendar: cal), prefs: prefs, now: now, calendar: cal)
        for r in reminders {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            content.threadIdentifier = r.kind.rawValue
            content.categoryIdentifier = r.kind == .upcoming ? Category.upcoming : Category.missed
            content.userInfo = ["kind": r.kind.rawValue, "sessionId": r.sessionId, "day": r.day.timeIntervalSince1970]
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: r.fireAt)
            let req = UNNotificationRequest(identifier: r.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(req)
        }
        pendingCount = reminders.count
        // A check-in already on screen for a session that is now done or moved is stale.
        let open = Set(reminders.map(\.id))
        let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix("missed|") && !open.contains($0) }
        let stillMissed = Set(source.plannedSessions(from: from, through: today, calendar: cal).filter { !$0.done }
            .map { "missed|\($0.sessionId)|\(ReminderPlanner.dayKey($0.day, calendar: cal))" })
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { !stillMissed.contains($0) })
    }

    private static func isOurs(_ id: String) -> Bool { id.hasPrefix("upcoming|") || id.hasPrefix("missed|") }

    /// Test notification in 5 s (Settings).
    func sendLocalTest() async {
        guard await requestAuthorization() else { return }
        let content = UNMutableNotificationContent()
        content.title = "MonkeyWorkout"
        content.body = "Reminders work. See you at the gym 💪"
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "test|\(UUID().uuidString)", content: content,
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
    }

    // MARK: Remote push

    /// Registers for APNs when follow alerts are on and the user allowed notifications.
    func registerRemoteIfNeeded() {
        guard allowed, prefs.followAchievements else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
    }

    /// Uploads token + prefs for the signed-in user (idempotent; cheap to call on every foreground).
    func syncRemote(_ model: AppModel) async {
        guard model.phase == .signedIn, !model.demo, let userId = model.user?.id else { return }
        if prefsDirty || registeredFor != userId {
            do {
                try await model.api.saveNotificationPrefs(prefs)
                prefsDirty = false
            } catch { /* retried on next foreground */ }
        }
        guard let token = deviceToken, registeredFor != "\(userId)|\(token)" else { return }
        #if DEBUG
        let env = "sandbox"
        #else
        let env = "production"
        #endif
        do {
            try await model.api.registerPushDevice(token: token, env: env, topic: Bundle.main.bundleIdentifier ?? "", timeZone: TimeZone.current.identifier)
            registeredFor = "\(userId)|\(token)"
        } catch { /* retried on next foreground */ }
    }

    /// Badges unlocked since the last check: a local "badge unlocked" notification (#76) and an
    /// announcement the server pushes to followers. The first check per account only records a
    /// baseline, so old badges never notify anyone.
    func announceNewBadges(_ model: AppModel, now: Date = Date()) async {
        guard model.phase == .signedIn, !model.demo, let userId = model.user?.id else { return }
        let key = "notifications.badges.\(userId)"
        let pendingKey = "notifications.badgeAnnouncements.\(userId)"
        let unlocked = Achievements.evaluate(records: model.state.history, weights: model.weightEntries,
                                             targetPerWeek: model.profile?.sessionsPerWeek ?? 3).filter(\.unlocked)
        guard let known = Self.load(Set<String>.self, key) else {
            save(Set(unlocked.map(\.id)), key)
            return
        }
        let recent = now.addingTimeInterval(-2 * 86_400)
        let fresh = unlocked.filter { !known.contains($0.id) }
        var pending = Self.load([AchievementAnnouncement].self, pendingKey) ?? []
        if !fresh.isEmpty {
            save(known.union(fresh.map(\.id)), key)
            let newOnes = fresh.filter { ($0.unlockedAt ?? .distantPast) >= recent }
            if prefs.ownAchievements, allowed {
                for b in newOnes { await postBadgeUnlocked(b) }
            }
            pending += newOnes.map { AchievementAnnouncement(id: "badge-\($0.id)", type: "badge", text: "Unlocked \($0.title): \($0.detail)") }
            save(pending, pendingKey)
        }
        guard !pending.isEmpty else { return }
        do {
            try await model.api.announceAchievements(Array(pending.prefix(30)))
            save(Array(pending.dropFirst(30)), pendingKey)
        } catch { /* retried on next change */ }
    }

    /// A new personal record: followers get "New PR: Bench press 100 kg × 3" (once per attempt).
    func announcePR(_ attempt: PRAttempt, model: AppModel) {
        guard model.phase == .signedIn, !model.demo, let userId = model.user?.id else { return }
        let pendingKey = "notifications.badgeAnnouncements.\(userId)"
        let name = Exercise.find(attempt.exerciseId)?.name ?? attempt.exerciseId
        let kg = String(format: "%g", attempt.kg)
        var pending = Self.load([AchievementAnnouncement].self, pendingKey) ?? []
        pending.append(AchievementAnnouncement(id: "pr-\(attempt.id.uuidString)", type: "pr", text: "New PR: \(name) \(kg) kg × \(attempt.reps)"))
        save(pending, pendingKey)
        Task {
            do {
                try await model.api.announceAchievements(Array(pending.prefix(30)))
                save(Array(pending.dropFirst(30)), pendingKey)
            } catch { /* flushed with the next badge check */ }
        }
    }

    private func postBadgeUnlocked(_ b: Badge) async {
        let content = UNMutableNotificationContent()
        content.title = "Achievement unlocked: \(b.title) 🏆"
        content.body = b.detail
        content.sound = .default
        content.threadIdentifier = "badge"
        content.categoryIdentifier = Category.badge
        content.userInfo = ["kind": "badge", "badgeId": b.id]
        try? await center.add(UNNotificationRequest(identifier: "badge|\(b.id)", content: content, trigger: nil))
    }

    /// Before sign-out: stop pushes to this device for this account, drop local reminders.
    func signOut(api: APIClient) async {
        if let token = deviceToken { try? await api.unregisterPushDevice(token: token) }
        registeredFor = nil
        prefsDirty = true
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        pendingCount = 0
    }

    // MARK: Storage

    private func save(_ value: some Encodable, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_: T.Type, _ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let kind = info["kind"] as? String
        let sessionId = info["sessionId"] as? String
        let day = (info["day"] as? Double).map { Date(timeIntervalSince1970: $0) }
        let action = response.actionIdentifier
        let badgeId = info["badgeId"] as? String
        let actorId = info["actorId"] as? String
        let actorName = info["actorName"] as? String
        await MainActor.run {
            if kind == "follow_achievement", let actorId {
                self.route = .member(userId: actorId, nickname: actorName ?? "")
                return
            }
            if kind == "badge", let badgeId {
                self.route = .badge(badgeId)
                return
            }
            guard let sessionId else { return }
            switch (kind, action) {
            case ("missed", Action.trainToday): self.route = .session(sessionId)
            case ("missed", _): self.route = .reschedule(sessionId: sessionId, day: day ?? Date())
            case ("upcoming", _): self.route = .session(sessionId)
            default: break
            }
        }
    }
}

/// Planned, not-done sessions from the training calendar (#68): dated, adapted around away periods and
/// moves, so a rescheduled session gets its reminder on the new day.
struct CalendarSessionSource: PlannedSessionSource {
    private let items: [PlannedSession]

    @MainActor init(model: AppModel, from: Date, through: Date) {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: through).map { $0.addingTimeInterval(-1) } ?? through
        items = model.plannedSessions(from: from, to: end).map {
            PlannedSession(sessionId: $0.session.id, title: $0.session.title, estMin: $0.session.estMin, day: $0.date, done: false)
        }
    }

    func plannedSessions(from: Date, through: Date, calendar cal: Calendar) -> [PlannedSession] {
        let last = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: through)) ?? through
        return items.filter { $0.day >= cal.startOfDay(for: from) && $0.day < last }
    }
}

/// Bridges UIKit's remote-notification callbacks into SwiftUI.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { NotificationManager.shared.configure() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { NotificationManager.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulator, missing aps-environment entitlement or no network: local reminders still work.
    }
}
