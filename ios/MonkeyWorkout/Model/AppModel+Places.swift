import Foundation
import WorkoutEngine

/// Where each day happens (#684, #700): the gym of a weekday, set every week or just for one day from Train.
extension AppModel {
    /// Places a day can be at: the plan's gym first, then the other saved ones, and Home always (#703): a saved home
    /// gym, else bodyweight at home.
    var placeChoices: [SavedGym] {
        let list = [homeGym] + otherGyms
        return list.contains { $0.kind == .home } ? list : list + [.builtInHome]
    }

    /// The travel period (#68) covering `weekday` of this week, if any.
    func tripThisWeek(_ weekday: Int) -> AwayPeriod? {
        awayThisWeek(weekday).flatMap { $0.kind == .travel ? $0 : nil }
    }

    /// Gym id `weekday` of this week is at: a one-off pick, else the weekly place, else the plan's gym.
    func placeId(onWeekday weekday: Int, now: Date = Date()) -> String {
        let cal = planCalendar
        let day = cal.date(byAdding: .day, value: weekday - 1, to: Progression.weekStart(now, cal)).map { PlanCalendar.key($0, cal) }
        if let day, let id = state.synced?.placeOnDay?[day] { return id }
        return profile?.place(onWeekday: weekday) ?? homeGym.id
    }

    /// Name of that gym ("Home", "Puls 5").
    func placeName(onWeekday weekday: Int, now: Date = Date()) -> String {
        let id = placeId(onWeekday: weekday, now: now)
        return placeChoices.first { $0.id == id }?.ref.name ?? gymName
    }

    /// Just this day (#700, design A): `weekday` of this week at `gymId`; picking the weekly place clears it.
    /// Days already past are dropped. Re-plans the rest of the week.
    func setPlaceToday(_ gymId: String, onWeekday weekday: Int, now: Date = Date()) {
        guard var sp = state.synced else { return }
        let cal = planCalendar
        guard let date = cal.date(byAdding: .day, value: weekday - 1, to: Progression.weekStart(now, cal)) else { return }
        let day = PlanCalendar.key(date, cal), today = PlanCalendar.key(now, cal)
        var dated = (sp.placeOnDay ?? [:]).filter { $0.key >= today }
        dated[day] = gymId == (profile?.place(onWeekday: weekday) ?? homeGym.id) ? nil : gymId
        sp.placeOnDay = dated.isEmpty ? nil : dated
        state.synced = sp
        state.profileDirty = true
        replanCurrentWeek(now: now)
        persist()
        Task { await sync() }
    }

    /// Every week (#684): `weekday` at `gymId`, as Training profile → Where I train sets it.
    func setPlaceEveryWeek(_ gymId: String, onWeekday weekday: Int) {
        guard var p = profile else { return }
        if p.dayPlaces == nil {
            // The days lifted on so far keep the plan's gym, so one pick doesn't reshuffle the week (#703).
            let days = p.gymWeekdays ?? (plan?.sessions ?? []).compactMap(\.weekday)
            for d in days where d != weekday { p.setPlace(homeGym.id, onWeekday: d) }
        }
        p.setPlace(gymId, onWeekday: weekday)
        // A one-off pick for that day this week would hide the new weekly place.
        let cal = planCalendar
        if let date = cal.date(byAdding: .day, value: weekday - 1, to: Progression.weekStart(Date(), cal)) {
            state.synced?.placeOnDay?[PlanCalendar.key(date, cal)] = nil
        }
        updateProfile(p)
    }
}

extension SavedGym {
    /// Home with no kit saved (#703): bodyweight and a mat. Saving a home gym in Your gym takes its place.
    static let builtInHome = SavedGym(ref: GymRef(id: "home:bodyweight", name: "Home", address: ""), kind: .home,
                                      equipment: TravelSetup.bodyweight.equipment)
}
