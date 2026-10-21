import CryptoKit
import Foundation

/// Over-the-air config (#583) from `/v1/app-config`: flags, values, minimum / recommended build and content packs.
/// App Review 2.5.2: data only, never code. Every field has a safe default, so an empty or old config changes nothing.
public struct RemoteConfig: Codable, Sendable, Equatable {
    public struct Flag: Codable, Sendable, Equatable {
        public var on: Bool
        public var minBuild: Int?
        public var maxBuild: Int?
        public var percent: Double?
        public var message: String?

        public init(on: Bool, minBuild: Int? = nil, maxBuild: Int? = nil, percent: Double? = nil, message: String? = nil) {
            self.on = on
            self.minBuild = minBuild
            self.maxBuild = maxBuild
            self.percent = percent
            self.message = message
        }
    }

    public struct Update: Codable, Sendable, Equatable {
        public var title: String
        public var body: String
        /// App Store or TestFlight link; the app falls back to TestFlight.
        public var url: String?

        public init(title: String, body: String, url: String? = nil) {
            self.title = title
            self.body = body
            self.url = url
        }
    }

    public struct PackRef: Codable, Sendable, Equatable {
        public var name: String
        public var sha256: String
        public var bytes: Int
        public var minBuild: Int?
        public var maxBuild: Int?
        public var url: String

        public init(name: String, sha256: String, bytes: Int, minBuild: Int? = nil, maxBuild: Int? = nil, url: String) {
            self.name = name
            self.sha256 = sha256
            self.bytes = bytes
            self.minBuild = minBuild
            self.maxBuild = maxBuild
            self.url = url
        }

        public func fits(build: Int) -> Bool { RemoteConfig.inRange(build, minBuild, maxBuild) }
    }

    public var version: String
    public var minimumBuild: Int
    public var recommendedBuild: Int
    public var update: Update?
    public var flags: [String: Flag]
    public var values: [String: JSONValue]
    public var packs: [PackRef]

    public init(version: String = "", minimumBuild: Int = 0, recommendedBuild: Int = 0, update: Update? = nil,
                flags: [String: Flag] = [:], values: [String: JSONValue] = [:], packs: [PackRef] = []) {
        self.version = version
        self.minimumBuild = minimumBuild
        self.recommendedBuild = recommendedBuild
        self.update = update
        self.flags = flags
        self.values = values
        self.packs = packs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        minimumBuild = try c.decodeIfPresent(Int.self, forKey: .minimumBuild) ?? 0
        recommendedBuild = try c.decodeIfPresent(Int.self, forKey: .recommendedBuild) ?? 0
        update = try c.decodeIfPresent(Update.self, forKey: .update)
        // One flag or pack this build can't read must not throw away the rest.
        flags = (try? c.decodeIfPresent([String: Lossy<Flag>].self, forKey: .flags))?.compactMapValues(\.value) ?? [:]
        values = (try? c.decodeIfPresent([String: JSONValue].self, forKey: .values)) ?? [:]
        packs = (try? c.decodeIfPresent([Lossy<PackRef>].self, forKey: .packs))?.compactMap(\.value) ?? []
    }

    public enum UpdateNeed: Sendable, Equatable { case none, recommended, required }

    public func updateNeed(build: Int) -> UpdateNeed {
        guard build > 0 else { return .none } // Debug / tests: no build number.
        if build < minimumBuild, update != nil { return .required }
        if build < recommendedBuild, update != nil { return .recommended }
        return .none
    }

    /// Off only when the server says so for this build and install bucket; unknown flags are on.
    public func isOn(_ name: String, build: Int, install: String) -> Bool {
        guard let f = flags[name], Self.inRange(build, f.minBuild, f.maxBuild) else { return true }
        guard f.on else { return false }
        guard let p = f.percent else { return true }
        return Double(Self.bucket(install, name)) < p
    }

    /// 0…99, stable per install and flag (FNV-1a), so a rollout keeps the same installs as it grows.
    public static func bucket(_ install: String, _ flag: String) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for b in (install + ":" + flag).utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return Int(h % 100)
    }

    static func inRange(_ build: Int, _ min: Int?, _ max: Int?) -> Bool {
        build >= (min ?? 0) && build <= (max ?? .max)
    }

    /// Ed25519 over the exact body bytes (`X-Content-Signature`). No public key in the build → not checked.
    public static func verify(_ data: Data, signature: String?, publicKey: String?) -> Bool {
        guard let publicKey, !publicKey.isEmpty else { return true }
        guard let signature, let sig = Data(base64Encoded: signature), let raw = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
        return key.isValidSignature(sig, for: data)
    }
}

private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// Any JSON value from `values`.
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }

    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var number: Double? { if case .number(let n) = self { n } else { nil } }
    public var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
}

/// Content packs (#583): a downloaded copy of a bundled data file, used from the next launch for the build that
/// fetched it. A new build drops it (it bundles its own, newer copy) until the server lists one for it again.
public struct ContentPacks: Sendable {
    public let directory: URL
    public let build: Int

    public static let shared = ContentPacks(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ContentPacks"),
        build: Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0)

    public init(directory: URL, build: Int) {
        self.directory = directory
        self.build = build
    }

    private struct Stamp: Codable { var sha256: String; var build: Int }

    private func file(_ name: String) -> URL { directory.appendingPathComponent("\(name).json") }
    private func stampFile(_ name: String) -> URL { directory.appendingPathComponent("\(name).stamp") }

    private func stamp(_ name: String) -> Stamp? {
        (try? Data(contentsOf: stampFile(name))).flatMap { try? JSONDecoder().decode(Stamp.self, from: $0) }
    }

    /// Hash of the pack kept for this build, if any.
    public func current(_ name: String) -> String? {
        stamp(name).flatMap { $0.build == build ? $0.sha256 : nil }
    }

    /// The pack for this build when there is one and `decode` accepts it, else the bundled file.
    public func load<T>(_ name: String, bundled: URL?, decode: (Data) throws -> T, valid: (T) -> Bool = { _ in true }) -> T? {
        if current(name) != nil, let data = try? Data(contentsOf: file(name)), let v = try? decode(data), valid(v) { return v }
        return bundled.flatMap { try? Data(contentsOf: $0) }.flatMap { try? decode($0) }
    }

    public func data(_ name: String) -> Data? {
        current(name) == nil ? nil : try? Data(contentsOf: file(name))
    }

    public enum StoreError: Error { case hashMismatch }

    /// Keeps `data` only when it hashes to `sha256` (the hash comes from the signed config).
    public func store(_ name: String, sha256: String, data: Data) throws {
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hex == sha256 else { throw StoreError.hashMismatch }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file(name), options: .atomic)
        try JSONEncoder().encode(Stamp(sha256: sha256, build: build)).write(to: stampFile(name), options: .atomic)
    }

    public func remove(_ name: String) {
        try? FileManager.default.removeItem(at: stampFile(name))
        try? FileManager.default.removeItem(at: file(name))
    }

    /// Packs to fetch and to drop for `config`, among the `known` names this build reads.
    public func plan(_ config: RemoteConfig, known: [String]) -> (fetch: [RemoteConfig.PackRef], drop: [String]) {
        let wanted = config.packs.filter { known.contains($0.name) && $0.fits(build: build) }
        let fetch = wanted.filter { current($0.name) != $0.sha256 }
        let drop = known.filter { n in !wanted.contains { $0.name == n } && stamp(n) != nil }
        return (fetch, drop)
    }
}
