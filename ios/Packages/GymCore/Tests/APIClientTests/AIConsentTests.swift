import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import APIClient

/// Third-party AI consent (#972): nothing goes to the server for a feature the member said no to.
struct AIConsentTests {
    @Test func stateAllowsOnlyAfterTheAnswer() {
        var s = AIConsentState()
        #expect(!s.allows(.coach))
        s.answer([.coach, .scans])
        #expect(s.allows(.coach) && s.allows(.scans) && !s.allows(.review))
        s.set(.review, true)
        s.set(.coach, false)
        #expect(s.allows(.review) && !s.allows(.coach))
        var no = AIConsentState()
        no.answer([])
        #expect(no.decided && AIFeature.allCases.allSatisfy { !no.allows($0) })
    }

    @Test func declinedFeatureNeverReachesTheServer() async throws {
        let store = InMemoryTokenStore(StoredTokens(accessToken: "a", accessExpiresAt: Date().addingTimeInterval(600), refreshToken: "r"))
        let hits = Counter()
        StubProtocol.register("ai.test") { req, _ in
            _ = hits.hit(req.url!.path)
            return (200, #"{"ideas":[],"remainingToday":3}"#)
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubProtocol.self]
        let api = APIClient(baseURL: URL(string: "https://ai.test")!, tokens: store, session: URLSession(configuration: cfg))
        let asked = Counter()
        await api.setAIConsent { f in _ = asked.hit(f.rawValue); return f != .scans }
        await #expect(throws: APIError.aiOff) {
            _ = try await api.gymScan(jpeg: Data([0xFF, 0xD8]), catalog: [])
        }
        await #expect(throws: APIError.aiOff) {
            _ = try await api.foodScan(jpeg: Data([0xFF, 0xD8]), catalog: [])
        }
        #expect(hits.get("/v1/me/gym-scan") == 0 && hits.get("/v1/me/food-scan") == 0)
        #expect(asked.get("scans") == 2)
        _ = try await api.mealIdeas(pantry: [], meal: "lunch", protein: 30, carbs: 40, diet: nil, avoid: [])
        #expect(hits.get("/v1/me/meal-ideas") == 1 && asked.get("ideas") == 1)
    }
}
