import CryptoKit
import Foundation
import Testing
@testable import WorkoutEngine

@Suite struct RemoteConfigTests {
    let json = """
    {"version":"v1","minimumBuild":58,"recommendedBuild":60,"update":{"title":"Build 60","body":"Fixes"},
     "flags":{"foodScan":{"on":false,"message":"Paused"},"askCoach":{"on":true,"percent":50},"old":{"on":false,"maxBuild":55},
              "broken":{"on":"yes"}},
     "values":{"coach.max":3,"copy":"Hi","on":true},
     "packs":[{"name":"recipes","sha256":"ab","bytes":2,"minBuild":59,"maxBuild":60,"url":"/v1/packs/recipes/ab"},{"name":42}]}
    """

    var config: RemoteConfig { try! JSONDecoder().decode(RemoteConfig.self, from: Data(json.utf8)) }

    @Test func decodesAndSkipsWhatItCantRead() {
        let c = config
        #expect(c.flags["broken"] == nil)
        #expect(c.flags.count == 3)
        #expect(c.packs.map(\.name) == ["recipes"])
        #expect(c.values["coach.max"]?.number == 3)
        #expect(c.values["copy"]?.string == "Hi")
        #expect(c.values["on"]?.bool == true)
        #expect((try? JSONDecoder().decode(RemoteConfig.self, from: Data("{}".utf8))) == RemoteConfig())
    }

    @Test func updateNeedFollowsBuild() {
        #expect(config.updateNeed(build: 57) == .required)
        #expect(config.updateNeed(build: 59) == .recommended)
        #expect(config.updateNeed(build: 60) == .none)
        #expect(config.updateNeed(build: 0) == .none)
        #expect(RemoteConfig(minimumBuild: 99).updateNeed(build: 50) == .none) // No text, no screen.
    }

    @Test func flagsByBuildAndBucket() {
        let c = config
        #expect(!c.isOn("foodScan", build: 59, install: "a"))
        #expect(c.isOn("old", build: 59, install: "a")) // Out of its build range.
        #expect(!c.isOn("old", build: 55, install: "a"))
        #expect(c.isOn("unknown", build: 59, install: "a"))
        let ons = (0..<400).filter { c.isOn("askCoach", build: 59, install: "install-\($0)") }.count
        #expect(ons > 150 && ons < 250)
        #expect(RemoteConfig.bucket("x", "askCoach") == RemoteConfig.bucket("x", "askCoach"))
    }

    @Test func signatureChecksExactBytes() {
        let key = Curve25519.Signing.PrivateKey()
        let body = Data(json.utf8)
        let sig = try! key.signature(for: body).base64EncodedString()
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        #expect(RemoteConfig.verify(body, signature: sig, publicKey: pub))
        #expect(!RemoteConfig.verify(body + Data(" ".utf8), signature: sig, publicKey: pub))
        #expect(!RemoteConfig.verify(body, signature: nil, publicKey: pub))
        #expect(RemoteConfig.verify(body, signature: nil, publicKey: nil))
    }

    @Test func packsStoreByHashAndStayWithTheirBuild() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let data = Data(#"[{"id":"x"}]"#.utf8)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let packs = ContentPacks(directory: dir, build: 59)
        #expect(throws: ContentPacks.StoreError.self) { try packs.store("recipes", sha256: "00", data: data) }
        try packs.store("recipes", sha256: sha, data: data)
        #expect(packs.current("recipes") == sha)
        #expect(packs.data("recipes") == data)
        // Next build: the pack is ignored and dropped unless the config lists one for it.
        let next = ContentPacks(directory: dir, build: 60)
        #expect(next.current("recipes") == nil)
        #expect(next.load("recipes", bundled: nil, decode: { $0 }) == nil)
        let ref = RemoteConfig.PackRef(name: "recipes", sha256: sha, bytes: data.count, maxBuild: 59, url: "/x")
        #expect(next.plan(RemoteConfig(packs: [ref]), known: ["recipes"]).drop == ["recipes"])
        #expect(packs.plan(RemoteConfig(packs: [ref]), known: ["recipes"]).fetch.isEmpty)
        let newer = RemoteConfig.PackRef(name: "recipes", sha256: "ff", bytes: 1, url: "/y")
        #expect(packs.plan(RemoteConfig(packs: [newer]), known: ["recipes"]).fetch == [newer])
    }

    @Test func badPackFallsBackToBundled() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let packs = ContentPacks(directory: dir, build: 59)
        let data = Data("[]".utf8)
        try packs.store("foods", sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), data: data)
        let bundled = dir.appendingPathComponent("bundled.json")
        try Data(#"[{"id":"b"}]"#.utf8).write(to: bundled)
        let list = packs.load("foods", bundled: bundled, decode: { try JSONDecoder().decode([[String: String]].self, from: $0) }, valid: { !$0.isEmpty })
        #expect(list?.first?["id"] == "b")
    }
}
