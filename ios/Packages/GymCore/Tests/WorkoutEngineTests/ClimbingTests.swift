import Foundation
import Testing
@testable import WorkoutEngine

/// Climbing gym exercises and the Wall session (#366).
@Suite struct ClimbingTests {
    @Test func climbingExercisesAreLibraryOnlyAndGrouped() {
        #expect(Climbing.ids.count == 25)
        #expect(Set(Climbing.ids).count == Climbing.ids.count)
        for id in Climbing.ids { #expect(Exercise.find(id) != nil, "\(id)") }
        for e in Exercise.climbingCatalog {
            #expect(Climbing.ids.contains(e.id), "\(e.id) not in a group")
            #expect(Exercise.libraryOnlyIds.contains(e.id), "\(e.id)")
            #expect(!e.generator, "\(e.id)")
        }
        // Every MonkeyGrade name points at a real exercise; the new wall drills all carry one.
        for id in Climbing.monkeyGradeSlug.keys { #expect(Exercise.find(id) != nil, "\(id)") }
        for g in [Climbing.Group.warmup, .cooldown] {
            for id in g.ids { #expect(Exercise.get(id).monkeyGradeSlug != nil, "\(id)") }
        }
        let used = Set(Exercise.catalog.flatMap(\.equipment))
        for eq in [Equipment.hangboard, .climbingWall, .liftBlock] {
            #expect(used.contains(eq), "\(eq) has no exercise")
            #expect(GymArea.of(eq) == .climbing)
        }
    }

    @Test func wallDaysResolveToPlayableSessions() {
        let all = WallSession.templates
        #expect(Set(all.map(\.sessionId)).count == all.count)
        for t in all {
            #expect(WorkoutTemplate.find(sessionId: t.sessionId) == t)
            #expect(!WorkoutTemplate.all.contains(t))
            for it in t.items { #expect(Exercise.find(it.exerciseId) != nil, "\(t.id): \(it.exerciseId)") }
            #expect(t.session.estMin > 0 && t.session.estMin <= 40, "\(t.id) \(t.session.estMin) min")
        }
        for d in WallDay.allCases {
            #expect(!d.parts.isEmpty)
            #expect(!d.summary.isEmpty)
        }
        // Climbing days: warm-up, the climbing, then after; the climb itself is not played here.
        #expect(WallDay.bouldering.parts.map(\.id) == ["wall-boulder-before", "climb", "wall-boulder-after"])
        #expect(WallDay.rest.parts.count == 1)
        // Warm-ups only warm up; nothing heavy before the wall.
        for t in [WallSession.boulderBefore, WallSession.hangboardBefore, WallSession.ropeBefore] {
            #expect(t.session.blocks.map(\.kind) == [.warmup], "\(t.id)")
        }
        // After bouldering: no pulling or heavy grip (antagonists only).
        #expect(WallSession.boulderAfter.items.allSatisfy { !Exercise.get($0.exerciseId).gripHeavy })
    }

    @Test func wallSessionIsOnByDefault() throws {
        #expect(Profile().climbDayAddon == nil)
        var p = Profile()
        p.climbDayAddon = false
        #expect(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p)).climbDayAddon == false)
    }
}
