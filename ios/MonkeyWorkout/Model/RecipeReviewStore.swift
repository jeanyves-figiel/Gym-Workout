import APIClient
import Foundation
import WorkoutEngine

/// Recipe reviews (#1017): anonymous counts per catalog recipe and the member's own review, cached for the session.
/// Own recipes and products are never reviewed (their ids aren't catalog ids).
@MainActor @Observable
final class RecipeReviewStore {
    static let shared = RecipeReviewStore()

    private(set) var summaries: [String: RecipeReviewSummary] = [:]
    private(set) var mine: [String: RecipeReview] = [:]
    private var loaded: Set<String> = []
    /// Recipes whose after-eating review prompt was answered or closed (kept on the device).
    private(set) var prompted: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "recipeReviewPrompted") ?? [])

    static func reviewable(_ r: Recipe) -> Bool { !r.isOwn && RecipeBook.catalog.contains { $0.id == r.id } }

    func load(_ ids: [String], api: APIClient, demo: Bool) async {
        let todo = ids.filter { !loaded.contains($0) }
        guard !todo.isEmpty else { return }
        if demo {
            for id in todo { summaries[id] = RecipeReviewSummary(reviews: 214, stars: 4.6, rated: 201, valuesRight: 188, flagged: 3) }
            loaded.formUnion(todo)
            return
        }
        guard let page = try? await api.recipeReviews(ids: todo) else { return }
        summaries.merge(page.summaries) { $1 }
        mine.merge(page.mine) { $1 }
        loaded.formUnion(todo)
    }

    func save(_ id: String, _ review: RecipeReview, api: APIClient, demo: Bool) async throws {
        markPrompted(id)
        if demo {
            mine[id] = review
            return
        }
        let saved = try await api.saveRecipeReview(id, review)
        mine[id] = saved.mine
        if let s = saved.summary { summaries[id] = s }
    }

    func markPrompted(_ id: String) {
        prompted.insert(id)
        UserDefaults.standard.set(Array(prompted), forKey: "recipeReviewPrompted")
    }

    /// Ask after "I ate this" only once per recipe, and never when already reviewed.
    func shouldPrompt(_ r: Recipe) -> Bool { Self.reviewable(r) && mine[r.id] == nil && !prompted.contains(r.id) }
}
