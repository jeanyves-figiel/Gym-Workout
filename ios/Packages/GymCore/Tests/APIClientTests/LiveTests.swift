import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import APIClient

/// Live group sessions (#626).
@Suite struct LiveTests {
    private func client(_ host: String) -> APIClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubProtocol.self]
        let tokens = InMemoryTokenStore(StoredTokens(accessToken: "a", accessExpiresAt: Date().addingTimeInterval(600), refreshToken: "r"))
        return APIClient(baseURL: URL(string: "https://\(host)")!, tokens: tokens, session: URLSession(configuration: cfg))
    }

    @Test func buddiesCheersAndChallenge() async throws {
        StubProtocol.register("live.test") { req, body in
            let sent = String(decoding: body ?? Data(), as: UTF8.self)
            switch (req.httpMethod!, req.url!.path) {
            case ("GET", "/v1/community/buddies"):
                return (200, #"{"buddies":[{"userId":"u2","nickname":"ana","avatarUrl":null,"level":4,"status":"paired","live":{"title":"Legs","exercise":"Squat","detail":"70 kg × 8","state":"set","updatedAt":"2026-10-22T10:00:00.000Z"},"shareLive":false},{"userId":"u3","nickname":"tom","avatarUrl":null,"level":null,"status":"invites_you","live":null}]}"#)
            case ("PUT", "/v1/community/live"):
                guard sent.contains(#""state":"rest""#), sent.contains(#""challengeWeek":"2026-W43""#) else { return (400, "{}") }
                return (204, "")
            case ("PATCH", "/v1/community/buddies/u2"):
                guard sent.contains(#""shareLive":true"#) else { return (400, "{}") }
                return (200, #"{"shareLive":true}"#)
            case ("POST", "/v1/community/buddies/u2/cheers"):
                guard sent.contains(#""kind":"banana""#) else { return (400, "{}") }
                return (204, "")
            case ("GET", "/v1/community/live/cheers"):
                return (200, #"{"cheers":[{"id":7,"from":{"userId":"u2","nickname":"ana"},"kind":"beast","at":"2026-10-22T10:00:00.000Z"}],"last":7}"#)
            case ("GET", "/v1/community/challenge"):
                return (200, #"{"week":"2026-W43","wod":{"name":"Tabata Tree","format":"tabata","minutes":12,"moves":["jump squats","push-ups","hollow rocks"],"by":null,"memberWeek":false,"card":17,"deckSize":60},"next":{"week":"2026-W44","memberWeek":true,"format":null,"minutes":null,"moveCount":null},"history":[{"week":"2026-W42","name":"Big Ape","rank":4},{"week":"2026-W41","name":"Treetop","rank":null}],"vote":{"week":"2026-W44","endsAt":"2026-10-25T10:00:00.000Z","finalists":[{"id":"s1","name":"Lemur Leap","format":"amrap","minutes":12,"moves":["10 burpees","15 air squats"],"by":{"userId":"u2","nickname":"ana"},"votes":3,"mine":true}]},"joined":41,"training":2,"leaderboard":[{"rank":1,"userId":"u9","nickname":"leo","avatarUrl":null,"level":null,"rounds":0,"reps":210,"seconds":null,"tier":"beast","live":true,"me":false}],"me":null}"#)
            case ("PUT", "/v1/community/challenge/score"):
                guard sent.contains(#""tier":"easy""#), sent.contains(#""reps":180"#) else { return (400, "{}") }
                return (200, #"{"week":"2026-W43","rounds":0,"reps":180,"seconds":null,"tier":"easy","rank":2,"best":true}"#)
            case ("GET", "/v1/community/challenge/suggestions"):
                return (200, #"{"suggestions":[{"id":"s1","name":"Lemur Leap","format":"amrap","minutes":12,"moves":["10 burpees","15 air squats"],"status":"approved","week":null,"createdAt":"2026-10-22T10:00:00.000Z"}],"moves":["air squats","burpees"]}"#)
            case ("POST", "/v1/community/challenge/suggestions"):
                guard sent.contains(#""format":"emom""#) else { return (400, "{}") }
                return (201, #"{"suggestion":{"id":"s2","name":"Ape Ladder","format":"emom","minutes":10,"moves":["10 burpees","10 sit-ups"],"status":"pending","week":null,"createdAt":"2026-10-22T10:00:00.000Z"}}"#)
            case ("PUT", "/v1/community/challenge/vote"):
                guard sent.contains(#""suggestionId":"s1""#) else { return (400, "{}") }
                return (200, #"{"week":"2026-W44","suggestionId":"s1"}"#)
            default: return (404, #"{"error":"not_found","message":"x"}"#)
            }
        }
        let api = client("live.test")
        let buddies = try await api.gymBuddies()
        #expect(buddies.map(\.status) == [.paired, .invitesYou])
        #expect(buddies[0].live?.state == .set && buddies[0].live?.detail == "70 kg × 8")
        // #675: kept from u2; u3 from an older server shares.
        #expect(!buddies[0].sharesLive && buddies[1].sharesLive)
        try await api.setBuddyShareLive("u2", true)
        try await api.setLive(LiveSet(title: "WOD", exercise: "Swings", state: .rest, challengeWeek: "2026-W43"))
        try await api.cheerBuddy("u2", .banana)
        let cheers = try await api.liveCheers(after: 0)
        #expect(cheers.last == 7 && cheers.cheers.first?.kind == .beast)
        let room = try await api.challengeRoom()
        #expect(room.joined == 41 && room.leaderboard.first?.live == true && room.me == nil)
        // #748: the server's WOD, teaser, history and vote.
        #expect(room.wod?.format == .tabata && room.wod?.card == 17 && room.wod?.headline == "Tabata 12′")
        #expect(room.next?.memberWeek == true && room.history?.first?.rank == 4)
        #expect(room.vote?.finalists.first?.mine == true && room.leaderboard.first?.tier == .beast)
        let score = try await api.sendChallengeScore(week: "2026-W43", rounds: 0, reps: 180, tier: .easy)
        #expect(score.rank == 2 && score.best && score.tier == .easy)
        let mine = try await api.challengeSuggestions()
        #expect(mine.suggestions.first?.status == .approved && mine.moves.count == 2)
        let s = try await api.suggestChallenge(name: "Ape Ladder", format: .emom, minutes: 10, moves: ["10 burpees", "10 sit-ups"])
        #expect(s.status == .pending)
        #expect(try await api.voteChallenge("s1").week == "2026-W44")
    }
}
