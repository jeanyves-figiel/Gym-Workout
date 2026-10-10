import Foundation
import Observation
import WatchConnectivity

/// Watch side of the phone link (#56): keeps the last snapshot on disk (works with the phone away),
/// queues logged sets and workouts back to the phone, and mirrors / remote-controls the iPhone player.
@MainActor @Observable
final class WatchStore: NSObject {
    var snapshot: WatchSnapshot
    /// iPhone player state while a workout runs on the phone.
    var live: WLive?
    var reachable = false

    private static let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("snapshot.json")

    override init() {
        snapshot = (try? Data(contentsOf: Self.url)).flatMap { try? JSONDecoder.watch.decode(WatchSnapshot.self, from: $0) } ?? WatchSnapshot()
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    var hasPlan: Bool { !snapshot.sessions.isEmpty || !snapshot.extras.isEmpty }
    var next: WSession? { snapshot.nextSessionId.flatMap(snapshot.session) ?? snapshot.sessions.first { !$0.done } }

    func send(_ event: WatchEvent) {
        guard WCSession.isSupported(), let data = try? JSONEncoder.watch.encode(event) else { return }
        WCSession.default.transferUserInfo([WatchKeys.event: data])
        // Reflect locally until the next snapshot arrives.
        if case let .finished(f) = event { markDone(f) }
    }

    func send(_ command: WCommand) {
        guard WCSession.isSupported(), WCSession.default.isReachable else { return }
        WCSession.default.sendMessage([WatchKeys.command: command.rawValue], replyHandler: nil, errorHandler: nil)
    }

    private func markDone(_ f: WFinished) {
        if let i = snapshot.sessions.firstIndex(where: { $0.id == f.sessionId }) { snapshot.sessions[i].done = true }
        if snapshot.nextSessionId == f.sessionId { snapshot.nextSessionId = snapshot.sessions.first { !$0.done }?.id }
        snapshot.progress.recent.insert(
            WRecent(title: snapshot.session(f.sessionId)?.title ?? "Workout", date: f.start,
                    minutes: Int(f.end.timeIntervalSince(f.start)) / 60, sets: f.setsDone.values.reduce(0, +)), at: 0)
        snapshot.progress.thisWeek += 1
        save()
    }

    fileprivate func receive(context: [String: Any]) {
        guard let data = context[WatchKeys.snapshot] as? Data,
              let s = try? JSONDecoder.watch.decode(WatchSnapshot.self, from: data) else { return }
        snapshot = s
        save()
    }

    fileprivate func receive(message: [String: Any]) {
        if message[WatchKeys.liveEnded] != nil { live = nil }
        if let data = message[WatchKeys.live] as? Data, let l = try? JSONDecoder.watch.decode(WLive.self, from: data) { live = l }
    }

    private func save() {
        guard let data = try? JSONEncoder.watch.encode(snapshot) else { return }
        try? data.write(to: Self.url, options: .atomic)
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let reachable = session.isReachable
        Task { @MainActor in
            self.reachable = reachable
            self.receive(context: context)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.reachable = reachable
            if !reachable { self.live = nil }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(context: applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.receive(message: message) }
    }
}
