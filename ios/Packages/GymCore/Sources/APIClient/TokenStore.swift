import Foundation
#if canImport(Security)
import Security
#endif

public protocol TokenStore: Sendable {
    func load() -> StoredTokens?
    func save(_ tokens: StoredTokens)
    func clear()
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: StoredTokens?

    public init(_ tokens: StoredTokens? = nil) { self.tokens = tokens }

    public func load() -> StoredTokens? { lock.withLock { tokens } }
    public func save(_ tokens: StoredTokens) { lock.withLock { self.tokens = tokens } }
    public func clear() { lock.withLock { tokens = nil } }
}

#if canImport(Security)
/// One generic-password Keychain item, this device only, readable after first unlock (background sync).
public struct KeychainItem: Sendable {
    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func load() -> Data? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return data
    }

    public func save(_ data: Data) {
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            _ = SecItemAdd(query.merging(attrs) { $1 } as CFDictionary, nil)
        }
    }

    public func clear() { _ = SecItemDelete(query as CFDictionary) }

    /// JSON-encoded value.
    public func loadJSON<T: Decodable>(_: T.Type) -> T? {
        load().flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    public func saveJSON(_ value: some Encodable) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        save(data)
    }
}

/// Tokens in the Keychain, this device only, readable after first unlock (background sync).
public final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    private let item: KeychainItem

    public init(service: String) { item = KeychainItem(service: service, account: "tokens") }

    public func load() -> StoredTokens? { item.loadJSON(StoredTokens.self) }
    public func save(_ tokens: StoredTokens) { item.saveJSON(tokens) }
    public func clear() { item.clear() }
}
#endif
