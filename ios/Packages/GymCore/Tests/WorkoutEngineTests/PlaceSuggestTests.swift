import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct PlaceSuggestTests {
    @Test func foldDropsAccentsAndPunctuation() {
        #expect(PlaceSuggest.fold("Zürich-Oerlikon ") == "zurich oerlikon")
        #expect(PlaceSuggest.fold("  Hotel  ADLON") == "hotel adlon")
    }

    @Test func townFromAddress() {
        #expect(PlaceSuggest.town(fromAddress: "Badenerstrasse 1, 8952 Schlieren, Switzerland") == "Schlieren")
        #expect(PlaceSuggest.town(fromAddress: "Unter den Linden 77, 10117 Berlin, Germany") == "Berlin")
        #expect(PlaceSuggest.town(fromAddress: "Main St, Springfield, USA") == "Springfield")
        #expect(PlaceSuggest.town(fromAddress: "") == nil)
    }

    @Test func typosStillMatch() {
        #expect(PlaceSuggest.distance("barcleona", "barcelona") == 1)
        #expect(PlaceSuggest.score("zurih", "Zürich") == 1)
        #expect(PlaceSuggest.score("zur", "Zürich") == 0)
        #expect(PlaceSuggest.score("oerl", "Zürich Oerlikon") == 0)
        #expect(PlaceSuggest.score("hotl adlon", "Hotel Adlon Kempinski") == 1)
        #expect(PlaceSuggest.score("paris", "Barcelona") == nil)
        #expect(PlaceSuggest.score("z", "Zürich") == nil)
    }

    @Test func correctionOnlyWhenOff() {
        let names = ["Barcelona", "Berlin", "Zürich"]
        #expect(PlaceSuggest.correction(for: "barcleona", among: names) == "Barcelona")
        #expect(PlaceSuggest.correction(for: "barc", among: names) == nil)
        #expect(PlaceSuggest.correction(for: "tokyo", among: names) == nil)
    }

    @Test func initialOrderAndDedupe() {
        let trip = AwayPeriod(kind: .travel, start: "2026-10-24", end: "2026-10-28", note: "Barcelona")
        let past = AwayPeriod(kind: .travel, start: "2026-09-01", end: "2026-09-03", note: "Lyon")
        let off = AwayPeriod(kind: .off, start: "2026-10-20", end: "2026-10-20", note: "Dentist")
        let recents = [PlaceSuggestion(kind: .recent, title: "barcelona"), PlaceSuggestion(kind: .recent, title: "Berlin Mitte")]
        let gym = GymRef(id: "g", name: "Puls 5", address: "Giessereistrasse 18, 8005 Zürich, Switzerland")
        let here = PlaceSuggestion(kind: .here, title: "Zurich")
        let list = PlaceSuggest.initial(trips: [past, off, trip], recents: recents, gyms: [gym], here: here, today: "2026-10-18")
        #expect(list.map(\.title) == ["Barcelona", "Berlin Mitte", "Zürich"])
        #expect(list[0].kind == .trip)
        #expect(list[0].subtitle == "24–28 Oct")
        #expect(list[2].subtitle == "Puls 5")
    }

    @Test func rememberMovesUpAndCaps() {
        var list: [PlaceSuggestion] = []
        for i in 0..<10 { list = PlaceSuggest.remember(PlaceSuggestion(kind: .trip, title: "Town \(i)"), in: list) }
        #expect(list.count == PlaceSuggest.recentLimit)
        list = PlaceSuggest.remember(PlaceSuggestion(kind: .here, title: "town 5"), in: list)
        #expect(list.first?.title == "town 5")
        #expect(list.first?.kind == .recent)
        #expect(list.filter { PlaceSuggest.fold($0.title) == "town 5" }.count == 1)
    }

    @Test func highlightLightsWordStarts() {
        let name = "Hotel Adlon Kempinski"
        let lit = PlaceSuggest.highlight("hotl adlon", in: name).map { String(name[$0]) }
        #expect(lit == ["Hot", "Adlon"])
        let z = "Zürich Airport"
        #expect(PlaceSuggest.highlight("zuri", in: z).map { String(z[$0]) } == ["Züri"])
    }

    @Test func matchesRankExactFirst() {
        let places = [PlaceSuggestion(kind: .recent, title: "Zug"), PlaceSuggestion(kind: .gym, title: "Zürich")]
        #expect(PlaceSuggest.matches("zuric", in: places).map(\.title) == ["Zürich"])
        #expect(PlaceSuggest.matches("zu", in: places).map(\.title) == ["Zug", "Zürich"])
    }
}
