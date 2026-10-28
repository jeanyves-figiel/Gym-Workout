import Foundation

// Set up the plan with Coach (#873): the member's sentence in, the plan form's values out; one form step in, a short
// answer and Coach's pick out (types in WorkoutEngine).

extension APIClient {
    private struct CoachPlanBody: Encodable, Sendable {
        var text: String
    }

    /// Errors: `daily_limit` / `busy` (429), `coach_unavailable` (503), `coach_failed` (502).
    public func coachPlan<R: Decodable & Sendable>(_ text: String, as _: R.Type) async throws -> R {
        try await authorized("POST", "/v1/me/coach-plan", CoachPlanBody(text: text), as: R.self)
    }

    /// Same errors as `coachPlan`.
    public func coachPlanHelp<A: Encodable & Sendable, R: Decodable & Sendable>(_ ask: A, as _: R.Type) async throws -> R {
        try await authorized("POST", "/v1/me/coach-plan/help", ask, as: R.self)
    }
}
