import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct InsightsFocusTests {
    @Test func suggestedFromGoal() {
        #expect(InsightsFocus.suggested(for: .strength) == .strength)
        #expect(InsightsFocus.suggested(for: .build) == .muscle)
        #expect(InsightsFocus.suggested(for: .endurance) == .endurance)
        #expect(InsightsFocus.suggested(for: .climbing) == .sport)
        #expect(InsightsFocus.suggested(for: .balanced) == .everything)
        #expect(InsightsFocus.suggested(for: nil) == .everything)
    }

    @Test func focusMovesWidgetsFirstAndKeepsEverything() {
        let classic = ProgressBoard.classic
        for focus in InsightsFocus.allCases {
            let b = classic.focused(on: focus, sports: [.run])
            // Nothing removed.
            for w in classic.widgets { #expect(b.contains(w.kind)) }
            let lead = focus.leading(sports: [.run])
            #expect(Array(b.widgets.prefix(lead.count)).map(\.kind) == lead.map(\.kind))
        }
        let s = classic.focused(on: .strength, sports: [])
        #expect(s.widgets.prefix(4).map(\.kind) == [.records, .programmes, .weekly, .training])
        #expect(s.widgets.count == classic.widgets.count)
        // Sizes the member picked are kept.
        #expect(s.widgets.first { $0.kind == .programmes }?.size == .small)
    }

    @Test func sportFocusAddsSportWidgets() {
        let b = ProgressBoard.classic.focused(on: .sport, sports: [.snowboard, .run, .hyrox])
        #expect(b.widgets.prefix(3).map(\.sport) == [.snowboard, .run, nil])
        #expect(b.widgets[0].size == .large)
        #expect(b.widgets.count == ProgressBoard.classic.widgets.count + 2)
    }

    @Test func everythingKeepsBoard() {
        let b = ProgressBoard.preset(.lifter, sports: [])
        #expect(b.focused(on: .everything, sports: []).matches(b))
    }

    @Test func unknownFocusDecodesAsEverything() throws {
        let f = try JSONDecoder().decode([InsightsFocus].self, from: Data(#"["mind","newer"]"#.utf8))
        #expect(f == [.mind, .everything])
    }
}
