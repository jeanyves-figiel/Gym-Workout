import Foundation
import WorkoutEngine

/// Customisable Train screen (#260): the member's widget layout, synced with the profile.
extension AppModel {
    /// Default Train screen for the member's game look and climbing.
    var classicTrainLayout: TrainLayout {
        let style = WatchHomePref.shared.style
        return .classic(coach: style == .coach, levelBar: style == .rings, climber: profile.map(Generator.isClimber) ?? false)
    }

    /// What Train shows: the member's layout, else the default (today's screen).
    var trainLayout: TrainLayout { state.synced?.trainLayout ?? classicTrainLayout }
    /// What Train shows: the layout without widgets of hidden tabs (#1004). Kept in the layout, back when the tab is.
    var visibleTrainLayout: TrainLayout {
        var l = trainLayout
        if !TabsPref.shared.shows(.fuel) { l.widgets.removeAll { $0.kind == .fuel } }
        return l
    }

    var trainLayoutCustomised: Bool { state.synced?.trainLayout != nil }

    func presetLayout(_ p: TrainLayout.Preset) -> TrainLayout {
        let style = WatchHomePref.shared.style
        return .preset(p, coach: style == .coach, levelBar: style == .rings, climber: profile.map(Generator.isClimber) ?? false)
    }

    /// Preset the current layout matches, if any.
    var trainPreset: TrainLayout.Preset? {
        guard trainLayoutCustomised else { return .classic }
        return TrainLayout.Preset.allCases.first { trainLayout.matches(presetLayout($0)) }
    }

    /// Saves the layout; the classic one is stored as nil so it keeps following the game look.
    func setTrainLayout(_ layout: TrainLayout?) {
        guard state.synced != nil else { return }
        let stored = layout.flatMap { $0.matches(classicTrainLayout) ? nil : $0 }
        guard state.synced?.trainLayout != stored else { return }
        state.synced?.trainLayout = stored
        state.profileDirty = true
        persist()
        Task { await sync() }
    }

    /// Style changed (#681): an edited layout swaps the old look's card for the new one's, like the default does.
    func restyleTrainLayout() {
        guard let saved = state.synced?.trainLayout else { return }
        let style = WatchHomePref.shared.style
        setTrainLayout(saved.restyled(coach: style == .coach, levelBar: style == .rings))
    }

    func editTrainLayout(_ change: (inout TrainLayout) -> Void) {
        var l = trainLayout
        change(&l)
        setTrainLayout(l)
    }
}
