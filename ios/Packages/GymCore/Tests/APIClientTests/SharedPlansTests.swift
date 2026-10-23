import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import APIClient

/// Shared plans (#666).
@Suite struct SharedPlansTests {
    struct Prog: Codable, Sendable, Hashable { var id: String; var name: String }

    private func client(_ host: String) -> APIClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubProtocol.self]
        let tokens = InMemoryTokenStore(StoredTokens(accessToken: "a", accessExpiresAt: Date().addingTimeInterval(600), refreshToken: "r"))
        return APIClient(baseURL: URL(string: "https://\(host)")!, tokens: tokens, session: URLSession(configuration: cfg))
    }

    private static let plan = #"{"id":"11111111-1111-4111-8111-111111111111","name":"PPL","about":null,"level":"beginner","goal":"strength","weeks":8,"sessionsPerWeek":3,"programme":{"id":"my-x","name":"PPL"},"author":{"userId":"u2","nickname":"ana","avatarUrl":null,"level":4},"mine":false,"visibility":"members","copies":2,"copiedByMe":false,"hidden":false,"createdAt":"2026-10-23T10:00:00.000Z"}"#

    @Test func listSaveCopyReport() async throws {
        StubProtocol.register("plans.test") { req, body in
            let sent = String(decoding: body ?? Data(), as: UTF8.self)
            switch (req.httpMethod!, req.url!.path) {
            case ("GET", "/v1/community/programs"):
                guard req.url!.query?.contains("level=beginner") == true else { return (400, "{}") }
                // The second plan's programme is unreadable for this app: skipped, not the whole list.
                return (200, #"{"programs":["# + Self.plan + #",{"id":"x","programme":42}],"nextBefore":null,"nextBeforeId":null}"#)
            case ("PUT", "/v1/community/programs/11111111-1111-4111-8111-111111111111"):
                guard sent.contains(#""level":"advanced""#), sent.contains(#""visibility":"members""#) else { return (400, "{}") }
                return (200, #"{"program":"# + Self.plan + "}")
            case ("POST", "/v1/community/programs/11111111-1111-4111-8111-111111111111/copy"):
                return (200, #"{"program":"# + Self.plan.replacingOccurrences(of: #""copies":2,"copiedByMe":false"#, with: #""copies":3,"copiedByMe":true"#) + "}")
            case ("POST", "/v1/community/programs/11111111-1111-4111-8111-111111111111/report"):
                return (202, #"{"status":"received","hidden":false}"#)
            case ("DELETE", "/v1/community/programs/11111111-1111-4111-8111-111111111111"):
                return (204, "")
            default: return (404, #"{"error":"not_found","message":"x"}"#)
            }
        }
        let api = client("plans.test")
        let list = try await api.sharedPlans(Prog.self, level: .beginner)
        #expect(list.count == 1 && list[0].programme.name == "PPL" && list[0].author.nickname == "ana")
        let id = "11111111-1111-4111-8111-111111111111"
        let saved = try await api.saveSharedPlan(id: id, SharedPlanDraft(name: "PPL", about: nil, level: .advanced, goal: nil, weeks: 8,
                                                                         sessionsPerWeek: 3, programme: Prog(id: "my-x", name: "PPL"), visibility: .members))
        #expect(saved.id == id)
        let copied = try await api.countSharedPlanCopy(id, as: Prog.self)
        #expect(copied.copies == 3 && copied.copiedByMe)
        #expect(try await api.reportSharedPlan(id, reason: .spam) == false)
        try await api.deleteSharedPlan(id)
    }
}
