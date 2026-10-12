import Foundation
import Observation
import WatchConnectivity
import WidgetKit

/// Watch side of the phone link (#56): keeps the last snapshot on disk (works with the phone away),
/// queues logged sets and workouts back to the phone, and mirrors / remote-controls the iPhone player.
@MainActor @Observable
final class WatchStore: NSObject {
    var snapshot: WatchSnapshot
    /// iPhone player state while a workout runs on the phone.
    var live: WLive?
    var reachable = false
    /// Game mode (#219): what the last workout finished on this Watch earned, for the Done screen.
    var reward: WReward?
    /// Home style picked on this Watch (#219) and when; the phone's pick in the snapshot wins when newer.
    private var localStyle = UserDefaults.standard.string(forKey: "homeStyle").flatMap(WatchHomeStyle.init)
    private var localStyleAt = UserDefaults.standard.object(forKey: "homeStyleAt") as? Date

    private static let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("snapshot.json")

    override init() {
        snapshot = (try? Data(contentsOf: Self.url)).flatMap { try? JSONDecoder.watch.decode(WatchSnapshot.self, from: $0) } ?? WatchSnapshot()
        super.init()
        #if DEBUG
        if Demo.on {
            snapshot = Demo.snapshot
            if Demo.screen == "summary" { reward = Demo.reward }
            if let s = Demo.homeStyle { localStyle = s; localStyleAt = .distantFuture }
            return
        }
        #endif
        // Complications (#190) read the App Group copy; seed it from a snapshot synced before they existed.
        if hasPlan, SharedSnapshot.load() == nil { save() }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    var hasPlan: Bool { !snapshot.sessions.isEmpty || !snapshot.extras.isEmpty }
    var next: WSession? { snapshot.nextSessionId.flatMap(snapshot.session) ?? snapshot.sessions.first { !$0.done } }

    /// Screens follow the home style (#219): Crown deck → full colour, Charge & go → tiles, Monkey coach → game.
    var theme: WTheme { WTheme(homeStyle) }

    var homeStyle: WatchHomeStyle {
        let remoteAt = snapshot.homeStyleChangedAt ?? .distantPast
        if let localStyle, (localStyleAt ?? .distantPast) >= remoteAt { return localStyle }
        return snapshot.homeStyle ?? localStyle ?? .default
    }

    func setHomeStyle(_ style: WatchHomeStyle) {
        let now = Date()
        localStyle = style
        localStyleAt = now
        UserDefaults.standard.set(style.rawValue, forKey: "homeStyle")
        UserDefaults.standard.set(now, forKey: "homeStyleAt")
        #if DEBUG
        if Demo.on { return }
        #endif
        send(.homeStyle(style, changedAt: now))
    }

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
        if var game = snapshot.game {
            // Game mode (#219): count the workout until the phone's next snapshot.
            let sets = f.setsDone.values.reduce(0, +)
            let before = (level: game.level, badges: Set(game.badges))
            game.xp += WGame.xp(sets: sets)
            game.workouts += 1
            game.totalSets += sets
            let p = snapshot.progress
            let earned = WBadge.earned(workouts: game.workouts, totalSets: game.totalSets,
                                       bestStreak: max(p.bestStreakWeeks, p.thisWeek >= p.target ? 1 : 0), records: p.records.count)
            game.badges = Array(before.badges.union(earned)).sorted()
            snapshot.game = game
            reward = WReward(xp: WGame.xp(sets: sets), levelUp: game.level > before.level ? game.level : nil,
                             badges: WBadge.allCases.filter { earned.contains($0.rawValue) && !before.badges.contains($0.rawValue) })
        }
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
        SharedSnapshot.save(data)
        WidgetCenter.shared.reloadAllTimelines()
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

struct WReward: Equatable {
    var xp: Int
    var levelUp: Int?
    var badges: [WBadge]
}

/// Look of every Watch screen, tied to the home style (#219).
enum WTheme {
    case colour, tiles, game

    init(_ style: WatchHomeStyle) {
        switch style {
        case .deck: self = .colour
        case .rings: self = .tiles
        case .coach: self = .game
        }
    }
}
