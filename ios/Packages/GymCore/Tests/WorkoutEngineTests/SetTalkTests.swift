import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct SetTalkTests {
    private let squat = SetTalkContext(exercise: "Back squat", set: 3, sets: 4, kg: 100, reps: 5, step: 2.5,
                                       done: [.init(kg: 100, reps: 5, rir: 1), .init(kg: 100, reps: 4, rir: 0)],
                                       lastTime: "97.5 kg × 5", restSec: 150,
                                       swaps: [.init(id: "leg-press", name: "Leg press"), .init(id: "hack-squat", name: "Hack squat")])

    @Test func painDropsWeightAndOffersSwap() throws {
        let a = try #require(SetTalk.rules("Felt it in my lower back", squat))
        #expect(a.actions == [.weight(90), .swap(id: "leg-press", name: "Leg press")])
        #expect(a.text.contains("90 kg"))
        #expect(a.source == .rules)
    }

    @Test func exerciseNameIsNotABodyPart() throws {
        let a = try #require(SetTalk.rules("Is back squat too heavy?", squat))
        #expect(a.actions == [.weight(95)])
    }

    @Test func tooLightNeedsRepsInReserve() {
        #expect(SetTalk.rules("too light?", squat) == nil)
        var easy = squat
        easy.done = [.init(kg: 100, reps: 5, rir: 4)]
        #expect(SetTalk.rules("too light?", easy)?.actions == [.weight(102.5)])
    }

    @Test func restFollowsPlanAndEffort() throws {
        let a = try #require(SetTalk.rules("Coach, how long should I rest?", squat))
        #expect(a.actions == [.rest(180)])
        #expect(a.text.hasPrefix("Take 3:00"))
    }

    @Test func otherQuestionsGoToAModel() {
        #expect(SetTalk.rules("What muscles does this work?", squat) == nil)
    }

    @Test func cleanedKeepsFixesThatFit() throws {
        let wire = SetTalkWireAnswer(answer: "  Go to 91 kg.  ", actions: [
            .init(kind: "weight", kg: 91), .init(kind: "weight", kg: 80), .init(kind: "swap", exerciseId: "unknown"),
            .init(kind: "rest", sec: 1000), .init(kind: "swap", exerciseId: "hack-squat"),
        ])
        let a = try #require(SetTalk.cleaned(wire, heard: "q", context: squat, source: .server))
        #expect(a.text == "Go to 91 kg.")
        #expect(a.actions == [.weight(90), .rest(600)])
    }

    @Test func cleanedDropsWildWeightsAndEmptyAnswers() {
        #expect(SetTalk.cleaned(.init(answer: "Go", actions: [.init(kind: "weight", kg: 200)]), heard: "q", context: squat, source: .server)?.actions == [])
        #expect(SetTalk.cleaned(.init(answer: "  "), heard: "q", context: squat, source: .server) == nil)
    }

    @Test func labels() {
        #expect(SetTalkAction.weight(92.5).label == "Use 92.5 kg")
        #expect(SetTalkAction.swap(id: "x", name: "Leg press").label == "Swap to leg press")
        #expect(SetTalkAction.rest(150).label == "Rest 2:30")
    }
}
