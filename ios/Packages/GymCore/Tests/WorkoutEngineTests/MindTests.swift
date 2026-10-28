import Foundation
import Testing
@testable import WorkoutEngine

/// Mental health & relaxation (#834).
@Suite struct MindTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 8))! }

    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))! }

    private func checkIn(_ offset: Int, _ mood: Int, _ feelings: [MindFeeling] = []) -> MindCheckIn {
        MindCheckIn(date: day(offset).addingTimeInterval(7 * 3600), mood: mood, feelings: feelings)
    }

    @Test func everySessionEndsOnABreathOut() {
        for b in Breath.allCases {
            let last = b.phases[b.phases.count - 1].kind
            #expect(last == .exhale || last == .rest, "\(b)")
            #expect(!b.lengths.isEmpty && b.defaultMinutes == b.lengths[0])
            #expect(b.colors.count == 2)
            #expect(b.cycles(minutes: 1) >= 1)
        }
        #expect(Set(Breath.allCases.map(\.label)).count == Breath.allCases.count)
        #expect(Breath.allCases.filter { $0.group == .relax } == [.bodyScan, .focus])
    }

    @Test func lengthRoundsToWholeCycles() {
        #expect(Breath.box.cycleSeconds == 16)
        #expect(Breath.box.cycles(minutes: 3) == 11)
        #expect(Breath.box.totalSeconds(minutes: 3) == 176)
        #expect(Breath.sleep478.cycleSeconds == 19)
        #expect(Breath.sleep478.cycles(minutes: 4) == 13)
    }

    @Test func phaseAtATime() {
        let b = Breath.box
        #expect(b.at(0, minutes: 3).phase.kind == .inhale)
        let h = b.at(5, minutes: 3)
        #expect(h.phase.kind == .hold && h.index == 1 && h.into == 1 && h.cycle == 0)
        #expect(b.at(16, minutes: 3).cycle == 1)
        #expect(b.at(16, minutes: 3).phase.kind == .inhale)
        // Past the end: the last breath of the last cycle.
        let end = b.at(1000, minutes: 3)
        #expect(end.phase.kind == .rest && end.index == 3 && end.cycle == 10)
        #expect(b.at(5, minutes: 3).cue == nil)
    }

    @Test func guidedCuesSpreadOverTheSession() {
        let b = Breath.bodyScan
        #expect(b.at(0, minutes: 8).cue == b.cues.first)
        #expect(b.at(b.totalSeconds(minutes: 8) - 1, minutes: 8).cue == b.cues.last)
        #expect(Breath.focus.at(0, minutes: 2).cue == Breath.focus.cues.first)
    }

    @Test func scoreNeedsAMindReading() {
        #expect(MindScore.score(.init()) == nil)
        #expect(MindScore.score(.init(workoutDays: 2, calmMinutes: 5)) == nil)
    }

    @Test func scoreWeighsMoodHrvSleepAndLoad() {
        #expect(MindScore.score(.init(mood: 5, hrv: 60, hrvBaseline: 50, sleepHours: 8, workoutDays: 0)) == 100)
        #expect(MindScore.score(.init(mood: 5, hrv: 60, hrvBaseline: 50, sleepHours: 9, workoutDays: 0, calmMinutes: 3)) == 100)
        #expect(MindScore.score(.init(mood: 1, hrv: 35, hrvBaseline: 50, sleepHours: 5, workoutDays: 3)) == 3)
        // Mood only: mood and load reweighted, 17.5 + 15 of 50.
        #expect(MindScore.score(.init(mood: 3)) == 65)
        #expect(MindScore.score(.init(mood: 3, calmMinutes: 10)) == 65 + MindScore.calmBonusMax)
        #expect(MindScore.parts(.init(mood: 3)).map(\.name) == ["Mood", "Load"])
        #expect(MindScore.Inputs(hrv: 50, hrvBaseline: 0).hrvRatio == nil)
    }

    @Test func levels() {
        #expect(MindScore.Level.of(75) == .calm)
        #expect(MindScore.Level.of(74) == .steady)
        #expect(MindScore.Level.of(55) == .steady)
        #expect(MindScore.Level.of(54) == .strained)
        #expect(MindScore.Level.of(35) == .strained)
        #expect(MindScore.Level.of(34) == .low)
    }

    @Test func coachPicks() {
        #expect(MindScore.coachPick(mood: 5, hrvRatio: 1, hour: 21).breath == .sleep478)
        #expect(MindScore.coachPick(mood: 1, hrvRatio: 1, hour: 9).breath == .sigh)
        #expect(MindScore.coachPick(mood: 4, hrvRatio: 0.8, hour: 14).breath == .box)
        #expect(MindScore.coachPick(mood: nil, hrvRatio: nil, hour: 8).breath == .wake)
        #expect(MindScore.coachPick(mood: 3, hrvRatio: nil, hour: 8).breath == .wake)
        #expect(MindScore.coachPick(mood: 4, hrvRatio: nil, hour: 8).breath == .box)
        #expect(MindScore.coachPick(mood: 3, hrvRatio: nil, hour: 15).breath == .box)
    }

    @Test func checkInClampsAndAveragesPerDay() {
        #expect(MindCheckIn(date: now, mood: 9).mood == 5)
        #expect(MindCheckIn(date: now, mood: 0).mood == 1)
        let same = [checkIn(0, 1), MindCheckIn(date: now.addingTimeInterval(3600), mood: 5), checkIn(-1, 3)]
        #expect(MindScore.averageMood(same, calendar: cal) == 4)
        #expect(MindScore.averageMood([], calendar: cal) == nil)
    }

    @Test func patternMoodAfterTraining() {
        let ins = [checkIn(-1, 5), checkIn(-2, 3), checkIn(-3, 4), checkIn(-4, 2), checkIn(-5, 5), checkIn(-6, 3)]
        let trained: Set<Date> = [day(-2), day(-4), day(-6)]
        let p = MindScore.pattern(checkIns: ins, workoutDays: trained, now: now, calendar: cal)
        #expect(p?.contains("higher the day after you train") == true)
        #expect(MindScore.pattern(checkIns: Array(ins.prefix(4)), workoutDays: trained, now: now, calendar: cal) == nil)
    }

    @Test func patternLowDaysAndShortSleep() {
        let ins = [checkIn(-1, 2, [.work]), checkIn(-2, 1, [.work, .sleep]), checkIn(-3, 4), checkIn(-4, 4), checkIn(-5, 3)]
        let p = MindScore.pattern(checkIns: ins, workoutDays: [], now: now, calendar: cal)
        #expect(p?.contains("come with work") == true)
        let plain = [checkIn(-1, 2), checkIn(-2, 1), checkIn(-3, 4), checkIn(-4, 4), checkIn(-5, 3)]
        let s = MindScore.pattern(checkIns: plain, workoutDays: [], shortSleepDays: [day(-1), day(-2)], now: now, calendar: cal)
        #expect(s?.contains("Short nights") == true)
        #expect(MindScore.pattern(checkIns: plain, workoutDays: [], now: now, calendar: cal) == nil)
    }

    @Test func howItWorksQuotesTheWeights() {
        let t = HowItWorks.topic("mind")!
        let text = t.parts.flatMap { [$0.text] + $0.rule }.joined(separator: "\n")
        #expect(text.contains("mood 35 · HRV 25 · sleep 25 · load 15"))
        #expect(text.contains("0.7 → 0, 1.2 → 1"))
        #expect(text.contains("0 → 1, 1 → 0.8, 2 → 0.5, 3 → 0.2"))
        #expect(text.contains("max +\(MindScore.calmBonusMax)"))
    }
}
