import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct GymSetupTests {
    @Test func zonesCoverEveryItemOnce() {
        let all = GymArea.allCases.flatMap(\.items) + GymArea.floor
        #expect(all.count == Equipment.allCases.count)
        #expect(Set(all) == Set(Equipment.allCases))
    }

    @Test func answersBuildEquipment() {
        var a = GymKind.hotel.guess
        #expect(Set(GymKind.hotel.equipment) == Set(GymArea.dumbbells.items + GymArea.cardio.items + GymArea.floor))
        a[.cables] = .unsure
        let (eq, unsure) = GymSetup.equipment(a)
        #expect(Set(unsure) == Set(GymArea.cables.items))
        #expect(Set(GymArea.cables.items).isSubset(of: Set(eq)))
        #expect(GymKind.bigClub.equipment.count == Equipment.allCases.count - GymArea.climbing.items.count)
        #expect(GymSetup.answers(for: GymKind.budget.equipment) == GymKind.budget.guess)
    }

    @Test func orderPutsZonesThePlanUsesFirst() {
        let plan = Generator.generateWeek(Profile(goal: .balanced, sessionsPerWeek: 3, experience: .intermediate), week: 1, seed: 1)
        let order = GymSetup.order(for: plan)
        #expect(order.count == GymArea.allCases.count)
        let counts = order.map { GymSetup.uses($0, in: plan) }
        #expect(counts == counts.sorted(by: >))
        // Nothing in the plan fits a park; everything fits a big club.
        #expect(GymSetup.misfits(plan, equipment: Equipment.allCases).isEmpty)
        #expect(!GymSetup.misfits(plan, equipment: GymKind.park.equipment).isEmpty)
    }

    @Test func savedGymRemovesItems() {
        let g = SavedGym(ref: SavedGym.customRef(name: "Hotel"), kind: .hotel, equipment: [.dumbbells, .bench, .treadmill], unsure: [.treadmill])
        #expect(!g.isPlace)
        let h = g.removing([.treadmill])
        #expect(h.equipment == [.dumbbells, .bench])
        #expect(h.unsure == nil)
        let bench = Exercise.catalog.first { $0.equipment.contains(.bench) && $0.equipment.contains(.barbell) }!
        #expect(bench.missing(from: [.bench]).contains(.barbell))
    }

    @Test func ownGymKeepsAddressAndPinButStaysPrivate() {
        let r = SavedGym.customRef(name: "Kraftwerk", address: "Badenerstrasse 12, Schlieren", latitude: 47.39, longitude: 8.45)
        let g = SavedGym(ref: r, equipment: [.dumbbells])
        #expect(!g.isPlace)
        #expect(r.id.hasPrefix("custom:"))
        #expect(r.address == "Badenerstrasse 12, Schlieren")
        #expect(r.latitude == 47.39 && r.longitude == 8.45)
        #expect(SavedGym.customRef(name: "Kraftwerk").id != r.id)
    }
}

@Suite struct EquipmentPictureTests {
    @Test func everyItemHasAPictureOfItInUse() {
        for e in Equipment.allCases {
            guard let ex = Exercise.find(e.pictureExerciseId) else {
                Issue.record("missing picture exercise for \(e)")
                continue
            }
            #expect(ex.equipment.contains(e), "\(e) picture \(ex.id)")
            #expect(ex.hasMedia, "\(e) picture has media")
        }
    }

    @Test func searchFindsOtherNames() {
        #expect(Equipment.stabilityBall.matches("swiss"))
        #expect(Equipment.cable.matches("Cables"))
        #expect(!Equipment.rower.matches("dumbbell"))
        #expect(GymArea.of(.ghd) == .stations)
        #expect(Equipment.assistedMachine.matches("gravitron"))
        #expect(Equipment.dipBelt.matches("vest"))
    }
}
