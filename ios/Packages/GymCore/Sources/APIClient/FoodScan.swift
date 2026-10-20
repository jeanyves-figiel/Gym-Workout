import Foundation

extension APIClient {
    /// Fuel (#496): food ids seen on one JPEG photo of a fridge, cupboard, shopping or receipt. Same errors as `gymScan`.
    public func foodScan(jpeg: Data, catalog: [GymScanItem]) async throws -> GymScanResult {
        struct Body: Encodable { var photo: String; var catalog: [GymScanItem] }
        return try await scanRequest("/v1/me/food-scan", Body(photo: jpeg.base64EncodedString(), catalog: catalog), as: GymScanResult.self)
    }
}
