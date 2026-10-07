import APIClient
import Foundation
import UIKit
import WorkoutEngine

@MainActor @Observable
final class AppModel {
    enum Phase: Equatable { case launching, signedOut, signedIn }

    var phase: Phase = .launching
    var user: User?
    var state = LocalState()
    var syncError: String?

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
            state.synced = SyncedProfile(profile: Demo.profile, seed: 7, week: 2)
            state.plan = Generator.generateWeek(Demo.profile, week: 2, seed: 7)
            if let first = state.plan?.sessions.first {
                state.done[first.id] = true
                state.logs = [LogEntry(date: Date(), exerciseId: "pull-up", weightKg: 10)]
            }
            phase = Demo.screen == "welcome" ? .signedOut : .signedIn
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
        await api.logout()
        resetLocal()
    }

    func signOutEverywhere() async throws {
        try await api.logoutAllDevices()
        resetLocal()
    }

    func deleteAccount(password: String?) async throws {
        try await api.deleteAccount(password: password)
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
    var plan: WeekPlan? { state.plan }

    func applyProfile(_ profile: Profile, seed: UInt32? = nil, week: Int = 1) {
        let s = seed ?? UInt32.random(in: 0...UInt32.max)
        let changed = state.synced?.week != week || state.synced?.seed != s || state.synced?.profile != profile
        state.synced = SyncedProfile(profile: profile, seed: s, week: week)
        state.plan = Generator.generateWeek(profile, week: week, seed: s)
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

    func newVariation() {
        guard let sp = state.synced else { return }
        applyProfile(sp.profile, week: sp.week)
    }

    func toggleTick(_ uid: String) {
        state.ticked[uid] = !(state.ticked[uid] ?? false)
        persist()
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

    /// First session of the week not yet completed.
    var nextSession: Session? { plan?.sessions.first { !(state.done[$0.id] ?? false) } }

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

    func swap(uid: String, to exerciseId: String) {
        guard var plan = state.plan else { return }
        for s in plan.sessions.indices {
            for b in plan.sessions[s].blocks.indices {
                for i in plan.sessions[s].blocks[b].items.indices where plan.sessions[s].blocks[b].items[i].uid == uid {
                    plan.sessions[s].blocks[b].items[i].exerciseId = exerciseId
                }
            }
        }
        state.plan = plan
        persist()
    }

    func logWeight(exerciseId: String, sessionId: String, kg: Double) {
        let entry = LogEntry(date: Date(), exerciseId: exerciseId, sessionId: sessionId, weightKg: kg)
        state.logs.append(entry)
        state.pendingLogIds.insert(entry.id)
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
            // 5 min overlap absorbs clock skew; merge is idempotent by id.
            let since = state.lastLogPull?.addingTimeInterval(-300)
            let remote = try await api.fetchLogs(since: since)
            var byId = Dictionary(state.logs.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            for l in remote where !state.pendingLogIds.contains(l.id) { byId[l.id] = l }
            state.logs = byId.values.sorted { $0.date < $1.date }
            state.lastLogPull = Date()
            syncError = nil
            persist()
        } catch APIError.signedOut {
            sessionExpired()
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func persist() {
        if !demo { store.save(state) }
    }
}
