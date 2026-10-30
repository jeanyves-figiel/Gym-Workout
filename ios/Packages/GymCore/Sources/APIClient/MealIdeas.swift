import Foundation

/// "What can I eat?" (#869): up to three meals made of pantry foods, by id with grams.
public struct MealIdeasResult: Codable, Sendable {
    public struct Idea: Codable, Sendable, Hashable {
        public struct Food: Codable, Sendable, Hashable {
            public var id: String
            public var grams: Double
        }

        public var name: String
        public var minutes: Int
        public var foods: [Food]
        public var steps: [String]
    }

    public var ideas: [Idea]
    public var remainingToday: Int
}

extension APIClient {
    /// `meal` breakfast, lunch, dinner or snack; `protein`/`carbs` grams still to eat today. Pro; same errors as `foodScan`.
    public func mealIdeas(pantry: [GymScanItem], meal: String, protein: Int, carbs: Int, diet: String?, avoid: [String]) async throws -> MealIdeasResult {
        struct Left: Encodable { var protein: Int; var carbs: Int }
        struct Body: Encodable { var pantry: [GymScanItem]; var meal: String; var left: Left; var diet: String?; var avoid: [String] }
        let body = Body(pantry: pantry, meal: meal, left: Left(protein: protein, carbs: carbs), diet: diet, avoid: avoid)
        try await requireAI(.ideas)
        return try await scanRequest("/v1/me/meal-ideas", body, as: MealIdeasResult.self)
    }
}
