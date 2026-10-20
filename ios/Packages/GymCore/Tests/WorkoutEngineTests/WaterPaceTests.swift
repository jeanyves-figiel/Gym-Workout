import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct WaterPaceTests {
    private let cal = Progression.calendar()
    private let prefs = FuelPrefs(goal: .maintain, meals: 4)
    private var day: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 20))! }

    private func plan(gymAt hour: Int? = nil, minutes: Int = 60) -> FuelPlan {
        let acts = hour.map { [FuelActivity(id: "g", kind: .gym, title: "Legs", start: cal.date(byAdding: .hour, value: $0, to: day)!,
                                            minutes: minutes, done: false)] } ?? []
        return Fuel.plan(FuelDayInput(day: day, weightKg: 75, activities: acts), prefs: prefs, calendar: cal)
    }

    @Test func paceRunsFromWakeToSleep() {
        let p = plan()
        #expect(WaterPace.expected(by: prefs.wake, plan: p, prefs: prefs, calendar: cal) == 0)
        #expect(WaterPace.expected(by: prefs.sleep, plan: p, prefs: prefs, calendar: cal) == p.glasses)
        let noon = WaterPace.expected(by: 12 * 60, plan: p, prefs: prefs, calendar: cal)
        #expect(noon > 0 && noon < p.glasses)
    }

    @Test func moreWaterBeforeTraining() {
        let rest = plan(), legs = plan(gymAt: 18)
        func window(_ p: FuelPlan) -> Int {
            WaterPace.expected(by: 18 * 60, plan: p, prefs: prefs, calendar: cal) - WaterPace.expected(by: 16 * 60, plan: p, prefs: prefs, calendar: cal)
        }
        #expect(window(legs) > window(rest))
        let b = WaterPace.buckets(legs, prefs: prefs, calendar: cal)
        #expect(b.contains { $0.training })
        #expect(abs(b.reduce(0) { $0 + $1.glasses } - Double(legs.glasses)) < 0.01)
    }

    @Test func remindsOnlyWhenBehind() {
        let p = plan()
        let water = WaterPrefs()
        let behind = WaterPace.nudges(p, glasses: 0, prefs: prefs, water: water, now: 8 * 60, calendar: cal)
        #expect(!behind.isEmpty)
        #expect(behind.allSatisfy { $0.minute > 8 * 60 && $0.minute < prefs.sleep })
        #expect(WaterPace.nudges(p, glasses: p.glasses, prefs: prefs, water: water, now: 8 * 60, calendar: cal).isEmpty)
        #expect(WaterPace.nudges(p, glasses: 0, prefs: prefs, water: WaterPrefs(remind: .off), now: 8 * 60, calendar: cal).isEmpty)
        // Ahead of pace in the morning: nothing until the pace catches up.
        let ahead = WaterPace.nudges(p, glasses: 4, prefs: prefs, water: water, now: 8 * 60, calendar: cal)
        #expect(ahead.allSatisfy { WaterPace.expected(by: $0.minute, plan: p, prefs: prefs, calendar: cal) > 4 })
    }

    @Test func quietDuringTrainingAndQuietHours() {
        let p = plan(gymAt: 13, minutes: 90)
        let hourly = WaterPrefs(remind: .hourly)
        let n = WaterPace.nudges(p, glasses: 0, prefs: prefs, water: hourly, now: 7 * 60, calendar: cal)
        #expect(!n.contains { $0.minute >= 13 * 60 && $0.minute < 14 * 60 + 30 })
        #expect(n.contains { $0.body.contains("Legs at 13:00") })
        let quiet = WaterPace.nudges(p, glasses: 0, prefs: prefs, water: hourly, now: 7 * 60, quiet: { $0 < 12 * 60 }, calendar: cal)
        #expect(quiet.allSatisfy { $0.minute >= 12 * 60 })
    }
}
