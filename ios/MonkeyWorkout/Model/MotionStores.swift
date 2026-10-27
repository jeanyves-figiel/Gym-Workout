import Foundation
import LiftSensor
import Observation
import UserNotifications
import WorkoutEngine

/// Saved WOD and combat timers (#622 A). On the device (Application Support), sent to the Watch with the snapshot.
@MainActor @Observable
final class WodStore {
    static let shared = WodStore()

    private(set) var timers: [WodTimer] = []

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("wod-timers.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.url), let list = try? JSONDecoder().decode([WodTimer].self, from: data) { timers = list }
    }

    func save(_ t: WodTimer) {
        var list = timers
        if let i = list.firstIndex(where: { $0.id == t.id }) { list[i] = t } else { list.insert(t, at: 0) }
        write(list)
    }

    func delete(_ t: WodTimer) { write(timers.filter { $0.id != t.id }) }

    /// Undo of a delete.
    func restore(_ t: WodTimer, at index: Int) {
        var list = timers
        list.insert(t, at: min(index, list.count))
        write(list)
    }

    func signOut() {
        timers = []
        try? FileManager.default.removeItem(at: Self.url)
    }

    /// The account's timers, kept on this device while signed out (#822).
    func exportData() -> Data? { try? JSONEncoder().encode(timers) }

    /// Brings back the timers an account had when it signed out on this device (#822).
    func restore(_ data: Data) {
        guard let list = try? JSONDecoder().decode([WodTimer].self, from: data) else { return }
        write(list)
    }

    private func write(_ list: [WodTimer]) {
        timers = list
        if let data = try? JSONEncoder().encode(list) {
            try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: Self.url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        WatchSync.shared.schedulePush()
    }
}

/// Swimming (#624): the swim plan (B), swim blocks added to gym days (C) and the pool length.
/// On the device (Application Support); the Watch gets today's and the next swim with the snapshot.
@MainActor @Observable
final class SwimStore {
    static let shared = SwimStore()

    struct Block: Codable, Hashable {
        var place: SwimWorkout.Place
        var minutes: Int

        var workout: SwimWorkout { SwimWorkout.block(minutes: minutes, place: place) }
    }

    struct Saved: Codable {
        var plan: SwimPlan?
        var pool = 25
        /// Gym-day swim blocks by session id.
        var blocks: [String: Block] = [:]
        /// Open water buddy alert after this many minutes (#615 B).
        var buddyMinutes = 60
    }

    private(set) var saved = Saved()

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("swim.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.url), let s = try? JSONDecoder().decode(Saved.self, from: data) { saved = s }
    }

    var plan: SwimPlan? { saved.plan }

    func block(for sessionId: String) -> Block? { saved.blocks[sessionId] }

    func setBlock(_ b: Block?, for sessionId: String) {
        var s = saved
        s.blocks[sessionId] = b
        write(s)
    }

    func setPlan(_ p: SwimPlan?) {
        var s = saved
        s.plan = p
        if let p { s.pool = p.pool }
        write(s)
    }

    func setPool(_ m: Int) {
        var s = saved
        s.pool = m
        s.plan?.pool = m
        write(s)
    }

    func setBuddyMinutes(_ m: Int) {
        var s = saved
        s.buddyMinutes = m
        write(s)
    }

    /// "1 km non-stop · week 3 of 8".
    func planLine(_ now: Date = Date()) -> String? {
        guard let p = saved.plan, let w = p.week(on: now) else { return nil }
        return "\(p.goal.label) · week \(w) of \(p.weeks)"
    }

    func signOut() {
        saved = Saved()
        try? FileManager.default.removeItem(at: Self.url)
    }

    /// The account's swim plan and blocks, kept on this device while signed out (#822).
    func exportData() -> Data? { try? JSONEncoder().encode(saved) }

    /// Brings back the swims an account had when it signed out on this device (#822).
    func restore(_ data: Data) {
        guard let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        write(s)
    }

    private func write(_ s: Saved) {
        saved = s
        if let data = try? JSONEncoder().encode(s) {
            try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: Self.url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        WatchSync.shared.schedulePush()
    }

    // MARK: Open water buddy alert (#615 B)

    /// The Watch started (or ended) an open water swim: alert on this iPhone if it is still running `minutes` later.
    nonisolated static func buddy(_ b: WSwimBuddy) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["swim-buddy"])
        guard !b.ended else { return }
        let due = b.start.addingTimeInterval(Double(b.minutes) * 60)
        guard due > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Open water swim still going"
        content.body = "Started \(b.start.formatted(date: .omitted, time: .shortened)), \(b.minutes) min ago. Check on your swimmer."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, due.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: "swim-buddy", content: content, trigger: trigger))
    }
}

extension AppModel {
    /// Gym weekdays of this week's plan in Calendar numbering (1 = Sunday), for the swim plan's days.
    var liftingWeekdays: Set<Int> {
        Set((plan?.sessions ?? []).compactMap(\.weekday).map { $0 % 7 + 1 })
    }

    /// Today's gym session, when it is planned today.
    var todaySession: Session? {
        let cal = planCalendar
        return plan?.sessions.first { cal.isDateInToday(day(of: $0)) && $0.weekday != nil }
    }

    /// What the Watch's swim screen shows (#624): today's swim (plan day first, else today's gym-day block) and the next one.
    func watchSwim(now: Date = Date()) -> WSwim? {
        let store = SwimStore.shared
        let block = todaySession.flatMap { store.block(for: $0.id) }
        guard store.plan != nil || block != nil || store.saved.pool != 25 else { return nil }
        var w = WSwim(pool: store.saved.pool, plan: store.planLine(now), buddyMinutes: store.saved.buddyMinutes)
        w.today = store.plan?.workout(on: now) ?? block?.workout
        if let next = store.plan?.next(from: now.addingTimeInterval(86_400)) {
            w.next = next.workout
            w.nextDay = next.day
        }
        return w
    }
}
