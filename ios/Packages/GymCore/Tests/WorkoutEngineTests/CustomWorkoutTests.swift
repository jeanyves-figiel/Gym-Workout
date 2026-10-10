import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct CustomWorkoutTests {
    private let sample = CustomWorkout(
        name: "Push day",
        items: [
            .init(exerciseId: "bench-press", sets: 4, reps: 8, restSec: 120),
            .init(exerciseId: "plank", sets: 3, reps: 45, restSec: 60, kcal: 12),
            .init(exerciseId: "dips", kcal: 40),
        ],
        createdAt: Date(timeIntervalSince1970: 1_790_000_000))

    @Test func codableRoundTrip() throws {
        // Default strategies (local store) and ISO 8601 (API).
        let local = try JSONDecoder().decode(CustomWorkout.self, from: JSONEncoder().encode(sample))
        #expect(local == sample)

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let api = try dec.decode(CustomWorkout.self, from: enc.encode(sample))
        #expect(api == sample)
    }

    @Test func decodesServerRecordsLeniently() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","name":"Legs","updatedAt":"2026-10-07T10:00:00.000Z",
         "items":[{"exerciseId":"back-squat"},{"id":"\(UUID().uuidString)","exerciseId":"leg-press","sets":5,"reps":12,"restSec":60,"kcal":30}]}
        """
        let w = try JSONDecoder().decode(CustomWorkout.self, from: Data(json.utf8))
        #expect(w.id == id)
        #expect(w.items.count == 2)
        #expect(w.items[0].sets == 3 && w.items[0].reps == 10 && w.items[0].restSec == CustomWorkout.defaultRestSec && w.items[0].kcal == nil)
        #expect(w.items[1].sets == 5 && w.items[1].kcal == 30)
        #expect(w.kcal == 30)
    }

    @Test func convertsToPlayableSession() {
        let s = sample.session
        #expect(s.id == sample.sessionId)
        #expect(s.isCustom && s.isStandalone && !s.isExample)
        #expect(s.displayTitle == "Push day")
        #expect(s.blocks.count == 1)
        #expect(s.blocks[0].kind == .strength)
        let items = s.blocks[0].items
        #expect(items.map(\.exerciseId) == ["bench-press", "plank", "dips"])
        #expect(items[0].prescription.sets == 4 && items[0].prescription.reps == "8" && items[0].prescription.restSec == 120)
        #expect(items[1].prescription.reps == "45 s") // time-based exercise
        #expect(items[1].prescription.note == "≈ 12 kcal")
        #expect(Set(items.map(\.uid)).count == 3)
        #expect(s.estMin > 0)

        // History works off the converted session.
        var done: [String: Int] = [:]
        for it in items { done[it.uid] = it.prescription.sets }
        let r = WorkoutRecord.build(session: s, week: 1, deload: false, setsDone: done, weights: ["bench-press": 60],
                                    startedAt: Date(), endedAt: Date().addingTimeInterval(1800), bodyMassKg: 70)
        #expect(r.sessionId == sample.sessionId)
        #expect(r.title == "Push day")
        #expect(r.totalSets == 10)
        #expect(r.volumeKg == 4 * 8 * 60)
    }

    @Test func uidsSurviveReorderAndEdit() {
        var w = sample
        let before = Dictionary(uniqueKeysWithValues: w.session.blocks[0].items.map { ($0.exerciseId, $0.uid) })
        w.items.reverse()
        w.items[0].sets = 5
        w.name = "Renamed"
        let after = w.session
        #expect(after.id == sample.sessionId)
        for it in after.blocks[0].items { #expect(before[it.exerciseId] == it.uid) }
    }

    @Test func skipsUnknownExercisesButKeepsThem() {
        var w = sample
        w.items.insert(.init(exerciseId: "from-a-future-catalog"), at: 1)
        #expect(w.items.count == 4)
        #expect(w.playableItems.count == 3)
        #expect(w.session.blocks[0].items.count == 3)
    }

    @Test func emptyWorkoutHasEmptySession() {
        let s = CustomWorkout(name: "Empty").session
        #expect(s.blocks.flatMap(\.items).isEmpty)
        #expect(s.estMin == 0)
    }

    @Test func singleCategoryUsesMatchingBlock() {
        let w = CustomWorkout(name: "Run", items: [.init(exerciseId: "rower", sets: 1, reps: 20)])
        let s = w.session
        #expect(s.blocks[0].kind == .cardio)
        #expect(s.focus == .conditioning)
        #expect(s.blocks[0].items[0].prescription.reps == "20 min")
        #expect(s.estMin == 21) // 20 min work + 1 min setup
    }

    @Test func addingPicksDefaultsPerMeasure() {
        let bench = CustomWorkout.Item(adding: Exercise.get("bench-press"))
        #expect(bench.sets == 3 && bench.reps == 10 && bench.restSec == CustomWorkout.defaultRestSec)
        #expect(CustomWorkout.Measure(Exercise.get("bench-press")) == .reps)
        let plank = CustomWorkout.Item(adding: Exercise.get("plank"))
        #expect(plank.reps == 30)
        #expect(CustomWorkout.Measure(Exercise.get("plank")) == .seconds)
        let rower = CustomWorkout.Item(adding: Exercise.get("rower"))
        #expect(rower.sets == 1 && rower.reps == 10)
        #expect(CustomWorkout.Measure(Exercise.get("rower")) == .minutes)
    }

    @Test func duplicatesExampleIntoEditableCopy() {
        let t = WorkoutTemplate.armsShoulder
        let c = CustomWorkout(duplicating: t)
        #expect(c.name == "Arms + Shoulder (copy)")
        #expect(c.items.map(\.exerciseId) == t.items.map(\.exerciseId))
        #expect(c.items.map(\.kcal) == t.items.map(\.kcal))
        #expect(c.items.allSatisfy { $0.sets == 3 && $0.reps == 10 && $0.restSec == WorkoutTemplate.restSec })
        #expect(c.session.blocks[0].items.count == t.session.blocks[0].items.count)
        #expect(!c.session.isExample)

        let d = c.duplicated()
        #expect(d.id != c.id)
        #expect(Set(d.items.map(\.id)).isDisjoint(with: c.items.map(\.id)))
        #expect(d.items.map(\.exerciseId) == c.items.map(\.exerciseId))
    }

    @Test func sanitizesInput() {
        var w = CustomWorkout(name: "   ", items: [.init(exerciseId: "dips", sets: 0, reps: 9999, restSec: -5, kcal: -1)])
        w = w.sanitized
        #expect(w.name == "My workout")
        #expect(w.items[0].sets == 1 && w.items[0].reps == 600 && w.items[0].restSec == 0 && w.items[0].kcal == 0)
        #expect(CustomWorkout(name: String(repeating: "x", count: 300)).sanitized.name.count == CustomWorkout.maxNameLength)
    }

    @Test func searchesCatalog() {
        #expect(Exercise.search().count == Exercise.catalog.count)
        #expect(Exercise.search("bench").contains { $0.id == "bench-press" })
        #expect(Exercise.search("BARBELL bench").contains { $0.id == "bench-press" })
        #expect(Exercise.search(category: .stretch).allSatisfy { $0.category == .stretch })
        let lats = Exercise.search(muscle: .lats)
        #expect(!lats.isEmpty && lats.allSatisfy { $0.muscles.contains(.lats) })
        #expect(Exercise.search("lats", category: .strength).contains { $0.id == "pull-up" })
        #expect(Exercise.search("zzzz-nothing").isEmpty)
        let names = Exercise.search().map(\.name)
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }
}
