import Foundation
import WorkoutEngine

/// Plan sport (#474): dated sport days and trips, and weekly sport days set from a calendar day.
extension AppModel {
    /// Dated sport days and trips, earliest first.
    var sportTrips: [SportTrip] { (profile?.sportTrips ?? []).sorted { ($0.start, $0.end) < ($1.start, $1.end) } }

    /// Adds or replaces a dated sport day or trip; trips that ended more than 8 weeks ago are dropped.
    func saveSportTrip(_ trip: SportTrip) {
        guard var p = profile else { return }
        var list = p.sportTrips ?? []
        if let i = list.firstIndex(where: { $0.id == trip.id }) { list[i] = trip } else { list.append(trip) }
        let cutoff = PlanCalendar.key(planCalendar.date(byAdding: .day, value: -56, to: Date())!, planCalendar)
        list = list.filter { $0.end >= cutoff }
        p.sportTrips = list.isEmpty ? nil : list
        updateProfile(p)
    }

    func deleteSportTrip(_ id: UUID) {
        guard var p = profile, p.sportTrips?.contains(where: { $0.id == id }) == true else { return }
        p.sportTrips?.removeAll { $0.id == id }
        if p.sportTrips?.isEmpty == true { p.sportTrips = nil }
        updateProfile(p)
    }

    /// Every week: adds the weekday to the sport's usual days (the sport is added, or switched back on, if needed).
    func addWeeklySportDay(_ sport: Sport, weekday: Int) {
        guard var p = profile else { return }
        if sport == .climbing {
            p.climbs = true
            p.climbingWeekdays = WeekSchedule.normalized((p.climbingWeekdays ?? []) + [weekday])
            p.syncClimbingDays()
        } else {
            var list = p.sports ?? []
            if let i = list.firstIndex(where: { $0.sport == sport }) {
                list[i].weekdays = WeekSchedule.normalized(list[i].weekdays + [weekday])
                list[i].paused = nil
            } else {
                list.append(SportPlan(sport: sport, weekdays: [weekday]))
            }
            p.sports = list
        }
        updateProfile(p)
    }
}
