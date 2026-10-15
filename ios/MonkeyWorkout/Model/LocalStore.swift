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
    /// "Can't train" dates and travel periods (#68). Optional so older profiles still decode.
    var away: [AwayPeriod]?
    /// Library workouts placed into the plan (#62): replaced or extra sessions of the current week.
    var planInserts: [PlanInsert]?
    /// Exercise swaps kept for future weeks (#101), per plan day. Kept across variations and weeks.
    var exerciseSwaps: [ExerciseSwap]?
    /// Member-steered exercise swaps for this week (#98). Optional so older profiles still decode.
    var variation: PlanVariation?
    /// One-off moves of this week's sessions to another day (#113).
    var moves: [SessionMove]?
    /// Per-workout rest / grouping overrides (#106), keyed by session id ("w2s1"); dropped on a week change.
    var sessionStyles: [String: SessionStyle]?
    /// Gyms the member set up, each with its own equipment (#162). Optional so older profiles still decode.
    var savedGyms: [SavedGym]?
    /// Training programme in progress (#255): replaces the plan while it runs. Optional so older profiles still decode.
    var programme: ActiveProgramme?
    /// Programmes finished or left (#255), newest last.
    var programmeHistory: [ProgrammeRecord]?
    /// Customised Train screen (#260); nil = the default layout.
    var trainLayout: TrainLayout?
    /// Programmes the member made or copied (#269).
    var customProgrammes: [Programme]?
    /// Monday ("yyyy-MM-dd") of the calendar week the plan belongs to (#266); a new calendar week moves the plan on.
    var weekOf: String?
    /// Exercise lists the member edited before starting (#295): plan sessions of this week and library workouts.
    var sessionEdits: [SessionEdit]?
    /// What the app learned about the member's exercise likes and dislikes (#299).
    var taste: MemberTaste?
    /// Affinities this week's plan is generated with (#299): frozen when a new week's plan is made, so learning
    /// never reshuffles the week in progress.
    var weekTaste: [String: Double]?
    /// "Learn from my choices" off (#299): nothing recorded, plans made without learned tastes.
    var tasteOff: Bool?
    /// What this week's plan changed because of learned tastes, for the coach's new-week card (#299).
    var tasteRecap: TasteRecap?

    /// Training profile with this week's learned tastes (#299): quick sessions and plan variations.
    var tasteProfile: Profile {
        var p = profile
        p.learnedTaste = weekTaste
        return p
    }

    /// Profile the plan is generated from: the training profile plus this week's per-workout overrides.
    var planProfile: Profile {
        var p = tasteProfile
        p.sessionStyles = sessionStyles?.filter { $0.key.hasPrefix("w\(week)s") }
        return p
    }
}

struct LocalState: Codable {
    var ownerId: String?
    var synced: SyncedProfile?
    var plan: WeekPlan?
    var done: [String: Bool] = [:]
    var ticked: [String: Bool] = [:]
    /// Missed sessions the member chose to skip this week (#266). Optional so older state files still decode.
    var skipped: [String: Bool]?
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
    /// Climbs not yet on the server / deleted here but not yet there (#312).
    var pendingClimbIds: Set<UUID>?
    var deletedClimbIds: Set<UUID>?
    /// Climbs logged before #312 lived only here: uploaded once, then this is true.
    var climbsUploaded: Bool?
    // Machine setup notes (#355). Photos live in their own files (`MachineNotePhotos`).
    var machineNotes: [MachineNote]?
    var pendingMachineNoteIds: Set<UUID>?
    var deletedMachineNoteIds: Set<UUID>?
    /// Notes whose photo changed here (new or removed) and isn't on the server yet.
    var pendingMachinePhotoIds: Set<UUID>?
    // Custom exercises (#52). Archived, never deleted.
    var customExerciseList: [CustomExercise]?
    var pendingCustomExerciseIds: Set<UUID>?
    // PR attempts (#60). Optional so older state files still decode.
    var prAttempts: [PRAttempt]?
    var pendingPRAttemptIds: Set<UUID>?
    var deletedPRAttemptIds: Set<UUID>?
    // Body measurements (#185). Optional so older state files still decode.
    var measurements: [BodyMeasurement]?
    var pendingMeasurementIds: Set<UUID>?
    var deletedMeasurementIds: Set<UUID>?
    // Server deletes still to send: undone workouts (#133) and the set logs removed with them or with a PR attempt.
    // Kept until the server confirms, so a full pull can't bring them back. Optional so older state files still decode.
    var deletedWorkoutIds: Set<UUID>?
    var deletedLogIds: Set<UUID>?
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
    /// Finish early (#300): the workout re-fitted to the time left, and when the member has to be done.
    var fitted: [Block]? = nil
    var fitEnd: Date? = nil
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

    func wipe() {
        try? FileManager.default.removeItem(at: url)
        MachineNotePhotos.wipe()
    }
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
        skipped = try? c.decodeIfPresent([String: Bool].self, forKey: .skipped)
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
        pendingClimbIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingClimbIds)
        deletedClimbIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .deletedClimbIds)
        climbsUploaded = try? c.decodeIfPresent(Bool.self, forKey: .climbsUploaded)
        machineNotes = try? c.decodeIfPresent([MachineNote].self, forKey: .machineNotes)
        pendingMachineNoteIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingMachineNoteIds)
        deletedMachineNoteIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .deletedMachineNoteIds)
        pendingMachinePhotoIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingMachinePhotoIds)
        activeWorkout = try? c.decodeIfPresent(ActiveWorkout.self, forKey: .activeWorkout)
        customExerciseList = try? c.decodeIfPresent([CustomExercise].self, forKey: .customExerciseList)
        pendingCustomExerciseIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingCustomExerciseIds)
        prAttempts = try? c.decodeIfPresent([PRAttempt].self, forKey: .prAttempts)
        pendingPRAttemptIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingPRAttemptIds)
        deletedPRAttemptIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .deletedPRAttemptIds)
        measurements = try? c.decodeIfPresent([BodyMeasurement].self, forKey: .measurements)
        pendingMeasurementIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingMeasurementIds)
        deletedMeasurementIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .deletedMeasurementIds)
        deletedWorkoutIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .deletedWorkoutIds)
        deletedLogIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .deletedLogIds)
    }
}
