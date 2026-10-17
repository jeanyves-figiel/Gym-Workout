import Foundation
import Testing
@testable import WorkoutEngine

private let day0 = ISO8601DateFormatter().date(from: "2026-09-07T10:00:00Z")!

private func set(_ kg: Double, _ reps: Int, day: Int = 0) -> SetLog {
    SetLog(date: day0.addingTimeInterval(Double(day) * 86_400), exerciseId: "bench-press", sessionId: "w1s\(day)", setIndex: 0, kg: kg, reps: reps)
}

@Suite struct CoachTests {
    @Test func everyMomentHasLinesInEveryStyle() {
        let moments: [CoachMoment] = [
            .start(exercises: 8), .setLogged(set: 1, of: 3, kg: 60, reps: 8, lastKg: 60, lastReps: 7), .finalSet(exercise: "Bench press"),
            .halfway(left: 4), .restEnding(seconds: 10), .record(exercise: "Bench press", kg: 62.5, reps: 8, heavierBy: 2.5),
            .finish(sets: 18, volumeKg: 3450, minutes: 52),
        ]
        for m in moments {
            for s in CoachStyle.allCases {
                let all = CoachLines.variants(m, style: s)
                #expect(all.count >= 2)
                #expect(all.allSatisfy { !$0.isEmpty && !$0.contains("Optional") })
                #expect(CoachLines.line(m, style: s, seed: -7) == all[7 % all.count])
            }
        }
    }

    @Test func keyMomentsAreSpokenAtKeyLevel() {
        #expect(CoachMoment.finalSet(exercise: "x").isKey)
        #expect(CoachMoment.record(exercise: "x", kg: 1, reps: 1, heavierBy: nil).isKey)
        #expect(!CoachMoment.restEnding(seconds: 10).isKey)
        #expect(!CoachMoment.setLogged(set: 1, of: 3, kg: 60, reps: 8, lastKg: nil, lastReps: nil).isKey)
    }

    @Test func studioKindsMatchTheServerGroups() {
        #expect(CoachMoment.start(exercises: 5).studioKind == "start")
        #expect(CoachMoment.setLogged(set: 1, of: 3, kg: 62.5, reps: 8, lastKg: 60, lastReps: 8).studioKind == "set-heavier")
        #expect(CoachMoment.setLogged(set: 1, of: 3, kg: 60, reps: 9, lastKg: 60, lastReps: 8).studioKind == "set-more")
        #expect(CoachMoment.setLogged(set: 1, of: 3, kg: 60, reps: 8, lastKg: 60, lastReps: 8).studioKind == "set-same")
        #expect(CoachMoment.setLogged(set: 1, of: 3, kg: 55, reps: 8, lastKg: 60, lastReps: 8).studioKind == "set")
        #expect(CoachMoment.setLogged(set: 1, of: 3, kg: 60, reps: 8, lastKg: nil, lastReps: nil).studioKind == "set")
        #expect(CoachMoment.record(exercise: "x", kg: 1, reps: 1, heavierBy: 2.5).studioKind == "record-heavier")
        #expect(CoachMoment.record(exercise: "x", kg: 1, reps: 1, heavierBy: nil).studioKind == "record")
        #expect(CoachMoment.restEnding(seconds: 10).studioKind == "rest")
        #expect(CoachMoment.finish(sets: 1, volumeKg: 0, minutes: 1).studioKind == "finish")
    }

    @Test func setLineComparesWithLastTime() {
        let more = CoachLines.variants(.setLogged(set: 2, of: 3, kg: 60, reps: 9, lastKg: 60, lastReps: 8), style: .hype)
        #expect(more[0] == "Boom! One rep more than last time!")
        let heavier = CoachLines.variants(.setLogged(set: 1, of: 3, kg: 62.5, reps: 8, lastKg: 60, lastReps: 8), style: .chill)
        #expect(heavier[0].contains("2.5 kg more than last time"))
        let first = CoachLines.variants(.setLogged(set: 1, of: 3, kg: 60, reps: 8, lastKg: nil, lastReps: nil), style: .drill)
        #expect(first[0] == "Set 1 of 3. Logged. Next.")
    }

    @Test func recordNeedsHistoryAndABetterSet() {
        // First time: no record spam.
        #expect(CoachLines.record(kg: 60, reps: 8, history: []).isRecord == false)
        let history = [set(60, 8), set(60, 8, day: 3)]
        // Heavier than ever.
        let heavier = CoachLines.record(kg: 62.5, reps: 5, history: history)
        #expect(heavier.isRecord)
        #expect(heavier.heavierBy == 2.5)
        // Same weight, more reps: higher e1RM.
        let reps = CoachLines.record(kg: 60, reps: 10, history: history)
        #expect(reps.isRecord)
        #expect(reps.heavierBy == nil)
        // Same set again: not a record.
        #expect(CoachLines.record(kg: 60, reps: 8, history: history).isRecord == false)
        #expect(CoachLines.record(kg: 55, reps: 9, history: history).isRecord == false)
    }
}

@Suite struct MemberAddressTests {
    @Test func pronounsArePrefilledFromGender() {
        #expect(Pronouns.suggested(gender: "woman") == .she)
        #expect(Pronouns.suggested(gender: "man") == .he)
        #expect(Pronouns.suggested(gender: "nonBinary") == .they)
        #expect(Pronouns.suggested(gender: "selfDescribe") == .they)
        #expect(Pronouns.suggested(gender: "preferNotToSay") == nil)
        #expect(Pronouns.suggested(gender: nil) == nil)
        #expect(Pronouns.text(.they, custom: nil) == "they/them")
        #expect(Pronouns.text(.custom, custom: "  xe/xem ") == "xe/xem")
        #expect(Pronouns.text(.custom, custom: " ") == nil)
    }

    @Test func callChoicesFollowPronouns() {
        #expect(CoachCall.options(for: .she).contains(.queen))
        #expect(!CoachCall.options(for: .she).contains(.king))
        #expect(CoachCall.options(for: .he).contains(.king))
        #expect(!CoachCall.options(for: .they).contains(.queen) && !CoachCall.options(for: nil).contains(.king))
        #expect(CoachCall.text(.queen, name: nil, pronouns: .she) == "Queen")
        #expect(CoachCall.text(.queen, name: nil, pronouns: .they) == nil)
        #expect(CoachCall.text(.name, name: "Jean-Yves Figiel", pronouns: nil) == "Jean-Yves")
        #expect(CoachCall.text(.name, name: "", pronouns: nil) == nil)
        #expect(CoachCall.text(.none, name: "Alex", pronouns: .he) == nil)
    }

    @Test func callGoesBeforeBigMomentsOnly() {
        #expect(CoachLines.called("Halfway!", moment: .halfway(left: 3), style: .hype, call: "Alex") == "Alex! Halfway!")
        #expect(CoachLines.called("Half done.", moment: .halfway(left: 3), style: .chill, call: "Alex") == "Alex. Half done.")
        #expect(CoachLines.called("Boom!", moment: .restEnding(seconds: 10), style: .hype, call: "Alex") == "Boom!")
        #expect(CoachLines.called("Done!", moment: .finish(sets: 1, volumeKg: 0, minutes: 1), style: .hype, call: nil) == "Done!")
    }
}
