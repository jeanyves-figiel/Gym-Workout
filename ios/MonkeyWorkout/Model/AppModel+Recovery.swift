import Foundation
import WorkoutEngine

/// Mobility & recovery days (#619): the rest-day routine (A) and the low-readiness swap (B).
extension AppModel {
    struct RecoverPick: Equatable {
        var area: Recovery.Area
        var template: WorkoutTemplate
        /// "Legs hit hard Mon + Wed".
        var why: String
    }

    /// Low readiness on a heavy day: today's session can move to a free later day, with a recover routine today.
    struct RecoverSwap: Equatable {
        var session: Session
        var to: Int
        /// "5H SLEEP", "HRV LOW".
        var marker: String
    }

    /// Routine for the area trained hardest in the last 7 days (finished workouts), full body when none stands out.
    func recoverPick(now: Date = Date()) -> RecoverPick {
        let cal = planCalendar
        let since = now.addingTimeInterval(-7 * 86_400)
        let records = state.history.filter { $0.startedAt >= since && $0.startedAt <= now }.map { r in
            (start: r.startedAt, load: Dictionary(r.muscleLoad.compactMap { k, v in Muscle(rawValue: k).map { ($0, v) } },
                                                  uniquingKeysWith: +))
        }
        var load: [Muscle: Double] = [:]
        for r in records { for (m, v) in r.load { load[m, default: 0] += v } }
        let area = Recovery.area(load)
        let days = Recovery.hardDays(records, area: area, calendar: cal)
        let why: String
        if days.isEmpty {
            why = records.isEmpty ? "Loosen up before the next session" : "Easy mobility for everything you trained"
        } else {
            let names = days.suffix(3).map { $0.formatted(.dateTime.weekday(.abbreviated)) }
            why = "\(area.label) hit hard \(names.joined(separator: " + "))"
        }
        return RecoverPick(area: area, template: Recovery.routine(area), why: why)
    }

    /// Readiness "Take it easier" on a day with a strength session not started: swap it to the next free day this week.
    var recoverSwap: RecoverSwap? {
        guard let snap = health?.snapshot, let assessed = Readiness.assess(snap), assessed.0 == .easy, let plan else { return nil }
        let today = todayWeekday
        guard let s = plan.sessions.first(where: { $0.weekday == today }), !doneIds.contains(s.id), activeWorkout(s.id) == nil,
              s.blocks.contains(where: { [.strength, .power].contains($0.kind) }) else { return nil }
        let taken = Set(plan.sessions.compactMap(\.weekday))
        guard let to = moveTargets(s.id).first(where: { $0 > today && !taken.contains($0) }) else { return nil }
        let marker: String
        if let sl = snap.sleepHours, sl < Readiness.minSleep {
            marker = "\(Int(sl.rounded(.down)))H SLEEP"
        } else {
            marker = assessed.1.first?.uppercased() ?? "LOW MARKERS"
        }
        return RecoverSwap(session: s, to: to, marker: marker)
    }

    /// Moves today's session to the swap's day; today becomes a rest day with the recover routine.
    func takeRecoverSwap(_ swap: RecoverSwap) {
        moveSession(swap.session.id, to: swap.to, swap: false)
    }
}
