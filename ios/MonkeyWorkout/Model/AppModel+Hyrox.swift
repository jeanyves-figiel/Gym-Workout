import APIClient
import Foundation
import LiftSensor
import WorkoutEngine

/// Hyrox (#426): settings from the hub, races recorded on the Watch (kept as sport sessions with their splits),
/// and what the Watch needs to race without the iPhone.
extension AppModel {
    var hyroxProfile: HyroxProfile { profile?.hyrox ?? HyroxProfile() }

    var hyroxDivision: HyroxDivision {
        let p = hyroxProfile
        return HyroxDivision(HyroxDivision.Category(rawValue: p.category) ?? .open, HyroxDivision.Group(rawValue: p.group) ?? .men)
    }

    var hyroxGoalSeconds: Double? { hyroxProfile.goalMinutes.map { Double($0) * 60 } }

    /// The Hyrox sport plan (days, race date), when the member added Hyrox to My sports.
    var hyroxPlan: SportPlan? { profile?.sports?.first { $0.sport == .hyrox } }

    /// Shows the hub entry: Hyrox is one of their sports, or they recorded a race.
    var doesHyrox: Bool { hyroxPlan != nil || profile?.hyrox != nil || !hyroxRaces.isEmpty }

    /// Races and sims recorded on the Watch, newest first.
    var hyroxRaces: [HyroxRace] { sportLogs.compactMap(\.hyrox) }

    /// Last full race before `race` (or the last one), for the report and the PB.
    func lastFullRace(before race: HyroxRace? = nil) -> HyroxRace? {
        hyroxRaces.first { $0.format == .full && $0.complete && $0.start < (race?.start ?? .distantFuture) && $0.id != race?.id }
    }

    func saveHyroxProfile(_ p: HyroxProfile) {
        guard var prof = profile, prof.hyrox != p else { return }
        prof.hyrox = p
        updateProfile(prof)
    }

    /// From the Watch (queued) or fixed in the report: one sport session with the race, same id as the Health
    /// workout, so Spotted shows it once and Health is not written again.
    func saveHyroxRace(_ race: HyroxRace) {
        let existing = sportLogs.first { $0.id == race.id }
        var log = existing ?? SportLog(id: race.id, sport: .hyrox, start: race.start, effort: race.format == .full ? 9 : 8, fromHealth: true)
        log.sport = .hyrox
        log.start = race.start
        log.minutes = max(1, Int((race.total / 60).rounded()))
        log.hyrox = race
        saveSport(log)
    }

    /// Settings, last race and upload key for the Watch snapshot.
    func watchHyrox(start: (format: HyroxFormat, at: Date)?) -> WHyrox? {
        // A start from the iPhone goes through even before Hyrox is in My sports (Explore, Track live: #439).
        guard doesHyrox || start != nil else { return nil }
        if watchUploadKey == nil { Task { await fetchWatchUploadKey() } }
        return WHyrox(division: hyroxDivision, goalSeconds: hyroxGoalSeconds, raceName: hyroxProfile.raceName,
                      raceDate: hyroxPlan?.event, lastRace: lastFullRace(), uploadKey: watchUploadKey,
                      apiBase: AppConfig.apiBaseURL.absoluteString, start: start?.format, startAt: start?.at)
    }

    /// One upload-only key per account; the Watch posts races with it when it has a network.
    /// Every snapshot build asks while the key is missing: one request at a time.
    private static var fetchingUploadKey = false

    func fetchWatchUploadKey() async {
        guard phase == .signedIn, !demo, watchUploadKey == nil, !Self.fetchingUploadKey else { return }
        Self.fetchingUploadKey = true
        defer { Self.fetchingUploadKey = false }
        let owner = state.ownerId
        // Signed out or another account meanwhile: that key isn't this account's.
        guard let key = try? await api.watchUploadKey(), phase == .signedIn, state.ownerId == owner,
              watchUploadKey == nil else { return }
        watchUploadKey = key
        Self.uploadKeyItem.save(Data(key.utf8))
        WatchSync.shared.push()
    }

    /// The key is a credential: this device's Keychain (after first unlock, for background snapshots), not state.json (#432).
    private static let uploadKeyItem = KeychainItem(service: AppConfig.keychainService, account: "watchUploadKey")

    /// At launch, after `state` is loaded: moves a key an older build kept in state.json to the Keychain.
    func loadWatchUploadKey() {
        if let legacy = state.watchUploadKey {
            Self.uploadKeyItem.save(Data(legacy.utf8))
            state.watchUploadKey = nil
            persist()
        }
        watchUploadKey = Self.uploadKeyItem.load().flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Sign-out, another account, reinstall.
    func clearWatchUploadKey() {
        watchUploadKey = nil
        Self.uploadKeyItem.clear()
    }
}
