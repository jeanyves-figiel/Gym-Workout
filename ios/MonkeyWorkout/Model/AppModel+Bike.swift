import Foundation
import WorkoutEngine

/// Cycling with sensors (#623): FTP for power zones, set by hand or by the Watch's 20′ test.
extension AppModel {
    var bikeFTP: Int? { state.synced?.bikeFTP }
    var bikeFTPTestedAt: Date? { state.synced?.bikeFTPTestedAt }

    func setBikeFTP(_ watts: Int?, testedAt: Date? = nil) {
        guard var sp = state.synced else { return }
        sp.bikeFTP = watts.map { min(2000, max(50, $0)) }
        if let testedAt { sp.bikeFTPTestedAt = testedAt }
        guard sp != state.synced else { return }
        state.synced = sp
        state.profileDirty = true
        persist()
        WatchSync.shared.push()
        Task { await sync() }
    }
}
