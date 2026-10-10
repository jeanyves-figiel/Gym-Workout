import APIClient
import Foundation
import WorkoutEngine

/// What gets synced as the server "profile": inputs that regenerate the plan deterministically.
struct SyncedProfile: Codable, Equatable, Sendable {
    var profile: Profile
    var seed: UInt32
    var week: Int
    /// Entered in-app (used when Apple Health lacks them).
    var body: BodyMetrics?
}

struct LocalState: Codable {
    var ownerId: String?
    var synced: SyncedProfile?
    var plan: WeekPlan?
    var done: [String: Bool] = [:]
    var ticked: [String: Bool] = [:]
    var logs: [LogEntry] = []
    var pendingLogIds: Set<UUID> = []
    var lastLogPull: Date?
    var profileDirty = false
    var history: [WorkoutRecord] = []
    var pendingHistoryIds: Set<UUID> = []
    var lastHistoryPull: Date?
    // Custom workouts (#28). Optional so state files written before them still decode.
    var customWorkoutList: [CustomWorkout]?
    var pendingCustomWorkoutIds: Set<UUID>?
    var deletedCustomWorkoutIds: Set<UUID>?
}

/// JSON file in Application Support, encrypted at rest by iOS data protection.
struct LocalStore {
    private let url: URL

    init(filename: String = "state.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent(filename)
    }

    func load() -> LocalState {
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(LocalState.self, from: data) else { return LocalState() }
        return s
    }

    func save(_ state: LocalState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func wipe() { try? FileManager.default.removeItem(at: url) }
}
