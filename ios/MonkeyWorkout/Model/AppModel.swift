import APIClient
import Foundation
import UIKit
import WorkoutEngine

@MainActor @Observable
final class AppModel {
    enum Phase: Equatable { case launching, signedOut, signedIn }

    var phase: Phase = .launching
    var user: User?
    var state = LocalState() {
        didSet {
            // Custom exercises resolve through `Exercise.find` everywhere (picker, sessions, history).
            if state.customExerciseList != oldValue.customExerciseList {
                CustomExercises.shared.replaceAll(state.customExerciseList ?? [])
            }
        }
    }
    var syncError: String?
    /// Variation before the last one applied this launch (#98); set while Train offers Undo.
    var variationUndo: VariationUndo?
    /// Workouts other members shared (#62), loaded on demand; not persisted.
    var sharedLibrary: [SharedWorkout] = []
    /// Apple Health readings for first-time load estimates (#115); set at launch.
    @ObservationIgnored weak var health: HealthManager?

    let api: APIClient
    private let store: LocalStore
    private var syncing = false
    private var resyncRequested = false

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

    func bootstrap() async {
        #if DEBUG
        if Demo.enabled {
            demo = true
            user = Demo.user
            state = LocalState()
            state.synced = SyncedProfile(profile: Demo.profile, seed: 7, week: Demo.week)
            state.plan = Generator.generateWeek(Demo.profile, week: Demo.week, seed: 7)
            if let first = state.plan?.sessions.first { state.done[first.id] = true }
            let demo = Demo.history()
            state.history = demo.records
            state.logs = demo.logs
            state.climbs = Demo.climbs()
            state.customWorkoutList = Demo.customWorkouts
            sharedLibrary = Demo.sharedWorkouts
            state.prAttempts = Demo.prAttempts()
            MonkeyGradeLink.shared.loadDemo(ownerId: Demo.user?.id ?? "demo")
            state.synced?.profile.climbDayAddon = true
            Community.shared.loadDemo(joined: Demo.screen != "community-join")
            state.customExerciseList = [Demo.customExercise]
            state.synced?.away = Demo.away()
            replanCurrentWeek()
            if Demo.screen == "progress-empty" {
                // New user: no sessions, PRs or logged climbs yet.
                state.history = []
                state.logs = []
                state.climbs = []
                state.prAttempts = []
            }
            phase = ["welcome", "signin", "signup", "verify"].contains(Demo.screen) ? .signedOut : .signedIn
            return
        }
        #endif
        state = store.load()
        await api.setOnSignedOut { [weak self] in
            Task { @MainActor in self?.sessionExpired() }
        }
        guard await api.hasSession else {
            phase = .signedOut
            return
        }
        phase = .signedIn // optimistic: works offline at the gym
        await refreshUser()
        await sync()
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
        }
        self.user = user
        phase = .signedIn
        persist()
        await pullProfile()
        await sync()
    }

    /// Explicit sign-out: revoke this device and wipe local data.
    func signOut() async {
        await NotificationManager.shared.signOut(api: api)
        await api.logout()
        resetLocal()
    }

    func signOutEverywhere() async throws {
        await NotificationManager.shared.signOut(api: api)
        try await api.logoutAllDevices()
        resetLocal()
    }

    func deleteAccount(password: String?) async throws {
        try await api.deleteAccount(password: password)
        await NotificationManager.shared.signOut(api: api)
        resetLocal()
    }

    /// Refresh token rejected: keep local data (unsynced logs survive), require sign-in.
    private func sessionExpired() {
        user = nil
        phase = .signedOut
    }

    private func resetLocal() {
        store.wipe()
        state = LocalState()
        user = nil
        phase = .signedOut
    }

    // MARK: Plan

    var profile: Profile? { state.synced?.profile }
    /// Generated week with kept exercise swaps (#101), the member's variation (#98) on top, and library workouts
    /// placed into it (#62).
    var plan: WeekPlan? { swappedPlan?.applying(state.synced?.variation).applying(state.synced?.planInserts ?? []) }
    /// Generated week with kept exercise swaps only: what a variation is made from.
    var swappedPlan: WeekPlan? { state.plan?.applying(swaps: state.synced?.exerciseSwaps ?? []) }

    func applyProfile(_ profile: Profile, seed: UInt32? = nil, week: Int = 1) {
        let s = seed ?? UInt32.random(in: 0...UInt32.max)
        let changed = state.synced?.week != week || state.synced?.seed != s || state.synced?.profile != profile
        // Plan inserts belong to one week: kept for a new variation or profile edit, dropped on a week change.
        // A variation's swaps only fit the exact plan they were made for.
        let variation = changed ? nil : state.synced?.variation
        state.synced = SyncedProfile(profile: profile, seed: s, week: week, body: state.synced?.body, away: state.synced?.away,
                                     planInserts: state.synced?.planInserts?.filter { $0.week == week },
                                     exerciseSwaps: state.synced?.exerciseSwaps, variation: variation, moves: state.synced?.moves)
        state.plan = Generator.generateWeek(profile, week: week, seed: s)
        replanCurrentWeek()
        if changed {
            state.done = [:]
            state.ticked = [:]
        }
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    func setWeek(_ week: Int) {
        guard let sp = state.synced else { return }
        applyProfile(sp.profile, seed: sp.seed, week: week)
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
        plan?.sessions.first { $0.id == id } ?? WorkoutTemplate.find(sessionId: id)?.session ?? customWorkout(sessionId: id)?.session
            ?? sharedWorkout(sessionId: id)?.workout.session
    }

    /// First session of the week not yet completed, by day (moved and extra sessions included).
    var nextSession: Session? {
        plan?.sessions.enumerated().sorted { ($0.element.weekday ?? 8, $0.offset) < ($1.element.weekday ?? 8, $1.offset) }
            .map(\.element).first { !(state.done[$0.id] ?? false) }
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

    /// Weekly working sets where `muscle` is a primary mover.
    func weeklySets(for muscle: Muscle) -> Int {
        guard let plan else { return 0 }
        return plan.sessions.flatMap { $0.blocks.filter { [BlockKind.power, .strength].contains($0.kind) }.flatMap(\.items) }
            .filter { Exercise.get($0.exerciseId).primary.contains(muscle) }
            .reduce(0) { $0 + $1.prescription.sets }
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

    func saveBody(_ body: BodyMetrics) {
        guard state.synced != nil else { return }
        state.synced?.body = body.isEmpty ? nil : body
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    var history: [WorkoutRecord] { state.history.sorted { $0.startedAt > $1.startedAt } }

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
        persist()
        Task { await sync() }
        Community.shared.didRecord(r, api: api, userId: user?.id)
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

    func deleteRecord(_ id: UUID) {
        state.history.removeAll { $0.id == id }
        state.pendingHistoryIds.remove(id)
        persist()
        Task { try? await api.deleteWorkout(id) }
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

    private func pullProfile() async {
        guard let remote = try? await api.fetchProfile(SyncedProfile.self) else { return }
        if state.synced == nil || !state.profileDirty {
            state.synced = remote
            state.plan = Generator.generateWeek(remote.profile, week: remote.week, seed: remote.seed)
            replanCurrentWeek()
            state.profileDirty = false
            persist()
        }
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
        do {
            if state.profileDirty, let sp = state.synced {
                try await api.saveProfile(sp)
                state.profileDirty = false
            }
            let pending = state.logs.filter { state.pendingLogIds.contains($0.id) }
            if !pending.isEmpty {
                try await api.pushLogs(pending)
                state.pendingLogIds.subtract(pending.map(\.id))
            }
            let pendingRecords = state.history.filter { state.pendingHistoryIds.contains($0.id) }
            if !pendingRecords.isEmpty {
                try await api.pushWorkouts(pendingRecords)
                state.pendingHistoryIds.subtract(pendingRecords.map(\.id))
            }
            let remoteHistory = try await api.fetchWorkouts(WorkoutRecord.self, since: state.lastHistoryPull?.addingTimeInterval(-300))
            var historyById = Dictionary(state.history.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            for r in remoteHistory where !state.pendingHistoryIds.contains(r.id) { historyById[r.id] = r }
            state.history = Array(historyById.values)
            state.lastHistoryPull = Date()
            // 5 min overlap absorbs clock skew; merge is idempotent by id.
            let since = state.lastLogPull?.addingTimeInterval(-300)
            let remote = try await api.fetchLogs(since: since)
            var byId = Dictionary(state.logs.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            for l in remote where !state.pendingLogIds.contains(l.id) { byId[l.id] = l }
            state.logs = byId.values.sorted { $0.date < $1.date }
            state.lastLogPull = Date()
            try await syncCustomExercises()
            try await syncCustomWorkouts()
            try await syncPRAttempts()
            syncError = nil
            persist()
        } catch APIError.signedOut {
            sessionExpired()
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Internal (not private) so model extensions in other files can save.
    func persist() {
        if !demo { store.save(state) }
    }
}
