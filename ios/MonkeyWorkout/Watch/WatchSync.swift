import APIClient
import Foundation
import LiftSensor
import WatchConnectivity
import WorkoutEngine

extension Notification.Name {
    /// A `WCommand` from the Watch for the iPhone workout player (object: WCommand).
    static let watchCommand = Notification.Name("watchCommand")
    /// Double tap on the Watch for the big screen timer (#622 C).
    static let watchTimerToggle = Notification.Name("watchTimerToggle")
    /// Live lift sensor state from the Watch for the iPhone player (object: WLiftLive, #383).
    static let watchLift = Notification.Name("watchLift")
    /// Practice mode state from the Watch (object: WLiftPracticeState, #410).
    static let watchPractice = Notification.Name("watchPractice")
    /// Live heart rate from the Watch tracking the iPhone workout (#371).
    static let watchHeartRate = Notification.Name("watchHeartRate")
    /// Film whole session (#957 C): ✓ / ✗ from the Watch (object: `FilmAnswer`).
    static let watchFilmAnswer = Notification.Name("watchFilmAnswer")
}

/// App style (#219, #227): one pick for the Watch home and screens and the iPhone's game look (Monkey coach,
/// Crown deck → Quest map, Charge & go → Level bar). Picked on the iPhone (Account → Style) or on the Watch;
/// the latest change wins.
@MainActor @Observable
final class WatchHomePref {
    static let shared = WatchHomePref()
    private static let key = "watchHomeStyle"
    private static let dateKey = "watchHomeStyleChangedAt"

    private(set) var style: WatchHomeStyle
    private(set) var changedAt: Date?
    /// XP bar and level chip colour, picked from Steel on (#242); lime before.
    private(set) var accent: GameAccent
    private static let accentKey = "gameAccent"

    private init() {
        style = UserDefaults.standard.string(forKey: Self.key).flatMap(WatchHomeStyle.init) ?? .default
        changedAt = UserDefaults.standard.object(forKey: Self.dateKey) as? Date
        accent = UserDefaults.standard.string(forKey: Self.accentKey).flatMap(GameAccent.init) ?? .lime
        #if DEBUG
        if Demo.enabled, let demo = Demo.appStyle { style = demo }
        #endif
    }

    func set(_ new: WatchHomeStyle, at date: Date = Date()) {
        if let changedAt, date <= changedAt { return }
        style = new
        changedAt = date
        UserDefaults.standard.set(new.rawValue, forKey: Self.key)
        UserDefaults.standard.set(date, forKey: Self.dateKey)
        WatchSync.shared.push()
    }

    func setAccent(_ new: GameAccent) {
        accent = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.accentKey)
        WatchSync.shared.push()
    }
}

/// What the Watch does when a workout starts on the iPhone (#347): ask, start automatically or stay quiet.
/// Picked on the iPhone (Settings → Apple Watch).
@MainActor @Observable
final class WatchStartPref {
    static let shared = WatchStartPref()
    private static let key = "watchStartMode"

    private(set) var mode: WatchStartMode

    private init() {
        mode = UserDefaults.standard.string(forKey: Self.key).flatMap(WatchStartMode.init) ?? .default
    }

    func set(_ new: WatchStartMode) {
        mode = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.key)
        WatchSync.shared.push()
    }
}

/// What an Apple Watch Ultra Action button press does during a workout (#349). Picked on the iPhone (Settings → Apple Watch).
@MainActor @Observable
final class WatchActionPref {
    static let shared = WatchActionPref()
    private static let key = "watchActionMode"

    private(set) var mode: WatchActionMode

    private init() {
        mode = UserDefaults.standard.string(forKey: Self.key).flatMap(WatchActionMode.init) ?? .default
    }

    func set(_ new: WatchActionMode) {
        mode = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.key)
        WatchSync.shared.push()
    }
}

/// Lift sensor on the Watch (#383): off, or on with the velocity-loss stop buzz.
@MainActor @Observable
final class WatchLiftPref {
    static let shared = WatchLiftPref()
    private static let key = "watchLiftMode"

    private static let lastOnKey = "watchLiftLastOn"
    private static let countingKey = "watchLiftCounting"
    private static let loggingKey = "watchLiftLogging"

    private(set) var mode: WatchLiftMode
    /// How strict counting is and how a racked set is logged (#410).
    private(set) var counting: WatchLiftCounting
    private(set) var logging: WatchLiftLogging

    private init() {
        mode = UserDefaults.standard.string(forKey: Self.key).flatMap(WatchLiftMode.init) ?? .default
        counting = UserDefaults.standard.string(forKey: Self.countingKey).flatMap(WatchLiftCounting.init) ?? .default
        logging = UserDefaults.standard.string(forKey: Self.loggingKey).flatMap(WatchLiftLogging.init) ?? .default
    }

    func set(_ new: WatchLiftMode) {
        mode = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.key)
        if new.on { UserDefaults.standard.set(new.rawValue, forKey: Self.lastOnKey) }
        WatchSync.shared.push()
    }

    /// Sensor on (with the last stop buzz picked) or off.
    func setOn(_ on: Bool) {
        set(on ? UserDefaults.standard.string(forKey: Self.lastOnKey).flatMap(WatchLiftMode.init) ?? .default : .off)
    }

    func set(_ new: WatchLiftCounting) {
        counting = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.countingKey)
        WatchSync.shared.push()
    }

    func set(_ new: WatchLiftLogging) {
        logging = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.loggingKey)
        WatchSync.shared.push()
    }
}

/// A paired Watch with MonkeyWorkout installed, observable so Train and Log sport redraw when the Watch link comes
/// up after they first drew (#462). Whether the Watch is on the wrist can't be read from the iPhone: the start fails then.
@MainActor @Observable
final class WatchLink {
    static let shared = WatchLink()
    var ready = false
}

/// iPhone side of the Watch companion (#56): sends plan/progress snapshots and the live player state,
/// applies sets and workouts logged on the Watch, and forwards Watch remote-control commands to the player.
@MainActor
final class WatchSync: NSObject {
    static let shared = WatchSync()

    private weak var model: AppModel?
    /// Last "Start race on Watch" (#426), sent with the snapshot.
    private(set) var hyroxStart: (format: HyroxFormat, at: Date)?
    /// Last "Start on Watch" for another sport (#439), sent with the snapshot.
    private(set) var sportStart: WSportStart?
    private weak var health: HealthManager?
    private var lastSnapshot: WatchSnapshot?
    private var handled: Set<UUID> = []
    /// Plan sessions sent to the Watch this launch: a workout finished there still records after the week rolled.
    private var knownSessions: [String: Session] = [:]
    /// Session of the iPhone workout the Watch tracks heart rate for (#347).
    private var trackedBy: String?
    /// Last iPhone player state, re-sent when the Watch app comes up mid-workout (#347).
    private var lastLive: WLive?
    /// Workouts finished while the Watch tracked them: the Watch saves the Health workout; the phone only if it can't (#347).
    private var awaitingWatch: [UUID: WorkoutRecord] = [:]
    /// Latest heart rate the Watch sent for the iPhone workout (#371).
    private var heartRate: (bpm: Int, at: Date)?

    /// Heart rate for the Live Activity: only while fresh (the Watch sends it every 10 s while tracking).
    var liveHeartRate: Int? {
        guard let h = heartRate, Date().timeIntervalSince(h.at) < 60 else { return nil }
        return h.bpm
    }

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func start(model: AppModel, health: HealthManager) {
        self.model = model
        self.health = health
        guard let session, session.delegate == nil else { return push() }
        session.delegate = self
        session.activate()
    }

    /// Pending `schedulePush()`.
    private var pushTask: Task<Void, Never>?

    /// `push()` once changes settle (1.5 s after the last call): a burst of edits builds one snapshot.
    func schedulePush() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.push()
        }
    }

    /// Sends the current snapshot when it changed and a Watch app is installed.
    func push() {
        // Sends everything now, so a scheduled push has nothing left to do.
        pushTask?.cancel()
        pushTask = nil
        // Home Screen widgets (#297) and Garmin watches (#550) follow the same changes.
        HomeWidgetSync.shared.push()
        GarminSync.shared.publish()
        // Pairing or installing the Watch app while the app runs shows Track on Watch without a restart (#462).
        if WatchLink.shared.ready != watchReady { WatchLink.shared.ready = watchReady }
        guard let model, let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        for s in model.plan?.sessions ?? [] { knownSessions[s.id] = s }
        var snap = Self.snapshot(model, readiness: health.flatMap { Readiness.assess($0.snapshot)?.0.title })
        snap.generatedAt = lastSnapshot?.generatedAt ?? snap.generatedAt
        guard snap != lastSnapshot else { return }
        snap.generatedAt = Date()
        lastSnapshot = snap
        guard let data = try? JSONEncoder.watch.encode(snap) else { return }
        try? session.updateApplicationContext([WatchKeys.snapshot: data])
    }

    /// Cheap fingerprint of what the snapshot depends on (the plan is cached, the lists only counted).
    static func changeKey(_ model: AppModel) -> String {
        let plan = model.plan.map { "\($0.seed)-\($0.week)-\($0.sessions.count)" } ?? "-"
        // Next up follows the day too (#266): a missed session stops being next.
        return "\(plan)|\(model.nextSession?.id ?? "-")|\(model.state.done.count)|\(model.state.history.count)|\(model.state.customWorkoutList?.count ?? 0)|\(model.state.logs.count)|\(ProStore.shared.locked)|\(model.user?.id ?? "-")|\(model.state.climbs?.count ?? 0)|\(model.state.sportLogs?.count ?? 0)|\(model.profile?.hyrox?.goalMinutes ?? 0)|\(model.watchUploadKey != nil)|\(model.state.skipped?.count ?? 0)-\(model.state.skippedAhead?.values.reduce(0) { $0 + $1.count } ?? 0)-\(model.profile?.sportOff?.count ?? 0)"
    }

    /// Mirrors the iPhone player on the Watch (best effort, only while the Watch app is reachable).
    func sendLive(_ live: WLive?) {
        lastLive = live
        guard let session, session.activationState == .activated, session.isReachable else { return }
        if let live, let data = try? JSONEncoder.watch.encode(live) {
            session.sendMessage([WatchKeys.live: data], replyHandler: nil, errorHandler: nil)
        } else {
            session.sendMessage([WatchKeys.liveEnded: true], replyHandler: nil, errorHandler: nil)
        }
    }

    /// Big screen timer (#622 C): shows it on the Watch with a double-tap start; nil closes it.
    func sendWodRemote(_ remote: WWodRemote?) {
        guard let session, session.activationState == .activated else { return }
        if let remote {
            guard session.isReachable, let data = try? JSONEncoder.watch.encode(remote) else { return }
            session.sendMessage([WatchKeys.wodRemote: data], replyHandler: nil, errorHandler: nil)
        } else if session.isReachable {
            session.sendMessage([WatchKeys.wodRemoteEnded: true], replyHandler: nil, errorHandler: nil)
        } else if session.isPaired, session.isWatchAppInstalled {
            // Out of reach as the player closes (#720): queued, so the Watch still ends its HIIT workout.
            session.transferUserInfo([WatchKeys.wodRemoteEnded: true])
        }
    }

    /// Gym buddy link (#626 B): a buddy's set or a cheer, shown over the Watch screen (best effort, reachable only).
    func sendBuddy(_ ping: WBuddyPing) {
        guard let session, session.activationState == .activated, session.isReachable,
              let data = try? JSONEncoder.watch.encode(ping) else { return }
        session.sendMessage([WatchKeys.buddy: data], replyHandler: nil, errorHandler: nil)
    }

    /// Film whole session (#957 C): the move the camera named, for ✓ / ✗ on the wrist (best effort, reachable only).
    func sendFilmGuess(_ guess: WFilmGuess) {
        guard let session, session.activationState == .activated, session.isReachable,
              let data = try? JSONEncoder.watch.encode(guess) else { return }
        session.sendMessage([WatchKeys.filmGuess: data], replyHandler: nil, errorHandler: nil)
    }

    /// The Watch app is open and can take a message now.
    var watchReachable: Bool {
        guard let session, session.activationState == .activated else { return false }
        return session.isReachable
    }

    /// Practice mode (#410): starts or recounts at `level` on the Watch, nil stops it.
    func practice(_ level: Double?) {
        guard let session, session.activationState == .activated, session.isReachable,
              let data = try? JSONEncoder.watch.encode(WLiftPracticeCommand(level: level)) else { return }
        session.sendMessage([WatchKeys.practice: data], replyHandler: nil, errorHandler: nil)
    }

    /// Wakes the Watch app when a workout starts on the iPhone so it can offer to track it (#347).
    /// Needs a paired Watch with the app installed; `HKHealthStore.startWatchApp` only reaches a Watch on the wrist.
    /// `asked`: the member tapped Move to Watch (#603), so the Never setting doesn't hold it back.
    func offerStart(sessionId: String, asked: Bool = false) {
        guard asked || WatchStartPref.shared.mode != .never, trackedBy != sessionId, let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        health?.startWatchApp()
    }

    /// "Start race on Watch" (#426): the format goes with the snapshot, then the Watch app is woken for cross training.
    func startHyrox(_ format: HyroxFormat, done: ((Bool) -> Void)? = nil) {
        hyroxStart = (format, Date())
        push()
        health?.startWatchApp(activity: .crossTraining, done: done)
    }

    /// A paired Watch with MonkeyWorkout installed: "Start on Watch" can reach it (#439).
    var watchReady: Bool {
        guard let session, session.activationState == .activated else { return false }
        return session.isPaired && session.isWatchAppInstalled
    }

    /// "Start on Watch" for another sport (#439): same path as Hyrox, the sport goes with the snapshot, then the
    /// Watch app is woken with the sport's workout type.
    /// `done`: false when the Watch could not be woken (not on the wrist, locked, out of reach).
    /// `run`: a planned run (#618), the Watch follows its steps.
    func startSport(_ sport: Sport, saver: Bool, run: RunWorkout? = nil, done: ((Bool) -> Void)? = nil) {
        sportStart = WSportStart(sport: sport.rawValue, saver: saver, at: Date(), run: run.map(AppModel.watchRun))
        push()
        health?.startWatchApp(activity: HealthManager.activityType(for: sport), done: done)
    }

    /// Climbing live (#829 A): the session goes with the snapshot, then the Watch app is woken for climbing.
    func startClimb() {
        sportStart = WSportStart(sport: Sport.climbing.rawValue, saver: false, at: Date())
        push()
        health?.startWatchApp(activity: .climbing)
    }

    /// Climbing live (#829 A): the session after a change on the iPhone. Queued when the Watch is away, so an end still
    /// reaches it.
    func sendClimb(_ live: WClimbLive) {
        schedulePush()
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder.watch.encode(live) else { return }
        let message = [WatchKeys.climbLive: data]
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in
                if live.ended != nil { session.transferUserInfo(message) }
            }
        } else if live.ended != nil {
            session.transferUserInfo(message)
        }
    }

    /// The Watch tracks heart rate for this iPhone workout, so the Watch saves its Health workout (#347).
    func watchTracks(_ sessionId: String) -> Bool { trackedBy == sessionId }

    /// Tells the Watch the iPhone workout ended and how; a tracked workout's Health save waits for the Watch (#347).
    func endLive(_ outcome: WLiveOutcome, sessionId: String, record: WorkoutRecord? = nil) {
        // Who saves the Health workout (#820): only the Watch this phone knows tracks the session, else the phone did.
        let watchSaves = trackedBy == sessionId
        if let record, watchSaves { waitForWatch(record) }
        if outcome != .paused, trackedBy == sessionId { trackedBy = nil }
        lastLive = nil
        guard let session, session.activationState == .activated else { return }
        var message: [String: Any] = [WatchKeys.liveEnded: true, WatchKeys.outcome: outcome.rawValue]
        if let record { message[WatchKeys.recordId] = record.id.uuidString }
        if outcome == .finished { message[WatchKeys.watchSaves] = watchSaves }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in
                // Missed: queue it so a tracking Watch still learns the workout ended.
                if outcome != .paused { session.transferUserInfo(message) }
            }
        } else if outcome != .paused, session.isPaired, session.isWatchAppInstalled {
            session.transferUserInfo(message)
        }
    }

    private func waitForWatch(_ record: WorkoutRecord) {
        awaitingWatch[record.id] = record
        // The Watch never answered (dead battery, off the wrist): save the Health workout on the iPhone.
        Task {
            try? await Task.sleep(for: .seconds(180))
            guard let r = awaitingWatch.removeValue(forKey: record.id) else { return }
            saveOnPhone(r)
        }
    }

    private func saveOnPhone(_ r: WorkoutRecord) {
        guard let health, let model else { return }
        Task {
            let hr = await health.save(r)
            model.attachHeartRate(r.id, avg: hr.avg, max: hr.max)
        }
    }

    // MARK: Watch → phone

    /// An event from another watch (Garmin, #550), handled like the Apple Watch's.
    func receive(_ event: WatchEvent) { apply(event) }

    private func apply(_ event: WatchEvent) {
        guard let model else { return }
        switch event {
        case let .setLogged(sessionId, exerciseId, setIndex, kg, reps, rir, date):
            // Dated when done on the watch (#820): a set queued while the phone was away stays in its workout.
            model.logSet(exerciseId: exerciseId, sessionId: sessionId, setIndex: setIndex, kg: kg, reps: reps, rir: rir, date: date ?? Date())
        case let .itemDone(uid):
            model.setTicked(uid)
        case let .homeStyle(style, changedAt):
            WatchHomePref.shared.set(style, at: changedAt)
        case let .tracking(sessionId, on):
            if on { trackedBy = sessionId } else if trackedBy == sessionId { trackedBy = nil }
            return
        case let .hyroxRace(race):
            model.saveHyroxRace(race)
        case let .bikeFTP(watts, date):
            model.setBikeFTP(watts, testedAt: date)
        case let .mindCheckIn(date, mood, feelings):
            model.checkIn(mood: mood, feelings: feelings.compactMap(MindFeeling.init(rawValue:)), at: date)
        case let .mindSession(breath, start, seconds):
            if let b = Breath(rawValue: breath) { model.finishCalm(b, from: start, to: start.addingTimeInterval(Double(seconds))) }
        case let .buddyCheer(userId, kind):
            if let k = LiveCheer(rawValue: kind) { LiveRoom.shared.cheer(userId, k, api: model.api) }
            return
        case let .filmAnswer(move, ok):
            NotificationCenter.default.post(name: .watchFilmAnswer, object: FilmAnswer(move: move, ok: ok))
            return
        case let .climbLive(live):
            guard let health else { return }
            ClimbLive.shared.fromWatch(live, model: model, health: health)
            return
        case let .liftSet(set):
            LiftSets.shared.add(set)
            // A correction changes what the Watch learned (pushed by LiftLearning).
            return
        case let .tracked(t):
            guard let r = awaitingWatch.removeValue(forKey: t.recordId) else { return }
            if t.savedToHealth { model.attachHeartRate(r.id, avg: t.avgHeartRate, max: t.maxHeartRate) } else { saveOnPhone(r) }
        case let .finished(f):
            guard !handled.contains(f.id) else { return }
            handled.insert(f.id)
            let before = (game: model.game, badges: model.badges)
            let r: WorkoutRecord
            let session = model.session(f.sessionId) ?? knownSessions[f.sessionId]
            if let session {
                r = model.recordWorkout(
                    session: session, setsDone: f.setsDone, startedAt: f.start, endedAt: f.end,
                    bodyMassKg: health?.snapshot.weightKg ?? model.body.weightKg)
            } else {
                // The session left the plan and wasn't sent since the app started: keep the workout with what the
                // Watch sent rather than drop it.
                r = WorkoutRecord.watchOnly(
                    sessionId: f.sessionId, title: f.title, week: model.plan?.week ?? 1, deload: model.plan?.deload ?? false,
                    startedAt: f.start, endedAt: f.end, kcal: f.kcal, avgHeartRate: f.avgHeartRate, maxHeartRate: f.maxHeartRate)
                model.state.history.append(r)
                model.state.pendingHistoryIds.insert(r.id)
                model.persist()
                Task { await model.sync() }
            }
            model.clearActiveWorkout(f.sessionId)
            // Finished on the Watch (#822 A): the twin player shows the finish screen for this record.
            MirroredWorkout.shared.recorded(r, session: session, sessionId: f.sessionId,
                                            reward: GameReward(before: before.game, after: model.game,
                                                               badgesBefore: before.badges, badgesAfter: model.badges))
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
            // Skipped workouts are gone on the Watch too (#854).
            s.sessions = plan.sessions.filter { !model.skippedOff($0) }.map { session($0, label: $0.dayLabel, planned: true, model: model) }
        }
        s.extras = WorkoutTemplate.all.map { session($0.session, label: "Example", model: model) }
            + model.customWorkouts.map { session($0.session, label: "My workout", model: model) }
        s.nextSessionId = model.nextSession?.id
        s.readiness = readiness
        s.pro = !ProStore.shared.locked
        s.homeStyle = WatchHomePref.shared.style
        s.homeStyleChangedAt = WatchHomePref.shared.changedAt
        s.watchStart = WatchStartPref.shared.mode
        s.actionButton = WatchActionPref.shared.mode
        s.bikeFTP = model.bikeFTP
        s.liftSensor = WatchLiftPref.shared.mode
        s.liftCounting = WatchLiftPref.shared.counting
        s.liftLogging = WatchLiftPref.shared.logging
        s.liftLearned = LiftLearning.shared.levels
        s.hyrox = model.watchHyrox(start: WatchSync.shared.hyroxStart)
        s.sportStart = WatchSync.shared.sportStart
        // Climbing live (#829): the Watch picks up the iPhone's session, only while one is tracked there.
        s.climbLive = ClimbLive.shared.session?.watch == true ? ClimbLive.shared.watchCopy : nil
        // Heart-rate zones (#609) and today's run (#618).
        s.zones = WZones(starts: model.heartZones.starts, buzz: ZonePrefs.buzz)
        s.run = model.todayRun.flatMap { model.runDone($0) ? nil : AppModel.watchRun($0.workout) }
        // Timers (#622) and swimming (#624).
        s.wods = WodStore.shared.timers
        s.swim = model.watchSwim()
        // Mind (#834): score, check-in, Coach's pick and the Calm sessions.
        s.mind = model.watchMind()
        let today = Date()
        let fuel = FuelStore.shared
        s.water = WWater(day: fuel.key(today), glasses: fuel.log(today).glasses, target: model.fuelPlan(on: today).glasses,
                         glassMl: fuel.prefs.glassMl)
        // Smart Stack (#612 A): Next up rises at the home gym.
        if let g = model.homePlace, let lat = g.latitude, let lng = g.longitude {
            s.gym = WGym(name: g.name, latitude: lat, longitude: lng)
        }
        let target = model.profile?.sessionsPerWeek ?? 3
        let stats = Progression.stats(records: model.state.history, weights: model.weightEntries, targetPerWeek: target)
        s.progress = WProgress(
            streakWeeks: stats.currentStreakWeeks, bestStreakWeeks: stats.bestStreakWeeks, thisWeek: stats.thisWeek, target: target,
            records: stats.personalRecords.prefix(5).map { WRecord(name: Exercise.find($0.exerciseId)?.name ?? "Exercise", kg: $0.kg) },
            recent: model.history.prefix(5).map { WRecent(title: $0.title, date: $0.startedAt, minutes: $0.durationSec / 60, sets: $0.totalSets) },
            recordCount: stats.personalRecords.count)
        // Game layer (#219, #227): same XP, level and badges as the iPhone.
        let game = model.game
        let badges = model.badges
        s.game = WGame(xp: game.xp, workouts: game.workouts, totalSets: game.totalSets,
                       badges: badges.filter(\.unlocked).map(\.id), weeksCleared: game.weeksCleared,
                       catalog: badges.map { WBadge(id: $0.id, title: $0.title, symbol: $0.symbol, tier: $0.tier.rawValue) },
                       accent: GameRank.of(level: game.level) >= .steel ? WatchHomePref.shared.accent : nil)
        return s
    }

    private static func session(_ session: Session, label: String, planned: Bool = false, model: AppModel) -> WSession {
        WSession(
            id: session.id, title: session.displayTitle, dayLabel: label, estMin: session.estMin,
            done: model.state.done[session.id] ?? false,
            tint: (session.blocks.first { $0.kind == .strength } ?? session.blocks.first)?.kind.category.tintHex ?? 0xCCFF3D,
            blocks: session.blocks.map { b in
                WBlock(title: b.title, tint: b.kind.category.tintHex, tint2: b.kind.category.tintHex2,
                       // A custom exercise not loaded yet (mid-sync) is left out rather than trapping in Exercise.get (#351).
                       items: b.items.filter { Exercise.find($0.exerciseId) != nil }
                           .map { item($0, block: b, sessionId: session.id, model: model) },
                       guided: b.kind == .cooldown ? true : nil)
            },
            missed: model.missedSessions.contains { $0.id == session.id },
            plannedOn: planned && session.weekday != nil ? WSession.dayKey(model.day(of: session)) : nil,
            skipped: model.skippedIds.contains(session.id) ? true : nil)
    }

    private static func item(_ it: PlannedExercise, block: Block, sessionId: String, model: AppModel) -> WItem {
        let e = Exercise.get(it.exerciseId)
        let loggable = it.isLoggable(in: block)
        let timed = TimedSpec(it.prescription, unit: e.unit)
        let suggestion = loggable ? model.loadSuggestion(for: it, sessionId: sessionId) : nil
        let kg = suggestion?.kg ?? (loggable ? model.lastWeight(it.exerciseId) : nil)
        return WItem(
            uid: it.uid, exerciseId: it.exerciseId, name: e.name, sets: max(1, it.prescription.sets), reps: it.prescription.reps,
            restSec: it.prescription.restSec, intensity: it.prescription.intensity, cues: Array(e.cues.prefix(3)),
            loggable: loggable, timedSec: timed?.workSec, easySec: timed?.easySec,
            kg: kg, targetReps: suggestion?.reps ?? it.prescription.repRange?.low,
            kgStep: LoadAdvisor.steps(for: e, kg: kg ?? 20).granularity,
            pairedName: it.pairedWith.flatMap(Exercise.find)?.name,
            // Superset members as the iPhone groups them (Block.groupMembers); one in another's rest isn't one.
            group: it.supersetWith == nil ? it.group?.first.map { String($0) } : nil)
    }
}

extension WatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            WatchLink.shared.ready = self.watchReady
            self.push()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switched to another Watch.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            WatchLink.shared.ready = self.watchReady
            self.lastSnapshot = nil
            self.push()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        // The Watch app just came up (woken by `offerStart`): show it the running workout at once (#347).
        Task { @MainActor in if let live = self.lastLive { self.sendLive(live) } }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let day = userInfo[WatchKeys.water] as? String {
            Task { @MainActor in
                guard let model = self.model, let date = PlanCalendar.date(day, Progression.calendar()) else { return }
                FuelStore.shared.addGlass(dayKey: day, plan: model.fuelPlan(on: date))
            }
            return
        }
        // Open water buddy alert (#615 B).
        if let data = userInfo[WatchKeys.swimBuddy] as? Data, let buddy = try? JSONDecoder.watch.decode(WSwimBuddy.self, from: data) {
            SwimStore.buddy(buddy)
            return
        }
        guard let data = userInfo[WatchKeys.event] as? Data, let event = try? JSONDecoder.watch.decode(WatchEvent.self, from: data) else { return }
        Task { @MainActor in self.apply(event) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // Tracking state is sent live so the finish knows who saves the Health workout (#347).
        if let data = message[WatchKeys.event] as? Data, let event = try? JSONDecoder.watch.decode(WatchEvent.self, from: data) {
            Task { @MainActor in self.apply(event) }
            return
        }
        if let data = message[WatchKeys.lift] as? Data, let lift = try? JSONDecoder.watch.decode(WLiftLive.self, from: data) {
            Task { @MainActor in NotificationCenter.default.post(name: .watchLift, object: lift) }
            return
        }
        if let data = message[WatchKeys.practiceState] as? Data, let state = try? JSONDecoder.watch.decode(WLiftPracticeState.self, from: data) {
            Task { @MainActor in NotificationCenter.default.post(name: .watchPractice, object: state) }
            return
        }
        if let bpm = message[WatchKeys.heartRate] as? Int {
            Task { @MainActor in
                self.heartRate = (bpm, Date())
                NotificationCenter.default.post(name: .watchHeartRate, object: nil)
            }
            return
        }
        if message[WatchKeys.wodCommand] != nil {
            Task { @MainActor in NotificationCenter.default.post(name: .watchTimerToggle, object: nil) }
            return
        }
        guard let raw = message[WatchKeys.command] as? String, let command = WCommand(rawValue: raw) else { return }
        Task { @MainActor in NotificationCenter.default.post(name: .watchCommand, object: command) }
    }
}

/// Film whole session (#957 C): the Watch's answer on a named move.
struct FilmAnswer {
    let move: Int
    let ok: Bool
}
