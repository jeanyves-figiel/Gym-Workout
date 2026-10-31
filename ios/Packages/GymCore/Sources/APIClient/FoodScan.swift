import Foundation

/// One food or drink seen on a photo (#573): `id` when it is a food on the app's list, else a new food with the model's
/// own name, group and values per 100 g. `sure` is false when the model was guessing.
public struct FoodSeen: Codable, Sendable, Hashable {
    public struct Per100: Codable, Sendable, Hashable {
        public var protein: Double
        public var carbs: Double
        public var fat: Double
        public var kcal: Double
    }

    public var id: String?
    public var name: String
    public var group: String
    public var sure: Bool
    public var alcohol: Bool
    public var per100: Per100
    /// Plate scan (#723): grams on the plate and caffeine, mg per 100 g.
    public var grams: Double?
    public var caffeine: Double?
}

public struct FoodScanResult: Codable, Sendable {
    /// Food ids on the list seen on the photo (servers before #573 send only these).
    public var items: [String]
    public var found: [FoodSeen]?
    /// Plate scan (#723): the dish, "" when the plate is separate foods.
    public var dish: String?
    /// Magic Snap (#733, `mode: auto`): "meal" (logged) or "stock" (What I have).
    public var kind: String?
    public var remainingToday: Int
}

extension APIClient {
    /// Fuel (#496): foods seen on one JPEG photo of a fridge, cupboard, shopping or receipt; with `plate` (#723) a cooked
    /// meal, answered with the dish and grams per food. Same errors as `gymScan`.
    public func foodScan(jpeg: Data, catalog: [GymScanItem], plate: Bool = false) async throws -> FoodScanResult {
        try await foodScan(jpeg: jpeg, catalog: catalog, mode: plate ? "plate" : "fridge")
    }

    /// `mode` "fridge", "plate" or "auto" (#733, Magic Snap: Monkey says which, in `kind`, and answers like a plate).
    public func foodScan(jpeg: Data, catalog: [GymScanItem], mode: String) async throws -> FoodScanResult {
        struct Body: Encodable { var photo: String; var catalog: [GymScanItem]; var mode: String }
        let body = Body(photo: jpeg.base64EncodedString(), catalog: catalog, mode: mode)
        try await requireAI(.scans)
        return try await scanRequest("/v1/me/food-scan", body, as: FoodScanResult.self)
    }
}
