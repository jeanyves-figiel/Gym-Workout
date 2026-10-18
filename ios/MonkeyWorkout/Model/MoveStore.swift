import Foundation
import WorkoutEngine

/// Daily Move (#454): steps and floors per day from Apple Health, the member's walking hour and the nudge log.
/// Stays on the device (Application Support, protected until first unlock); never sent to the server.
@MainActor @Observable
final class MoveStore {
    static let shared = MoveStore()

    struct Saved: Codable {
        /// XP counts from this day on (the day Daily Move first read Health), so updating doesn't jump levels.
        var since: Date?
        var days: [DayMove] = []
        var hour = DailyMove.defaultHour
        /// Day keys: last nudge, last "Rest day" tap, last day with a workout in this app.
        var nudged: String?
        var restDay: String?
        var busy: String?
    }

    private(set) var saved = Saved()
    /// Walking XP so far (cached: `DailyMove.totalXP` walks every day).
    private(set) var xp = 0

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("daily-move.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.url), let s = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = s
            xp = Self.xp(s)
        }
    }

    private var cal: Calendar { Progression.calendar() }

    var hasData: Bool { saved.days.contains { $0.steps > 0 } }

    var today: DayMove {
        let start = cal.startOfDay(for: Date())
        return saved.days.first { $0.day == start } ?? DayMove(day: start, steps: 0)
    }

    var usual: Int { DailyMove.usual(saved.days, before: Date(), calendar: cal) }
    var todayXP: Int { DailyMove.xp(today) }
    var activeDaysThisWeek: Int { DailyMove.activeDays(saved.days, weekOf: Date(), calendar: cal) }
    var hour: Int { saved.hour }

    /// Days and walking hour from a Health read.
    func update(days: [DayMove], hour: Int?) {
        var s = saved
        if s.since == nil { s.since = cal.startOfDay(for: Date()) }
        s.days = days.sorted { $0.day < $1.day }
        if let hour { s.hour = hour }
        save(s)
    }

    func key(_ d: Date) -> String { ReminderPlanner.dayKey(d, calendar: cal) }

    func markNudged(_ now: Date = Date()) {
        var s = saved
        s.nudged = key(now)
        save(s)
    }

    /// A workout done in this app today (also when it isn't saved to Health): no nudge.
    func markBusy(_ day: Date) {
        guard saved.busy != key(day) else { return }
        var s = saved
        s.busy = key(day)
        save(s)
    }

    /// "Rest day": no nudge today.
    func restToday(_ now: Date = Date()) {
        var s = saved
        s.restDay = key(now)
        save(s)
    }

    #if DEBUG
    /// Demo screens: two weeks of walking, today a bit short of the usual. Not saved.
    func demo(now: Date = Date()) {
        let today = cal.startOfDay(for: now)
        let steps = [7800, 9100, 6400, 8800, 10200, 7400, 8300, 9600, 5200, 8100, 8900, 7700, 9900, 8400]
        var days = steps.enumerated().compactMap { i, n in
            cal.date(byAdding: .day, value: -(i + 1), to: today).map { DayMove(day: $0, steps: n, floors: 6 + i % 5) }
        }
        days.append(DayMove(day: today, steps: 6840, floors: 9))
        let since = cal.date(byAdding: .day, value: -6, to: today)
        saved = Saved(since: since, days: days.sorted { $0.day < $1.day }, hour: 18)
        xp = Self.xp(saved)
    }
    #endif

    func signOut() {
        save(Saved())
        try? FileManager.default.removeItem(at: Self.url)
    }

    private func save(_ s: Saved) {
        saved = s
        xp = Self.xp(s)
        guard let data = try? JSONEncoder().encode(s) else { return }
        let url = Self.url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Only days since Daily Move started earn XP; earlier days only set the usual.
    private static func xp(_ s: Saved) -> Int {
        guard let since = s.since else { return 0 }
        return DailyMove.totalXP(s.days, since: since, calendar: Progression.calendar())
    }
}
