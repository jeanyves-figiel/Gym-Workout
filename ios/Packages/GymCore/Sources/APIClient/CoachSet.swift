import Foundation

// Talk to Coach mid-set (#874): the question and the set on screen in, a short answer and up to 2 fixes out (types in
// WorkoutEngine).

extension APIClient {
    private struct CoachSetBody<C: Encodable & Sendable>: Encodable, Sendable {
        var question: String
        var context: C
    }

    /// Errors: `daily_limit` / `busy` (429), `pro_required` (402), `coach_unavailable` (503), `coach_failed` (502).
    public func coachSet<C: Encodable & Sendable, R: Decodable & Sendable>(_ question: String, context: C, as _: R.Type) async throws -> R {
        try await requireAI(.coach)
        return try await authorized("POST", "/v1/me/coach-set", CoachSetBody(question: question, context: context), as: R.self)
    }
}
