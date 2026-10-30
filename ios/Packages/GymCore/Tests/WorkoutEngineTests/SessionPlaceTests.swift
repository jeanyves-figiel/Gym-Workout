import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct SessionPlaceTests {
    private let gym = SavedGym(ref: GymRef(id: "g1", name: "Block Factory", address: "Zürich", latitude: 47.4, longitude: 8.5), equipment: [])
    private let crag = SessionPlace.map(name: "Magic Wood", address: "Ausserferrera", latitude: 46.5, longitude: 9.4)
    private let laax = SessionPlace.map(name: "Laax", address: nil, latitude: 46.84, longitude: 9.26)

    @Test func gymPlaceKeepsGymId() {
        let p = SessionPlace(gym: gym)
        #expect(p.id == "g1" && p.gymId == "g1" && p.name == "Block Factory" && p.address == "Zürich")
    }

    @Test func mapPlaceSameSpotSameId() {
        #expect(SessionPlace.map(name: "Magic Wood", address: nil, latitude: 46.5001, longitude: 9.4001).id == crag.id)
        #expect(SessionPlace.map(name: "Magic Wood", address: nil, latitude: 47.5, longitude: 9.4).id != crag.id)
        #expect(SessionPlace.typed(" My garage ").name == "My garage")
    }

    @Test func chipsPutThisSportFirstThenGyms() {
        let t = Date()
        let used = [
            SessionPlaces.Use(sport: .snowboard, place: laax, start: t),
            SessionPlaces.Use(sport: .climbing, place: crag, start: t.addingTimeInterval(-86_400)),
        ]
        // Untyped places from before #960 only list for the sport they were logged for; a gym needs a boulder wall.
        #expect(SessionPlaces.chips(for: .climbing, used: used, gyms: [gym]).map(\.name) == ["Magic Wood"])
        var wall = gym
        wall.extras = [.boulderWall]
        #expect(SessionPlaces.chips(for: .climbing, used: used, gyms: [wall]).map(\.name) == ["Magic Wood", "Block Factory"])
        // Outdoor sports skip gyms.
        #expect(SessionPlaces.chips(for: .snowboard, used: used, gyms: [wall]).map(\.name) == ["Laax"])
        // The picked place stays listed, once.
        #expect(SessionPlaces.chips(for: .climbing, current: laax, used: used, gyms: [wall]).map(\.name) == ["Laax", "Magic Wood", "Block Factory"])
        #expect(SessionPlaces.last(for: .climbing, used: used) == crag)
        #expect(SessionPlaces.last(for: .hike, used: used) == nil)
    }

    // MARK: - Place types (#960)

    private let puls5 = SavedGym(ref: GymRef(id: "puls5", name: "Fitnesspark Puls 5", address: "Zürich"), equipment: [])
    private let minimum = SessionPlace.map(name: "Minimum Boulder", address: "Zürich", latitude: 47.38, longitude: 8.52, kind: .climbingGym)
    private let gimmelwald = SessionPlace.map(name: "Gimmelwald", address: nil, latitude: 46.55, longitude: 7.89, kind: .crag)
    private let laaxResort = SessionPlace.map(name: "Laax", address: nil, latitude: 46.84, longitude: 9.26, kind: .skiResort)

    @Test func fitnessGymNeverOfferedForClimbing() {
        let t = Date()
        // Even logged there before, a gym without a boulder wall no longer shows nor starts a climb log.
        let used = [SessionPlaces.Use(sport: .climbing, place: SessionPlace(gym: puls5), start: t)]
        #expect(SessionPlaces.chips(for: .climbing, used: used, gyms: [puls5]).isEmpty)
        #expect(SessionPlaces.start(for: .climbing, used: used, gyms: [puls5]) == nil)
        // It still fits Hyrox, and a pool makes it a swim place.
        #expect(SessionPlaces.chips(for: .hyrox, used: [], gyms: [puls5]).map(\.name) == ["Fitnesspark Puls 5"])
        var pool = puls5
        pool.extras = [.pool]
        #expect(SessionPlaces.chips(for: .swim, used: used, gyms: [pool]).map(\.name) == ["Fitnesspark Puls 5"])
        #expect(SessionPlaces.chips(for: .squash, used: [], gyms: [pool]).isEmpty)
    }

    @Test func typedPlacesFilterBySport() {
        let t = Date()
        let used = [
            SessionPlaces.Use(sport: .snowboard, place: laaxResort, start: t),
            SessionPlaces.Use(sport: .climbing, place: gimmelwald, start: t.addingTimeInterval(-60)),
        ]
        // A ski resort used for snowboarding shows for ski; a crag never does.
        #expect(SessionPlaces.chips(for: .ski, used: used, gyms: []).map(\.name) == ["Laax"])
        #expect(SessionPlaces.chips(for: .mountaineering, used: used, gyms: []).map(\.name) == ["Gimmelwald"])
        #expect(SessionPlaces.chips(for: .other, used: used, gyms: [puls5]).count == 3)
    }

    @Test func homeSpotStartsTheLog() {
        let t = Date()
        let used = [SessionPlaces.Use(sport: .climbing, place: gimmelwald, start: t)]
        var book = PlaceBook()
        book.toggleHome(minimum)
        #expect(book.home(.climbing) == minimum && book.isHome(minimum))
        #expect(SessionPlaces.start(for: .climbing, used: used, gyms: [], book: book) == minimum)
        #expect(SessionPlaces.chips(for: .climbing, used: used, gyms: [], book: book).map(\.name) == ["Minimum Boulder", "Gimmelwald"])
        // No home: where it was done last.
        #expect(SessionPlaces.start(for: .climbing, used: used, gyms: []) == gimmelwald)
        // Tap again: not home any more; retyped to another group: not that group's home.
        var again = book
        again.toggleHome(minimum)
        #expect(again.home(.climbing) == nil)
        var moved = minimum
        moved.kind = .studio
        book.save(moved)
        #expect(book.home(.climbing) == nil && book.resolve(SessionPlace.map(name: "Minimum Boulder", address: nil, latitude: 47.38,
                                                                             longitude: 8.52)).kind == .studio)
        book.remove(moved.id)
        #expect(book.places.isEmpty && book.homes.isEmpty)
    }

    @Test func everySportHasPlaceKinds() {
        for s in Sport.allCases {
            #expect(!s.placeKinds.isEmpty)
            #expect(s.placeKinds.contains { $0.group == s.placeGroup } || s == .other)
        }
        #expect(Sport.climbing.placeHint == "Climbing gym, crag…")
        // Every type has a group, every group a sport that searches its types.
        for g in PlaceGroup.allCases { #expect(!g.kinds.isEmpty) }
    }

    @Test func kindDecodesFromOldPlaces() throws {
        let old = #"{"id":"map:x","name":"X"}"#.data(using: .utf8)!
        let p = try JSONDecoder().decode(SessionPlace.self, from: old)
        #expect(p.kind == nil && p.effectiveKind == nil)
        #expect(SessionPlace(gym: puls5).effectiveKind == .gym)
    }
}
