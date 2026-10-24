import Foundation
import Testing
@testable import WorkoutEngine

/// Daily routines (#689).
@Suite struct RoutineTests {
    @Test func everyLengthFitsAndResolves() {
        #expect(Set(Routine.templates.map(\.sessionId)).count == Routine.templates.count)
        for r in Routine.allCases {
            #expect(r.lengths.contains(r.defaultLength))
            for m in r.lengths {
                let t = r.template(minutes: m)
                #expect(WorkoutTemplate.find(sessionId: t.sessionId) == t)
                #expect(Routine.of(sessionId: t.sessionId) == r)
                #expect(!WorkoutTemplate.all.contains(t))
                for it in t.items { #expect(Exercise.find(it.exerciseId) != nil, "\(t.id): \(it.exerciseId)") }
                #expect(abs(t.session.estMin - m) <= 2, "\(t.id) \(t.session.estMin) min")
            }
        }
        // Longer = more work.
        #expect(Routine.stretch.template(minutes: 30).items.count > Routine.stretch.template(minutes: 5).items.count)
        // Off-list lengths snap to the nearest one.
        #expect(Routine.desk.template(minutes: 30) == Routine.desk.template(minutes: 10))
    }

    @Test func dailyHangsStayLowLoad() throws {
        for m in Routine.hangs.lengths {
            let t = Routine.hangs.template(minutes: m)
            let hang = try #require(t.items.first { $0.exerciseId == "open-hand-hang" })
            #expect(hang.reps == 10 && hang.restSec == 50)
            #expect(hang.intensity == Routine.hangIntensity)
            #expect(t.session.blocks.flatMap(\.items).contains { $0.prescription.intensity == Routine.hangIntensity })
            // Never a max-hang or repeater session.
            #expect(!t.items.contains { ["max-hangs", "repeaters"].contains($0.exerciseId) })
        }
        #expect(Routine.hangs.template(minutes: 20).items.first { $0.exerciseId == "open-hand-hang" }!.sets
                > Routine.hangs.template(minutes: 5).items.first { $0.exerciseId == "open-hand-hang" }!.sets)
    }

    @Test func dailyDefaultsAndStreak() {
        #expect(Routine.dailyDefaults(climber: true) == [.stretch, .hangs])
        #expect(Routine.dailyDefaults(climber: false) == [.stretch, .morning])
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: today)! }
        #expect(Routine.stretch.streak([day(0), day(1), day(2), day(4)], today: today, calendar: cal) == 3)
        // Not yet done today: yesterday's streak still counts.
        #expect(Routine.stretch.streak([day(1), day(2)], today: today, calendar: cal) == 2)
        #expect(Routine.stretch.streak([day(2)], today: today, calendar: cal) == 0)
    }

    /// More built-ins and Train's add cards (#732).
    @Test func moreRoutinesAndCoachPick() {
        #expect(Routine.allCases.count == 11)
        #expect(Set(Routine.allCases.map(\.short)).count == Routine.allCases.count)
        #expect(Routine.rollout.kind == .recovery)
        #expect(Routine.rollout.template(minutes: 10).kit == "Foam roller")
        #expect(Routine.starters(climber: true).contains(.hangs))
        #expect(!Routine.starters(climber: false).contains(.hangs))
        #expect(Routine.coachPick(focus: .pull, climbing: false).routine == .shoulders)
        #expect(Routine.coachPick(focus: .legs, climbing: false).routine == .hips)
        #expect(Routine.coachPick(focus: .conditioning, climbing: false).routine == .legs)
        #expect(Routine.coachPick(focus: nil, climbing: false).routine == .rollout)
        #expect(Routine.coachPick(focus: .push, climbing: true).routine == .wrists)
    }
}
