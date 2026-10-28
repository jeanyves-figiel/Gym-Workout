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
        #expect(SessionPlaces.chips(for: .climbing, used: used, gyms: [gym]).map(\.name) == ["Magic Wood", "Block Factory", "Laax"])
        // Outdoor-only sports skip gyms.
        #expect(SessionPlaces.chips(for: .snowboard, used: used, gyms: [gym]).map(\.name) == ["Laax", "Magic Wood"])
        // The picked place stays listed, once.
        #expect(SessionPlaces.chips(for: .climbing, current: laax, used: used, gyms: [gym]).map(\.name) == ["Laax", "Magic Wood", "Block Factory"])
        #expect(SessionPlaces.last(for: .climbing, used: used) == crag)
        #expect(SessionPlaces.last(for: .hike, used: used) == nil)
    }
}
