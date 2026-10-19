import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct TrainLayoutTests {
    @Test func classicMatchesTodaysTrainScreen() {
        let l = TrainLayout.classic(coach: true, levelBar: false, climber: true)
        #expect(l.widgets.map(\.kind) == [.actions, .coach, .programme, .week, .nextUp, .move, .fuel, .climbing, .thisWeek])
        #expect(l.widgets.first { $0.kind == .nextUp }?.size == .large)
        let rings = TrainLayout.classic(coach: false, levelBar: true, climber: false)
        #expect(rings.widgets.map(\.kind) == [.actions, .programme, .week, .level, .nextUp, .move, .fuel, .thisWeek])
    }

    @Test func smallWidgetsPairUp() {
        let l = TrainLayout([TrainWidget(.streak), TrainWidget(.records), TrainWidget(.body), TrainWidget(.week, size: .wide), TrainWidget(.level, size: .small)])
        let rows = l.rows
        #expect(rows.count == 4)
        guard case .pair(let a, let b) = rows[0] else { Issue.record("expected pair"); return }
        #expect(a.kind == .streak && b?.kind == .records)
        guard case .pair(let c, nil) = rows[1] else { Issue.record("expected lone small"); return }
        #expect(c.kind == .body)
        guard case .full(let w) = rows[2] else { Issue.record("expected full"); return }
        #expect(w.kind == .week)
        guard case .pair(let d, nil) = rows[3] else { Issue.record("expected trailing small"); return }
        #expect(d.kind == .level)
    }

    @Test func sizesAndLooksStayValid() {
        #expect(TrainWidget(.actions, size: .small).size == .wide)
        #expect(TrainWidget(.calendar, look: .kg).look == nil)
        #expect(TrainWidget(.calendar).resolvedLook == .week)
        var w = TrainWidget(.nextUp, size: .small)
        #expect(w.nextSize == .wide)
        w.size = .large
        #expect(w.nextSize == .small)
        var l = TrainLayout([TrainWidget(.thisWeek)])
        l.update(l.widgets[0].id) { $0.size = .small }
        #expect(l.widgets[0].size == .large)
    }

    @Test func addRemoveMove() {
        var l = TrainLayout([TrainWidget(.week), TrainWidget(.nextUp)])
        l.add(.week)
        #expect(l.widgets.count == 2)
        l.add(.streak, at: 1)
        #expect(l.widgets.map(\.kind) == [.week, .streak, .nextUp])
        l.move(l.widgets[2].id, to: l.widgets[0].id)
        #expect(l.widgets.map(\.kind) == [.nextUp, .week, .streak])
        l.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(l.widgets.map(\.kind) == [.week, .streak, .nextUp])
        l.remove(l.widgets[1].id)
        #expect(l.widgets.map(\.kind) == [.week, .nextUp])
        #expect(!l.addable.contains(.week) && l.addable.contains(.streak))
    }

    @Test func presetsMatch() {
        let data = TrainLayout.preset(.data, coach: true, levelBar: false, climber: false)
        #expect(data.matches(TrainLayout.preset(.data, coach: false, levelBar: true, climber: true)))
        #expect(!data.matches(TrainLayout.preset(.minimal, coach: true, levelBar: false, climber: false)))
        for p in TrainLayout.Preset.allCases {
            let l = TrainLayout.preset(p, coach: true, levelBar: false, climber: true)
            #expect(Set(l.widgets.map(\.kind)).count == l.widgets.count)
        }
    }

    @Test func roundTripsAndSkipsUnknownWidgets() throws {
        let l = TrainLayout.preset(.data, coach: true, levelBar: false, climber: false)
        let back = try JSONDecoder().decode(TrainLayout.self, from: JSONEncoder().encode(l))
        #expect(back == l)
        let json = """
        {"widgets":[{"id":"\(UUID().uuidString)","kind":"hologram","size":"wide"},
                    {"id":"\(UUID().uuidString)","kind":"calendar","size":"huge","look":"year"},
                    {"id":"\(UUID().uuidString)","kind":"streak","size":"small"}]}
        """
        let decoded = try JSONDecoder().decode(TrainLayout.self, from: Data(json.utf8))
        #expect(decoded.widgets.map(\.kind) == [.calendar, .streak])
        #expect(decoded.widgets[0].size == .wide && decoded.widgets[0].look == nil)
    }
}

@Suite struct TrainWidgetIdTests {
    @Test func defaultLayoutKeepsIds() {
        let a = TrainLayout.classic(coach: true, levelBar: false, climber: true)
        let b = TrainLayout.classic(coach: true, levelBar: false, climber: true)
        #expect(a == b)
        #expect(Set(TrainWidgetKind.allCases.map(\.stableId)).count == TrainWidgetKind.allCases.count)
    }
}
