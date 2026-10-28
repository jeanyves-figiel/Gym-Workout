import Foundation

// Weekly Coach review (#867): the app's week digest in, Coach's score, summary and changes out (types in WorkoutEngine).

extension APIClient {
    private struct CoachReviewBody<D: Encodable & Sendable>: Encodable, Sendable {
        var digest: D
    }

    /// Errors: `daily_limit` (429), `pro_required` (402), `coach_unavailable` (503), `coach_failed` (502).
    public func coachReview<D: Encodable & Sendable, R: Decodable & Sendable>(_ digest: D, as _: R.Type) async throws -> R {
        try await authorized("POST", "/v1/me/coach-review", CoachReviewBody(digest: digest), as: R.self)
    }
}
