import AppIntents
import Foundation
import UserNotifications
import WidgetKit

/// Water widgets (#520): the widget extension can't open Fuel's file, so a tapped glass waits in the App Group
/// until the app is next active and counts it on the day it was tapped.
enum WaterQueue {
    static let kind = "MonkeyWorkoutWater"
    private static let key = "water.pending"

    private static var defaults: UserDefaults? { HomeWidgetStore.group.flatMap { UserDefaults(suiteName: $0) } }

    private static var all: [Double] { defaults?.array(forKey: key) as? [Double] ?? [] }

    static func add(_ n: Int = 1, at date: Date = Date()) {
        defaults?.set(all + Array(repeating: date.timeIntervalSince1970, count: n), forKey: key)
    }

    /// Glasses tapped on `day` the app hasn't counted yet.
    static func pending(on day: Date, calendar cal: Calendar = .current) -> Int {
        all.filter { cal.isDate(Date(timeIntervalSince1970: $0), inSameDayAs: day) }.count
    }

    /// Hands the waiting glasses to the app. Only the taps read leave the queue (#716): one tapped on the widget
    /// meanwhile waits for the next take.
    static func take() -> [Date] {
        let read = all
        guard !read.isEmpty else { return [] }
        var left = all
        for t in read { if let i = left.firstIndex(of: t) { left.remove(at: i) } }
        if left.isEmpty { defaults?.removeObject(forKey: key) } else { defaults?.set(left, forKey: key) }
        return read.map { Date(timeIntervalSince1970: $0) }
    }

    /// Sign-out (#716): glasses tapped for the account signed out aren't counted for the next one.
    static func wipe() {
        defaults?.removeObject(forKey: key)
    }
}

/// "+1 glass" on the water widget, and in Shortcuts.
struct AddWaterIntent: AppIntent {
    static var title: LocalizedStringResource { "Add a glass of water" }
    static var description: IntentDescription { "Counts a glass of water in Fuel for today." }
    static var openAppWhenRun: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        WaterQueue.add()
        WidgetCenter.shared.reloadTimelines(ofKind: WaterQueue.kind)
        // The next reminder asked for the glass just had; the app plans the rest when it opens.
        let center = UNUserNotificationCenter.current()
        let next = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("water|") }
            .min { Self.fire($0) < Self.fire($1) }
        if let next { center.removePendingNotificationRequests(withIdentifiers: [next.identifier]) }
        return .result()
    }

    private static func fire(_ r: UNNotificationRequest) -> Date {
        (r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
    }
}
