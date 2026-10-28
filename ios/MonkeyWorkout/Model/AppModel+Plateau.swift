import Foundation
import WorkoutEngine

// Plateau explainer (#875): stalled lifts from history, for the exercise page and the finish screen.
extension AppModel {
    /// The lift when it is stalled; nil otherwise or without the on-device Coach.
    func stalledLift(_ exerciseId: String) -> StalledLift? {
        guard OnDeviceCoach.available else { return nil }
        return Plateaus.stalled(exerciseId, records: state.history, sessionsPerWeek: profile?.sessionsPerWeek ?? 3,
                                sleepHours: health?.snapshot.sleepHours, style: setStyle(exerciseId), calendar: planCalendar)
    }

    /// The longest stalled lift of a workout just done.
    func stalledLift(in record: WorkoutRecord) -> StalledLift? {
        guard OnDeviceCoach.available else { return nil }
        return Plateaus.stalled(in: record, records: state.history, sessionsPerWeek: profile?.sessionsPerWeek ?? 3,
                                sleepHours: health?.snapshot.sleepHours, styles: state.synced?.setStyles ?? [:],
                                calendar: planCalendar).first
    }
}
