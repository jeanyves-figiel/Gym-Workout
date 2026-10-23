import Foundation
import Testing
@testable import WorkoutEngine

/// New member onboarding (#664): steps left feed the set-up card; ✕ hides it, finishing every step ends it.
@Suite struct OnboardingTests {
    @Test func stepsInOrder() {
        #expect(OnboardingStep.allCases.map(\.short) == ["Gym", "Machines", "Map", "Plan", "Tour"])
        #expect(OnboardingStep.gym.next == .machines)
        #expect(OnboardingStep.tour.next == nil)
        #expect(OnboardingStep.plan.number == 4)
    }

    @Test func skippedStepsWaitOnTheCard() {
        var p = OnboardingProgress()
        p.complete(.gym)
        p.complete(.plan)
        p.complete(.plan)
        #expect(p.done == [.gym, .plan])
        #expect(p.later == [.machines, .map, .tour])
        #expect(p.showsCard)
        #expect(p.fraction == 0.4)
    }

    @Test func closedOrFinishedHidesTheCard() {
        var p = OnboardingProgress(done: [.gym])
        p.cardHidden = true
        #expect(!p.showsCard)
        #expect(p.later.count == 4)
        var all = OnboardingProgress()
        for s in OnboardingStep.allCases { all.complete(s) }
        #expect(all.finished)
        #expect(!all.showsCard)
    }

    @Test func roundTrips() throws {
        let p = OnboardingProgress(done: [.machines, .tour], cardHidden: true)
        let back = try JSONDecoder().decode(OnboardingProgress.self, from: JSONEncoder().encode(p))
        #expect(back == p)
    }
}
