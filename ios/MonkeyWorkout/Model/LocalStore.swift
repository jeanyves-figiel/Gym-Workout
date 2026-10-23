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
    /// This week's per-workout session types (#342), keyed by session id ("w2s1"); dropped on a week change.
    var sessionFoci: [String: Focus]?
    /// Gyms the member set up, each with its own equipment (#162). Optional so older profiles still decode.
    var savedGyms: [SavedGym]?
    /// Training programme in progress (#255): replaces the plan while it runs. Optional so older profiles still decode.
    var programme: ActiveProgramme?
    /// Programmes finished or left (#255), newest last.
    var programmeHistory: [ProgrammeRecord]?
    /// Customised Train screen (#260); nil = the default layout.
    var trainLayout: TrainLayout?
    /// Customised Progress page (#444); nil = the default board.
    var progressBoard: ProgressBoard?
    /// Programmes the member made or copied (#269).
    var customProgrammes: [Programme]?
    /// Lift Focus block in progress (#499).
    var liftFocus: LiftFocus?
    /// Set style per exercise id (#499, Pro Sets); missing = straight sets.
    var setStyles: [String: SetStyle]?
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
    /// Growing with the member (#495): level, block reviews, long-term goal, weekly notices, the coach's memory.
    var growth: GrowthState?
    /// Sport add-on (#620 C): a 15′ sport block in a few gym sessions a week; nil = none.
    var sportAddOn: SportAddOnPref?
    /// Calisthenics skill tree (#621): best tests and the skill of the month.
    var skills: SkillProgress?
    /// Cycling FTP in watts (#623) and when it was last tested; power zones follow it.
    var bikeFTP: Int?
    var bikeFTPTestedAt: Date?
    /// Life-stage programme check-in (#625): due date, birth, weeks off, doctor's OK.
    var lifeStage: LifeStageCheckIn?
    /// New member onboarding (#664): steps done and the set-up card closed; nil = member from before it.
    var onboarding: OnboardingProgress?

    /// Training profile with this week's learned tastes (#299): quick sessions and plan variations.
    var tasteProfile: Profile {
        var p = profile
        p.learnedTaste = weekTaste
        // Longer warm-up cardio from 50 (#375).
        p.birthYear = body?.birthYear
        return p
    }

    /// Profile the plan is generated from: the training profile plus this week's per-workout overrides.
    var planProfile: Profile {
        var p = tasteProfile
        p.sessionStyles = sessionStyles?.filter { $0.key.hasPrefix("w\(week)s") }
        p.sessionFoci = sessionFoci?.filter { $0.key.hasPrefix("w\(week)s") }
        return p
    }
}

/// Growing with the member (#495). Every field optional so older profiles still decode.
struct GrowthState: Codable, Equatable, Sendable {
    /// Growth level; nil = the start of the member's experience band.
    var level: Int?
    /// Blocks reviewed so far.
    var blocks: Int?
    /// Monday ("yyyy-MM-dd") of the last block reviewed, applied or closed.
    var reviewedBlock: String?
    /// Long-term goal; nil = the suggested one.
    var goal: GrowthGoal?
    /// Monday of the week whose "Monkey noticed" bar was closed.
    var noticedClosed: String?
    /// What the member asked the coach to remember.
    var notes: [String]?
    /// Daily auto-tune off.
    var tuneOff: Bool?
}

/// Today's auto-tune choices (#495), on this device only: a picked level, sore muscle groups, undone changes.
struct DayTune: Codable, Equatable {
    /// "yyyy-MM-dd"; another day's choices don't apply.
    var day: String
    var level: TuneLevel?
    var sore: [MuscleGroup] = []
    var undone: [String] = []
}

struct LocalState: Codable {
    var ownerId: String?
    var synced: SyncedProfile?
    var plan: WeekPlan?
    var done: [String: Bool] = [:]
    var ticked: [String: Bool] = [:]
    /// Missed sessions the member chose to skip this week (#266). Optional so older state files still decode.
    var skipped: [String: Bool]?
    /// Sessions of later weeks skipped ahead (#671): that week's Monday ("yyyy-MM-dd") → session ids.
    var skippedAhead: [String: [String]]?
    /// Today's auto-tune choices (#495).
    var dayTune: DayTune?
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
    // Other sport sessions (#416), synced like climbs.
    var sportLogs: [SportLog]?
    var pendingSportIds: Set<UUID>?
    var deletedSportIds: Set<UUID>?
    /// Legacy (#426): the Watch upload key now lives in the Keychain (#432, `AppModel.watchUploadKey`).
    /// Still decoded so `AppModel.loadWatchUploadKey` can move it there; nil once moved, so never written again.
    var watchUploadKey: String?
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
    /// "Taken?" taps in the player (#406): learns when each gym zone is busy. Local only.
    var busyTaps: [BusyTap]?
    /// Build as I go (#490): the empty-start workout being built in the player, kept until the next one. Local only.
    var freestyle: Session?
    /// How the member felt after each workout (#501), `Feel` raw values by record id. Local only.
    var feels: [UUID: Int]?
    /// Apple effort 1–10 per workout (#614), by record id. Local only (Apple Health keeps its own copy).
    var efforts: [UUID: Int]?
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
    /// Saved as the app went to the background with the player open (#359): iOS may close a suspended app, so the
    /// next launch reopens the player, keeps counting the time and the rest still running.
    var interrupted: Bool? = nil
    var restEnd: Date? = nil
    var restTotal: Int? = nil
}

/// JSON file in Application Support, encrypted at rest by iOS data protection.
struct LocalStore {
    private let url: URL
    /// Saves and wipes run in order on one queue: a background save never lands after a later save or a wipe.
    private static let queue = DispatchQueue(label: "LocalStore.io", qos: .utility)
    private final class Wipes { var count = 0 }
    private let wipes = Wipes()

    init(filename: String = "state.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent(filename)
    }

    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    func load() -> LocalState {
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(LocalState.self, from: data) else { return LocalState() }
        return s
    }

    /// Times this store was wiped (main thread): a save planned before a wipe is dropped (`AppModel.persist`).
    var wipeCount: Int { wipes.count }

    /// Saves now, after any background save queued before it.
    func save(_ state: LocalState) {
        let url = url
        Self.queue.sync { Self.write(state, to: url) }
    }

    /// Encodes and writes off the calling thread, after any save queued before it.
    func saveInBackground(_ state: LocalState) {
        let url = url
        Self.queue.async { Self.write(state, to: url) }
    }

    private static func write(_ state: LocalState, to url: URL) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func wipe() {
        wipes.count += 1
        let url = url
        // After any queued save, so none brings the file back.
        Self.queue.sync { try? FileManager.default.removeItem(at: url) }
        MachineNotePhotos.wipe()
    }
}

extension LocalState {
    /// Lenient: missing keys fall back to defaults, so state files from older builds keep decoding.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        // Lists of records skip one that does not decode instead of losing the whole list.
        func lossy<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> LossyArray<T>? {
            try? c.decodeIfPresent(LossyArray<T>.self, forKey: key)
        }
        ownerId = try c.decodeIfPresent(String.self, forKey: .ownerId)
        synced = try? c.decodeIfPresent(SyncedProfile.self, forKey: .synced)
        plan = try? c.decodeIfPresent(WeekPlan.self, forKey: .plan)
        done = (try? c.decodeIfPresent([String: Bool].self, forKey: .done)) ?? [:]
        ticked = (try? c.decodeIfPresent([String: Bool].self, forKey: .ticked)) ?? [:]
        skipped = try? c.decodeIfPresent([String: Bool].self, forKey: .skipped)
        skippedAhead = try? c.decodeIfPresent([String: [String]].self, forKey: .skippedAhead)
        let logList = lossy(LogEntry.self, .logs)
        logs = logList?.elements ?? []
        pendingLogIds = (try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingLogIds)) ?? []
        lastLogPull = try? c.decodeIfPresent(Date.self, forKey: .lastLogPull)
        // Set logs lost here are still on the server: the next pull fetches them all again, not just the changes.
        if (logList == nil && c.contains(.logs)) || (logList?.skipped ?? 0) > 0 { lastLogPull = nil }
        profileDirty = (try? c.decodeIfPresent(Bool.self, forKey: .profileDirty)) ?? false
        history = lossy(WorkoutRecord.self, .history)?.elements ?? []
        pendingHistoryIds = (try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingHistoryIds)) ?? []
        lastHistoryPull = try? c.decodeIfPresent(Date.self, forKey: .lastHistoryPull)
        customWorkoutList = lossy(CustomWorkout.self, .customWorkoutList)?.elements
        pendingCustomWorkoutIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingCustomWorkoutIds)
        deletedCustomWorkoutIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .deletedCustomWorkoutIds)
        climbs = lossy(ClimbLog.self, .climbs)?.elements
        pendingClimbIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingClimbIds)
        deletedClimbIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .deletedClimbIds)
        climbsUploaded = try? c.decodeIfPresent(Bool.self, forKey: .climbsUploaded)
        sportLogs = lossy(SportLog.self, .sportLogs)?.elements
        watchUploadKey = try? c.decodeIfPresent(String.self, forKey: .watchUploadKey)
        pendingSportIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingSportIds)
        deletedSportIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .deletedSportIds)
        machineNotes = lossy(MachineNote.self, .machineNotes)?.elements
        pendingMachineNoteIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingMachineNoteIds)
        deletedMachineNoteIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .deletedMachineNoteIds)
        pendingMachinePhotoIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingMachinePhotoIds)
        activeWorkout = try? c.decodeIfPresent(ActiveWorkout.self, forKey: .activeWorkout)
        customExerciseList = lossy(CustomExercise.self, .customExerciseList)?.elements
        pendingCustomExerciseIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingCustomExerciseIds)
        prAttempts = lossy(PRAttempt.self, .prAttempts)?.elements
        pendingPRAttemptIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingPRAttemptIds)
        deletedPRAttemptIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .deletedPRAttemptIds)
        measurements = lossy(BodyMeasurement.self, .measurements)?.elements
        pendingMeasurementIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .pendingMeasurementIds)
        deletedMeasurementIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .deletedMeasurementIds)
        deletedWorkoutIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .deletedWorkoutIds)
        deletedLogIds = try? c.decodeIfPresent(Set<UUID>.self, forKey: .deletedLogIds)
        busyTaps = lossy(BusyTap.self, .busyTaps)?.elements
        freestyle = try? c.decodeIfPresent(Session.self, forKey: .freestyle)
        dayTune = try? c.decodeIfPresent(DayTune.self, forKey: .dayTune)
        feels = try? c.decodeIfPresent([UUID: Int].self, forKey: .feels)
        efforts = try? c.decodeIfPresent([UUID: Int].self, forKey: .efforts)
    }
}
