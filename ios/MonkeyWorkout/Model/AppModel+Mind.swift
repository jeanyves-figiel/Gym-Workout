import Foundation
import WorkoutEngine

/// Mind (#834): today's Mind score inputs from the check-in, Health and history; check-ins and calm sessions saved
/// to `MindStore` and Apple Health.
extension AppModel {
    /// Days (start of day) with a finished workout, daily routines left out (a stretch isn't training load).
    func workoutDays(since: Date) -> Set<Date> {
        let cal = planCalendar
        return Set(state.history.filter { $0.startedAt >= since && Routine.of(sessionId: $0.sessionId) == nil }
            .map { cal.startOfDay(for: $0.startedAt) })
    }

    func mindInputs(now: Date = Date()) -> MindScore.Inputs {
        let cal = planCalendar
        let store = MindStore.shared
        let snap = health?.snapshot
        let since = cal.date(byAdding: .day, value: -(MindScore.loadDays - 1), to: cal.startOfDay(for: now)) ?? now
        return MindScore.Inputs(mood: store.checkIn(on: now)?.mood, hrv: snap?.hrv, hrvBaseline: snap?.hrvBaseline,
                                sleepHours: snap?.sleepHours, workoutDays: workoutDays(since: since).count,
                                calmMinutes: store.calmMinutes(on: now))
    }

    /// Today's Mind score, nil without a check-in, HRV or sleep.
    var mindScore: Int? { MindScore.score(mindInputs()) }

    /// Coach's breathing pick for now.
    var mindPick: (breath: Breath, why: String) {
        let i = mindInputs()
        return MindScore.coachPick(mood: i.mood, hrvRatio: i.hrvRatio, hour: planCalendar.component(.hour, from: Date()))
    }

    /// Coach's pattern from the last 28 days of check-ins, nil until there are enough.
    var mindPattern: String? {
        let cal = planCalendar
        let now = Date()
        let since = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now)) ?? now
        return MindScore.pattern(checkIns: MindStore.shared.saved.checkIns, workoutDays: workoutDays(since: since), now: now, calendar: cal)
    }

    /// Saves today's score for the week bars (called when a Mind card shows).
    func recordMindScore() {
        if let s = mindScore { MindStore.shared.record(score: s) }
    }

    func checkIn(mood: Int, feelings: [MindFeeling]) {
        let c = MindCheckIn(date: Date(), mood: mood, feelings: feelings)
        MindStore.shared.addCheckIn(c)
        recordMindScore()
        guard !demo else { return }
        Task { await health?.saveCheckIn(c) }
    }

    /// A breathing or relax session finished (or stopped after a minute or more): mindful minutes. `healthAfter`
    /// seconds: Health gets it only if the session is still saved then (Undo of a stopped session takes it back).
    @discardableResult
    func finishCalm(_ breath: Breath, from start: Date, to end: Date, healthAfter: Double = 0) -> MindSession? {
        let seconds = Int(end.timeIntervalSince(start))
        guard seconds >= 60 else { return nil }
        let m = MindSession(date: start, breath: breath, seconds: seconds)
        MindStore.shared.addSession(m)
        recordMindScore()
        guard !demo else { return m }
        Task {
            if healthAfter > 0 { try? await Task.sleep(nanoseconds: UInt64(healthAfter * 1_000_000_000)) }
            guard MindStore.shared.saved.sessions.contains(m) else { return }
            await health?.saveMindful(from: start, to: end)
        }
        return m
    }
}
