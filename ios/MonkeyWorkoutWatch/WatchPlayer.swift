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
        /// When the set was logged (#820): sent with it and with its effort, so the phone dates it right.
        var at: Date?
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
    /// Wrist Coach advice applied for this exercise + set (#608 C), so it doesn't ask again.
    var coachApplied: String?
    /// Superset member to go to once the rest after the round ends (#716).
    var pendingJump: Int?
    /// "Next in" countdown after an exercise's last set (#990): when it moves on by itself.
    var autoNextAt: Date?

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
        // Resting after a superset round: the member it goes back to.
        if case .rest = phase, let j = pendingJump, steps.indices.contains(j) {
            let s = steps[j]
            return "\(s.name) · set \((setsDone[s.uid] ?? 0) + 1) of \(s.sets)"
        }
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
            r[i].at = Date()
            for j in r.indices where j > i && !r[j].logged { r[j].kg = r[i].kg }
            rows[step.uid] = r
            events.append(.setLogged(sessionId: session.id, exerciseId: step.exerciseId, setIndex: i, kg: r[i].kg, reps: r[i].reps, rir: nil,
                                   date: r[i].at))
            effortSet = i
        }
        setsDone[step.uid] = i + 1
        timedEnd = nil
        timedRemaining = nil
        if i + 1 >= step.sets { events.append(.itemDone(uid: step.uid)) }
        WKInterfaceDevice.current().play(.success)
        // Superset / circuit (#716), as on the iPhone: on to the next member without rest, rest after the round.
        if let jump = groupNext(after: step), let target = steps.firstIndex(where: { $0.uid == jump.uid }) {
            guard jump.restSec > 0 else {
                if target != index { move(to: target) }
                return events
            }
            pendingJump = target == index ? nil : target
            phase = .rest(end: Date().addingTimeInterval(TimeInterval(jump.restSec)), total: jump.restSec, effortSet: effortSet)
            return events
        }
        let rest = i + 1 < step.sets ? (step.easySec ?? step.restSec) : 0
        if rest > 0 || effortSet != nil {
            phase = .rest(end: rest > 0 ? Date().addingTimeInterval(TimeInterval(rest)) : nil, total: rest, effortSet: effortSet)
        } else if i + 1 >= step.sets {
            // Last set: as Settings → Workout flow on the iPhone (#990): straight on, a countdown, or wait for Next.
            // nil (older phone app) = straight on.
            let sec = WatchStore.current?.snapshot.autoNextSec ?? 0
            if sec == 0 {
                events += advance()
            } else {
                let end = sec > 0 ? Date().addingTimeInterval(TimeInterval(sec)) : nil
                phase = .rest(end: end, total: max(sec, 0), effortSet: nil)
                autoNextAt = end
            }
        }
        return events
    }

    /// Effort for the set just done; closes the overlay when there is no rest running.
    func effort(_ rir: Int) -> [WatchEvent] {
        guard case let .rest(end, total, effortSet?) = phase, let step, var r = rows[step.uid], r.indices.contains(effortSet) else { return [] }
        r[effortSet].rir = rir
        rows[step.uid] = r
        let logged = WatchEvent.setLogged(sessionId: session.id, exerciseId: step.exerciseId, setIndex: effortSet, kg: r[effortSet].kg, reps: r[effortSet].reps, rir: rir,
                                             date: r[effortSet].at)
        if end == nil { return [logged] + skipRest() }
        phase = .rest(end: end, total: total, effortSet: nil)
        return [logged]
    }

    /// Closes the rest/effort overlay; after an exercise's last set this moves to the next exercise.
    @discardableResult
    func skipRest() -> [WatchEvent] {
        phase = .work
        autoNextAt = nil
        if let j = pendingJump {
            move(to: j)
            return []
        }
        if let step, done >= step.sets { return advance() }
        return []
    }

    // MARK: Supersets (#716)

    /// Members of the superset `it` belongs to, in order within its block; just the item when it isn't grouped.
    private func groupMembers(of it: WItem) -> [WItem] {
        guard let g = it.group, let b = session.blocks.first(where: { $0.items.contains { $0.uid == it.uid } }) else { return [it] }
        return b.items.filter { $0.group == g }
    }

    /// Where to go after a set of a grouped `it`, as Block.next(after:setsDone:) on the iPhone: the next member still
    /// owing a set this round (no rest), else the first member with sets left (after the rest). nil when `it` isn't
    /// grouped or the whole group is done.
    private func groupNext(after it: WItem) -> (uid: String, restSec: Int)? {
        let members = groupMembers(of: it)
        guard members.count > 1, let i = members.firstIndex(where: { $0.uid == it.uid }) else { return nil }
        let left: (WItem) -> Bool = { (self.setsDone[$0.uid] ?? 0) < $0.sets }
        let round = setsDone[it.uid] ?? 0
        if let n = members[(i + 1)...].first(where: { left($0) && (self.setsDone[$0.uid] ?? 0) < round }) {
            return (n.uid, 0)
        }
        guard let first = members.first(where: left) else { return nil }
        return (first.uid, it.restSec)
    }

    private func move(to target: Int) {
        pendingJump = nil
        autoNextAt = nil
        index = target
        phase = .work
        timedEnd = nil
        timedRemaining = nil
        autoStartGuided()
    }

    func addRest() {
        guard case let .rest(end?, total, effortSet) = phase else { return }
        let base = max(end, Date())
        phase = .rest(end: base.addingTimeInterval(15), total: total + 15, effortSet: effortSet)
    }

    // MARK: Guided cool-down (#619 C)

    /// The step is in a block the Watch guides on its own.
    func isGuided(_ it: WItem) -> Bool { session.blocks.first { $0.items.contains { $0.uid == it.uid } }?.guided == true }
    /// A guided per-side hold: one timer runs both sides.
    func bothSides(_ it: WItem) -> Bool { isGuided(it) && it.reps.contains("side") }
    /// Seconds the timer runs for a step: both sides of a guided per-side hold.
    func workSec(_ it: WItem) -> Int? { it.timedSec.map { bothSides(it) ? $0 * 2 : $0 } }
    /// When a guided per-side hold that ends at `end` switches sides.
    func sideSwitch(endingAt end: Date) -> Date? {
        guard let step, bothSides(step), let w = step.timedSec else { return nil }
        return end.addingTimeInterval(-TimeInterval(w))
    }
    /// "2 of 4" inside a guided block.
    var guidedPosition: (index: Int, count: Int)? {
        guard let step, isGuided(step),
              let b = session.blocks.first(where: { $0.items.contains { $0.uid == step.uid } }),
              let i = b.items.firstIndex(where: { $0.uid == step.uid }) else { return nil }
        return (i + 1, b.items.count)
    }

    /// A guided timed step starts its timer on arrival.
    private func autoStartGuided() {
        guard phase == .work, let step, isGuided(step), let w = workSec(step), done < step.sets else { return }
        timedEnd = Date().addingTimeInterval(TimeInterval(w))
        timedRemaining = nil
        WKInterfaceDevice.current().play(.start)
    }

    /// Starts, pauses or resumes timed work.
    func toggleTimer() {
        guard let step, let work = workSec(step) else { return }
        if let end = timedEnd {
            timedRemaining = max(0, end.timeIntervalSinceNow)
            timedEnd = nil
        } else {
            timedEnd = Date().addingTimeInterval(timedRemaining ?? TimeInterval(work))
        }
    }

    // MARK: Action button (#349)

    /// One Action button press: does the step `mode` calls for and returns a short label saying what happened.
    func actionPress(_ mode: WatchActionMode) -> (label: String, events: [WatchEvent])? {
        guard phase != .finished, let step else { return nil }
        if case .rest = phase {
            let before = index
            let events = skipRest()
            WKInterfaceDevice.current().play(.click)
            return (phase == .finished ? "Workout done" : index != before ? "Next: \(self.step?.name ?? "")" : "Rest skipped", events)
        }
        let timed = step.timedSec != nil && done < step.sets
        switch mode {
        case .set:
            break
        case .smart:
            if timed { return toggleTimerPress() }
        case .rest:
            if timed { return toggleTimerPress() }
            if done < step.sets {
                let rest = (step.easySec ?? step.restSec) > 0 ? (step.easySec ?? step.restSec) : 60
                phase = .rest(end: Date().addingTimeInterval(TimeInterval(rest)), total: rest, effortSet: nil)
                WKInterfaceDevice.current().play(.start)
                return ("Rest \(Self.clock(TimeInterval(rest)))", [])
            }
        }
        if done >= step.sets {
            let events = advance()
            WKInterfaceDevice.current().play(.click)
            return (phase == .finished ? "Workout done" : "Next: \(self.step?.name ?? "")", events)
        }
        let set = done + 1
        let events = completeSet()
        return (phase == .finished ? "Workout done" : "✓ Set \(set) logged", events)
    }

    private func toggleTimerPress() -> (label: String, events: [WatchEvent]) {
        toggleTimer()
        WKInterfaceDevice.current().play(timedEnd != nil ? .start : .stop)
        return (timedEnd != nil ? "Timer started" : "Timer paused", [])
    }

    func advance() -> [WatchEvent] {
        var events: [WatchEvent] = []
        if let step, done >= step.sets { events.append(.itemDone(uid: step.uid)) }
        pendingJump = nil
        autoNextAt = nil
        timedEnd = nil
        timedRemaining = nil
        // A superset member finished earlier in the round is passed over (#716).
        if let next = steps.indices.first(where: { $0 > index && (setsDone[steps[$0].uid] ?? 0) < steps[$0].sets }) {
            index = next
            phase = .work
            autoStartGuided()
        } else {
            phase = .finished
            endedAt = Date()
        }
        return events
    }

    func back() {
        guard index > 0 else { return }
        pendingJump = nil
        autoNextAt = nil
        index -= 1
        phase = .work
        timedEnd = nil
        timedRemaining = nil
    }

    var mainLabel: String {
        guard let step else { return "FINISH" }
        if done >= step.sets { return index == steps.count - 1 ? "FINISH" : "NEXT" }
        if let work = workSec(step) {
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
