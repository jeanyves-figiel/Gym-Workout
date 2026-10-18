import APIClient
import Foundation

/// Climbing session log (#44): Apple Health is written by the caller. Synced to the server since #312
/// (queued like PR attempts: kept across restarts, retried by `sync()`).
extension AppModel {
    var climbLogs: [ClimbLog] { (state.climbs ?? []).sorted { $0.start > $1.start } }

    func saveClimb(_ log: ClimbLog) {
        var list = state.climbs ?? []
        if let i = list.firstIndex(where: { $0.id == log.id }) { list[i] = log } else { list.append(log) }
        state.climbs = list
        state.pendingClimbIds = (state.pendingClimbIds ?? []).union([log.id])
        persist()
        Task { await sync() }
        Task { await Community.shared.autoShare(autoShareWins(), api: api, userId: user?.id) }
    }

    func deleteClimb(_ id: UUID) {
        state.climbs?.removeAll { $0.id == id }
        state.pendingClimbIds?.remove(id)
        state.deletedClimbIds = (state.deletedClimbIds ?? []).union([id])
        persist()
        Task { await sync() }
    }

    func syncClimbs() async throws {
        // Climbs logged before #312 were only on this device: send them all once.
        if state.climbsUploaded != true {
            state.pendingClimbIds = (state.pendingClimbIds ?? []).union((state.climbs ?? []).map(\.id))
            state.climbsUploaded = true
        }
        for id in state.deletedClimbIds ?? [] {
            do {
                try await api.deleteClimb(id)
            } catch let APIError.server(status, _, _) where status == 404 {
                // Already gone.
            }
            state.deletedClimbIds?.remove(id)
        }
        let pendingIds = state.pendingClimbIds ?? []
        let pending = (state.climbs ?? []).filter { pendingIds.contains($0.id) }
        if !pending.isEmpty {
            try await api.pushClimbs(pending)
            state.pendingClimbIds?.subtract(pending.map(\.id))
        }
        let remote = try await api.fetchClimbs(ClimbLog.self)
        let stillPending = state.pendingClimbIds ?? []
        let deleted = state.deletedClimbIds ?? []
        var merged = remote.filter { !stillPending.contains($0.id) && !deleted.contains($0.id) }
        merged += (state.climbs ?? []).filter { stillPending.contains($0.id) }
        var seen = Set<UUID>()
        state.climbs = merged.filter { seen.insert($0.id).inserted }
    }
}
