import Foundation
import WorkoutEngine

/// A gym-type workout another watch app wrote to Apple Health (#549): Garmin Connect, Polar Flow, Coros, Suunto…
/// Matched to the planned session of its day, so a workout recorded on any watch can mark it done.
struct GymEntry: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let start: Date
    let end: Date
    /// App that wrote it ("Connect", "Polar Flow"…).
    let source: String
    /// Device it was recorded on ("Fenix 8"), when Health knows it.
    var device: String?
    var avgHR: Double?
    var maxHR: Double?
    var kcal: Double?

    var minutes: Int { max(1, Int(end.timeIntervalSince(start) / 60)) }
    /// "Garmin Fenix 8", else the app's name.
    var label: String { device ?? source }
}

extension AppModel {
    /// The other-watch workout found in Health for a session's day (#549): not done yet, and not already a workout here
    /// (a record starting within 30 minutes of it). Latest first.
    func healthMatch(for s: Session, in entries: [GymEntry]?) -> GymEntry? {
        guard let entries, !doneIds.contains(s.id) else { return nil }
        let cal = planCalendar
        let sessionDay = day(of: s)
        return entries.filter { e in
            cal.isDate(e.start, inSameDayAs: sessionDay) && e.start <= Date()
                && !state.history.contains { abs($0.startedAt.timeIntervalSince(e.start)) < 30 * 60 }
        }
        .max { $0.start < $1.start }
    }

    /// Mark done from a watch workout (#549): every planned set, the watch's times, heart rate and calories.
    func markDone(_ s: Session, from e: GymEntry) {
        var sets: [String: Int] = [:]
        for b in s.blocks { for it in b.items { sets[it.uid] = it.prescription.sets } }
        logFromHealth(s, e, setsDone: sets, weights: [:], start: e.start, minutes: e.minutes)
    }

    /// Logs a session with what was done, enriched with the watch workout's heart rate and calories.
    func logFromHealth(_ s: Session, _ e: GymEntry, setsDone: [String: Int], weights: [String: Double], start: Date, minutes: Int) {
        let r = logMissed(s, setsDone: setsDone, weights: weights, start: start, minutes: minutes)
        guard let i = state.history.firstIndex(where: { $0.id == r.id }) else { return }
        state.history[i].kcal = e.kcal ?? state.history[i].kcal
        state.history[i].avgHeartRate = e.avgHR
        state.history[i].maxHeartRate = e.maxHR
        persist()
        Task { await sync() }
    }
}
