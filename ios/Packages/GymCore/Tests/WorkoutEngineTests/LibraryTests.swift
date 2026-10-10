import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct LibraryTests {
    private let profile = Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate, climbingDaysPerWeek: 0)
    private let push = CustomWorkout(
        name: "Push day",
        items: [.init(exerciseId: "bench-press", sets: 4, reps: 8, restSec: 120), .init(exerciseId: "dips")],
        createdAt: Date(timeIntervalSince1970: 1_790_000_000))

    @Test func visibilityRoundTripsAndDefaultsToPrivate() throws {
        var w = push
        #expect(w.visibility == .private)
        w.visibility = .members
        let back = try JSONDecoder().decode(CustomWorkout.self, from: JSONEncoder().encode(w))
        #expect(back == w)

        // Older records without the field, unknown values and the server's read-only flag.
        let json = """
        {"id":"\(UUID().uuidString)","name":"Legs","items":[],"visibility":"friends","hidden":true,"saves":3}
        """
        let old = try JSONDecoder().decode(CustomWorkout.self, from: Data(json.utf8))
        #expect(old.visibility == .private)
        #expect(old.hidden)
        // `hidden` is never sent back.
        let sent = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        #expect(!sent.contains("hidden"))
    }

    @Test func decodesSharedWorkoutsAndCopiesThemPrivately() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString.lowercased())","name":"Engine builder","visibility":"members","saves":12,"sharedAt":"2026-10-10T10:00:00.000Z",
         "author":{"userId":"u1","nickname":"lea_climbs","avatarUrl":null},
         "items":[{"id":"\(UUID().uuidString)","exerciseId":"rower","sets":1,"reps":10,"restSec":60}]}
        """
        let s = try JSONDecoder().decode(SharedWorkout.self, from: Data(json.utf8))
        #expect(s.id == id && s.author.nickname == "lea_climbs" && s.saves == 12)
        #expect(s.workout.sessionId == CustomWorkout(id: id, name: "x").sessionId)

        let copy = s.copy()
        #expect(copy.id != s.id && copy.name == "Engine builder" && copy.visibility == .private)
        #expect(copy.items.map(\.exerciseId) == ["rower"] && copy.items[0].id != s.items[0].id)
    }

    @Test func replacesAndAddsPlanSessions() {
        let plan = Generator.generateWeek(profile, week: 2, seed: 7)
        let replace = PlanInsert(week: 2, replacing: 1, workout: push)
        let extra = PlanInsert(week: 2, weekday: 6, workout: push)
        let otherWeek = PlanInsert(week: 3, replacing: 0, workout: push)
        let outOfRange = PlanInsert(week: 2, replacing: 9, workout: push)

        let p = plan.applying([replace, extra, otherWeek, outOfRange])
        #expect(p.sessions.count == plan.sessions.count + 1)
        #expect(p.sessions[0] == plan.sessions[0])
        #expect(p.sessions[1].id == replace.sessionId)
        #expect(p.sessions[1].index == 1 && p.sessions[1].weekday == plan.sessions[1].weekday)
        #expect(p.sessions[1].displayTitle == "Push day" && p.sessions[1].isPlanInsert)
        #expect(p.sessions[1].planInsertId == replace.id)
        #expect(p.sessions.last!.id == extra.sessionId && p.sessions.last!.weekday == 6 && p.sessions.last!.index == plan.sessions.count)

        // Unique ids: ticks never mix with the library copy or another insert of the same workout.
        let uids = p.sessions.flatMap { $0.blocks.flatMap(\.items) }.map(\.uid)
        #expect(Set(uids).count == uids.count)
        #expect(!uids.contains { push.session.blocks[0].items.map(\.uid).contains($0) })
        #expect(p.sessions[1].blocks[0].items.allSatisfy { $0.uid.hasPrefix(replace.sessionId) })

        #expect(plan.applying([]) == plan)
        #expect(plan.applying([otherWeek]) == plan)
        #expect(!plan.sessions[0].isPlanInsert && plan.sessions[0].planInsertId == nil)
    }

    @Test func planInsertsRoundTrip() throws {
        let ins = [PlanInsert(week: 1, replacing: 0, workout: push), PlanInsert(week: 1, weekday: 3, workout: push)]
        #expect(try JSONDecoder().decode([PlanInsert].self, from: JSONEncoder().encode(ins)) == ins)
    }
}
