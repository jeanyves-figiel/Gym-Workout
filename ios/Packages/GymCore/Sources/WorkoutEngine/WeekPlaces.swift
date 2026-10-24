import Foundation

// MARK: - Week places (#684, design A)

/// The kit of a gym the member lifts at on some weekdays: its name, equipment and zones.
public struct DayKit: Codable, Hashable, Sendable {
    public var gymId: String
    public var name: String
    public var equipment: [Equipment]
    public var layout: GymLayout?

    public init(gymId: String, name: String, equipment: [Equipment], layout: GymLayout? = nil) {
        self.gymId = gymId
        self.name = name
        self.equipment = equipment
        self.layout = layout
    }
}

extension Profile {
    /// Saved gym id the member lifts at on `weekday`; nil = the plan's gym.
    public func place(onWeekday weekday: Int) -> String? { dayPlaces?[String(weekday)] }

    /// Sets (or clears, with nil) the gym of `weekday`. A day with a gym becomes a gym day.
    public mutating func setPlace(_ gymId: String?, onWeekday weekday: Int) {
        var places = dayPlaces ?? [:]
        places[String(weekday)] = gymId
        dayPlaces = places.isEmpty ? nil : places
        guard dayPlaces != nil else { return }
        let days = places.keys.compactMap(Int.init).sorted()
        gymWeekdays = days.isEmpty ? nil : days
    }

    /// One-off places (#700, "just today"): `dated` maps a day ("yyyy-MM-dd") to a gym id; the days of the week
    /// starting `weekStart` take that gym's kit instead of their weekday's. `kit` resolves a gym id: nil = the plan's
    /// own gym (or one no longer saved), so the day goes back to the plan's kit.
    public func placing(_ dated: [String: String], weekStart: Date, _ cal: Calendar, kit: (String) -> DayKit?) -> Profile {
        var kits = dayKits ?? [:]
        var touched = false
        for (i, key) in PlanCalendar.dayKeys(weekStart: weekStart, cal).enumerated() {
            guard let id = dated[key] else { continue }
            kits[String(i + 1)] = kit(id)
            touched = true
        }
        guard touched else { return self }
        var p = self
        p.dayKits = kits.isEmpty ? nil : kits
        return p
    }

    /// Kit for `weekday` when it isn't the plan's own gym.
    public func kit(onWeekday weekday: Int) -> DayKit? { dayKits?[String(weekday)] }

    /// Profile for sessions at `kit`: its equipment and zones, no per-day kits or runs (those are applied once).
    func at(_ kit: DayKit?) -> Profile {
        var p = self
        p.dayKits = nil
        p.runGoal = nil
        if let kit {
            p.equipment = kit.equipment
            p.gymLayout = kit.layout
        }
        return p
    }
}

extension Generator {
    /// Rebuilds each session for the gym of its weekday (#684): blocks come from the same week generated with that
    /// gym's equipment, so the session type and day stay. Sessions already at the right gym, `skip` ids and library
    /// workouts are kept. Without per-day kits the plan is returned unchanged.
    public static func fitPlaces(_ plan: WeekPlan, _ profile: Profile, skip: Set<String> = [], split: [Focus]? = nil) -> WeekPlan {
        guard let kits = profile.dayKits, !kits.isEmpty else { return plan }
        var plan = plan
        var weeks: [String: WeekPlan] = [:]
        for i in plan.sessions.indices {
            let s = plan.sessions[i]
            guard let wd = s.weekday, !skip.contains(s.id), !s.isPlanInsert else { continue }
            let kit = profile.kit(onWeekday: wd)
            guard kit?.name != s.place else { continue }
            let key = kit?.gymId ?? ""
            if weeks[key] == nil {
                weeks[key] = generateWeek(profile.at(kit), week: plan.week, seed: plan.seed, split: split)
            }
            guard let t = weeks[key]?.sessions.first(where: { $0.id == s.id && $0.focus == s.focus }) else { continue }
            plan.sessions[i].blocks = t.blocks
            plan.sessions[i].estMin = t.estMin
            plan.sessions[i].hiit = t.hiit
            plan.sessions[i].place = kit?.name
            plan.sessions[i].synergy = nil
        }
        return plan
    }
}
