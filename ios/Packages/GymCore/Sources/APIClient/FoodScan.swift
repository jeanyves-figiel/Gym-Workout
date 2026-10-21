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
}

public struct FoodScanResult: Codable, Sendable {
    /// Food ids on the list seen on the photo (servers before #573 send only these).
    public var items: [String]
    public var found: [FoodSeen]?
    public var remainingToday: Int
}

extension APIClient {
    /// Fuel (#496): foods seen on one JPEG photo of a fridge, cupboard, shopping or receipt. Same errors as `gymScan`.
    public func foodScan(jpeg: Data, catalog: [GymScanItem]) async throws -> FoodScanResult {
        struct Body: Encodable { var photo: String; var catalog: [GymScanItem] }
        return try await scanRequest("/v1/me/food-scan", Body(photo: jpeg.base64EncodedString(), catalog: catalog), as: FoodScanResult.self)
    }
}
