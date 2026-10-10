import Foundation

/// Climbing session log (#44): kept on this device; Apple Health is written by the caller.
extension AppModel {
    var climbLogs: [ClimbLog] { (state.climbs ?? []).sorted { $0.start > $1.start } }

    func saveClimb(_ log: ClimbLog) {
        var list = state.climbs ?? []
        if let i = list.firstIndex(where: { $0.id == log.id }) { list[i] = log } else { list.append(log) }
        state.climbs = list
        persist()
    }

    func deleteClimb(_ id: UUID) {
        state.climbs?.removeAll { $0.id == id }
        persist()
    }
}
