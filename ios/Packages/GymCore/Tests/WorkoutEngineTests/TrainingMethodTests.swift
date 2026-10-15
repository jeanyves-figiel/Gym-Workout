import Foundation
import Testing
@testable import WorkoutEngine

private func profile(_ method: TrainingMethod?, goal: Goal = .balanced, sessions: Int = 4) -> Profile {
    Profile(goal: goal, sessionsPerWeek: sessions, experience: .intermediate, climbingDaysPerWeek: 0, method: method)
}

/// Strength blocks (not circuits) of a generated week, in session order.
private func strength(_ plan: WeekPlan) -> [Block] {
    plan.sessions.compactMap { s in s.blocks.first { $0.kind == .strength && $0.title == "Strength" } }
}

private let day0 = ISO8601DateFormatter().date(from: "2026-09-07T10:00:00Z")!
private let squat = Exercise.get("back-squat")

private func logged(_ kg: Double, _ reps: [Int], rir: Int?) -> ExerciseSession {
    let sets = reps.enumerated().map { i, r in
        SetLog(date: day0.addingTimeInterval(Double(i) * 180), exerciseId: squat.id, sessionId: "w2s1", setIndex: i, kg: kg, reps: r, rir: rir)
    }
    return ExerciseSession(date: day0, sessionId: "w2s1", week: 2, deload: false, sets: sets)
}

private let rx = Prescription(sets: 3, reps: "6–10", restSec: 120, intensity: "RPE 8")

@Suite struct TrainingMethodTests {
    @Test func defaultIsBlockAndOlderProfilesDecode() throws {
        let json = #"{"goal":"build","sessionsPerWeek":4,"experience":"beginner","climbingDaysPerWeek":0,"equipment":["dumbbells"]}"#
        let p = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        #expect(p.method == nil && p.trainingMethod == .block)
        // Explicit block = no method: same plan as before #156.
        for week in 1...4 {
            #expect(Generator.generateWeek(profile(nil), week: week, seed: 9) == Generator.generateWeek(profile(.block), week: week, seed: 9))
        }
    }

    @Test func dayZonesRotatePerSessionType() {
        // Upper / lower / upper / lower: each type gets two different zones.
        #expect(DayZone.of(firstIndex: 0, occurrence: 0) == .heavy)
        #expect(DayZone.of(firstIndex: 0, occurrence: 1) == .moderate)
        #expect(DayZone.of(firstIndex: 1, occurrence: 0) == .moderate)
        #expect(DayZone.of(firstIndex: 1, occurrence: 1) == .light)
        // Push / pull / legs twice: never the same zone twice for one type.
        let ppl = [0, 1, 2].map { f in Set([0, 1].map { DayZone.of(firstIndex: f, occurrence: $0) }) }
        #expect(ppl.allSatisfy { $0.count == 2 })
    }

    @Test func undulatingMainLiftRepsFollowTheDay() throws {
        let blocks = strength(Generator.generateWeek(profile(.undulating), week: 2, seed: 3))
        try #require(blocks.count == 4)
        let reps = blocks.map { $0.items[0].prescription.reps }
        #expect(reps[0].hasPrefix("3–5"))   // upper, heavy
        #expect(reps[1].hasPrefix("5–8"))   // lower, moderate (balanced goal's own range)
        #expect(reps[3].hasPrefix("10–12")) // lower, light
        #expect(blocks[0].note?.hasPrefix("Heavy day") == true)
    }

    @Test func minimalDoseIsShortWithTwoHardSets() {
        let p = profile(.minimal, goal: .build, sessions: 3)
        #expect(Generator.sessionMinutes(p) <= Generator.minimalSessionMinutes)
        #expect(p.group == .supersets)
        let plan = Generator.generateWeek(p, week: 1, seed: 4)
        for b in strength(plan) {
            #expect(b.items.filter { $0.supersetWith == nil }.count <= Generator.minimalStrengthItems)
            #expect(b.items.allSatisfy { $0.prescription.sets == 2 })
        }
        let groups = MuscleWorkoutOptions(groups: [.chest, .back], minutes: 45)
        #expect(CustomWorkout.generate(groups, profile: p, seed: 2).items.allSatisfy { $0.sets == 2 })
    }

    @Test func volumeSetsRiseThroughTheBlockThenDeload() {
        let p = profile(.volume)
        let weekly = (1...4).map { w in
            VolumeTargets.sets(Generator.generateWeek(p, week: w, seed: 6).sessions)
        }
        let total = weekly.map { s in VolumeTargets.tracked.reduce(0) { $0 + (s[$1] ?? 0) } }
        #expect(total[2] > total[0])
        #expect(total[3] < total[0])
        #expect(VolumeTargets.target(week: 1, experience: .intermediate) == 10)
        #expect(VolumeTargets.target(week: 3, experience: .advanced) == 18)
        #expect(VolumeTargets.target(week: 3, experience: .beginner) == 13)
    }

    @Test func volumeOnlyChangesAccessorySets() {
        let block = Generator.generateWeek(profile(nil), week: 3, seed: 8)
        let volume = Generator.generateWeek(profile(.volume), week: 3, seed: 8)
        #expect(block.sessions.map { $0.blocks.map { $0.items.map(\.exerciseId) } } == volume.sessions.map { $0.blocks.map { $0.items.map(\.exerciseId) } })
        for (a, b) in zip(strength(block), strength(volume)) {
            #expect(a.items[0].prescription.sets == b.items[0].prescription.sets)
            #expect(b.items.dropFirst().allSatisfy { $0.prescription.sets <= max(VolumeTargets.maxSetsPerExercise, 3) })
        }
    }

    @Test func autoregulatedLoadFollowsLoggedRIR() {
        let easy = [logged(100, [8, 8, 8], rir: 4)]
        // Block: reps below the top of 6–10 → hold.
        #expect(LoadAdvisor.suggest(exercise: squat, prescription: rx, week: 2, deload: false, history: easy)?.action == .hold)
        // Autoregulated: 4 RIR vs target 2 → +2 increments.
        let up = LoadAdvisor.suggest(exercise: squat, prescription: rx, week: 2, deload: false, history: easy, method: .autoregulated)
        #expect(up?.action == .increase && up?.kg == 105)
        let hard = [logged(100, [6, 6, 6], rir: 0)]
        let down = LoadAdvisor.suggest(exercise: squat, prescription: rx, week: 2, deload: false, history: hard, method: .autoregulated)
        #expect(down?.action == .decrease && down?.kg == 95)
    }

    @Test func autoregulatedUsesRatedSetsWhenSomeAreUnrated() {
        // Rating is optional in the player (#357): two rated sets at 4 RIR, one logged without a rating.
        var partial = logged(100, [8, 8, 8], rir: 4)
        partial.sets[1].rir = nil
        let up = LoadAdvisor.suggest(exercise: squat, prescription: rx, week: 2, deload: false, history: [partial], method: .autoregulated)
        #expect(up?.action == .increase && up?.kg == 105)
        // Nothing rated: the reps rules decide (8 of 6–10 → hold).
        let unrated = [logged(100, [8, 8, 8], rir: nil)]
        #expect(LoadAdvisor.suggest(exercise: squat, prescription: rx, week: 2, deload: false, history: unrated, method: .autoregulated)?.action == .hold)
    }

    @Test func easesInAfterTwoWeeksOff() {
        let history = [logged(100, [10, 10, 10], rir: 2)]
        let back = LoadAdvisor.suggest(exercise: squat, prescription: rx, week: 2, deload: false, history: history,
                                       now: day0.addingTimeInterval(20 * 86_400))
        #expect(back?.action == .decrease && back?.kg == 90)
        let soon = LoadAdvisor.suggest(exercise: squat, prescription: rx, week: 2, deload: false, history: history,
                                       now: day0.addingTimeInterval(5 * 86_400))
        #expect(soon?.action == .increase)
    }

    @Test func lowReadinessEasesTheSession() throws {
        let session = Generator.generateWeek(profile(.autoregulated), week: 2, seed: 5).sessions[0]
        let eased = session.easedForReadiness()
        let before = try #require(strength(WeekPlan(week: 2, deload: false, seed: 5, sessionMinutes: 60, sessions: [session])).first)
        let after = try #require(strength(WeekPlan(week: 2, deload: false, seed: 5, sessionMinutes: 60, sessions: [eased])).first)
        #expect(after.items.map(\.uid) == before.items.map(\.uid))
        #expect(after.items[0].prescription.sets == before.items[0].prescription.sets)
        for (a, b) in zip(before.items.dropFirst(), after.items.dropFirst()) where a.prescription.sets > 1 {
            #expect(b.prescription.sets == a.prescription.sets - 1)
        }
        if let rpe = before.items[0].prescription.rpeValue {
            #expect(after.items[0].prescription.rpeValue == rpe - 1)
        }
        #expect(eased.estMin <= session.estMin)
        #expect(after.note?.hasPrefix("Low readiness") == true)
    }

    @Test func everyMethodCitesSources() {
        for m in TrainingMethod.allCases {
            #expect(m.sources.count >= 2)
            #expect(m.sources.allSatisfy { $0.url?.host == "pubmed.ncbi.nlm.nih.gov" && $0.year >= 2000 })
        }
        #expect(Set(TrainingMethod.allCases.flatMap(\.sources)).count == TrainingMethod.allCases.reduce(0) { $0 + $1.sources.count })
    }
}
