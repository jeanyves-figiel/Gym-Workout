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
    /// "Pick another day": the day picker itself, not the check-in.
    case move(sessionId: String)
    /// Badge just unlocked (#76).
    case badge(String)
    /// Someone you follow achieved something: their community page.
    case member(userId: String, nickname: String)

    var id: String {
        switch self {
        case let .session(s): "session|\(s)"
        case let .reschedule(s, d): "reschedule|\(s)|\(d.timeIntervalSince1970)"
        case let .move(s): "move|\(s)"
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
        static let move = "MOVE_NUDGE"
        static let water = "WATER_NUDGE"
        static let comeback = "COMEBACK_NUDGE"
    }

    enum Action {
        static let trainToday = "TRAIN_TODAY"
        static let reschedule = "RESCHEDULE"
        static let moveLater = "MOVE_LATER"
        static let moveRest = "MOVE_REST"
        static let waterOne = "WATER_ONE"
        static let waterTwo = "WATER_TWO"
        static let waterLater = "WATER_LATER"
        static let comebackNow = "COMEBACK_NOW"
        static let comebackTonight = "COMEBACK_TONIGHT"
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
    /// Comeback offer taken from the banner (#876 C); Train adds the workout and clears it.
    var comebackPick: ComebackPick?
    /// On-device rewording of Coach reminders, by their facts: rebuilds don't ask the model again.
    @ObservationIgnored private var reworded: [String: CoachNudge] = [:]

    private var deviceToken: String?
    private var registeredFor: String?
    private var prefsDirty = true
    /// The latest `reschedule`; the next one waits for it.
    @ObservationIgnored private var rescheduleTask: Task<Void, Never>?
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
            // Water (#520): counted from the banner or the Watch, without opening the app.
            UNNotificationCategory(identifier: Category.water, actions: [
                UNNotificationAction(identifier: Action.waterOne, title: "+1 glass", options: []),
                UNNotificationAction(identifier: Action.waterTwo, title: "+2", options: []),
                UNNotificationAction(identifier: Action.waterLater, title: "Later", options: []),
            ], intentIdentifiers: []),
            // Comeback nudge (#876 C): one kind offer after 2+ missed sessions or a long break.
            UNNotificationCategory(identifier: Category.comeback, actions: [
                UNNotificationAction(identifier: Action.comebackNow, title: "Start \(CoachNudges.comebackMinutes)′ now", options: [.foreground]),
                UNNotificationAction(identifier: Action.comebackTonight, title: "Tonight 19:00", options: [.foreground]),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.move, actions: [
                UNNotificationAction(identifier: Action.moveLater, title: "Later", options: []),
                UNNotificationAction(identifier: Action.moveRest, title: "Rest day", options: []),
            ], intentIdentifiers: []),
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

    /// Rebuilds pending session reminders and check-ins from the current plan. Calls run one after another: two
    /// rebuilds interleaving at their awaits would leave reminders from the older plan.
    func reschedule(_ model: AppModel, now: Date = Date()) async {
        let previous = rescheduleTask
        let task = Task {
            await previous?.value
            await self.rebuildReminders(model, now: now)
        }
        rescheduleTask = task
        await task.value
    }

    private func rebuildReminders(_ model: AppModel, now: Date) async {
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
        let sessions = source.plannedSessions(from: from, through: through, calendar: cal)
        let reminders = ReminderPlanner.plan(sessions, prefs: prefs, now: now, calendar: cal)
        let history = model.state.history
        let planned = Dictionary(sessions.map { ($0.sessionId, $0) }) { a, _ in a }
        var reworded = 0
        for r in reminders {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            // Coach-written reminder (#876 A): from the member's last time; the next few reworded on the iPhone.
            if r.kind == .upcoming, let s = planned[r.sessionId],
               var nudge = CoachNudges.reminder(title: s.title, sessionId: s.sessionId, focus: s.focus, estMin: s.estMin, day: r.day,
                                                history: history, calendar: cal) {
                if reworded < 3 { nudge = await rewordOnDevice(nudge); reworded += 1 }
                content.body = nudge.body
            }
            content.sound = .default
            content.threadIdentifier = r.kind.rawValue
            content.categoryIdentifier = r.kind == .upcoming ? Category.upcoming : Category.missed
            content.userInfo = ["kind": r.kind.rawValue, "sessionId": r.sessionId, "day": r.day.timeIntervalSince1970]
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: r.fireAt)
            let req = UNNotificationRequest(identifier: r.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(req)
        }
        let nudges = await scheduleSportNudges(model.profile, away: model.away, today: today, now: now, calendar: cal)
        let comeback = await scheduleComeback(model, now: now, calendar: cal)
        pendingCount = reminders.count + nudges + comeback
        // A check-in already on screen for a session that is now done or moved is stale.
        let open = Set(reminders.map(\.id))
        let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix("missed|") && !open.contains($0) }
        let stillMissed = Set(source.plannedSessions(from: from, through: today, calendar: cal).filter { !$0.done }
            .map { "missed|\($0.sessionId)|\(ReminderPlanner.dayKey($0.day, calendar: cal))" })
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { !stillMissed.contains($0) })
        await scheduleWater(now: now)
        await scheduleSupplements(now: now)
    }

    /// Sport-day start nudge (#418, design C): 08:00 on planned sport days, mirrored to the Watch. Dives are left to dive apps.
    private func scheduleSportNudges(_ profile: Profile?, away: [AwayPeriod], today: Date, now: Date, calendar cal: Calendar) async -> Int {
        guard let profile, prefs.sessionReminders else { return 0 }
        var count = 0
        for offset in 0..<8 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  let fire = cal.date(bySettingHour: 8, minute: 0, second: 0, of: day), fire > now else { continue }
            let wd = WeekSchedule.fromCalendar(cal.component(.weekday, from: day))
            guard let sport = profile.sportDays(on: day, away: away).first(where: { $0.weekday == wd && $0.sport != .scubaDiving })?.sport else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(sport.label) today?"
            content.body = "Start it on your Apple Watch: route, speed and HR, with a battery saver mode."
            content.sound = .default
            content.threadIdentifier = "sport"
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let id = "sport|\(sport.rawValue)|\(ReminderPlanner.dayKey(day, calendar: cal))"
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            count += 1
        }
        return count
    }

    private static func isOurs(_ id: String) -> Bool {
        id.hasPrefix("upcoming|") || id.hasPrefix("missed|") || id.hasPrefix("sport|") || id.hasPrefix("comeback|")
    }

    // MARK: Coach nudges (#876)

    private static let comebackSentKey = "notifications.comebackSent"

    /// Comeback nudge (C): once per drift (2+ missed sessions since the last workout, or a long break), at the next
    /// 12:00 or 17:00. Rebuilt with the plan, so a workout done before it fires cancels it.
    private func scheduleComeback(_ model: AppModel, now: Date, calendar cal: Calendar) async -> Int {
        guard prefs.comebackNudge, let at = CoachNudges.comebackFireAt(now: now, prefs: prefs, calendar: cal) else { return 0 }
        let history = model.state.history
        let key = CoachNudges.driftKey(history: history, calendar: cal)
        let store = UserDefaults.standard
        // Sent already for this drift: the one scheduled before has fired.
        if let sent = store.dictionary(forKey: Self.comebackSentKey), sent["key"] as? String == key,
           let fired = sent["at"] as? Double, Date(timeIntervalSince1970: fired) <= now { return 0 }
        let focus = model.comebackFocus
        guard var nudge = CoachNudges.comeback(missedDays: model.missedDays, focus: focus, history: history, fireAt: at, calendar: cal)
        else { return 0 }
        nudge = await rewordOnDevice(nudge)
        let content = UNMutableNotificationContent()
        content.title = nudge.title
        content.body = nudge.body
        content.sound = .default
        content.threadIdentifier = "comeback"
        content.categoryIdentifier = Category.comeback
        content.userInfo = ["kind": "comeback", "focus": focus.rawValue]
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
        try? await center.add(UNNotificationRequest(identifier: key, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        store.set(["key": key, "at": at.timeIntervalSince1970], forKey: Self.comebackSentKey)
        return 1
    }

    /// The nudge in Coach's words from the on-device model (#608); the built text when it isn't there.
    private func rewordOnDevice(_ nudge: CoachNudge) async -> CoachNudge {
        let cacheKey = nudge.title + "|" + nudge.facts.joined(separator: "|")
        if let done = reworded[cacheKey] { return done }
        guard let better = await OnDeviceCoach.nudge(nudge) else { return nudge }
        reworded[cacheKey] = better
        return better
    }

    /// "Tonight 19:00" on the comeback nudge: a reminder for the workout it just added to today.
    func scheduleTonight(_ session: Session, now: Date = Date()) async {
        let cal = Calendar.current
        guard let at = cal.date(bySettingHour: 19, minute: 0, second: 0, of: now), at > now else { return }
        let content = UNMutableNotificationContent()
        content.title = "Tonight: \(session.displayTitle)"
        content.body = "\(session.estMin) min, ready on Train. Coach is in."
        content.sound = .default
        content.threadIdentifier = LocalReminder.Kind.upcoming.rawValue
        content.categoryIdentifier = Category.upcoming
        content.userInfo = ["kind": LocalReminder.Kind.upcoming.rawValue, "sessionId": session.id]
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
        try? await center.add(UNNotificationRequest(identifier: "tonight|\(session.id)", content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    // MARK: Daily Move (#454)

    /// The slow-day nudge, right now (decided by `HealthManager.checkMoveNudge` from fresh steps).
    func postMoveNudge(steps: Int, usual: Int) async {
        await refreshAuthorization()
        guard allowed else { return }
        let text = DailyMove.message(steps: steps, usual: usual)
        await postMove(id: "move|\(MoveStore.shared.key(Date()))", title: text.title, body: text.body, trigger: nil)
    }

    /// "Later": one reminder an hour from now, still inside the evening and out of quiet hours.
    func moveLater(now: Date = Date()) async {
        let at = now.addingTimeInterval(3600)
        let cal = Calendar.current
        let minute = cal.component(.hour, from: at) * 60 + cal.component(.minute, from: at)
        guard cal.isDate(at, inSameDayAs: now), minute < 21 * 60, !prefs.isQuiet(minute) else { return }
        await postMove(id: "move-later|\(MoveStore.shared.key(now))", title: "Up for that walk now? 👣",
                       body: "Steps and stairs count toward your level.",
                       trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false))
    }

    // MARK: Fuel (#496)

    /// One refuel reminder a day, 90 min after a workout, unless the recovery meal was counted (then cancelled)
    /// or it would land in quiet hours or after 22:00.
    func scheduleRefuel(dayKey: String, now: Date = Date()) async {
        await refreshAuthorization()
        guard allowed else { return }
        let at = now.addingTimeInterval(90 * 60)
        let cal = Calendar.current
        let minute = cal.component(.hour, from: at) * 60 + cal.component(.minute, from: at)
        guard cal.isDate(at, inSameDayAs: now), minute < 22 * 60, !prefs.isQuiet(minute) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Refuel time 🍽️"
        content.body = "Protein and carbs help you recover. Open Fuel for ideas that fit today."
        content.sound = .default
        content.threadIdentifier = "fuel"
        content.userInfo = ["kind": "fuel"]
        try? await center.add(UNNotificationRequest(identifier: "fuel|\(dayKey)", content: content,
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 90 * 60, repeats: false)))
    }

    /// Water nudges for the rest of today (#520, design A), on the pace from `WaterPace`: rebuilt whenever a glass is
    /// counted, the water settings change or the plan is rescheduled.
    func scheduleWater(now: Date = Date()) async {
        // A "Later" the member asked for stays (#820): this runs at every foreground.
        let old = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix("water|") && !$0.hasPrefix("water|later|") }
        center.removePendingNotificationRequests(withIdentifiers: old)
        #if DEBUG
        if Demo.enabled { return }
        #endif
        let store = FuelStore.shared
        guard allowed, store.saved.setUp, let plan = store.planFor?(now) else { return }
        let cal = Calendar.current
        let minute = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let nudges = WaterPace.nudges(plan, glasses: store.log(now).glasses, prefs: store.prefs, water: store.waterPrefs,
                                      now: minute, quiet: { [prefs] in prefs.isQuiet($0) }, calendar: cal)
        let day = cal.startOfDay(for: now)
        for n in nudges {
            // Clock time, not minutes after midnight: a DST day keeps 8:00 at 8:00 (#716).
            guard let at = cal.date(bySettingHour: n.minute / 60, minute: n.minute % 60, second: 0, of: day), at > now else { continue }
            await postWater(id: "water|\(store.key(now))|\(n.minute)", title: n.title, body: n.body,
                            trigger: UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: at), repeats: false))
        }
    }

    /// Supplement reminders (#572): one at each take the member asked a reminder for, today and the next 2 days,
    /// skipping takes already ticked and quiet hours. Rebuilt when the stack changes, a take is ticked or the plan moves.
    func scheduleSupplements(now: Date = Date()) async {
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("supp|") }
        center.removePendingNotificationRequests(withIdentifiers: old)
        #if DEBUG
        if Demo.enabled { return }
        #endif
        let store = FuelStore.shared
        guard allowed, store.stack.contains(where: { $0.rhythm?.remind == true }), let planFor = store.planFor else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        for offset in 0..<3 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let log = store.log(day)
            for dose in planFor(day).supplements where log.ticks[dose.id] == nil && !prefs.isQuiet(dose.minute) {
                guard store.stack.first(where: { Supplements.tickId($0) == dose.id || dose.id.hasPrefix(Supplements.tickId($0) + "-") })?
                        .rhythm?.remind == true,
                      let at = cal.date(bySettingHour: dose.minute / 60, minute: dose.minute % 60, second: 0, of: day), at > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "\(dose.supplement.emoji) \(dose.supplement.name)"
                content.body = [dose.reason, dose.supplement.dose].filter { !$0.isEmpty }.joined(separator: " · ")
                content.sound = .default
                content.threadIdentifier = "fuel"
                content.userInfo = ["kind": "fuel"]
                try? await center.add(UNNotificationRequest(identifier: "supp|\(store.key(day))|\(dose.id)", content: content,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: at), repeats: false)))
            }
        }
    }

    /// "Later": one water nudge in an hour, outside quiet hours and before 22:00.
    func waterLater(now: Date = Date()) async {
        let at = now.addingTimeInterval(3600)
        let cal = Calendar.current
        let minute = cal.component(.hour, from: at) * 60 + cal.component(.minute, from: at)
        guard cal.isDate(at, inSameDayAs: now), minute < 22 * 60, !prefs.isQuiet(minute) else { return }
        await postWater(id: "water|later|\(Int(at.timeIntervalSince1970))", title: "Time for a glass 💧",
                        body: "A glass now keeps you on pace.", trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false))
    }

    private func postWater(id: String, title: String, body: String, trigger: UNNotificationTrigger) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "water"
        content.categoryIdentifier = Category.water
        content.userInfo = ["kind": "water"]
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func cancelRefuel(dayKey: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["fuel|\(dayKey)"])
    }

    private func postMove(id: String, title: String, body: String, trigger: UNNotificationTrigger?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "move"
        content.categoryIdentifier = Category.move
        content.userInfo = ["kind": "move"]
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

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
        resetPrefs()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        pendingCount = 0
    }

    /// Back to the defaults (sign-out, another account signing in): one account's choices never reach the next.
    func resetPrefs() {
        prefs = NotificationPrefs()
        prefsDirty = true
        UserDefaults.standard.removeObject(forKey: Self.comebackSentKey)
        reworded = [:]
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
    // Completion-handler forms, answered on the main thread (#351). The `async` forms let Swift call UIKit's handler from
    // a background thread; for a tapped notification that handler updates the app snapshot and UIKit aborts the app
    // ("_performBlockAfterCATransactionCommitSynchronizes"), e.g. tapping the rest-over alert to get back to a workout.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        DispatchQueue.main.async { completionHandler([.banner, .list, .sound]) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if info["kind"] as? String == "move", [Action.moveLater, Action.moveRest].contains(response.actionIdentifier) {
            let later = response.actionIdentifier == Action.moveLater
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if !later { MoveStore.shared.restToday() }
                }
                Task { @MainActor in
                    if later { await NotificationManager.shared.moveLater() }
                    completionHandler()
                }
            }
            return
        }
        if info["kind"] as? String == "water", [Action.waterOne, Action.waterTwo, Action.waterLater].contains(response.actionIdentifier) {
            let action = response.actionIdentifier
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if action != Action.waterLater { FuelStore.shared.addGlasses(action == Action.waterTwo ? 2 : 1) }
                }
                Task { @MainActor in
                    if action == Action.waterLater { await NotificationManager.shared.waterLater() }
                    completionHandler()
                }
            }
            return
        }
        if info["kind"] as? String == "comeback", [Action.comebackNow, Action.comebackTonight].contains(response.actionIdentifier) {
            let pick = ComebackPick(focus: Focus(rawValue: info["focus"] as? String ?? "") ?? .fullUpper,
                                    tonight: response.actionIdentifier == Action.comebackTonight)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { NotificationManager.shared.comebackPick = pick }
                completionHandler()
            }
            return
        }
        let route = Self.route(kind: info["kind"] as? String, action: response.actionIdentifier,
                               sessionId: info["sessionId"] as? String,
                               day: (info["day"] as? Double).map { Date(timeIntervalSince1970: $0) },
                               badgeId: info["badgeId"] as? String,
                               actorId: info["actorId"] as? String, actorName: info["actorName"] as? String)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let route { NotificationManager.shared.route = route }
            }
            completionHandler()
        }
    }

    /// Where a tapped notification goes; nil = just open the app.
    nonisolated static func route(kind: String?, action: String, sessionId: String?, day: Date?,
                                  badgeId: String?, actorId: String?, actorName: String?) -> NotificationRoute? {
        // Gym buddy invite or pairing (#626) opens the member's page, where Gym buddy accepts.
        if kind == "follow_achievement" || kind == "buddy_invite", let actorId { return .member(userId: actorId, nickname: actorName ?? "") }
        if kind == "badge", let badgeId { return .badge(badgeId) }
        guard let sessionId else { return nil }
        switch (kind, action) {
        case ("missed", Action.reschedule): return .move(sessionId: sessionId)
        // "Train today" too: the missed day's own page can't start it (#537), the check-in's Train now can.
        case ("missed", _): return .reschedule(sessionId: sessionId, day: day ?? Date())
        case ("upcoming", _): return .session(sessionId)
        default: return nil
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
            PlannedSession(sessionId: $0.session.id, title: $0.session.title, estMin: $0.session.estMin, day: $0.date, done: false,
                           focus: $0.session.focus)
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
        MainActor.assumeIsolated {
            NotificationManager.shared.configure()
            MirroredWorkout.shared.listen()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { NotificationManager.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulator, missing aps-environment entitlement or no network: local reminders still work.
    }

    /// Upright on iPhone except in the workout player (#362).
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { OrientationLock.mask }
    }

    /// AirPlay / HDMI screen: its own workout layout instead of the mirrored phone (#724). Everything else keeps
    /// SwiftUI's own scene.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            config.delegateClass = TVSceneDelegate.self
        }
        return config
    }
}
