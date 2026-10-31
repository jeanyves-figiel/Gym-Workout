import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct HowItWorksTests {
    private func text(_ id: String) -> String {
        let t = HowItWorks.topic(id)!
        return ([t.summary] + t.parts.flatMap { [$0.text] + $0.rule }).joined(separator: "\n")
    }

    @Test func topicsAreCompleteAndUnique() {
        let ids = HowItWorks.topics.map(\.id)
        #expect(Set(ids).count == ids.count)
        for t in HowItWorks.topics {
            #expect(!t.parts.isEmpty, "\(t.id) has no parts")
            #expect(!t.sources.isEmpty, "\(t.id) has no sources")
            #expect(t.colors.count == 2)
            #expect(!t.shows.isEmpty)
        }
    }

    /// The page quotes the numbers the app uses, so a change in the code shows on the page.
    @Test func quotesTheConstantsInUse() {
        #expect(text("xp").contains("max(\(GameProgress.minWorkoutXP), \(GameProgress.perWorkout) + \(GameProgress.perSet) × sets done)"))
        #expect(text("xp").contains("XP ÷ \(GameProgress.perLevel) + 1"))
        #expect(text("move").contains("max \(DailyMove.dailyCap) XP a day"))
        #expect(text("fuel").contains("build 2"))
        #expect(text("fuel").contains("lose 2.2"))
        #expect(text("readiness").contains("< \(AutoTune.lightBelow)"))
        #expect(text("zones").contains("goal \(HeartZones.zone2Goal) min"))
        #expect(text("caffeine").contains("\(Supplements.caffeineGuideMg) mg"))
        #expect(text("plan").contains("Week 4: \(Generator.weekLabel(4))"))
        #expect(HowItWorks.topic("methods")!.parts.count == TrainingMethod.allCases.count + 1)
        #expect(text("form").contains("trunk lean: \(HowItWorks.fmt(FormModel.Limit.torsoLean))° more"))
        #expect(text("form").contains("−\(FormFault.kneesIn.penalty)"))
    }

    /// Every topic names at least one study (#976); the app's own choices are marked as such, never passed off as science.
    @Test func everyTopicIsBackedByAStudy() {
        for t in HowItWorks.topics {
            #expect(t.sources.contains { !$0.hasPrefix(HowItWorks.appDesign) }, "\(t.id) cites no study")
            for s in t.sources where s.localizedCaseInsensitiveContains("app design") {
                #expect(s.hasPrefix(HowItWorks.appDesign), "\(t.id): mark app choices with \(HowItWorks.appDesign)")
            }
        }
        for id in ["warmup", "pain", "life", "coach"] { #expect(HowItWorks.topic(id) != nil, "\(id) missing") }
        #expect(text("warmup").contains("\(PRPlanner.maxAttempts) attempts at most"))
        #expect(text("pain").contains(PainProtect.notAdvice))
        #expect(text("life").contains(LifeStage.talkTest))
        #expect(text("coach").contains("\(CoachNudges.driftMissed) planned sessions missed"))
    }

    @Test func rankBandsMatchTheLadder() {
        func rank(_ level: Int) -> String { GameProgress(xp: (level - 1) * GameProgress.perLevel).rank }
        #expect(rank(2) == "Rookie" && rank(3) == "Regular" && rank(7) == "Regular" && rank(8) == "Iron")
        #expect(rank(15) == "Steel" && rank(25) == "Titan" && rank(40) == "Legend")
        #expect(text("xp").contains("Rookie 1–2 · Regular 3–7 · Iron 8–14 · Steel 15–24 · Titan 25–39 · Legend 40+"))
    }

    @Test func numbersFormatPlainly() {
        #expect(HowItWorks.fmt(2) == "2")
        #expect(HowItWorks.fmt(4.5) == "4.5")
        #expect(HowItWorks.fmt(0.82) == "0.82")
    }
}
