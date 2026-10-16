import Foundation
import LiftSensor
import Observation
import WorkoutEngine

/// Reps and bar speed the Apple Watch measured per set (#383). Kept on this iPhone only (Application Support,
/// encrypted at rest by data protection), newest 3000 sets; wiped on sign-out with the local state.
@MainActor @Observable
final class LiftSets {
    static let shared = LiftSets()

    private(set) var sets: [WLiftSet] = []

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("lift-sets.json")
    }

    private init() {
        #if DEBUG
        if Demo.enabled { sets = Self.demo; return }
        #endif
        if let data = try? Data(contentsOf: Self.url), let s = try? JSONDecoder.watch.decode([WLiftSet].self, from: data) { sets = s }
    }

    /// Adds a measured set; a set measured again (same session, exercise and set) replaces the old one.
    func add(_ set: WLiftSet) {
        sets.removeAll { $0.id == set.id || ($0.sessionId == set.sessionId && $0.exerciseId == set.exerciseId && $0.setIndex == set.setIndex
            && Calendar.current.isDate($0.date, inSameDayAs: set.date)) }
        sets.append(set)
        if sets.count > 3000 { sets.removeFirst(sets.count - 3000) }
        save()
    }

    func sets(exerciseId: String) -> [WLiftSet] { sets.filter { $0.exerciseId == exerciseId }.sorted { $0.date < $1.date } }

    /// Last day this exercise was measured, its sets in order.
    func lastDay(exerciseId: String) -> [WLiftSet] {
        let all = sets(exerciseId: exerciseId)
        guard let last = all.last else { return [] }
        return all.filter { Calendar.current.isDate($0.date, inSameDayAs: last.date) }.sorted { $0.setIndex < $1.setIndex }
    }

    /// Estimated 1RM from load and speed over the last 30 days (fastest rep per load), when the lift has a
    /// known minimum velocity and two loads were measured.
    func estimatedOneRepMax(exercise: Exercise) -> Double? {
        guard let profile = LiftProfile.for(name: exercise.name, exerciseId: exercise.id), let mvt = profile.minimumVelocity else { return nil }
        let since = Date().addingTimeInterval(-30 * 86400)
        var best: [Double: Double] = [:]
        for s in sets(exerciseId: exercise.id) where s.date >= since && !s.machine {
            if let v = s.best, s.kg > 0 { best[s.kg] = max(best[s.kg] ?? 0, v) }
        }
        return LoadVelocity.estimatedOneRepMax(best.map { LoadVelocity.Point(kg: $0.key, velocity: $0.value) }, minimumVelocity: mvt)
    }

    func wipe() {
        sets = []
        try? FileManager.default.removeItem(at: Self.url)
    }

    private func save() {
        guard let data = try? JSONEncoder.watch.encode(sets) else { return }
        try? data.write(to: Self.url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    #if DEBUG
    private static var demo: [WLiftSet] {
        let day = Date().addingTimeInterval(-86400)
        func set(_ i: Int, _ kg: Double, _ v: [Double]) -> WLiftSet {
            WLiftSet(sessionId: "demo", exerciseId: "bench-press", setIndex: i, date: day.addingTimeInterval(Double(i) * 180), kg: kg,
                     velocities: v, peaks: v.map { $0 * 1.6 }, ranges: v.map { _ in 0.41 }, concentric: v.map { 0.41 / $0 },
                     eccentric: v.map { _ in 1.5 }, machine: false)
        }
        return [
            set(0, 60, [0.92, 0.9, 0.88, 0.86, 0.85, 0.83, 0.82, 0.8]),
            set(1, 70, [0.78, 0.76, 0.74, 0.71, 0.69, 0.66, 0.64]),
            set(2, 80, [0.66, 0.64, 0.61, 0.58, 0.55, 0.53]),
            set(3, 80, [0.64, 0.61, 0.58, 0.55, 0.52]),
        ]
    }
    #endif
}
