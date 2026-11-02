import Foundation
import WorkoutEngine

/// Drinks (#1039): +1 taps, Coach logs and good times weeks. Stays on the device (Application Support, protected until
/// first unlock), never sent to the server, never in Social or shares. Coach sees a one-line total only with the
/// member's yes to the week review (health data).
@MainActor @Observable
final class DrinkStore {
    static let shared = DrinkStore()

    struct Saved: Codable {
        var entries: [DrinkEntry] = []
        var periods: [GoodTimesPeriod] = []
        /// The weekly guide line was put away.
        var guideSeen = false
    }

    private(set) var saved = Saved()

    /// Kept for 60 days: enough for the 4-week support check.
    static let keepDays = 60

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("drinks.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.url), let s = try? JSONDecoder().decode(Saved.self, from: data) { saved = s }
    }

    @discardableResult
    func add(_ kind: DrinkKind, count: Int = 1, at date: Date = Date()) -> DrinkEntry {
        let e = DrinkEntry(date: date, kind: kind, count: count)
        var s = saved
        s.entries.append(e)
        save(s)
        return e
    }

    func remove(_ id: UUID) {
        var s = saved
        s.entries.removeAll { $0.id == id }
        save(s)
    }

    func savePeriod(_ p: GoodTimesPeriod) {
        var s = saved
        s.periods.removeAll { $0.id == p.id }
        s.periods.append(p)
        s.periods.sort { $0.start < $1.start }
        save(s)
    }

    func deletePeriod(_ id: UUID) {
        var s = saved
        s.periods.removeAll { $0.id == id }
        save(s)
    }

    func hideGuide() {
        var s = saved
        s.guideSeen = true
        save(s)
    }

    #if DEBUG
    /// Demo screens: a good times week from today, three drinks last night. Not saved.
    func demo(now: Date = Date()) {
        let cal = Progression.calendar()
        let today = PlanCalendar.key(now, cal)
        let end = cal.date(byAdding: .day, value: 5, to: now).map { PlanCalendar.key($0, cal) } ?? today
        let night = cal.startOfDay(for: now).addingTimeInterval(-3 * 3600)
        saved = Saved(entries: [DrinkEntry(date: night, kind: .beer, count: 3), DrinkEntry(date: night.addingTimeInterval(3600), kind: .cocktail)],
                      periods: [GoodTimesPeriod(start: today, end: end, note: "Holiday")])
    }
    #endif

    func signOut() {
        saved = Saved()
        try? FileManager.default.removeItem(at: Self.url)
    }

    private func save(_ s: Saved) {
        var s = s
        let cutoff = Date().addingTimeInterval(-Double(Self.keepDays) * 86_400)
        s.entries.removeAll { $0.date < cutoff }
        let today = PlanCalendar.key(Date(), Progression.calendar())
        s.periods.removeAll { $0.end < PlanCalendar.key(cutoff, Progression.calendar()) && $0.end < today }
        saved = s
        guard let data = try? JSONEncoder().encode(s) else { return }
        let url = Self.url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
