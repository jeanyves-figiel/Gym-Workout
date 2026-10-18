import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct ProgressBoardTests {
    @Test func classicIsTodaysPage() {
        let b = ProgressBoard.classic
        #expect(b.widgets.map(\.kind) == [.level, .streak, .training, .body, .records, .badges, .muscles, .programmes, .history, .consistency, .weekly])
        #expect(b.rows.count == 8)
    }

    @Test func sportWidgetsOnePerSport() {
        var b = ProgressBoard([])
        b.add(.sport(.climbing))
        b.add(.sport(.hyrox, size: .large))
        b.add(.sport(.climbing, size: .large))
        #expect(b.widgets.map(\.sport) == [.climbing, .hyrox])
        #expect(b.widgets[0].id != b.widgets[1].id)
        #expect(b.contains(sport: .hyrox))
        #expect(!b.addable.contains(.sport))
        #expect(ProgressWidget(.streak, sport: .ski).sport == nil)
    }

    @Test func sizesStayValid() {
        #expect(ProgressWidget(.level, size: .small).size == .wide)
        var b = ProgressBoard([.sport(.run)])
        #expect(b.widgets[0].size == .small)
        b.update(b.widgets[0].id) { $0.size = $0.nextSize }
        #expect(b.widgets[0].size == .wide)
        b.update(b.widgets[0].id) { $0.size = .large }
        #expect(b.widgets[0].nextSize == .small)
    }

    @Test func roundTripsAndSkipsUnknown() throws {
        let b = ProgressBoard.preset(.sports, sports: [.climbing, .snowboard])
        let data = try JSONEncoder().encode(b)
        #expect(try JSONDecoder().decode(ProgressBoard.self, from: data) == b)
        let json = #"{"widgets":[{"kind":"streak","size":"huge"},{"kind":"rocket"},{"kind":"sport","sport":"hyrox","size":"large"}]}"#
        let d = try JSONDecoder().decode(ProgressBoard.self, from: Data(json.utf8))
        #expect(d.widgets.map(\.kind) == [.streak, .sport])
        #expect(d.widgets[0].size == .wide)
        #expect(d.widgets[1].sport == .hyrox && d.widgets[1].size == .large)
    }

    @Test func presetsMatch() {
        let p = ProgressBoard.preset(.lifter, sports: [])
        #expect(p.matches(ProgressBoard.preset(.lifter, sports: [.run])))
        #expect(!p.matches(.classic))
        #expect(ProgressBoard.preset(.sports, sports: []).widgets.first?.sport == .climbing)
    }

    @Test func moves() {
        var b = ProgressBoard.classic
        let streak = b.widgets[1].id, level = b.widgets[0].id
        b.move(streak, to: level)
        #expect(b.widgets.prefix(2).map(\.kind) == [.streak, .level])
    }
}
