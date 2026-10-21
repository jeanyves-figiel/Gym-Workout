import APIClient
import Foundation
import Observation
import WorkoutEngine

/// Features the server can pause (#583). A flag missing from the config, or unknown to this build, is on.
enum RemoteFlag: String {
    case foodScan, gymScan, askCoach
}

/// Over-the-air config (#583): flags, values and the update prompt from `/v1/app-config`, plus content packs
/// (recipes, foods, What's new, Coach tips) used from the next launch. Data only, never code (App Review 2.5.2).
/// Kept on disk, so it holds offline; the first launch with nothing kept behaves like the bundled app.
@MainActor @Observable
final class Remote {
    static let shared = Remote()

    /// Pack names this build reads; others in the config are ignored.
    static let packNames = ["recipes", "foods", "whats-new", "coach-tips"]

    private(set) var config: RemoteConfig
    private var etag: String?
    private var fetchedAt: Date?

    let build = ContentPacks.shared.build
    /// Random per install: rollout buckets, never sent anywhere.
    let install: String = {
        let key = "remote.install"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    private static let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("remote-config.json")
    private static let etagKey = "remote.etag"
    private static let publicKey = Bundle.main.object(forInfoDictionaryKey: "CONTENT_PUBLIC_KEY") as? String

    private init() {
        config = (try? Data(contentsOf: Self.file)).flatMap { try? JSONDecoder().decode(RemoteConfig.self, from: $0) } ?? RemoteConfig()
        etag = config.version.isEmpty ? nil : UserDefaults.standard.string(forKey: Self.etagKey)
    }

    // MARK: Reading

    func isOn(_ flag: RemoteFlag) -> Bool {
        #if DEBUG
        if Demo.enabled { return Demo.screen != "remote-paused" }
        #endif
        return config.isOn(flag.rawValue, build: build, install: install)
    }

    /// The paused card's text when `flag` is off.
    func pausedMessage(_ flag: RemoteFlag) -> String? {
        isOn(flag) ? nil : config.flags[flag.rawValue]?.message ?? "Paused while we fix it. Back soon."
    }

    func value(_ key: String) -> JSONValue? { config.values[key] }

    var updateNeed: RemoteConfig.UpdateNeed {
        #if DEBUG
        if Demo.enabled { return Demo.screen == "remote-required" ? .required : Demo.screen == "remote-banner" ? .recommended : .none }
        #endif
        return config.updateNeed(build: build)
    }

    var update: RemoteConfig.Update {
        config.update ?? .init(title: "New version ready", body: "Update to get the latest fixes.", url: nil)
    }

    /// The config's link, else TestFlight (the app isn't on the App Store yet).
    var updateURL: URL {
        config.update?.url.flatMap(URL.init(string:)) ?? URL(string: "itms-beta://")!
    }

    /// Coach Monkey tips from the `coach-tips` pack, read once per launch like the other packs.
    let coachTips: [RemoteTip] = {
        let build = ContentPacks.shared.build
        return (ContentPacks.shared.load("coach-tips", bundled: nil, decode: { try JSONDecoder().decode([RemoteTip].self, from: $0) }) ?? [])
            .filter { build >= ($0.minBuild ?? 0) && build <= ($0.maxBuild ?? .max) }
    }()

    // MARK: Fetching

    /// At launch and back in the foreground, at most every 5 minutes. Failures keep what's on disk.
    func refresh(_ api: APIClient, force: Bool = false) async {
        #if DEBUG
        if Demo.enabled { return }
        #endif
        if !force, let at = fetchedAt, Date().timeIntervalSince(at) < 300 { return }
        fetchedAt = Date()
        guard let got = try? await api.appConfig(etag: etag) else {
            await syncPacks(api) // 304: the config is the same, a pack may still be missing.
            return
        }
        guard RemoteConfig.verify(got.data, signature: got.signature, publicKey: Self.publicKey),
              let next = try? JSONDecoder().decode(RemoteConfig.self, from: got.data) else { return }
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? got.data.write(to: Self.file, options: .atomic)
        etag = got.etag
        UserDefaults.standard.set(got.etag, forKey: Self.etagKey)
        config = next
        await syncPacks(api)
    }

    private func syncPacks(_ api: APIClient) async {
        let packs = ContentPacks.shared
        let plan = packs.plan(config, known: Self.packNames)
        for name in plan.drop { packs.remove(name) }
        for ref in plan.fetch {
            // Hash from the (signed) config: a pack that doesn't match is not kept.
            if let data = try? await api.contentPack(ref.url) { try? packs.store(ref.name, sha256: ref.sha256, data: data) }
        }
    }
}

/// One tip of the `coach-tips` pack (#583).
struct RemoteTip: Decodable {
    var id: String
    var text: String
    /// Two RGB hex colours.
    var tint: [String]?
    var cta: String
    var action: String
    var minBuild: Int?
    var maxBuild: Int?

    var colors: (UInt32, UInt32) {
        let c = (tint ?? []).compactMap { UInt32($0, radix: 16) }
        return c.count == 2 ? (c[0], c[1]) : (0x3D5AFF, 0x1E9BFF)
    }
}
