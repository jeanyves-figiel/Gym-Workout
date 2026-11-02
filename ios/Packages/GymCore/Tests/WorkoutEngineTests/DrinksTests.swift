import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct DrinksTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return c
    }()

    func at(_ day: Int, _ hour: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    @Test func lastNightCountsSinceYesterdayNoon() {
        let e = [DrinkEntry(date: at(6, 11), kind: .beer), DrinkEntry(date: at(6, 21), kind: .wine, count: 2),
                 DrinkEntry(date: at(7, 1), kind: .cocktail)]
        let n = Drinks.total(Drinks.lastNight(e, now: at(7, 9), calendar: cal))
        #expect(n == 3.5)
    }

    @Test func tonightRunsPastMidnight() {
        let e = [DrinkEntry(date: at(6, 22), kind: .beer), DrinkEntry(date: at(7, 2), kind: .shot)]
        #expect(Drinks.total(Drinks.tonight(e, now: at(7, 3), calendar: cal)) == 2)
        #expect(Drinks.total(Drinks.tonight(e, now: at(7, 10), calendar: cal)) == 0)
    }

    @Test func pointsAndWater() {
        #expect(Drinks.points(0) == 0)
        #expect(Drinks.points(2) == -5)
        #expect(Drinks.points(6) == -15)
        #expect(Drinks.points(12) == -20)
        #expect(Drinks.waterBonus(lastNight: 6, goodTimes: false) == 3)
        #expect(Drinks.waterBonus(lastNight: 20, goodTimes: true) == Drinks.maxWaterBonus + Drinks.goodTimesWater)
    }

    @Test func drinksMakeTheDayLight() {
        let fresh = AutoTune.assess(TuneInputs(sleepHours: 8.2))
        #expect(fresh.level != .light)
        let after = AutoTune.assess(TuneInputs(sleepHours: 8.2, drinks: 6, hoursSinceDrink: 8))
        #expect(after.level == .light)
        #expect(after.factors.contains { $0.id == "drinks" && $0.points == -15 })
        #expect(after.reason.lowercased().contains("drinks"))
        let week = AutoTune.assess(TuneInputs(hrv: 62, hrvBaseline: 54, sleepHours: 8.5, goodTimes: true))
        #expect(week.level == .light)
    }

    @Test func morningAfterSteps() {
        let soon = Drinks.morningAfter(standard: 6, hoursSince: 7, extraGlasses: 3)
        #expect(soon.first?.kind == .rest)
        #expect(soon.contains { $0.kind == .sleep })
        let later = Drinks.morningAfter(standard: 3, hoursSince: 14, extraGlasses: 2)
        #expect(later.first?.kind == .walk)
        #expect(Drinks.morningAfter(standard: 0, hoursSince: nil, extraGlasses: 0).isEmpty)
    }

    @Test func supportOnlyAfterRepeatedHeavyWeeks() {
        let now = at(30, 10)
        var e: [DrinkEntry] = []
        for w in 1...3 {
            let d = cal.date(byAdding: .day, value: -7 * w, to: now)!
            e.append(DrinkEntry(date: d, kind: .beer, count: 16))
        }
        #expect(Drinks.heavyWeeks(e, now: now, calendar: cal) == 3)
        #expect(Drinks.showsSupport(e, now: now, calendar: cal))
        #expect(!Drinks.showsSupport(Array(e.prefix(2)), now: now, calendar: cal))
    }

    @Test func coachWords() {
        #expect(DrinkKind.from("2 glasses of prosecco") == .wine)
        #expect(DrinkKind.from("tequila") == .shot)
        #expect(DrinkKind.from("pints") == .beer)
        #expect(DrinkKind.from("mojito") == .cocktail)
    }

    @Test func goodTimesCovers() {
        let p = GoodTimesPeriod(start: "2026-11-08", end: "2026-11-02")
        #expect(p.start == "2026-11-02")
        #expect(p.covers("2026-11-05"))
        #expect(!p.covers("2026-11-09"))
    }
}
