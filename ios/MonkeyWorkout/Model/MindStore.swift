import Foundation
import WorkoutEngine

/// Mind (#834): mood check-ins, finished breathing / relax sessions and each day's Mind score.
/// Stays on the device (Application Support, protected until first unlock); never sent to the server.
/// Check-ins and sessions also go to Apple Health (State of Mind, mindful minutes) when Health is connected.
@MainActor @Observable
final class MindStore {
    static let shared = MindStore()

    struct Saved: Codable {
        var checkIns: [MindCheckIn] = []
        var sessions: [MindSession] = []
        /// Day key (`ReminderPlanner.dayKey`) → that day's last Mind score, for the 7-day bars.
        var scores: [String: Int] = [:]
    }

    private(set) var saved = Saved()

    /// Kept for 90 days: enough for the 28-day patterns and the week bars.
    static let keepDays = 90

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("mind.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.url), let s = try? JSONDecoder().decode(Saved.self, from: data) { saved = s }
    }

    private var cal: Calendar { Progression.calendar() }

    func key(_ d: Date) -> String { ReminderPlanner.dayKey(d, calendar: cal) }

    /// Today's last check-in.
    func checkIn(on day: Date = Date()) -> MindCheckIn? {
        saved.checkIns.last { cal.isDate($0.date, inSameDayAs: day) }
    }

    /// Calm minutes finished on `day`.
    func calmMinutes(on day: Date = Date()) -> Int {
        saved.sessions.filter { cal.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.seconds } / 60
    }

    /// Calm minutes this week (Monday on).
    var weekMinutes: Int {
        let start = Progression.weekStart(Date(), cal)
        return saved.sessions.filter { $0.date >= start }.reduce(0) { $0 + $1.seconds } / 60
    }

    struct Day: Hashable {
        let day: Date
        /// nil = no score that day.
        let score: Int?
    }

    /// Scores of the last 7 days, oldest first.
    func week(endingOn day: Date = Date()) -> [Day] {
        let today = cal.startOfDay(for: day)
        return (0..<7).reversed().compactMap { i in
            cal.date(byAdding: .day, value: -i, to: today).map { d in Day(day: d, score: saved.scores[key(d)]) }
        }
    }

    func addCheckIn(_ c: MindCheckIn) {
        var s = saved
        s.checkIns.append(c)
        save(s)
    }

    /// Undo of a check-in Coach logged (#999).
    func removeCheckIn(_ c: MindCheckIn) {
        var s = saved
        guard let i = s.checkIns.lastIndex(of: c) else { return }
        s.checkIns.remove(at: i)
        save(s)
    }

    func addSession(_ m: MindSession) {
        var s = saved
        s.sessions.append(m)
        save(s)
    }

    /// Undo of a session stopped early.
    func removeSession(_ m: MindSession) {
        guard let i = saved.sessions.lastIndex(of: m) else { return }
        var s = saved
        s.sessions.remove(at: i)
        save(s)
    }

    /// Today's score, written only when it changed.
    func record(score: Int, on day: Date = Date()) {
        guard saved.scores[key(day)] != score else { return }
        var s = saved
        s.scores[key(day)] = score
        save(s)
    }

    #if DEBUG
    /// Demo screens: two weeks of check-ins and scores, a few sessions this week, no check-in today. Not saved.
    func demo(now: Date = Date(), checkedIn: Bool = false) {
        let today = cal.startOfDay(for: now)
        let moods = [4, 3, 4, 2, 4, 5, 3, 4, 4, 2, 3, 5, 4]
        let feelings: [[MindFeeling]] = [[.training], [.work], [.family, .training], [.work, .sleep], [], [.friends], [.work]]
        var s = Saved()
        for (i, m) in moods.enumerated() {
            guard let d = cal.date(byAdding: .day, value: -(i + 1), to: today) else { continue }
            s.checkIns.append(MindCheckIn(date: d.addingTimeInterval(7.5 * 3600), mood: m, feelings: feelings[i % feelings.count]))
        }
        s.checkIns.sort { $0.date < $1.date }
        if checkedIn { s.checkIns.append(MindCheckIn(date: now, mood: 4, feelings: [.work, .training])) }
        let scores = [66, 74, 41, 60, 80, 69, 58, 72, 77, 45, 62, 81, 70]
        for (i, v) in scores.enumerated() {
            if let d = cal.date(byAdding: .day, value: -(i + 1), to: today) { s.scores[key(d)] = v }
        }
        for (i, b) in [Breath.box, .sleep478, .sigh, .bodyScan, .box].enumerated() {
            if let d = cal.date(byAdding: .day, value: -i, to: today) {
                s.sessions.append(MindSession(date: d.addingTimeInterval(8 * 3600), breath: b, seconds: b.defaultMinutes * 60 + 30))
            }
        }
        saved = s
    }
    #endif

    func signOut() {
        saved = Saved()
        try? FileManager.default.removeItem(at: Self.url)
    }

    private func save(_ s: Saved) {
        var s = s
        let cutoff = Date().addingTimeInterval(-Double(Self.keepDays) * 86_400)
        s.checkIns.removeAll { $0.date < cutoff }
        s.sessions.removeAll { $0.date < cutoff }
        let keep = Set((0..<Self.keepDays).compactMap { cal.date(byAdding: .day, value: -$0, to: Date()).map(key) })
        s.scores = s.scores.filter { keep.contains($0.key) }
        saved = s
        guard let data = try? JSONEncoder().encode(s) else { return }
        let url = Self.url
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
