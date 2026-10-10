import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import APIClient

private func client(_ host: String) -> APIClient {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [StubProtocol.self]
    let tokens = InMemoryTokenStore(StoredTokens(accessToken: "a", accessExpiresAt: Date().addingTimeInterval(600), refreshToken: "r"))
    return APIClient(baseURL: URL(string: "https://\(host)")!, tokens: tokens, session: URLSession(configuration: cfg))
}

private let postJSON = #"""
{"id":"4f0c1c1e-8a7b-4c47-9a63-0d1b0a3c2f10","author":{"userId":"u2","nickname":"bench_bea","avatarUrl":"/v1/community/avatars/x"},
"mine":false,"kind":"workout","refId":"w1","visibility":"members","caption":"80 kg!","payload":{"title":"Upper body","metric":{"value":"6.4","unit":"t lifted"},
"style":"strength","stats":[{"label":"min","value":"52"}]},"hidden":false,"createdAt":"2026-10-10T10:00:00.000Z",
"reactions":{"like":2,"strong":1,"fire":0,"clap":0},"myReactions":["like"]}
"""#

@Suite struct CommunityTests {
    @Test func decodesFeedAndSendsShareBody() async throws {
        StubProtocol.register("community.test") { req, body in
            switch (req.httpMethod!, req.url!.path) {
            case ("GET", "/v1/community/feed"):
                guard req.url!.query?.contains("scope=mine") == true else { return (400, "{}") }
                return (200, #"{"posts":[\#(postJSON)],"nextBefore":null}"#)
            case ("POST", "/v1/community/posts"):
                let sent = String(decoding: body ?? Data(), as: UTF8.self)
                guard sent.contains(#""visibility":"public""#), sent.contains(#""kind":"badge""#) else { return (400, "{}") }
                return (200, #"{"post":\#(postJSON)}"#)
            case ("PUT", "/v1/community/posts/p1/reactions/strong"):
                return (200, #"{"post":\#(postJSON)}"#)
            default: return (404, #"{"error":"not_found","message":"x"}"#)
            }
        }
        let api = client("community.test")
        let page = try await api.communityFeed(.mine)
        let p = try #require(page.posts.first)
        #expect(page.nextBefore == nil)
        #expect(p.count(.like) == 2 && p.reacted(.like) && !p.reacted(.strong))
        #expect(p.totalCheers == 3)
        #expect(p.payload.metric?.unit == "t lifted")
        #expect(api.resolve(p.author.avatarUrl)?.absoluteString == "https://community.test/v1/community/avatars/x")
        _ = try await api.sharePost(kind: "badge", refId: "s8", visibility: .everyone, caption: nil, card: CommunityCard(title: "Unbreakable"))
        _ = try await api.react("p1", .strong, on: true)
    }

    @Test func uploadsAvatarAsJPEG() async throws {
        StubProtocol.register("avatar.test") { req, body in
            guard req.value(forHTTPHeaderField: "Content-Type") == "image/jpeg", body == Data([0xFF, 0xD8, 0xFF, 0xD9]) else { return (400, "{}") }
            return (200, #"{"profile":{"userId":"u1","nickname":"jy_","bio":null,"avatarUrl":"/v1/community/avatars/a","defaultVisibility":"private","autoShare":false,"guidelinesAcceptedAt":"2026-10-10T10:00:00.000Z","sharedPosts":0,"cheersReceived":0}}"#)
        }
        let p = try await client("avatar.test").uploadAvatar(jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        #expect(p.defaultVisibility == .onlyMe)
        #expect(p.avatarUrl == "/v1/community/avatars/a")
    }
}
