import Foundation

/// Gym Map (#406): the walk a session takes through the member's gym, zone by zone, from the entrance.
public struct GymRoute: Hashable, Sendable {
    public struct Stop: Hashable, Sendable {
        public var zone: GymLayout.Zone
        /// Exercises done there, in order (ones done anywhere ride the stop they fall in).
        public var exerciseIds: [String]
    }

    public var stops: [Stop]
    /// Rough walking distance from the entrance through every stop; nil without a floor plan.
    public var metres: Int?

    /// Times the member changes zone.
    public var walks: Int { max(0, stops.count - 1) }
}

extension GymLayout {
    /// Plan size in metres without a room scan: a typical gym floor (the plan is drawn 4:5, width:height).
    public static let planWidthM = 30.0
    public static let planHeightM = 37.5

    /// Entrance, or the middle of the bottom wall.
    public var entrance: Point { door ?? Point(x: 0.5, y: 1) }

    /// Metres between two plan points (scanned room size, else a typical gym floor).
    public func metres(_ a: Point, _ b: Point) -> Double {
        let dx = (a.x - b.x) * (sizeM?.x ?? Self.planWidthM), dy = (a.y - b.y) * (sizeM?.y ?? Self.planHeightM)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Route through the gym for exercises in workout order. Consecutive exercises in one zone are one stop; an
    /// exercise done anywhere stays at the stop it falls in (or the first stop when it comes before any).
    public func route(_ exerciseIds: [String]) -> GymRoute {
        var stops: [GymRoute.Stop] = []
        var loose: [String] = []
        for id in exerciseIds {
            guard let e = Exercise.find(id), let z = zone(of: e) else {
                if stops.isEmpty { loose.append(id) } else { stops[stops.count - 1].exerciseIds.append(id) }
                continue
            }
            if stops.last?.zone.id == z.id {
                stops[stops.count - 1].exerciseIds.append(id)
            } else {
                stops.append(GymRoute.Stop(zone: z, exerciseIds: stops.isEmpty ? loose + [id] : [id]))
            }
        }
        var walked: Int?
        if hasPlan {
            var at = entrance
            var sum = 0.0
            for s in stops {
                guard let c = s.zone.rect?.center else { continue }
                sum += metres(at, c)
                at = c
            }
            walked = Int(sum.rounded())
        }
        return GymRoute(stops: stops, metres: walked)
    }
}

/// "Taken?" tap (#406): the member found a zone busy at this time.
public struct BusyTap: Codable, Hashable, Sendable {
    public var zoneId: String
    public var at: Date

    public init(zoneId: String, at: Date) {
        self.zoneId = zoneId
        self.at = at
    }
}

/// Rush hours learned from the member's own "Taken?" taps (#406).
public enum GymBusy {
    /// Taps kept: the last 8 weeks.
    public static let window: TimeInterval = 56 * 86_400
    /// Within this many minutes of the time of day counts as "around now".
    public static let slackMin = 45

    /// Taps on `zone` around `date`'s time of day in the last 8 weeks; one on the same weekday counts double.
    public static func score(_ taps: [BusyTap], zone: String, at date: Date, calendar: Calendar = .current) -> Int {
        let minute = { (d: Date) -> Int in
            let c = calendar.dateComponents([.hour, .minute], from: d)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        let now = minute(date)
        let day = calendar.component(.weekday, from: date)
        return taps.reduce(0) { sum, t in
            guard t.zoneId == zone, t.at <= date, date.timeIntervalSince(t.at) <= window else { return sum }
            let diff = abs(minute(t.at) - now)
            guard min(diff, 1440 - diff) <= slackMin else { return sum }
            return sum + (calendar.component(.weekday, from: t.at) == day ? 2 : 1)
        }
    }

    /// Busy around this time often enough to plan around (two taps, or one on the same weekday).
    public static func usuallyBusy(_ taps: [BusyTap], zone: String, at date: Date, calendar: Calendar = .current) -> Bool {
        score(taps, zone: zone, at: date, calendar: calendar) >= 2
    }
}
