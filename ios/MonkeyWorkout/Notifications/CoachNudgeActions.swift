import Foundation
import WorkoutEngine

/// "Start 20′ now" or "Tonight 19:00" on the comeback nudge (#876 C).
struct ComebackPick: Equatable, Sendable {
    var focus: Focus
    var tonight: Bool
}

extension AppModel {
    /// Days this week's planned sessions were missed and not skipped (#876 C).
    var missedDays: [Date] {
        let cal = planCalendar
        let start = WeekPlan.weekStart(of: Date(), calendar: cal)
        return missedSessions.compactMap { s in s.weekday.flatMap { cal.date(byAdding: .day, value: $0 - 1, to: start) } }
    }

    /// What the comeback offer trains: the first missed session's focus, else the next one's.
    var comebackFocus: Focus { (missedSessions.first ?? nextSession)?.focus ?? .fullUpper }

    /// The offer taken: a 20-min generated session of `focus` added to today (it counts for the Comeback quest like any
    /// workout). Now → straight in the player on Train; tonight → a 19:00 reminder for it.
    func acceptComeback(_ pick: ComebackPick) async {
        guard let s = quickSession(pick.focus, minutes: CoachNudges.comebackMinutes),
              let insert = addExtra(CustomWorkout(name: "Comeback · \(pick.focus.quickLabel)"), generated: s, weekday: todayWeekday),
              let added = plan?.sessions.first(where: { $0.planInsertId == insert.id }) else { return }
        tab = .train
        if pick.tonight {
            await NotificationManager.shared.scheduleTonight(added)
        } else {
            PlayerLaunch.shared.sessionId = added.id
        }
    }
}
