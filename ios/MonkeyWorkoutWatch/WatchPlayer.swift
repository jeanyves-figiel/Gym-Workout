import Foundation
import Observation
import WatchKit

/// Workout run on the Watch: steps, sets, kg × reps per set, effort, rest and timed work.
@MainActor @Observable
final class WatchPlayer {
    struct Row: Equatable {
        var kg: Double
        var reps: Int
        var rir: Int?
        var logged = false
    }

    enum Phase: Equatable {
        case work
        /// After a set: rest countdown (nil end = no rest) and whether effort is still to give.
        case rest(end: Date?, total: Int, effortSet: Int?)
        case finished
    }

    let session: WSession
    let steps: [WItem]
    let started = Date()
    var index = 0
    var setsDone: [String: Int] = [:]
    var rows: [String: [Row]] = [:]
    var phase: Phase = .work
    /// Timed work: end of the running countdown, or remaining seconds while paused.
    var timedEnd: Date?
    var timedRemaining: TimeInterval?
    var endedAt: Date?

    init(session: WSession) {
        self.session = session
        steps = session.items
        for it in steps where it.loggable {
            rows[it.uid] = (0..<it.sets).map { _ in Row(kg: it.kg ?? 0, reps: it.targetReps ?? 8) }
        }
    }

    var step: WItem? { steps.indices.contains(index) ? steps[index] : nil }
    var nextStep: WItem? { steps.indices.contains(index + 1) ? steps[index + 1] : nil }
    var done: Int { step.map { setsDone[$0.uid] ?? 0 } ?? 0 }
    var totalSets: Int { setsDone.values.reduce(0, +) }

    /// Row of the coming set (or the last one when all are done).
    var currentRow: Row? {
        guard let step, let r = rows[step.uid], !r.isEmpty else { return nil }
        return r[min(done, r.count - 1)]
    }

    var upNext: String {
        guard let step else { return "Finish" }
        // Resting between sets: the coming set; otherwise the next exercise.
        if case .rest = phase, done < step.sets { return "\(step.name) · set \(done + 1) of \(step.sets)" }
        return nextStep.map { "\($0.name) · \($0.sets > 1 ? "\($0.sets)×" : "")\($0.reps)" } ?? "Finish"
    }

    // MARK: Editing the coming set

    func adjustKg(_ sign: Double) {
        guard let step, var r = rows[step.uid], !r.isEmpty else { return }
        let i = min(done, r.count - 1)
        r[i].kg = max(0, ((r[i].kg + sign * step.kgStep) / step.kgStep).rounded() * step.kgStep)
        rows[step.uid] = r
    }

    func setReps(_ reps: Int) {
        guard let step, var r = rows[step.uid], !r.isEmpty else { return }
        r[min(done, r.count - 1)].reps = min(100, max(0, reps))
        rows[step.uid] = r
    }

    // MARK: Flow

    /// Completes the current set; returns events to send to the phone.
    func completeSet() -> [WatchEvent] {
        guard let step, done < step.sets else { return advance() }
        var events: [WatchEvent] = []
        let i = done
        var effortSet: Int?
        if step.loggable, var r = rows[step.uid], r.indices.contains(i) {
            r[i].logged = true
            for j in r.indices where j > i && !r[j].logged { r[j].kg = r[i].kg }
            rows[step.uid] = r
            events.append(.setLogged(sessionId: session.id, exerciseId: step.exerciseId, setIndex: i, kg: r[i].kg, reps: r[i].reps, rir: nil))
            effortSet = i
        }
        setsDone[step.uid] = i + 1
        timedEnd = nil
        timedRemaining = nil
        if i + 1 >= step.sets { events.append(.itemDone(uid: step.uid)) }
        let rest = i + 1 < step.sets ? (step.easySec ?? step.restSec) : 0
        WKInterfaceDevice.current().play(.success)
        if rest > 0 || effortSet != nil {
            phase = .rest(end: rest > 0 ? Date().addingTimeInterval(TimeInterval(rest)) : nil, total: rest, effortSet: effortSet)
        } else if i + 1 >= step.sets {
            // Last set: straight on to the next exercise.
            events += advance()
        }
        return events
    }

    /// Effort for the set just done; closes the overlay when there is no rest running.
    func effort(_ rir: Int) -> [WatchEvent] {
        guard case let .rest(end, total, effortSet?) = phase, let step, var r = rows[step.uid], r.indices.contains(effortSet) else { return [] }
        r[effortSet].rir = rir
        rows[step.uid] = r
        let logged = WatchEvent.setLogged(sessionId: session.id, exerciseId: step.exerciseId, setIndex: effortSet, kg: r[effortSet].kg, reps: r[effortSet].reps, rir: rir)
        if end == nil { return [logged] + skipRest() }
        phase = .rest(end: end, total: total, effortSet: nil)
        return [logged]
    }

    /// Closes the rest/effort overlay; after an exercise's last set this moves to the next exercise.
    @discardableResult
    func skipRest() -> [WatchEvent] {
        phase = .work
        if let step, done >= step.sets { return advance() }
        return []
    }

    func addRest() {
        guard case let .rest(end?, total, effortSet) = phase else { return }
        let base = max(end, Date())
        phase = .rest(end: base.addingTimeInterval(15), total: total + 15, effortSet: effortSet)
    }

    /// Starts, pauses or resumes timed work.
    func toggleTimer() {
        guard let step, let work = step.timedSec else { return }
        if let end = timedEnd {
            timedRemaining = max(0, end.timeIntervalSinceNow)
            timedEnd = nil
        } else {
            timedEnd = Date().addingTimeInterval(timedRemaining ?? TimeInterval(work))
        }
    }

    func advance() -> [WatchEvent] {
        var events: [WatchEvent] = []
        if let step, done >= step.sets { events.append(.itemDone(uid: step.uid)) }
        timedEnd = nil
        timedRemaining = nil
        if index >= steps.count - 1 {
            phase = .finished
            endedAt = Date()
        } else {
            index += 1
            phase = .work
        }
        return events
    }

    func back() {
        guard index > 0 else { return }
        index -= 1
        phase = .work
        timedEnd = nil
        timedRemaining = nil
    }

    var mainLabel: String {
        guard let step else { return "FINISH" }
        if done >= step.sets { return index == steps.count - 1 ? "FINISH" : "NEXT" }
        if let work = step.timedSec {
            if timedEnd != nil { return "PAUSE" }
            return timedRemaining == nil ? "START \(Self.clock(TimeInterval(work)))" : "RESUME"
        }
        return "SET \(done + 1) DONE"
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func kg(_ v: Double) -> String {
        var t = String(format: "%.2f", v)
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t
    }
}
