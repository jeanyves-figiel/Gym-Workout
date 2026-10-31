import Foundation

/// Recipe reviews (#1017): what members say about a catalog recipe, anonymous counts.
public struct RecipeReviewSummary: Codable, Sendable, Equatable {
    public var reviews: Int
    /// Average stars (1 decimal), nil when nobody gave stars.
    public var stars: Double?
    public var rated: Int
    /// Members who said the numbers look right / flagged them.
    public var valuesRight: Int
    public var flagged: Int

    public init(reviews: Int = 0, stars: Double? = nil, rated: Int = 0, valuesRight: Int = 0, flagged: Int = 0) {
        self.reviews = reviews
        self.stars = stars
        self.rated = rated
        self.valuesRight = valuesRight
        self.flagged = flagged
    }
}

/// The member's own review. `numbers`: right | portion-big | portion-small | kcal-off; `cooking`: easy | steps-unclear | took-longer.
public struct RecipeReview: Codable, Sendable, Equatable {
    public var stars: Int?
    public var numbers: String?
    public var cooking: String?
    public var updatedAt: String?

    public init(stars: Int? = nil, numbers: String? = nil, cooking: String? = nil, updatedAt: String? = nil) {
        self.stars = stars
        self.numbers = numbers
        self.cooking = cooking
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool { stars == nil && numbers == nil && cooking == nil }
}

public struct RecipeReviewsPage: Codable, Sendable {
    public var summaries: [String: RecipeReviewSummary]
    public var mine: [String: RecipeReview]
}

public struct RecipeReviewSaved: Codable, Sendable {
    public var mine: RecipeReview
    public var summary: RecipeReviewSummary?
}

extension APIClient {
    public func recipeReviews(ids: [String]) async throws -> RecipeReviewsPage {
        let list = ids.prefix(300).joined(separator: ",")
        return try await authorized("GET", "/v1/recipe-reviews?ids=\(list)", Empty?.none, as: RecipeReviewsPage.self)
    }

    public func saveRecipeReview(_ recipeId: String, _ review: RecipeReview) async throws -> RecipeReviewSaved {
        struct Body: Encodable { var stars: Int?; var numbers: String?; var cooking: String? }
        return try await authorized("PUT", "/v1/me/recipe-reviews/\(recipeId)", Body(stars: review.stars, numbers: review.numbers, cooking: review.cooking),
                                    as: RecipeReviewSaved.self)
    }

    public func deleteRecipeReview(_ recipeId: String) async throws {
        _ = try await authorizedRaw("DELETE", "/v1/me/recipe-reviews/\(recipeId)", Empty?.none)
    }
}
