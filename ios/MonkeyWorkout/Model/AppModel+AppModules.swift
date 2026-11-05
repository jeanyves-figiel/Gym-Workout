import Foundation
import WorkoutEngine

/// App level and modules (#1052, design A + B): picked at sign up, changed in Settings → My app. Synced with the
/// profile; nil = everything, so members from before see the app as it was.
extension AppModel {
    var appModules: AppModules { state.synced?.appModules ?? .everything }

    /// Whether a module is on.
    func shows(_ module: AppModule) -> Bool { appModules.shows(module) }

    func setAppLevel(_ level: AppLevel) {
        saveModules(AppModules(level: level))
    }

    func setModule(_ module: AppModule, on: Bool) {
        var m = appModules
        m.set(module, on: on)
        saveModules(m)
    }

    private func saveModules(_ m: AppModules) {
        guard state.synced != nil else { return }
        // A module just turned on shows its tab again on this device too (My tabs, #1004).
        let was = appModules
        for tab in MainTab.allCases {
            guard let module = tab.module, m.shows(module), !was.shows(module) else { continue }
            TabsPref.shared.set(tab, shown: true)
        }
        state.synced?.appModules = m == .everything ? nil : m
        state.profileDirty = true
        persist()
        Task { await sync() }
    }
}
