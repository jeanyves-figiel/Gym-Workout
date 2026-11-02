import Foundation
import WorkoutEngine

/// Drinks and good times weeks (#1039, mix A + B + C from `drinks-log/{a,b,c}.png`): readiness, water target,
/// Train's morning-after card and Coach's drinks line read from here. Kind words, no judgement, health first.
extension AppModel {
    var drinks: [DrinkEntry] { DrinkStore.shared.saved.entries }

    /// Standard drinks since yesterday noon.
    func drinksLastNight(now: Date = Date()) -> Double {
        Drinks.total(Drinks.lastNight(drinks, now: now, calendar: planCalendar))
    }

    func hoursSinceDrink(now: Date = Date()) -> Double? { Drinks.hoursSinceLast(drinks, now: now) }

    /// The good times week covering `date`.
    func goodTimes(on date: Date = Date()) -> GoodTimesPeriod? {
        let key = PlanCalendar.key(date, planCalendar)
        return DrinkStore.shared.saved.periods.first { $0.covers(key) }
    }

    /// Today's or the next one within 14 days, for the Calendar and Train.
    var upcomingGoodTimes: GoodTimesPeriod? {
        let cal = planCalendar
        let today = PlanCalendar.key(Date(), cal)
        let limit = cal.date(byAdding: .day, value: 14, to: Date()).map { PlanCalendar.key($0, cal) } ?? today
        return DrinkStore.shared.saved.periods.first { $0.end >= today && $0.start <= limit }
    }

    /// Glasses added to `day`'s water target: after drinks last night, and each good times day.
    func drinkWaterBonus(on day: Date) -> Int {
        let cal = planCalendar
        let isToday = cal.isDateInToday(day)
        let lastNight = isToday ? drinksLastNight() : 0
        return Drinks.waterBonus(lastNight: lastNight, goodTimes: goodTimes(on: day) != nil)
    }

    /// Train's morning-after card (C): shown from 3 standard drinks since yesterday noon, or any drink in the last 12 h.
    var morningAfter: [Drinks.Step]? {
        let n = drinksLastNight()
        let since = hoursSinceDrink()
        let recent = since.map { $0 < Drinks.noTrainingHours } ?? false
        guard n >= 3 || (recent && n > 0) else { return nil }
        let steps = Drinks.morningAfter(standard: n, hoursSince: since, extraGlasses: Drinks.waterBonus(lastNight: n, goodTimes: false))
        return steps.isEmpty ? nil : steps
    }

    /// Today's heavy session can move to a free later day (as the readiness swap, #619 B).
    var drinksSwap: RecoverSwap? {
        guard morningAfter != nil, let plan else { return nil }
        let today = todayWeekday
        guard let s = plan.sessions.first(where: { $0.weekday == today }), !doneIds.contains(s.id), activeWorkout(s.id) == nil,
              s.blocks.contains(where: { [.strength, .power].contains($0.kind) }) else { return nil }
        let taken = Set(plan.sessions.compactMap(\.weekday))
        guard let to = moveTargets(s.id).first(where: { $0 > today && !taken.contains($0) }) else { return nil }
        return RecoverSwap(session: s, to: to, marker: "DRINKS")
    }

    /// A kind line about the last 4 weeks; only after `Drinks.supportFrom` heavy weeks.
    var drinksSupport: String? {
        Drinks.showsSupport(drinks, now: Date(), calendar: planCalendar) ? Drinks.supportLine : nil
    }

    /// One plain line for Coach (#1010 digest), only with the week-review consent.
    var coachDrinksLine: String? {
        let n = drinksLastNight()
        let week = Drinks.total(drinks.filter { $0.date >= Date().addingTimeInterval(-7 * 86_400) })
        let gt = goodTimes()
        guard n > 0 || week > 0 || gt != nil else { return nil }
        var parts: [String] = []
        if let gt { parts.append("in a good times week (holiday drinks planned) until \(gt.end)") }
        if n > 0 { parts.append(String(format: "%.0f standard drinks since yesterday noon", n)) }
        if let h = hoursSinceDrink(), h < Drinks.noTrainingHours { parts.append(String(format: "last drink %.0f h ago", h)) }
        if week > 0 { parts.append(String(format: "%.0f this week", week)) }
        return "Drinks: " + parts.joined(separator: ", ") + "."
    }
}
