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
    // Logged climbs (#44). Optional so older state files still decode.
    var climbs: [ClimbLog]?
    // PR attempts (#60). Optional so older state files still decode.
    var prAttempts: [PRAttempt]?
    var pendingPRAttemptIds: Set<UUID>?
    var deletedPRAttemptIds: Set<UUID>?
    /// Workout paused in the player, resumed at the same point (#57). Local only.
    var activeWorkout: ActiveWorkout?
}

/// Where the player stopped: exercise index, sets done per item and active time so far.
struct ActiveWorkout: Codable, Equatable {
    var sessionId: String
    var index: Int
    var setsDone: [String: Int]
    /// Active seconds before the pause; paused time is not counted.
    var elapsed: TimeInterval
    var updatedAt: Date
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

extension LocalState {
    /// Lenient: missing keys fall back to defaults, so state files from older builds keep decoding.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        ownerId = try c.decodeIfPresent(String.self, forKey: .ownerId)
        synced = try? c.decodeIfPresent(SyncedProfile.self, forKey: .synced)
        plan = try? c.decodeIfPresent(WeekPlan.self, forKey: .plan)
        done = (try? c.decodeIfPresent([String: Bool].self, forKey: .done)) ?? [:]
        ticked = (try? c.decodeIfPresent([String: Bool].self, forKey: .ticked)) ?? [:]
        logs = (try? c.decodeIfPresent([LogEntry].self, forKey: .logs)) ?? []
        pendingLogIds = (try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingLogIds)) ?? []
        lastLogPull = try? c.decodeIfPresent(Date.self, forKey: .lastLogPull)
        profileDirty = (try? c.decodeIfPresent(Bool.self, forKey: .profileDirty)) ?? false
        history = (try? c.decodeIfPresent([WorkoutRecord].self, forKey: .history)) ?? []
        pendingHistoryIds = (try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingHistoryIds)) ?? []
        lastHistoryPull = try? c.decodeIfPresent(Date.self, forKey: .lastHistoryPull)
        customWorkoutList = try? c.decodeIfPresent([CustomWorkout].self, forKey: .customWorkoutList)
        pendingCustomWorkoutIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingCustomWorkoutIds)
        deletedCustomWorkoutIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .deletedCustomWorkoutIds)
        climbs = try? c.decodeIfPresent([ClimbLog].self, forKey: .climbs)
        activeWorkout = try? c.decodeIfPresent(ActiveWorkout.self, forKey: .activeWorkout)
        prAttempts = try? c.decodeIfPresent([PRAttempt].self, forKey: .prAttempts)
        pendingPRAttemptIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingPRAttemptIds)
        deletedPRAttemptIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .deletedPRAttemptIds)
    }
}
