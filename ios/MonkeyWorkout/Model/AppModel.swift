import APIClient
import Foundation
import Network
import UIKit
import WorkoutEngine

@MainActor @Observable
final class AppModel {
    enum Phase: Equatable { case launching, signedOut, signedIn }

    var phase: Phase = .launching
    var user: User?
    var state = LocalState() {
        didSet {
            // Derived values (plan, calendar, game…) are cached until the state changes (`AppModel+Cache`).
            stateVersion &+= 1
            // Custom exercises resolve through `Exercise.find` everywhere (picker, sessions, history).
            if state.customExerciseList != oldValue.customExerciseList {
                CustomExercises.shared.replaceAll(state.customExerciseList ?? [])
            }
        }
    }
    var syncError: String?
    /// Upload-only key the Watch uses to send a Hyrox race straight to the server (#426). In this device's
    /// Keychain, not state.json (#432); see `AppModel+Hyrox`.
    var watchUploadKey: String?
    /// Variation before the last one applied this launch (#98); set while Train offers Undo.
    var variationUndo: VariationUndo?
    /// Pro offer after the first plan (#126); not persisted, so it shows once.
    var offerPro = false
    /// Programme just finished (#255): Train shows its finish sheet once; not persisted.
    var finishedProgramme: ProgrammeRecord?
    /// Selected tab, so Train widgets (#260) can open Progress.
    var tab: MainTab = .train
    /// Settings sheet, opened from the avatar on every tab (#496).
    var settingsOpen = false
    /// Progress section to scroll to when Progress opens from a Train widget (#260).
    var progressJump: ProgressSection?
    /// Explore mode to show when Explore opens from elsewhere, e.g. Progress → Programmes with none started (#345).
    var exploreJump: LibraryView.Mode?
    /// Workouts other members shared (#62), loaded on demand; not persisted.
    var sharedLibrary: [SharedWorkout] = []
    /// Gym Map (#406): the plan other members at the home gym agree with, and its live crowd; loaded on demand.
    var sharedGymMap: SharedGymMap<GymLayout>?
    var gymCrowd: GymCrowd?
    /// Bumped on every change to `state`: keys the derived-value caches (`AppModel+Cache`).
    @ObservationIgnored private(set) var stateVersion = 0
    @ObservationIgnored var derived = DerivedCache()
    /// Gym zones changed from the player (#352): the plan follows once the running workout is over; not persisted.
    @ObservationIgnored var replanAfterWorkout = false
    /// Apple Health readings for first-time load estimates (#115); set at launch.
    @ObservationIgnored weak var health: HealthManager?

    let api: APIClient
    private let store: LocalStore
    private var syncing = false
    private var resyncRequested = false
    /// Silent retry after a failed sync: 5 s, 15 s, 1 min, then every 5 min while the app is active; reset on success.
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryAttempt = 0
    private static let retryDelays: [UInt64] = [5, 15, 60, 300]
    /// Connectivity regained with something unsent → sync.
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var online = true
    /// Coalesced save waiting to run (`persist()`).
    @ObservationIgnored private var persistTask: Task<Void, Never>?

    init(api: APIClient, store: LocalStore) {
        self.api = api
        self.store = store
    }

    static func live() -> AppModel {
        let api = APIClient(
            baseURL: AppConfig.apiBaseURL,
            tokens: KeychainTokenStore(service: AppConfig.keychainService),
            deviceName: UIDevice.current.name)
        return AppModel(api: api, store: LocalStore())
    }

    // MARK: Lifecycle & auth

    private(set) var demo = false
    /// Demo screens' "today" (1 = Monday …), so screenshots don't depend on the day CI runs (#266).
    var demoToday: Int?

    func bootstrap() async {
        #if DEBUG
        if Demo.enabled {
            demo = true
            user = Demo.user
            state = LocalState()
            state.synced = SyncedProfile(profile: Demo.profile, seed: 7, week: Demo.week)
            state.plan = Generator.generateWeek(Demo.profile, week: Demo.week, seed: 7)
            // What Monkey learned (#299): learned likes / dislikes and the coach's new-week card.
            if ["taste", "train-taste", "profile"].contains(Demo.screen) { applyDemoTaste() }
            if let first = state.plan?.sessions.first { state.done[first.id] = true }
            let demo = Demo.history()
            state.history = demo.records
            state.logs = demo.logs
            if ["train-smart", "block-tweak", "auto-tune", "growth-path", "coach-memory"].contains(Demo.screen) { applyDemoGrowth() }
            // Kind streaks (#501): 16 days away, then the first session back today (Comeback quest 1/3).
            if Demo.screen == "train-comeback", let last = state.history.max(by: { $0.startedAt < $1.startedAt }) {
                let cut = Date().addingTimeInterval(-16 * 86_400)
                state.history.removeAll { $0.startedAt > cut }
                var back = last
                back.id = UUID()
                back.startedAt = Date().addingTimeInterval(-3 * 3600)
                state.history.append(back)
            }
            state.climbs = Demo.climbs()
            if ["history-page", "progress-sports"].contains(Demo.screen) { state.sportLogs = Demo.sportLogs() }
            state.customWorkoutList = Demo.customWorkouts
            sharedLibrary = Demo.sharedWorkouts
            state.prAttempts = Demo.prAttempts()
            state.measurements = Demo.measurements()
            MonkeyGradeLink.shared.loadDemo(ownerId: Demo.user?.id ?? "demo")
            state.synced?.profile.climbDayAddon = true
            if Demo.screen == "explore-volume" { state.synced?.profile.method = .volume }
            Community.shared.loadDemo(joined: Demo.screen != "community-join")
            if ["paywall", "pro", "pro-offer", "pro-gate"].contains(Demo.screen) { ProStore.shared.loadDemo(pro: Demo.screen == "pro") }
            state.customExerciseList = [Demo.customExercise]
            state.synced?.away = Demo.away()
            state.synced?.savedGyms = Demo.savedGyms
            // Machine setups (#355).
            state.machineNotes = Demo.machineNotes(plan: state.plan, home: Demo.profile.gym ?? Gym.puls5.ref)
            // Your gym UI test (#271): 48 of the full inventory, 20 off.
            if Demo.screen == "gym-missing" { state.synced?.profile.equipment = Array(Gym.puls5.equipment.prefix(48)) }
            // Customised Train screens (#260).
            switch Demo.screen {
            case "train-data", "train-customise": state.synced?.trainLayout = presetLayout(.data)
            case "train-climber": state.synced?.trainLayout = presetLayout(.climber)
            case "train-minimal": state.synced?.trainLayout = presetLayout(.minimal)
            case "train-looks":
                state.synced?.trainLayout = TrainLayout([
                    TrainWidget(.calendar, size: .large, look: .month), TrainWidget(.volume, size: .wide, look: .minutes),
                    TrainWidget(.records, size: .wide), TrainWidget(.muscles, size: .large), TrainWidget(.lastWorkout, size: .wide),
                ])
            // Customised Progress (#444): sport cards for snowboard, Hyrox and running.
            case "progress-sports":
                state.synced?.progressBoard = ProgressBoard([
                    .sport(.snowboard, size: .large), .sport(.hyrox, size: .wide), .sport(.run),
                    ProgressWidget(.streak), ProgressWidget(.history), ProgressWidget(.training), ProgressWidget(.records),
                ])
            // Lift Focus (#499): week 5 of a 10-week bench block.
            case "lift-focus", "lift-lab":
                state.synced?.liftFocus = LiftFocus(exerciseId: "bench-press", targetKg: 120,
                                                    start: Date().addingTimeInterval(-28 * 86400), weeks: 10, template: .monkeyPeak,
                                                    startOneRepMax: 105, weakPoint: .lockout)
            default: break
            }
            // Gym zones (#274): supersets kept in one zone.
            if ["session-zones", "swap-zones", "player-zones"].contains(Demo.screen) {
                state.synced?.profile.gymLayout = Demo.layout
                state.synced?.profile.grouping = .supersets
            }
            replanCurrentWeek()
            Demo.programme(self)
            Demo.missed(self)
            Demo.sportTrips(self)
            if Demo.screen == "workout-style", let id = state.plan?.sessions.dropFirst().first?.id {
                setSessionStyle(id, SessionStyle(rest: .short, grouping: .supersets))
            }
            if Demo.screen == "progress-empty" {
                // New user: no sessions, PRs or logged climbs yet.
                state.history = []
                state.logs = []
                state.climbs = []
                state.prAttempts = []
            }
            phase = ["welcome", "signin", "signin-2step", "signup", "verify"].contains(Demo.screen) ? .signedOut : .signedIn
            return
        }
        #endif
        await forgetTokensAfterReinstall()
        state = store.load()
        loadWatchUploadKey()
        startConnectivityWatch()
        await api.setOnSignedOut { [weak self] in
            Task { @MainActor in self?.sessionExpired() }
        }
        guard await api.hasSession else {
            phase = .signedOut
            return
        }
        if state.synced == nil {
            // No plan on this device (state.json lost or never synced): fetch the account and its profile first, so
            // onboarding never replaces a plan the server has. The launch spinner stays meanwhile.
            await refreshUser()
            guard await api.hasSession else {
                phase = .signedOut
                return
            }
            claimOwnerIfNeeded()
            await pullProfile()
            phase = .signedIn
        } else {
            phase = .signedIn // optimistic: works offline at the gym
            await refreshUser()
            claimOwnerIfNeeded()
        }
        await sync()
        await ProStore.shared.start(api: api, userId: user?.id)
    }

    /// State written without an owner (lost state.json, older build) belongs to the signed-in account.
    private func claimOwnerIfNeeded() {
        guard state.ownerId == nil, let user else { return }
        state.ownerId = user.id
        persist()
    }

    private static let installedKey = "app.installed"

    /// The Keychain survives uninstall, UserDefaults don't: first launch of a new install drops tokens left from
    /// the old one. An update from a build before this flag already has its state.json and stays signed in.
    private func forgetTokensAfterReinstall() async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.installedKey) else { return }
        if !store.exists {
            await api.forgetTokens()
            MonkeyGradeLink.shared.disconnect()
            clearWatchUploadKey()
        }
        defaults.set(true, forKey: Self.installedKey)
    }

    func refreshUser() async {
        do { user = try await api.me() } catch { /* offline: keep cached state */ }
    }

    /// Call after any successful sign-in / verification.
    func didAuthenticate(_ user: User) async {
        if state.ownerId != user.id {
            store.wipe()
            state = LocalState()
            state.ownerId = user.id
            // The previous account's set history, Fuel, Move, Pro, Health cache, prefs and keys.
            wipeAccountLocalData()
        }
        self.user = user
        phase = .signedIn
        persist()
        startConnectivityWatch()
        await pullProfile()
        await sync()
        await ProStore.shared.start(api: api, userId: user.id)
    }

    /// Explicit sign-out: revoke this device and wipe local data.
    func signOut() async {
        await flushPendingSync()
        await NotificationManager.shared.signOut(api: api)
        await api.logout()
        resetLocal()
    }

    func signOutEverywhere() async throws {
        await flushPendingSync()
        await NotificationManager.shared.signOut(api: api)
        try await api.logoutAllDevices()
        resetLocal()
    }

    /// Caller confirms it's the member first (`ReauthGate`, #257).
    func deleteAccount() async throws {
        try await api.deleteAccount()
        await NotificationManager.shared.signOut(api: api)
        resetLocal()
    }

    /// Refresh token rejected: keep local data (unsynced logs survive), require sign-in.
    private func sessionExpired() {
        stopAutoSync()
        user = nil
        phase = .signedOut
    }

    /// Data export shared from Account (temporary directory); removed on sign-out and account deletion.
    static var exportFileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gym-workout-export.json")
    }

    private func resetLocal() {
        stopAutoSync()
        store.wipe()
        state = LocalState()
        user = nil
        phase = .signedOut
        wipeAccountLocalData()
        // Signed-out snapshots for the Watch and the Home Screen widgets (WatchSync.push refreshes both).
        WatchSync.shared.push()
    }

    /// The account's data kept outside state.json on this device: wiped on sign-out and when another account signs in.
    private func wipeAccountLocalData() {
        ProStore.shared.reset()
        LiftSets.shared.wipe()
        LiftLearning.shared.wipe()
        // Personal copies outside state.json: cached Health readings, the data export, HTTP responses.
        HealthManager.clearCache()
        MoveStore.shared.signOut()
        FuelStore.shared.signOut()
        NotificationManager.shared.resetPrefs()
        // The MonkeyGrade sign-in and the Watch upload key live in this device's Keychain, not in state.json.
        MonkeyGradeLink.shared.disconnect()
        clearWatchUploadKey()
        try? FileManager.default.removeItem(at: Self.exportFileURL)
        URLCache.shared.removeAllCachedResponses()
    }

    /// Before a sign-out wipes this device: one last try (5 s at most) to send what hasn't reached the server.
    private func flushPendingSync() async {
        guard phase == .signedIn, !demo, hasPendingSync else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.sync() }
            group.addTask { try? await Task.sleep(nanoseconds: 5_000_000_000) }
            await group.next()
            group.cancelAll()
        }
    }

    // MARK: Plan

    var profile: Profile? { state.synced?.profile }
    /// Generated week with kept exercise swaps (#101), the member's variation (#98) on top, and library workouts
    /// placed into it (#62).
    /// On a low-readiness day, RIR-autoregulated plans (#156) ease today's session; with daily auto-tune (#495)
    /// today's session follows the tuned level and sore muscles instead.
    var plan: WeekPlan? {
        let key = derivedKey
        if let c = derived.plan, c.key == key { return c.value }
        let p = makePlan()
        derived.plan = (key, p)
        return p
    }

    private func makePlan() -> WeekPlan? {
        guard let edited = uneditedPlan?.applying(edits: state.synced?.sessionEdits ?? []) else { return nil }
        // Lift Focus and Pro Sets (#499): the focus lift's block sets, then the member's set styles.
        let p = expertPlan(edited)
        // Daily auto-tune (#495) replaces the low-readiness easing when on.
        if tuneOn { return tuned(p).plan }
        return p.easedForReadiness(readinessEasedIds(p))
    }

    /// The plan before the member's per-workout exercise edits (#295): what an edit is made on.
    var uneditedPlan: WeekPlan? {
        swappedPlan?.applying(state.synced?.variation).applying(state.synced?.planInserts ?? [])
    }

    /// Today's sessions when an RIR-autoregulated plan meets a "Take it easier" readiness (#156): sessions on
    /// today's weekday, or the next one not done when the plan has no weekdays.
    func readinessEasedIds(_ p: WeekPlan) -> Set<String> {
        guard profile?.trainingMethod == .autoregulated, let snap = health?.snapshot,
              Readiness.assess(snap)?.0 == .easy else { return [] }
        let today = WeekSchedule.fromCalendar(Calendar.current.component(.weekday, from: Date()))
        let dated = p.sessions.filter { $0.weekday == today }
        if !dated.isEmpty { return Set(dated.map(\.id)) }
        if p.sessions.contains(where: { $0.weekday != nil }) { return [] }
        return p.sessions.first { state.done[$0.id] != true }.map { [$0.id] } ?? []
    }

    /// Whether today's session is eased for low readiness (#156).
    var readinessEased: Bool { !tuneOn && (plan.map { !readinessEasedIds($0).isEmpty } ?? false) }
    /// Generated week with kept exercise swaps only: what a variation is made from.
    /// Variation rotation (#182) comes first so kept swaps still find the exercise they replace.
    var swappedPlan: WeekPlan? {
        let swaps = state.synced?.exerciseSwaps ?? []
        guard let plan = state.plan else { return nil }
        let rotated = profile.map { plan.rotatingVariations(for: $0, swaps: swaps) } ?? plan
        return rotated.applying(swaps: swaps)
    }

    /// `rolled`: a new calendar week even when the cycle week and seed come out the same.
    func applyProfile(_ profile: Profile, seed: UInt32? = nil, week: Int = 1, rolled: Bool = false) {
        let s = seed ?? UInt32.random(in: 0...UInt32.max)
        let newWeek = rolled || state.synced?.week != week || state.synced?.seed != s
        let changed = newWeek || state.synced?.profile != profile
        // Plan inserts belong to one week: kept for a new variation or profile edit, dropped on a week change.
        // A variation's swaps only fit the exact plan they were made for.
        let variation = changed ? nil : state.synced?.variation
        // Per-workout styles (#106) are kept for a new variation or profile edit, dropped on a week change.
        let sp = SyncedProfile(profile: profile, seed: s, week: week, body: state.synced?.body, away: state.synced?.away,
                               planInserts: state.synced?.planInserts?.filter { $0.week == week },
                               exerciseSwaps: state.synced?.exerciseSwaps, variation: variation, moves: state.synced?.moves,
                               sessionStyles: state.synced?.sessionStyles?.filter { $0.key.hasPrefix("w\(week)s") },
                               // Per-workout session types (#342) belong to this week only.
                               sessionFoci: newWeek ? nil : state.synced?.sessionFoci,
                               savedGyms: state.synced?.savedGyms, programme: state.synced?.programme,
                               programmeHistory: state.synced?.programmeHistory, trainLayout: state.synced?.trainLayout,
                               progressBoard: state.synced?.progressBoard,
                               customProgrammes: state.synced?.customProgrammes,
                               liftFocus: state.synced?.liftFocus, setStyles: state.synced?.setStyles,
                               weekOf: state.synced?.weekOf,
                               // Exercise edits (#295): library workouts keep theirs; this week's plan days only within the week.
                               sessionEdits: state.synced?.sessionEdits.map { list in list.filter { $0.week == nil || !newWeek } }.flatMap { $0.isEmpty ? nil : $0 },
                               // Learned tastes (#299) shape the plan from the next new week on.
                               taste: state.synced?.taste,
                               weekTaste: newWeek ? freshWeekTaste : state.synced?.weekTaste)
        let keptGrowth = state.synced?.growth
        let learning = (tasteOff: state.synced?.tasteOff, recap: newWeek ? nil : state.synced?.tasteRecap)
        state.synced = sp
        state.synced?.tasteOff = learning.tasteOff
        state.synced?.tasteRecap = learning.recap
        // Growing with the member (#495) outlives every week and profile edit.
        state.synced?.growth = keptGrowth
        // A profile edit (goal, days, gym…) re-plans the rest of this week (#194): sessions already done and the
        // one in progress keep their content; everything else follows the new profile.
        let kept = newWeek ? [] : doneIds.union([state.activeWorkout?.sessionId].compactMap { $0 })
        state.plan = Generator.generateWeek(sp.planProfile, week: week, seed: s).keeping(kept, from: state.plan)
        replanCurrentWeek()
        if newWeek { makeTasteRecap() }
        if newWeek {
            state.done = [:]
            state.ticked = [:]
            state.skipped = nil
        } else if changed {
            state.ticked = state.ticked.filter { uid, _ in kept.contains { uid.hasPrefix($0 + "-") } }
        }
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    func setWeek(_ week: Int) {
        // A running programme sets the week itself (#255).
        guard let sp = state.synced, runningProgramme == nil else { return }
        applyProfile(sp.profile, seed: sp.seed, week: week)
    }

    /// Section edit from the Training profile hub or Community (#99): keeps this week and its variation seed.
    func updateProfile(_ profile: Profile) {
        guard let sp = state.synced else { return applyProfile(profile) }
        // A running programme keeps its goal, split, method and focus (#255); its signature days follow the edit.
        if let prog = runningProgramme {
            applyProfile(prog.profile(from: profile), seed: sp.seed, week: sp.week)
            placeSignatures()
            return
        }
        applyProfile(profile, seed: sp.seed, week: sp.week)
    }

    func setTicked(_ uid: String, _ on: Bool = true) {
        guard state.ticked[uid] != on else { return }
        state.ticked[uid] = on
        persist()
    }

    func markDone(_ sessionId: String) {
        state.done[sessionId] = true
        persist()
    }

    /// A session of this week's plan, an example workout, one of the user's custom workouts or a member's shared one.
    func session(_ id: String) -> Session? {
        plan?.sessions.first { $0.id == id } ?? standaloneSession(id).map { $0.applying(sessionEdit(id)) }
    }

    /// An example, own or shared library workout opened on its own (not part of this week's plan), unedited.
    func standaloneSession(_ id: String) -> Session? {
        freestyleSession(id) ?? WorkoutTemplate.find(sessionId: id)?.session ?? customWorkout(sessionId: id)?.session
            ?? sharedWorkout(sessionId: id)?.workout.session
    }

    /// First session not yet completed from today on, by day (moved and extra sessions included). Sessions of
    /// earlier days that weren't done are missed (#266), not next.
    var nextSession: Session? {
        plan.flatMap { WeekProgress.next($0, today: todayWeekday, done: doneIds) }
    }

    var completedCount: Int { plan?.sessions.filter { state.done[$0.id] ?? false }.count ?? 0 }

    /// Normalised muscle load across the whole week.
    var weekHeat: [Muscle: Double] {
        guard let plan else { return [:] }
        var load: [Muscle: Double] = [:]
        for s in plan.sessions { for (m, v) in Generator.muscleLoad(s.blocks) { load[m, default: 0] += v } }
        let mx = load.values.max() ?? 1
        return load.mapValues { $0 / max(mx, 1e-9) }
    }

    /// Weekly working sets (power + strength blocks) in the current plan.
    var weeklyWorkingSets: Int {
        guard let plan else { return 0 }
        return plan.sessions.flatMap { $0.blocks.filter { [BlockKind.power, .strength].contains($0.kind) }.flatMap(\.items) }
            .reduce(0) { $0 + $1.prescription.sets }
    }

    /// Weekly working sets where `muscle` is a primary mover.
    func weeklySets(for muscle: Muscle) -> Int {
        guard let plan else { return 0 }
        return plan.sessions.flatMap { $0.blocks.filter { [BlockKind.power, .strength].contains($0.kind) }.flatMap(\.items) }
            .filter { Exercise.get($0.exerciseId).primary.contains(muscle) }
            .reduce(0) { $0 + $1.prescription.sets }
    }

    /// This week's hard-set target for `muscle` on a Volume-method plan (#156); nil when the method or muscle has none.
    func volumeTarget(for muscle: Muscle) -> Int? {
        guard let plan, let profile, profile.trainingMethod == .volume, VolumeTargets.tracked.contains(muscle) else { return nil }
        return VolumeTargets.target(week: plan.week, experience: profile.experience)
    }

    /// Hard sets per muscle the way Volume targets count them (primary 1, secondary ½, strength blocks).
    var weeklyHardSets: [Muscle: Double] { plan.map { VolumeTargets.sets($0.sessions) } ?? [:] }

    /// Most recent finished workout that loaded each muscle.
    var lastTrained: [Muscle: Date] {
        var out: [Muscle: Date] = [:]
        for r in state.history {
            for (k, v) in r.muscleLoad where v > 0 {
                guard let m = Muscle(rawValue: k) else { continue }
                if r.startedAt > out[m] ?? .distantPast { out[m] = r.startedAt }
            }
        }
        return out
    }

    func toggleDone(_ sessionId: String) {
        state.done[sessionId] = !(state.done[sessionId] ?? false)
        persist()
    }

    /// Replaces a planned exercise (#101). `keep`: also for that day in future weeks (synced with the profile);
    /// otherwise this week's session only.
    func swap(uid: String, to exerciseId: String, keep: Bool = false) {
        guard var plan = state.plan,
              let s = plan.sessions.firstIndex(where: { $0.blocks.contains { $0.items.contains { $0.uid == uid } } }) else { return }
        let session = plan.sessions[s]
        guard let generated = session.blocks.flatMap(\.items).first(where: { $0.uid == uid })?.exerciseId else { return }
        // What the member saw before swapping (kept swap and variation applied) tells the app what they left (#299).
        let shown = uneditedPlan?.sessions.flatMap { $0.blocks.flatMap(\.items) }.first { $0.uid == uid }?.exerciseId ?? generated
        learnTaste { $0.learn(swap: shown, to: exerciseId, kept: keep, at: Date()) }
        if keep, var sp = state.synced {
            let rule = ExerciseSwap(weekday: session.weekday, sessionIndex: session.index, from: generated, to: exerciseId)
            var rules = sp.exerciseSwaps ?? []
            rules.removeAll { $0.sameSlot(rule) }
            if exerciseId != generated { rules.append(rule) }
            sp.exerciseSwaps = rules.isEmpty ? nil : rules
            // A variation swap on this item would hide the kept one (#98).
            sp.variation?.swaps[uid] = nil
            state.synced = sp
            state.profileDirty = true
            persist()
            Task { await sync() }
            return
        }
        for b in plan.sessions[s].blocks.indices {
            for i in plan.sessions[s].blocks[b].items.indices where plan.sessions[s].blocks[b].items[i].uid == uid {
                plan.sessions[s].blocks[b].items[i].exerciseId = exerciseId
            }
        }
        // A kept rule for the old pick no longer matches, so this week shows `exerciseId`.
        state.plan = plan
        // A variation swap on this item would override the manual one (#98).
        if state.synced?.variation?.swaps[uid] != nil {
            state.synced?.variation?.swaps[uid] = exerciseId
            state.profileDirty = true
        }
        persist()
    }

    /// Items of this week's generated plan; library inserts, examples and custom workouts are fixed lists.
    func canSwap(uid: String) -> Bool {
        state.plan?.sessions.contains { $0.blocks.contains { $0.items.contains { $0.uid == uid } } } ?? false
    }

    /// The kept swap that produced the planned item `uid`, if any.
    func keptSwap(uid: String) -> ExerciseSwap? {
        guard let raw = state.plan?.sessions.first(where: { $0.blocks.contains { $0.items.contains { $0.uid == uid } } }),
              let item = raw.blocks.flatMap(\.items).first(where: { $0.uid == uid }) else { return nil }
        return state.synced?.exerciseSwaps?.first { $0.matches(raw) && $0.from == item.exerciseId }
    }

    /// Stops a kept swap: the day gets the generated exercise back.
    func removeKeptSwap(_ rule: ExerciseSwap) {
        guard var sp = state.synced else { return }
        sp.exerciseSwaps?.removeAll { $0.sameSlot(rule) }
        if sp.exerciseSwaps?.isEmpty == true { sp.exerciseSwaps = nil }
        state.synced = sp
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    // MARK: Body & history

    var body: BodyMetrics { state.synced?.body ?? BodyMetrics() }

    /// Figure on every body map (#110): the user's pick, else suggested from sex.
    var bodyFigure: BodyMapLayout.Figure { body.figure ?? BodyMetrics.suggestedFigure(sex: body.sex) }

    /// Name the coach can call you (#415): account first name, else Community nickname.
    var callableName: String? {
        let n = (user?.name ?? "").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? Community.shared.me.nickname : n
    }

    /// What the coach says before big moments ("Alex!"), nil = no call (#415).
    var coachCallName: String? {
        let b = body
        return CoachCall.text(b.coachCall ?? CoachCall.suggested(hasName: callableName != nil), name: callableName, pronouns: b.effectivePronouns)
    }

    /// The coach calls you by your name (not a term like Champ).
    var coachCallIsName: Bool {
        coachCallName != nil && (body.coachCall ?? CoachCall.suggested(hasName: callableName != nil)) == .name
    }

    func setBodyFigure(_ figure: BodyMapLayout.Figure) {
        var b = body
        b.figure = figure
        saveBody(b)
    }

    func saveBody(_ body: BodyMetrics) {
        guard state.synced != nil else { return }
        state.synced?.body = body.isEmpty ? nil : body
        state.profileDirty = true
        persist()
        Task { await sync() }
        Task { await CoachVoiceStore.shared.fetchCall(model: self) }
    }

    /// Pronouns shown next to your nickname (#415): only when turned on in How we talk to you.
    var communityPronouns: String? { body.showPronouns == true ? body.pronounsText : nil }

    /// Newest first.
    var history: [WorkoutRecord] {
        let version = observedStateVersion
        if let c = derived.history, c.key == version { return c.value }
        let sorted = state.history.sorted { $0.startedAt > $1.startedAt }
        derived.history = (version, sorted)
        return sorted
    }

    var weightEntries: [WeightEntry] {
        state.logs.compactMap { l in l.weightKg.map { WeightEntry(exerciseId: l.exerciseId, date: l.date, kg: $0, reps: l.reps) } }
    }

    /// Weights logged for each exercise during one session.
    func sessionWeights(_ sessionId: String) -> [String: Double] {
        var out: [String: Double] = [:]
        for l in state.logs where l.sessionId == sessionId { if let kg = l.weightKg { out[l.exerciseId] = kg } }
        return out
    }

    /// Stores a finished session; returns it so Health can enrich it.
    @discardableResult
    func recordWorkout(session: Session, setsDone: [String: Int], startedAt: Date, endedAt: Date, bodyMassKg: Double?) -> WorkoutRecord {
        let r = WorkoutRecord.build(
            session: session, week: plan?.week ?? 1, deload: plan?.deload ?? false,
            setsDone: setsDone, weights: sessionWeights(session.id),
            startedAt: startedAt, endedAt: endedAt, bodyMassKg: bodyMassKg)
        state.history.append(r)
        state.pendingHistoryIds.insert(r.id)
        state.done[session.id] = true
        learnTaste { $0.learn(from: r) }
        // A library workout's edit was for this run only (#295); the next time starts from the workout itself.
        if plan?.sessions.contains(where: { $0.id == session.id }) != true { dropSessionEdit(session.id) }
        persist()
        Task { await sync() }
        Task { await Community.shared.autoShare(autoShareWins(), api: api, userId: user?.id) }
        return r
    }

    func attachHeartRate(_ id: UUID, avg: Double?, max: Double?) {
        guard avg != nil || max != nil, let i = state.history.firstIndex(where: { $0.id == id }) else { return }
        state.history[i].avgHeartRate = avg
        state.history[i].maxHeartRate = max
        state.pendingHistoryIds.insert(id)
        persist()
        Task { await sync() }
    }

    /// Undo a finished workout as if it never happened (#133): removes the record, the sets logged during it
    /// (so progression, PRs, starting loads and progress ignore them), its auto-shared community post, and marks
    /// the session not done so it can be done again. Removed on the server too. Apple Health keeps its workout.
    func undoWorkout(_ id: UUID) {
        guard let r = state.history.first(where: { $0.id == id }) else { return }
        let logs = setLogs(of: r)
        state.history.removeAll { $0.id == id }
        state.pendingHistoryIds.remove(id)
        let logIds = Set(logs.map(\.id))
        state.logs.removeAll { logIds.contains($0.id) }
        state.pendingLogIds.subtract(logIds)
        if r.week == plan?.week, Date().timeIntervalSince(r.startedAt) < 8 * 86_400, let s = plan?.sessions.first(where: { $0.id == r.sessionId }) {
            state.done[s.id] = nil
            for b in s.blocks { for it in b.items { state.ticked[it.uid] = nil } }
            if state.activeWorkout?.sessionId == s.id { state.activeWorkout = nil }
        }
        // Queued, not fire-and-forget: a failed delete is retried by the next sync, and pulls skip these ids meanwhile.
        state.deletedWorkoutIds = (state.deletedWorkoutIds ?? []).union([id])
        state.deletedLogIds = (state.deletedLogIds ?? []).union(logIds)
        persist()
        Community.shared.didUndo(r, api: api)
        Task { await sync() }
    }

    /// Set logs of a recorded workout: same session, from its start until the end (plus slack for pauses),
    /// never into a later workout of the same session.
    func setLogs(of r: WorkoutRecord) -> [LogEntry] {
        let next = state.history.filter { $0.sessionId == r.sessionId && $0.startedAt > r.startedAt }.map(\.startedAt).min()
        let from = r.startedAt.addingTimeInterval(-60)
        let to = min(next ?? .distantFuture, r.endedAt.addingTimeInterval(6 * 3600))
        return state.logs.filter { $0.sessionId == r.sessionId && $0.date >= from && $0.date < to }
    }

    /// The record of a plan session done this week, for Undo workout on the session page.
    func recordThisWeek(_ sessionId: String) -> WorkoutRecord? {
        state.history.filter { $0.sessionId == sessionId && $0.week == plan?.week && Date().timeIntervalSince($0.startedAt) < 8 * 86_400 }.max { $0.startedAt < $1.startedAt }
    }

    func logWeight(exerciseId: String, sessionId: String, kg: Double) {
        let entry = LogEntry(date: Date(), exerciseId: exerciseId, sessionId: sessionId, weightKg: kg)
        state.logs.append(entry)
        state.pendingLogIds.insert(entry.id)
        persist()
        Task { await sync() }
    }

    /// Per-set log (kg × reps, optional RIR). Re-logging the same set of the same session today updates it in place.
    func logSet(exerciseId: String, sessionId: String, setIndex: Int, kg: Double, reps: Int, rir: Int?) {
        if let i = state.logs.firstIndex(where: {
            $0.exerciseId == exerciseId && $0.sessionId == sessionId && $0.setIndex == setIndex && Calendar.current.isDateInToday($0.date)
        }) {
            state.logs[i].weightKg = kg
            state.logs[i].reps = reps
            state.logs[i].rir = rir
            state.pendingLogIds.insert(state.logs[i].id)
        } else {
            let entry = LogEntry(date: Date(), exerciseId: exerciseId, sessionId: sessionId, weightKg: kg, reps: reps, setIndex: setIndex, rir: rir)
            state.logs.append(entry)
            state.pendingLogIds.insert(entry.id)
        }
        persist()
        Task { await sync() }
    }

    func lastWeight(_ exerciseId: String) -> Double? {
        state.logs.last { $0.exerciseId == exerciseId && $0.weightKg != nil }?.weightKg
    }

    // MARK: Sync

    /// Server profile replaces the local one unless a local edit is still unsaved (the next push sends it).
    /// Unchanged → nothing, so this week's one-off swaps stay; done and running sessions keep their content.
    private func pullProfile() async {
        guard let remote = try? await api.fetchProfile(SyncedProfile.self) else { return }
        guard state.synced == nil || !state.profileDirty, remote != state.synced else { return }
        let sameWeek = state.synced.map { $0.week == remote.week && $0.seed == remote.seed && $0.weekOf == remote.weekOf } ?? false
        let kept = sameWeek ? doneIds.union([state.activeWorkout?.sessionId].compactMap { $0 }) : []
        state.synced = remote
        state.plan = Generator.generateWeek(remote.planProfile, week: remote.week, seed: remote.seed).keeping(kept, from: state.plan)
        replanCurrentWeek()
        state.profileDirty = false
        persist()
    }

    /// Something not yet on the server: edits, new records or queued deletes.
    var hasPendingSync: Bool {
        state.profileDirty || !state.pendingLogIds.isEmpty || !state.pendingHistoryIds.isEmpty
            || !(state.deletedWorkoutIds ?? []).isEmpty || !(state.deletedLogIds ?? []).isEmpty
            || !(state.pendingCustomWorkoutIds ?? []).isEmpty || !(state.deletedCustomWorkoutIds ?? []).isEmpty
            || !(state.pendingCustomExerciseIds ?? []).isEmpty
            || !(state.pendingPRAttemptIds ?? []).isEmpty || !(state.deletedPRAttemptIds ?? []).isEmpty
            || !(state.pendingMeasurementIds ?? []).isEmpty || !(state.deletedMeasurementIds ?? []).isEmpty
            || !(state.pendingClimbIds ?? []).isEmpty || !(state.deletedClimbIds ?? []).isEmpty
            || !(state.pendingMachineNoteIds ?? []).isEmpty || !(state.deletedMachineNoteIds ?? []).isEmpty
            || !(state.pendingMachinePhotoIds ?? []).isEmpty
    }

    func sync() async {
        guard phase == .signedIn, !demo else { return }
        guard !syncing else {
            resyncRequested = true
            return
        }
        syncing = true
        defer {
            syncing = false
            if resyncRequested {
                resyncRequested = false
                Task { await sync() }
            }
        }
        // Each step runs even when an earlier one failed (a bad record doesn't hold back the rest);
        // the first error is the one shown.
        var firstError: Error?
        guard await runSyncStep(&firstError, { try await self.pushProfile() }),
              // Edits from another device; skipped while a local edit is still unsaved.
              await runSyncStep(&firstError, { if !self.state.profileDirty { await self.pullProfile() } }),
              await runSyncStep(&firstError, { try await self.pushLogs() }),
              await runSyncStep(&firstError, { try await self.pushHistory() }),
              await runSyncStep(&firstError, { try await self.pushQueuedDeletes() }),
              await runSyncStep(&firstError, { try await self.pullHistory() }),
              await runSyncStep(&firstError, { try await self.pullLogs() }),
              await runSyncStep(&firstError, { try await self.syncCustomExercises() }),
              await runSyncStep(&firstError, { try await self.syncCustomWorkouts() }),
              await runSyncStep(&firstError, { try await self.syncPRAttempts() }),
              await runSyncStep(&firstError, { try await self.syncMeasurements() }),
              await runSyncStep(&firstError, { try await self.syncClimbs() }),
              await runSyncStep(&firstError, { try await self.syncSports() }),
              await runSyncStep(&firstError, { try await self.syncMachineNotes() })
        else { return sessionExpired() }
        persist()
        if let firstError {
            syncError = Self.syncMessage(firstError)
            scheduleRetry()
        } else {
            syncError = nil
            retryAttempt = 0
            retryTask?.cancel()
            retryTask = nil
        }
    }

    /// Member-facing sync status: never raw server validation text (#404).
    static func syncMessage(_ error: Error) -> String {
        switch error as? APIError {
        case .network?: "Offline. Changes will sync when you're back online."
        case .signedOut?: APIError.signedOut.localizedDescription
        default: "Some changes haven't synced yet. We'll keep trying."
        }
    }

    /// One sync step; a failure is remembered (first one wins) and the next steps still run.
    /// Returns false when the session is gone, so the sync stops.
    private func runSyncStep(_ firstError: inout Error?, _ work: () async throws -> Void) async -> Bool {
        guard !Task.isCancelled else {
            if firstError == nil { firstError = CancellationError() }
            return true
        }
        do {
            try await work()
        } catch APIError.signedOut {
            return false
        } catch {
            if firstError == nil { firstError = error }
        }
        return true
    }

    private func pushProfile() async throws {
        guard state.profileDirty, let sp = state.synced else { return }
        try await api.saveProfile(sp)
        // An edit made while the save was in flight stays dirty, so the next sync sends it.
        if state.synced == sp { state.profileDirty = false }
    }

    private func pushLogs() async throws {
        let pending = state.logs.filter { state.pendingLogIds.contains($0.id) }
        guard !pending.isEmpty else { return }
        try await api.pushLogs(pending)
        // Only clear what is unchanged since the push started (a set re-logged meanwhile stays queued).
        let current = Dictionary(state.logs.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        for l in pending where current[l.id].map({ $0 == l }) ?? true { state.pendingLogIds.remove(l.id) }
    }

    private func pushHistory() async throws {
        let pendingRecords = state.history.filter { state.pendingHistoryIds.contains($0.id) }
        guard !pendingRecords.isEmpty else { return }
        try await api.pushWorkouts(pendingRecords)
        // Heart rate attached while the push was in flight stays queued for the next sync.
        let current = Dictionary(state.history.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        for r in pendingRecords where current[r.id].map({ $0 == r }) ?? true { state.pendingHistoryIds.remove(r.id) }
    }

    /// Server deletes queued by Undo workout (#133) and PR-attempt removal; each id is dropped once the server
    /// confirms (a 404 means it's already gone). Remaining ids are retried by the next sync.
    private func pushQueuedDeletes() async throws {
        var firstError: Error?
        for id in state.deletedWorkoutIds ?? [] {
            do {
                try await deleteOnServer { try await self.api.deleteWorkout(id) }
                state.deletedWorkoutIds?.remove(id)
            } catch APIError.signedOut {
                throw APIError.signedOut
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        for id in state.deletedLogIds ?? [] {
            do {
                try await deleteOnServer { try await self.api.deleteLog(id) }
                state.deletedLogIds?.remove(id)
            } catch APIError.signedOut {
                throw APIError.signedOut
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    private func deleteOnServer(_ delete: () async throws -> Void) async throws {
        do {
            try await delete()
        } catch let APIError.server(status, _, _) where status == 404 {
            // Already gone on the server.
        }
    }

    private func pullHistory() async throws {
        // Full pull: the server list is the truth, so workouts removed elsewhere (undo on another device,
        // admin undo) drop off this device too instead of lingering in Progress totals (#213).
        // Unsynced local records are kept; workouts whose delete is still queued stay gone.
        let remoteHistory = try await api.fetchWorkouts(WorkoutRecord.self)
        let deleted = state.deletedWorkoutIds ?? []
        var historyById = Dictionary(remoteHistory.filter { !deleted.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        for r in state.history where state.pendingHistoryIds.contains(r.id) { historyById[r.id] = r }
        state.history = Array(historyById.values)
        state.lastHistoryPull = Date()
    }

    private func pullLogs() async throws {
        // 5 min overlap absorbs clock skew; merge is idempotent by id.
        let since = state.lastLogPull?.addingTimeInterval(-300)
        let changes = try await api.fetchLogChanges(since: since)
        let deleted = state.deletedLogIds ?? []
        var byId = Dictionary(state.logs.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        for l in changes.logs where !state.pendingLogIds.contains(l.id) && !deleted.contains(l.id) { byId[l.id] = l }
        // Deleted on the server since the last pull (undo on another device): drop here too, even with a local
        // edit still queued, since the server ignores re-uploads of deleted ids (#432).
        for id in changes.deleted { byId[id] = nil }
        state.pendingLogIds.subtract(changes.deleted)
        state.logs = byId.values.sorted { $0.date < $1.date }
        // The server's clock, compared with its own timestamps next time; this device's only when it didn't send one.
        state.lastLogPull = changes.serverTime ?? Date()
    }

    // MARK: Automatic retry

    /// Backoff retry after a failed sync, only while the app is in the foreground.
    private func scheduleRetry() {
        guard phase == .signedIn, !demo else { return }
        retryTask?.cancel()
        let delay = Self.retryDelays[min(retryAttempt, Self.retryDelays.count - 1)]
        retryAttempt += 1
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled, let self, UIApplication.shared.applicationState == .active else { return }
            await self.sync()
        }
    }

    /// Watches connectivity: back online with something unsent → sync (silently).
    private func startConnectivityWatch() {
        guard pathMonitor == nil, !demo else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.connectivityChanged(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "AppModel.connectivity", qos: .utility))
        pathMonitor = monitor
    }

    private func connectivityChanged(online now: Bool) {
        let regained = now && !online
        online = now
        guard regained, phase == .signedIn, hasPendingSync, UIApplication.shared.applicationState == .active else { return }
        retryAttempt = 0
        Task { await sync() }
    }

    /// Sign-out or expired session: no more automatic syncs.
    private func stopAutoSync() {
        retryTask?.cancel()
        retryTask = nil
        retryAttempt = 0
        pathMonitor?.cancel()
        pathMonitor = nil
        online = true
    }

    /// Internal (not private) so model extensions in other files can save. Coalesced: a burst of changes is encoded
    /// and written once, off the main thread, shortly after the last one; at once while the app isn't active (it may
    /// be suspended any moment).
    func persist() {
        guard !demo else { return }
        guard UIApplication.shared.applicationState == .active else { return persistNow() }
        persistTask?.cancel()
        let wipes = store.wipeCount
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            // A sign-out or account switch wiped the file meanwhile: nothing of before goes back to disk.
            guard !Task.isCancelled, let self, self.store.wipeCount == wipes else { return }
            self.persistTask = nil
            self.store.saveInBackground(self.state)
        }
    }

    /// Writes the state now, after any write already queued.
    func persistNow() {
        persistTask?.cancel()
        persistTask = nil
        if !demo { store.save(state) }
    }

    /// The app leaves the foreground: a coalesced save still waiting is written now.
    func flushPersist() {
        guard persistTask != nil else { return }
        persistNow()
    }
}
