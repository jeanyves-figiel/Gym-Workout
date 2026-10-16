import Foundation
import Testing
@testable import WorkoutEngine

/// Workout chat (#381): settings from the coach → generator options → workout.
@Suite struct CoachChatTests {
    private let profile = Profile(goal: .balanced, experience: .intermediate, climbingDaysPerWeek: 0)

    @Test func optionsTakeTheSessionMinusWarmupAndCooldown() {
        let s = CoachWorkoutSettings(name: "Legs", minutes: 45, groups: ["legs", "hips", "wings"], rest: "short",
                                     grouping: "supersets", avoidGroups: ["shoulders", "legs"], avoidEquipment: ["barbell", "spaceship"],
                                     avoidKeywords: ["Lunge", "x"])
        let o = s.options
        #expect(o.groups == [.legs, .hips])
        #expect(o.minutes == 34)
        #expect(o.rest == .short)
        #expect(o.grouping == .supersets)
        // A trained group is never also avoided.
        #expect(o.avoidGroups == [.shoulders])
        #expect(o.avoidEquipment == [.barbell])
        #expect(o.avoidKeywords == ["lunge"])
        #expect(CoachWorkoutSettings(name: "", minutes: 12, groups: ["core"], rest: "?", grouping: "?").options.minutes == 10)
    }

    @Test func avoidedGroupsEquipmentAndWordsStayOut() throws {
        let s = CoachWorkoutSettings(name: "Shoulder-safe legs", minutes: 60, groups: ["legs", "hips", "chest"],
                                     avoidGroups: ["shoulders"], avoidEquipment: ["barbell"], avoidKeywords: ["lunge"])
        for seed: UInt32 in 1...8 {
            let w = s.workout(profile: profile, seed: seed)
            #expect(w.name == "Shoulder-safe legs")
            #expect(!w.items.isEmpty)
            for it in w.items {
                let e = try #require(it.exercise)
                #expect(!(e.primary + e.secondary).contains { $0.group == .shoulders }, "\(e.id)")
                #expect(!e.equipment.contains(.barbell), "\(e.id)")
                #expect(!e.name.lowercased().contains("lunge"), "\(e.id)")
            }
        }
    }

    @Test func sameSettingsWithoutAvoidsMatchTheMuscleGenerator() {
        let s = CoachWorkoutSettings(name: "", minutes: 56, groups: ["back", "arms"])
        let a = s.workout(profile: profile, seed: 3).items.map(\.exerciseId)
        let b = CustomWorkout.generate(MuscleWorkoutOptions(groups: [.back, .arms], minutes: 45), profile: profile, seed: 3).items.map(\.exerciseId)
        #expect(a == b)
        #expect(s.workout(profile: profile, seed: 3).name == "Arms + Back")
    }

    @Test func decodesTheServerAnswer() throws {
        let json = #"{"name":"Push","minutes":40,"groups":["chest"],"rest":"standard","grouping":"straight","avoidGroups":[],"avoidEquipment":[],"avoidKeywords":[]}"#
        let s = try JSONDecoder().decode(CoachWorkoutSettings.self, from: Data(json.utf8))
        #expect(s.options.groups == [.chest])
    }
}
