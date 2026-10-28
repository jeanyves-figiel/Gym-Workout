import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct WeekReviewTests {
    private let digest = WeekReviewDigest(
        weekOf: "2026-10-26",
        days: [.init(weekday: 1, title: "Push", done: true), .init(weekday: 4, title: "Legs", done: false)],
        next: [
            .init(id: "w2-push", weekday: 1, title: "Push", lifts: [.init(uid: "a", name: "Bench press", sets: 4), .init(uid: "b", name: "Dips", sets: 8)]),
            .init(id: "w2-legs", weekday: 4, title: "Legs", lifts: [.init(uid: "c", name: "Back squat", sets: 4)]),
        ],
        offDays: [6]
    )

    private func review(_ changes: [WeekReviewChange]) -> WeekReview {
        WeekReview(weekOf: "2026-10-26", score: 140, headline: "  4 of 5 done  ", summary: "Strong week.", changes: changes)
    }

    @Test func keepsChangesTheAppCanMake() {
        let r = review([
            .init(kind: .move, sessionId: "w2-legs", weekday: 2, label: "Move legs to Tue"),
            .init(kind: .lighter, sessionId: "w2-push", weekday: 5, uid: "a", label: "Lighter Mon"),
            .init(kind: .addSet, sessionId: "w2-push", uid: "a", label: "+1 set bench"),
        ]).cleaned(for: digest)
        #expect(r.score == 100)
        #expect(r.headline == "4 of 5 done")
        #expect(r.changes.map(\.kind) == [.move, .lighter, .addSet])
        #expect(r.changes[1].weekday == nil && r.changes[1].uid == nil)
    }

    @Test func dropsUnknownOrImpossibleChanges() {
        let r = review([
            .init(kind: .move, sessionId: "nope", weekday: 2, label: "Unknown"),
            .init(kind: .move, sessionId: "w2-legs", weekday: 6, label: "Onto a day off"),
            .init(kind: .move, sessionId: "w2-legs", weekday: 1, label: "Onto another workout"),
            .init(kind: .move, sessionId: "w2-legs", weekday: 4, label: "Same day"),
            .init(kind: .addSet, sessionId: "w2-push", uid: "b", label: "Already at max sets"),
            .init(kind: .addSet, sessionId: "w2-push", uid: "zz", label: "Unknown lift"),
            .init(kind: .lighter, sessionId: "w2-push", label: "   "),
        ]).cleaned(for: digest)
        #expect(r.changes.isEmpty)
    }

    @Test func skipTakesNoOtherChangeAndAtMostThree() {
        let r = review([
            .init(kind: .skip, sessionId: "w2-legs", label: "Skip legs"),
            .init(kind: .lighter, sessionId: "w2-legs", label: "Lighter legs"),
            .init(kind: .lighter, sessionId: "w2-push", label: "Lighter push"),
            .init(kind: .lighter, sessionId: "w2-push", label: "Twice"),
            .init(kind: .addSet, sessionId: "w2-push", uid: "a", label: "+1 bench"),
            .init(kind: .move, sessionId: "w2-push", weekday: 3, label: "Push to Wed"),
        ]).cleaned(for: digest)
        #expect(r.changes.map(\.label) == ["Skip legs", "Lighter push", "+1 bench"])
    }

    @Test func reviewsOnSundayAndMonday() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = TimeZone(identifier: "UTC")!
        let sunday = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 18)))
        let monday = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 8)))
        let tuesday = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 3)))
        let reviewed = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 26)))
        #expect(WeekReview.reviewedWeek(on: sunday, calendar: cal) == reviewed)
        #expect(WeekReview.reviewedWeek(on: monday, calendar: cal) == reviewed)
        #expect(WeekReview.reviewedWeek(on: tuesday, calendar: cal) == nil)
    }

    @Test func lighterAndAddSetChangeSetsAndTime() {
        func item(_ uid: String, sets: Int, group: String? = nil) -> PlannedExercise {
            PlannedExercise(uid: uid, exerciseId: "bench-press", slot: .hPush,
                            prescription: Prescription(sets: sets, reps: "8", restSec: 90), group: group, estSec: sets * 100)
        }
        let blocks = [
            Block(kind: .warmup, title: "Warm-up", targetMin: 5, items: [item("w", sets: 2)]),
            Block(kind: .strength, title: "Strength", targetMin: 40, items: [item("a", sets: 4, group: "A1"), item("b", sets: 4, group: "A2"), item("c", sets: 1)]),
        ]
        let light = blocks.lighter()
        #expect(light[0].items[0].prescription.sets == 2)
        #expect(light[1].items.map(\.prescription.sets) == [3, 3, 1])
        #expect(light[1].items[0].estSec == 300)
        let more = blocks.addingSet("a")
        #expect(more[1].items.map(\.prescription.sets) == [5, 5, 1])
        #expect(blocks.addingSet("c")[1].items.map(\.prescription.sets) == [4, 4, 2])
    }
}

@Suite struct WeekReviewDigestTests {
    private let monday = Date(timeIntervalSince1970: 1_793_000_000)

    private func record(_ daysAgo: Double, _ exerciseId: String, kg: Double) -> WorkoutRecord {
        var r = WorkoutRecord(id: UUID(), startedAt: monday.addingTimeInterval(daysAgo * 86_400), durationSec: 3600, sessionId: "s", week: 1,
                              deload: false, focus: .push, title: "Push", exercises: [], kcal: nil, avgHeartRate: nil, maxHeartRate: nil, muscleLoad: [:])
        r.exercises = [ExerciseRecord(uid: "u", exerciseId: exerciseId, category: .strength, setsDone: 3, setsPlanned: 3, reps: 5, weightKg: kg)]
        return r
    }

    @Test func bestsAreNewHighsOfTheWeek() {
        let id = "bench-press"
        let recs = [record(-7, id, kg: 82.5), record(1, id, kg: 85), record(-3, "back-squat", kg: 120), record(2, "back-squat", kg: 110)]
        let bests = WeekReviewDigest.bests(records: recs, from: monday, to: monday.addingTimeInterval(7 * 86_400))
        #expect(bests.count == 1)
        #expect(bests[0].hasSuffix("85 kg (was 82.5)"))
    }

    @Test func moodAverageAndWhatWeighed() {
        let c = [
            MindCheckIn(date: monday.addingTimeInterval(3600), mood: 2, feelings: [.work, .sleep]),
            MindCheckIn(date: monday.addingTimeInterval(86_400), mood: 1, feelings: [.work]),
            MindCheckIn(date: monday.addingTimeInterval(2 * 86_400), mood: 5, feelings: [.family]),
            MindCheckIn(date: monday.addingTimeInterval(-86_400), mood: 1, feelings: [.money]),
        ]
        let m = WeekReviewDigest.mood(c, from: monday, to: monday.addingTimeInterval(7 * 86_400))
        #expect(m.average == 2.7)
        #expect(m.about == ["Work", "Sleep"])
        #expect(WeekReviewDigest.mood([], from: monday, to: monday).average == nil)
    }
}
