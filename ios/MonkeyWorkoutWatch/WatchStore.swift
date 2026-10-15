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
    /// The iPhone started a workout and woke this Watch (#347): the start prompt shows.
    var offered = false
    /// Last store made by the app, for the app delegate the iPhone wakes (#347).
    static weak var current: WatchStore?
    /// Woken before the store existed.
    static var pendingPhoneStart = false
    private var workout: WorkoutManager { .shared }
    /// Phone paused its workout while this Watch tracked it (#347).
    private var pausedAt: Date?
    private var finishing = false
    /// Game mode (#219): what the last workout finished on this Watch earned, for the Done screen.
    var reward: WReward?
    /// Home style picked on this Watch (#219) and when; the phone's pick in the snapshot wins when newer.
    private var localStyle = UserDefaults.standard.string(forKey: "homeStyle").flatMap(WatchHomeStyle.init)
    private var localStyleAt = UserDefaults.standard.object(forKey: "homeStyleAt") as? Date

    private static let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("snapshot.json")

    override init() {
        snapshot = (try? Data(contentsOf: Self.url)).flatMap { try? JSONDecoder.watch.decode(WatchSnapshot.self, from: $0) } ?? WatchSnapshot()
        super.init()
        Self.current = self
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
        if Self.pendingPhoneStart {
            Self.pendingPhoneStart = false
            phoneStarted()
        }
    }

    var hasPlan: Bool { !snapshot.sessions.isEmpty || !snapshot.extras.isEmpty }
    // The phone decides (#266): nil = nothing left this week, never an earlier missed session.
    var next: WSession? { snapshot.nextSessionId.flatMap(snapshot.session) }

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
        let i = snapshot.sessions.firstIndex { $0.id == f.sessionId }
        if let i { snapshot.sessions[i].done = true }
        // Next one later this week, never an earlier missed one (#266); the phone's next snapshot settles it.
        if snapshot.nextSessionId == f.sessionId {
            snapshot.nextSessionId = i.flatMap { i in snapshot.sessions[(i + 1)...].first { !$0.done }?.id }
        }
        snapshot.progress.recent.insert(
            WRecent(title: snapshot.session(f.sessionId)?.title ?? "Workout", date: f.start,
                    minutes: Int(f.end.timeIntervalSince(f.start)) / 60, sets: f.setsDone.values.reduce(0, +)), at: 0)
        snapshot.progress.thisWeek += 1
        if var game = snapshot.game {
            // Game layer (#219, #227): count the workout until the phone's next snapshot; badges come with it.
            let sets = f.setsDone.values.reduce(0, +)
            let level = game.level
            var xp = WGame.xp(sets: sets)
            let cleared = snapshot.progress.thisWeek == snapshot.progress.target
            if cleared {
                xp += WGame.weekBonus
                game.weeksCleared = (game.weeksCleared ?? 0) + 1
            }
            game.xp += xp
            game.workouts += 1
            game.totalSets += sets
            snapshot.game = game
            reward = WReward(xp: xp, levelUp: game.level > level ? game.level : nil, weekCleared: cleared, badges: [])
        }
        save()
    }

    fileprivate func receive(context: [String: Any]) {
        guard let data = context[WatchKeys.snapshot] as? Data,
              let s = try? JSONDecoder.watch.decode(WatchSnapshot.self, from: data) else { return }
        // Badges the finished workout unlocked arrive with the phone's snapshot (#227).
        if reward != nil, let before = snapshot.game, let after = s.game {
            let new = after.earned.filter { !before.badges.contains($0.id) && !(reward?.badges.contains($0) ?? false) }
            reward?.badges += new
        }
        snapshot = s
        save()
    }

    fileprivate func receive(message: [String: Any]) {
        if message[WatchKeys.liveEnded] != nil {
            live = nil
            phoneEnded(message[WatchKeys.outcome].flatMap { $0 as? String }.flatMap(WLiveOutcome.init),
                       recordId: (message[WatchKeys.recordId] as? String).flatMap(UUID.init))
        }
        if let data = message[WatchKeys.live] as? Data, let l = try? JSONDecoder.watch.decode(WLive.self, from: data) {
            live = l
            if pausedAt != nil, workout.phoneSessionId != nil {
                pausedAt = nil
                workout.resume()
            }
        }
    }

    // MARK: iPhone workout on the Watch (#347)

    /// Title of the iPhone workout, from its live state or the plan.
    var phoneWorkout: (title: String, estMin: Int?, exercises: Int?, tint: UInt32) {
        let s = live?.sessionId.flatMap(snapshot.session) ?? (live == nil ? next : nil)
        return (live?.sessionTitle ?? s?.title ?? "Workout", live?.estMin ?? s?.estMin,
                live?.exercises ?? s.map { $0.blocks.reduce(0) { $0 + $1.items.count } }, s?.tint ?? live?.tint ?? 0xCCFF3D)
    }

    /// The iPhone woke the Watch app for a workout it started.
    func phoneStarted() {
        guard workout.phoneSessionId == nil, !workout.running else { return }
        if snapshot.watchStart == .always {
            Task { await trackPhoneWorkout() }
        } else {
            offered = true
            Task { await workout.prepare() }
        }
    }

    /// Start prompt accepted (or start mode is automatic): track heart rate and energy while following the iPhone player.
    func trackPhoneWorkout() async {
        offered = false
        let id = live?.sessionId ?? snapshot.nextSessionId ?? "phone"
        await workout.start(title: phoneWorkout.title, phoneSessionId: id)
        if workout.running { sendNow(.tracking(sessionId: id, on: true)) }
    }

    func declineOffer() {
        offered = false
        if !workout.running { workout.discard() }
    }

    /// Stops tracking without saving; the iPhone saves the Health workout itself.
    func stopTracking() {
        guard let id = workout.phoneSessionId else { return }
        workout.discard()
        pausedAt = nil
        sendNow(.tracking(sessionId: id, on: false))
    }

    private func phoneEnded(_ outcome: WLiveOutcome?, recordId: UUID?) {
        if offered, outcome != .paused, outcome != nil { declineOffer() }
        guard let id = workout.phoneSessionId else { return }
        switch outcome {
        case .finished:
            guard !finishing else { return }
            finishing = true
            Task {
                defer { finishing = false }
                let kcal = workout.activeKcal
                let avg = workout.averageHeartRate
                let max = workout.maxHeartRate
                let saved = await workout.finish(sets: nil)
                pausedAt = nil
                if let recordId {
                    send(.tracked(WTracked(recordId: recordId, avgHeartRate: avg, maxHeartRate: max,
                                           kcal: saved ? kcal : nil, savedToHealth: saved)))
                }
            }
        case .discarded:
            stopTracking()
        case .paused, nil:
            guard !finishing else { return }
            // Paused on the iPhone: keep the session; drop it if the workout doesn't resume within 30 minutes.
            guard pausedAt == nil else { return }
            let at = Date()
            pausedAt = at
            workout.pause()
            Task {
                try? await Task.sleep(for: .seconds(30 * 60))
                if pausedAt == at, workout.phoneSessionId == id { stopTracking() }
            }
        }
    }

    /// Sent at once when the phone is reachable (it decides who saves the Health workout), queued otherwise.
    private func sendNow(_ event: WatchEvent) {
        guard WCSession.isSupported(), let data = try? JSONEncoder.watch.encode(event) else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage([WatchKeys.event: data], replyHandler: nil) { _ in
                WCSession.default.transferUserInfo([WatchKeys.event: data])
            }
        } else {
            WCSession.default.transferUserInfo([WatchKeys.event: data])
        }
    }

    private func save() {
        guard let data = try? JSONEncoder.watch.encode(snapshot) else { return }
        try? data.write(to: Self.url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
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
            // While tracking an iPhone workout, keep showing its last state until it comes back (#347).
            if !reachable, WorkoutManager.shared.phoneSessionId == nil { self.live = nil }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(context: applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.receive(message: message) }
    }

    /// iPhone workout ended while this Watch was out of reach (#347).
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.receive(message: userInfo) }
    }
}

struct WReward: Equatable {
    var xp: Int
    var levelUp: Int?
    /// This workout met the week's goal: quest chest bonus included in `xp`.
    var weekCleared = false
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
