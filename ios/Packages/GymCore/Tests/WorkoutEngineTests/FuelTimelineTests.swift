import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct FuelTimelineTests {
    private let cal = Progression.calendar()
    private var day: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 20))! }

    /// Climbing 18:00–20:00 covers the 19:00 dinner: dinner moves to 20:30 as the recovery meal, once (#524).
    @Test func dinnerInsideTrainingIsTheOnlyRecoveryMeal() {
        let climb = FuelActivity(id: "c", kind: .sport(.climbing), title: "Climbing",
                                 start: cal.date(byAdding: .hour, value: 18, to: day)!, minutes: 120, done: false)
        let plan = Fuel.plan(FuelDayInput(day: day, weightKg: 75, activities: [climb]), prefs: FuelPrefs(goal: .build, meals: 5), calendar: cal)
        let after = plan.slots.filter { $0.minute >= 20 * 60 && $0.minute < 21 * 60 + 30 }
        #expect(after.count == 1)
        #expect(after.first?.kind == .dinner && after.first?.afterTraining == true)
        #expect(Set(plan.slots.map(\.minute)).count == plan.slots.count)
    }
}
