import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct AppModulesTests {
    @Test func levelsSetModules() {
        let w = AppModules(level: .workouts)
        #expect(w.on == [.insights])
        let p = AppModules(level: .plan)
        #expect(p.on == [.plan, .coach, .insights])
        #expect(AppModules.everything.on == AppModule.allCases)
        #expect(AppModules.everything.off.isEmpty)
    }

    @Test func toggleFollowsLevel() {
        var m = AppModules(level: .workouts)
        m.set(.plan, on: true)
        #expect(m.level == nil)
        #expect(m.summary == "2 of \(AppModule.allCases.count)")
        m.set(.coach, on: true)
        #expect(m.level == .plan)
        #expect(m.summary == "Follow a plan")
        // Turning off twice keeps one entry.
        m.set(.coach, on: false)
        m.set(.coach, on: false)
        #expect(m.off.filter { $0 == "coach" }.count == 1)
    }

    @Test func unknownNamesSurviveAndLevelDecodesTolerant() throws {
        let json = #"{"level":"zen","off":["fuel","hologram"]}"#.data(using: .utf8)!
        let m = try JSONDecoder().decode(AppModules.self, from: json)
        #expect(m.level == .everything)
        #expect(!m.shows(.fuel))
        #expect(m.shows(.social))
        #expect(m.off.contains("hologram"))
    }

    @Test func trainLayoutDropsOffWidgets() {
        let l = TrainLayout.classic(coach: true, levelBar: true, climber: true)
        let simple = l.showing(AppModules(level: .workouts))
        for w in simple.widgets {
            if let module = w.kind.module { #expect(module == .insights) }
        }
        #expect(simple.widgets.contains { $0.kind == .nextUp })
        #expect(!simple.widgets.contains { $0.kind == .coach })
        #expect(l.showing(.everything) == l)
    }
}
