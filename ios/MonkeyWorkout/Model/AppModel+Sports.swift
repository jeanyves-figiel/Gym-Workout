import APIClient
import Foundation
import WorkoutEngine

/// Other sport sessions (#416): logged here or rated from Apple Health. Apple Health is written by the caller.
/// Synced to the server like climbs (queued, kept across restarts, retried by `sync()`).
extension AppModel {
    var sportLogs: [SportLog] { (state.sportLogs ?? []).sorted { $0.start > $1.start } }

    func saveSport(_ log: SportLog) {
        var list = state.sportLogs ?? []
        if let i = list.firstIndex(where: { $0.id == log.id }) { list[i] = log } else { list.append(log) }
        state.sportLogs = list
        state.pendingSportIds = (state.pendingSportIds ?? []).union([log.id])
        persist()
        Task { await sync() }
    }

    func deleteSport(_ id: UUID) {
        state.sportLogs?.removeAll { $0.id == id }
        state.pendingSportIds?.remove(id)
        state.deletedSportIds = (state.deletedSportIds ?? []).union([id])
        persist()
        Task { await sync() }
    }

    /// Spotted (#416): the member's effort for a Health session, kept as a log with the same id.
    func rateSport(_ entry: SportEntry, effort: Int) {
        saveSport(SportLog(id: entry.id, sport: entry.sport, start: entry.start, minutes: entry.minutes, effort: effort,
                           distanceKm: entry.distanceKm, fromHealth: true))
    }

    /// Spotted (#416): today's session swapped to a type that spares what the sport loaded, this week only.
    func swapAfterSport(_ s: Session, to focus: Focus) {
        guard canChangeFocus(s) else { return }
        setSessionFocus(s, to: focus, everyWeek: false)
    }

    func syncSports() async throws {
        for id in state.deletedSportIds ?? [] {
            do {
                try await api.deleteSport(id)
            } catch let APIError.server(status, _, _) where status == 404 {
                // Already gone.
            }
            state.deletedSportIds?.remove(id)
        }
        let pendingIds = state.pendingSportIds ?? []
        let pending = (state.sportLogs ?? []).filter { pendingIds.contains($0.id) }
        if !pending.isEmpty {
            try await api.pushSports(pending)
            state.pendingSportIds?.subtract(pending.map(\.id))
        }
        let remote = try await api.fetchSports(SportLog.self)
        let stillPending = state.pendingSportIds ?? []
        let deleted = state.deletedSportIds ?? []
        var merged = remote.filter { !stillPending.contains($0.id) && !deleted.contains($0.id) }
        merged += (state.sportLogs ?? []).filter { stillPending.contains($0.id) }
        var seen = Set<UUID>()
        state.sportLogs = merged.filter { seen.insert($0.id).inserted }
    }
}
