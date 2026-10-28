import Foundation

/// Personal Coach nudges (#876, designs A + C from `ai-epic/e2.png`). Timing stays by rules (the member's reminder times,
/// quiet hours); the words come from their own history. The on-device model may reword `facts`; this text is the fallback
/// and what iPhones without Apple Intelligence get. Nothing leaves the phone.
public struct CoachNudge: Equatable, Sendable {
    public var title: String
    public var body: String
    /// Plain facts for the on-device model.
    public var facts: [String]

    public init(title: String, body: String, facts: [String] = []) {
        self.title = title
        self.body = body
        self.facts = facts
    }
}

public enum CoachNudges {
    /// Planned sessions missed since the last workout before Coach calls it drifting (C).
    public static let driftMissed = 2
    /// Length of the comeback offer's workout.
    public static let comebackMinutes = 20
    /// Workouts it takes to know when the member usually starts.
    static let usualMinRecords = 4

    // MARK: A · smart reminder text

    /// The session reminder in the member's words: the last time they did this session (or this focus), its top lift and
    /// the number to beat, and when they usually start. Nil without a matching workout: the plain reminder stays.
    public static func reminder(title: String, sessionId: String, focus: Focus?, estMin: Int, day: Date,
                                history: [WorkoutRecord], calendar: Calendar) -> CoachNudge? {
        let earlier = history.filter { $0.startedAt < calendar.startOfDay(for: day) }.sorted { $0.startedAt > $1.startedAt }
        guard let last = earlier.first(where: { $0.sessionId == sessionId }) ?? focus.flatMap({ f in earlier.first { $0.focus == f } })
        else { return nil }
        let when = relativeDay(last.startedAt, from: day, calendar: calendar)
        var facts = ["Today's workout: \(title), \(estMin) min", "Last time: \(last.title), \(when.lowercased())"]
        var lines: [String] = []
        let lifts = last.exercises.filter { $0.setsDone > 0 && ($0.weightKg ?? 0) > 0 && $0.category != .warmup }
        if let top = lifts.max(by: { strength($0) < strength($1) }), let w = top.weightKg {
            let name = Exercise.find(top.exerciseId)?.name ?? top.exerciseId
            let reps = top.reps.map { " × \(Int($0.rounded()))" } ?? ""
            facts.append("\(name): \(WorkoutRecap.kg(w)) kg\(reps), \(top.setsDone) of \(top.setsPlanned) sets")
            lines.append("\(when) you did \(WorkoutRecap.kg(w)) kg on \(name.lowercased()).")
            if top.setsDone >= top.setsPlanned {
                let next = w + (w >= 20 ? 2.5 : 1)
                facts.append("Suggested: \(WorkoutRecap.kg(next)) kg on \(name)")
                lines.append("Go get \(WorkoutRecap.kg(next)) kg.")
            } else {
                facts.append("Suggested: all \(top.setsPlanned) sets at \(WorkoutRecap.kg(w)) kg")
                lines.append("All \(top.setsPlanned) sets at \(WorkoutRecap.kg(w)) kg today.")
            }
        } else {
            lines.append("\(when): \(last.title), \(last.totalSets) sets. Beat it.")
        }
        if let usual = usualStart(history, calendar: calendar) {
            facts.append("Usually starts around \(NotificationPrefs.clock(usual))")
            lines.append("\(estMin) min, you usually start around \(NotificationPrefs.clock(usual)).")
        } else {
            lines.append("\(estMin) min.")
        }
        return CoachNudge(title: "Today: \(title)", body: lines.joined(separator: " "), facts: facts)
    }

    /// Minute of day the member usually starts (median of the last 12 workouts, to 5 min); nil with too few.
    public static func usualStart(_ history: [WorkoutRecord], calendar: Calendar) -> Int? {
        let recent = history.sorted { $0.startedAt > $1.startedAt }.prefix(12)
        guard recent.count >= usualMinRecords else { return nil }
        let minutes = recent.map { calendar.component(.hour, from: $0.startedAt) * 60 + calendar.component(.minute, from: $0.startedAt) }.sorted()
        let median = minutes[minutes.count / 2]
        return min(1435, Int((Double(median) / 5).rounded()) * 5)
    }

    // MARK: C · comeback nudge

    /// Once per drift: the last workout's day (or "none"), so a new workout starts a new count.
    public static func driftKey(history: [WorkoutRecord], calendar: Calendar) -> String {
        history.map(\.startedAt).max().map { "comeback|" + ReminderPlanner.dayKey($0, calendar: calendar) } ?? "comeback|none"
    }

    /// One kind, specific offer when the member drifts: `driftMissed` planned sessions missed since their last workout,
    /// or the Comeback quest's "welcome back" (`Comeback.gapDays` away), which the offer then starts. Nil when on track.
    /// `missedDays`: days of planned sessions missed and not skipped; `fireAt`: when it shows (sets "lunch" or "evening").
    public static func comeback(missedDays: [Date], focus: Focus, history: [WorkoutRecord], fireAt: Date, calendar: Calendar) -> CoachNudge? {
        let last = history.map(\.startedAt).max()
        let missed = missedDays.filter { d in last.map { calendar.startOfDay(for: d) > calendar.startOfDay(for: $0) } ?? true }.count
        let away = Comeback.current(records: history, now: fireAt).flatMap { $0.done == 0 ? $0.daysAway : nil }
        guard missed >= driftMissed || away != nil else { return nil }
        let what = "\(comebackMinutes)-min \(label(focus)) session"
        let slot = calendar.component(.hour, from: fireAt) < 15 ? "your lunch break" : "before dinner"
        var facts = ["Offer: a \(what), now or tonight at 19:00"]
        if let away {
            facts.append("\(away) days since the last workout; the first one back starts the Comeback quest, +\(Comeback.xpPerSession) XP a session")
            return CoachNudge(title: "\(away) days away?",
                              body: "A \(what) starts your Comeback quest, +\(Comeback.xpPerSession) XP. Want it?", facts: facts)
        }
        facts.append("\(missed) planned sessions missed this week")
        return CoachNudge(title: "Busy week?", body: "A \(what) fits \(slot). Want it?", facts: facts)
    }

    /// Next comeback slot after `now`: 12:00 or 17:00 today, else 12:00 tomorrow, moved out of quiet hours.
    public static func comebackFireAt(now: Date, prefs: NotificationPrefs, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        let soon = now.addingTimeInterval(5 * 60)
        for (offset, minutes) in [(0, 12 * 60), (0, 17 * 60), (1, 12 * 60)] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let at = ReminderPlanner.fireDate(day: day, minutes: minutes, prefs: prefs, calendar: calendar), at > soon else { continue }
            return at
        }
        return nil
    }

    /// "upper body", "legs", "chest & triceps".
    public static func label(_ f: Focus) -> String {
        switch f {
        case .fullUpper, .upper: "upper body"
        case .fullLower, .lower: "lower body"
        case .fullPower: "full-body power"
        case .push: "push"
        case .pull: "pull"
        case .legs: "legs"
        case .conditioning: "conditioning"
        case .chestTri: "chest & triceps"
        case .backBi: "back & biceps"
        case .shouldersArms: "shoulders & arms"
        case .chestBack: "chest & back"
        case .posterior: "posterior chain"
        }
    }

    // MARK: Helpers

    private static func strength(_ e: ExerciseRecord) -> Double { e.estimatedOneRepMax ?? e.weightKg ?? 0 }

    /// "Yesterday", "Last Monday" (within a week of `day`), else "On 12 Oct".
    static func relativeDay(_ date: Date, from day: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: day)).day ?? 0
        if days == 1 { return "Yesterday" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        if days <= 7 {
            f.dateFormat = "EEEE"
            return "Last \(f.string(from: date))"
        }
        f.dateFormat = "d MMM"
        return "On \(f.string(from: date))"
    }
}
