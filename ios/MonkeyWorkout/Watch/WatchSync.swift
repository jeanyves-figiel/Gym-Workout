import Foundation
import WatchConnectivity
import WorkoutEngine

extension Notification.Name {
    /// A `WCommand` from the Watch for the iPhone workout player (object: WCommand).
    static let watchCommand = Notification.Name("watchCommand")
}

/// iPhone side of the Watch companion (#56): sends plan/progress snapshots and the live player state,
/// applies sets and workouts logged on the Watch, and forwards Watch remote-control commands to the player.
@MainActor
final class WatchSync: NSObject {
    static let shared = WatchSync()

    private weak var model: AppModel?
    private weak var health: HealthManager?
    private var lastSnapshot: WatchSnapshot?
    private var handled: Set<UUID> = []

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func start(model: AppModel, health: HealthManager) {
        self.model = model
        self.health = health
        guard let session, session.delegate == nil else { return push() }
        session.delegate = self
        session.activate()
    }

    /// Sends the current snapshot when it changed and a Watch app is installed.
    func push() {
        guard let model, let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        var snap = Self.snapshot(model, readiness: health.flatMap { Readiness.assess($0.snapshot)?.0.title })
        snap.generatedAt = lastSnapshot?.generatedAt ?? snap.generatedAt
        guard snap != lastSnapshot else { return }
        snap.generatedAt = Date()
        lastSnapshot = snap
        guard let data = try? JSONEncoder.watch.encode(snap) else { return }
        try? session.updateApplicationContext([WatchKeys.snapshot: data])
    }

    /// Cheap fingerprint of what the snapshot depends on.
    static func changeKey(_ model: AppModel) -> String {
        let plan = model.plan.map { "\($0.seed)-\($0.week)-\($0.sessions.count)" } ?? "-"
        return "\(plan)|\(model.state.done.count)|\(model.state.history.count)|\(model.customWorkouts.count)|\(model.state.logs.count)"
    }

    /// Mirrors the iPhone player on the Watch (best effort, only while the Watch app is reachable).
    func sendLive(_ live: WLive?) {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        if let live, let data = try? JSONEncoder.watch.encode(live) {
            session.sendMessage([WatchKeys.live: data], replyHandler: nil, errorHandler: nil)
        } else {
            session.sendMessage([WatchKeys.liveEnded: true], replyHandler: nil, errorHandler: nil)
        }
    }

    // MARK: Watch → phone

    private func apply(_ event: WatchEvent) {
        guard let model else { return }
        switch event {
        case let .setLogged(sessionId, exerciseId, setIndex, kg, reps, rir):
            model.logSet(exerciseId: exerciseId, sessionId: sessionId, setIndex: setIndex, kg: kg, reps: reps, rir: rir)
        case let .itemDone(uid):
            model.setTicked(uid)
        case let .finished(f):
            guard !handled.contains(f.id), let session = model.session(f.sessionId) else { return }
            handled.insert(f.id)
            let r = model.recordWorkout(
                session: session, setsDone: f.setsDone, startedAt: f.start, endedAt: f.end,
                bodyMassKg: health?.snapshot.weightKg ?? model.body.weightKg)
            model.clearActiveWorkout(f.sessionId)
            if f.savedToHealth {
                model.attachHeartRate(r.id, avg: f.avgHeartRate, max: f.maxHeartRate)
            } else if let health {
                Task {
                    let hr = await health.save(r)
                    model.attachHeartRate(r.id, avg: hr.avg ?? f.avgHeartRate, max: hr.max ?? f.maxHeartRate)
                }
            }
        }
        push()
    }

    // MARK: Snapshot

    static func snapshot(_ model: AppModel, readiness: String?) -> WatchSnapshot {
        var s = WatchSnapshot()
        if let plan = model.plan {
            s.week = plan.week
            s.weeks = Generator.mesocycleWeeks
            s.deload = plan.deload
            s.sessions = plan.sessions.map { session($0, label: $0.dayLabel, model: model) }
        }
        s.extras = WorkoutTemplate.all.map { session($0.session, label: "Example", model: model) }
            + model.customWorkouts.map { session($0.session, label: "My workout", model: model) }
        s.nextSessionId = model.nextSession?.id
        s.readiness = readiness
        let target = model.profile?.sessionsPerWeek ?? 3
        let stats = Progression.stats(records: model.state.history, weights: model.weightEntries, targetPerWeek: target)
        s.progress = WProgress(
            streakWeeks: stats.currentStreakWeeks, bestStreakWeeks: stats.bestStreakWeeks, thisWeek: stats.thisWeek, target: target,
            records: stats.personalRecords.prefix(5).map { WRecord(name: Exercise.get($0.exerciseId).name, kg: $0.kg) },
            recent: model.history.prefix(5).map { WRecent(title: $0.title, date: $0.startedAt, minutes: $0.durationSec / 60, sets: $0.totalSets) })
        return s
    }

    private static func session(_ session: Session, label: String, model: AppModel) -> WSession {
        WSession(
            id: session.id, title: session.displayTitle, dayLabel: label, estMin: session.estMin,
            done: model.state.done[session.id] ?? false,
            tint: (session.blocks.first { $0.kind == .strength } ?? session.blocks.first)?.kind.category.tintHex ?? 0xCCFF3D,
            blocks: session.blocks.map { b in
                WBlock(title: b.title, tint: b.kind.category.tintHex, tint2: b.kind.category.tintHex2,
                       items: b.items.map { item($0, block: b, sessionId: session.id, model: model) })
            })
    }

    private static func item(_ it: PlannedExercise, block: Block, sessionId: String, model: AppModel) -> WItem {
        let e = Exercise.get(it.exerciseId)
        let loggable = block.kind == .strength && !e.equipment.isEmpty && e.unit != .sec
        let timed = TimedSpec(it.prescription, unit: e.unit)
        let suggestion = loggable ? model.loadSuggestion(for: it, sessionId: sessionId) : nil
        let kg = suggestion?.kg ?? (loggable ? model.lastWeight(it.exerciseId) : nil)
        return WItem(
            uid: it.uid, exerciseId: it.exerciseId, name: e.name, sets: max(1, it.prescription.sets), reps: it.prescription.reps,
            restSec: it.prescription.restSec, intensity: it.prescription.intensity, cues: Array(e.cues.prefix(3)),
            loggable: loggable, timedSec: timed?.workSec, easySec: timed?.easySec,
            kg: kg, targetReps: suggestion?.reps ?? it.prescription.repRange?.low,
            kgStep: LoadAdvisor.steps(for: e, kg: kg ?? 20).granularity,
            pairedName: it.pairedWith.flatMap(Exercise.find)?.name)
    }
}

extension WatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.push() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switched to another Watch.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.lastSnapshot = nil
            self.push()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WatchKeys.event] as? Data, let event = try? JSONDecoder.watch.decode(WatchEvent.self, from: data) else { return }
        Task { @MainActor in self.apply(event) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let raw = message[WatchKeys.command] as? String, let command = WCommand(rawValue: raw) else { return }
        Task { @MainActor in NotificationCenter.default.post(name: .watchCommand, object: command) }
    }
}
