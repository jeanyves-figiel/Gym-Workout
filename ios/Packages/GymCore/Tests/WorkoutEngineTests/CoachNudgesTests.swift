import Foundation
import Testing
@testable import WorkoutEngine

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Zurich")!
    return c
}()

private func date(_ s: String) -> Date {
    let f = DateFormatter()
    f.calendar = cal
    f.timeZone = cal.timeZone
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
}

private func record(_ at: String, session: String = "push", bench: Double = 82.5, setsDone: Int = 3) -> WorkoutRecord {
    WorkoutRecord(
        id: UUID(), startedAt: date(at), durationSec: 50 * 60, sessionId: session, week: 1, deload: false, focus: .push, title: "Push day",
        exercises: [
            ExerciseRecord(uid: "a", exerciseId: "bench-press", category: .strength, setsDone: setsDone, setsPlanned: 3, reps: 8, weightKg: bench),
            ExerciseRecord(uid: "b", exerciseId: "db-bench", category: .strength, setsDone: 3, setsPlanned: 3, reps: 10, weightKg: 20),
        ],
        kcal: nil, avgHeartRate: nil, maxHeartRate: nil, muscleLoad: [:])
}

/// Personal Coach nudges (#876): A reminder text, C comeback offer.
@Suite struct CoachNudgesTests {
    @Test func reminderQuotesLastTimeAndTheNumberToBeat() throws {
        let n = try #require(CoachNudges.reminder(title: "Push", sessionId: "push", focus: .push, estMin: 50,
                                                  day: date("2026-10-19 00:00"), history: [record("2026-10-12 18:00")], calendar: cal))
        #expect(n.title == "Today: Push")
        #expect(n.body == "Last Monday you did 82.5 kg on barbell bench press. Go get 85 kg. 50 min.")
        #expect(n.facts.contains("Suggested: 85 kg on Barbell bench press"))
    }

    @Test func reminderAsksToFinishSetsFirstAndFallsBackToFocus() throws {
        let n = try #require(CoachNudges.reminder(title: "Push", sessionId: "new", focus: .push, estMin: 50,
                                                  day: date("2026-10-13 00:00"), history: [record("2026-10-12 18:00", setsDone: 2)], calendar: cal))
        #expect(n.body.hasPrefix("Yesterday you did 82.5 kg"))
        #expect(n.body.contains("All 3 sets at 82.5 kg today."))
        #expect(CoachNudges.reminder(title: "Legs", sessionId: "legs", focus: .legs, estMin: 50, day: date("2026-10-13 00:00"),
                                     history: [record("2026-10-12 18:00")], calendar: cal) == nil)
    }

    @Test func usualStartIsTheMedianToFiveMinutes() {
        let h = ["2026-10-05 18:00", "2026-10-07 18:10", "2026-10-09 17:50", "2026-10-12 18:05"].map { record($0) }
        #expect(CoachNudges.usualStart(h, calendar: cal) == 18 * 60 + 5)
        #expect(CoachNudges.usualStart(Array(h.prefix(3)), calendar: cal) == nil)
        let n = CoachNudges.reminder(title: "Push", sessionId: "push", focus: nil, estMin: 50, day: date("2026-10-19 00:00"), history: h, calendar: cal)
        #expect(n?.body.hasSuffix("50 min, you usually start around 18:05.") == true)
    }

    @Test func comebackOnlyWhenDrifting() throws {
        let h = [record("2026-10-12 18:00")]
        let at = date("2026-10-16 12:00")
        let missed = [date("2026-10-14 00:00"), date("2026-10-15 00:00")]
        let n = try #require(CoachNudges.comeback(missedDays: missed, focus: .upper, history: h, fireAt: at, calendar: cal))
        #expect(n.title == "Busy week?")
        #expect(n.body == "A 20-min upper body session fits your lunch break. Want it?")
        #expect(CoachNudges.comeback(missedDays: Array(missed.prefix(1)), focus: .upper, history: h, fireAt: at, calendar: cal) == nil)
        // Missed before the last workout don't count.
        #expect(CoachNudges.comeback(missedDays: [date("2026-10-10 00:00"), date("2026-10-11 00:00")], focus: .upper, history: h,
                                     fireAt: at, calendar: cal) == nil)
    }

    @Test func longBreakOffersTheComebackQuest() throws {
        let n = try #require(CoachNudges.comeback(missedDays: [], focus: .legs, history: [record("2026-10-07 12:00")],
                                                  fireAt: date("2026-10-19 17:00"), calendar: cal))
        #expect(n.title == "12 days away?")
        #expect(n.body == "A 20-min legs session starts your Comeback quest, +100 XP. Want it?")
    }

    @Test func comebackSlotsAndOncePerDrift() {
        let p = NotificationPrefs()
        #expect(CoachNudges.comebackFireAt(now: date("2026-10-16 09:00"), prefs: p, calendar: cal) == date("2026-10-16 12:00"))
        #expect(CoachNudges.comebackFireAt(now: date("2026-10-16 13:00"), prefs: p, calendar: cal) == date("2026-10-16 17:00"))
        #expect(CoachNudges.comebackFireAt(now: date("2026-10-16 18:00"), prefs: p, calendar: cal) == date("2026-10-17 12:00"))
        #expect(CoachNudges.driftKey(history: [record("2026-10-12 18:00")], calendar: cal) == "comeback|2026-10-12")
        #expect(CoachNudges.driftKey(history: [], calendar: cal) == "comeback|none")
    }

    @Test func prefsDecodeWithoutComebackKey() throws {
        let p = try JSONDecoder().decode(NotificationPrefs.self, from: Data(#"{"moveNudges":false}"#.utf8))
        #expect(p.comebackNudge && !p.moveNudges)
    }
}
