import Foundation

// Gym Map (#406): floor plans shared per gym, live crowd from "Taken?" taps, and the photo scan.

/// The plan members at a gym agree with most (yours not counted).
public struct SharedGymMap<Layout: Codable & Sendable>: Codable, Sendable {
    public var layout: Layout
    /// Members who mapped this gym.
    public var members: Int
    /// How much the plans agree (0–100); nil with one plan.
    public var agreement: Int?

    public init(layout: Layout, members: Int, agreement: Int?) {
        self.layout = layout
        self.members = members
        self.agreement = agreement
    }
}

/// Busy taps at a gym: right now (last 20 min) and per local hour on today's weekday (8 weeks).
public struct GymCrowd: Codable, Sendable, Equatable {
    public struct Live: Codable, Sendable, Equatable {
        /// Zone name, lowercased.
        public var zone: String
        public var reports: Int

        public init(zone: String, reports: Int) {
            self.zone = zone
            self.reports = reports
        }
    }

    public struct Forecast: Codable, Sendable, Equatable {
        public var zone: String
        /// 24 counts, one per local hour.
        public var hours: [Int]

        public init(zone: String, hours: [Int]) {
            self.zone = zone
            self.hours = hours
        }
    }

    public var now: [Live]
    public var forecast: [Forecast]

    public init(now: [Live] = [], forecast: [Forecast] = []) {
        self.now = now
        self.forecast = forecast
    }

    /// Members who found `zone` busy in the last 20 minutes.
    public func reports(_ zone: String) -> Int { now.first { $0.zone == zone.lowercased() }?.reports ?? 0 }
}

public struct GymScanItem: Codable, Sendable {
    public var id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct GymScanResult: Codable, Sendable {
    /// Equipment ids seen on the photo.
    public var items: [String]
    public var remainingToday: Int
}

extension APIClient {
    private static func q(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? ""
    }

    /// Other members' plan for this gym; nil when nobody mapped it.
    public func sharedGymMap<L: Codable & Sendable>(_ gym: GymPlace, as _: L.Type) async throws -> SharedGymMap<L>? {
        var path = "/v1/gyms/maps?id=\(Self.q(gym.id))&name=\(Self.q(gym.name))"
        if let lat = gym.latitude, let lng = gym.longitude { path += "&lat=\(lat)&lng=\(lng)" }
        return try await authorized("GET", path, Empty?.none, as: SharedMapAnswer<L>.self).map
    }

    /// Your plan for this gym; replaces your earlier one.
    public func shareGymMap<L: Codable & Sendable>(_ gym: GymPlace, layout: L) async throws {
        _ = try await authorizedRaw("PUT", "/v1/gyms/maps", SharedMapBody(gym: gym, layout: layout))
    }

    /// "Taken?": `zone` (its name) is busy right now.
    public func reportBusy(gymId: String, zone: String) async throws {
        struct G: Encodable { var id: String }
        struct Body: Encodable { var gym: G; var zone: String }
        _ = try await authorizedRaw("POST", "/v1/gyms/busy", Body(gym: G(id: gymId), zone: zone))
    }

    /// Live crowd and rush hours; `utcOffsetMinutes` makes the hours local.
    public func gymCrowd(gymId: String, utcOffsetMinutes: Int) async throws -> GymCrowd {
        try await authorized("GET", "/v1/gyms/crowd?id=\(Self.q(gymId))&tz=\(utcOffsetMinutes)", Empty?.none, as: GymCrowd.self)
    }

    /// Equipment seen on one JPEG photo. Errors: `pro_required` (402), `verification_required` (403), `daily_limit` (429),
    /// `scan_unavailable` (503), `scan_failed` (502), `bad_photo` (400).
    public func gymScan(jpeg: Data, catalog: [GymScanItem]) async throws -> GymScanResult {
        struct Body: Encodable { var photo: String; var catalog: [GymScanItem] }
        return try await scanRequest("/v1/me/gym-scan", Body(photo: jpeg.base64EncodedString(), catalog: catalog), as: GymScanResult.self)
    }
}

private struct SharedMapAnswer<L: Codable & Sendable>: Decodable, Sendable {
    var map: SharedGymMap<L>?
}

private struct SharedMapBody<L: Codable & Sendable>: Encodable, Sendable {
    var gym: GymPlace
    var layout: L
}
