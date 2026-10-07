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
/// Tokens in the Keychain, this device only, readable after first unlock (background sync).
public final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    private let service: String
    private let account = "tokens"

    public init(service: String) { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func load() -> StoredTokens? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(StoredTokens.self, from: data)
    }

    public func save(_ tokens: StoredTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            _ = SecItemAdd(query.merging(attrs) { $1 } as CFDictionary, nil)
        }
    }

    public func clear() { _ = SecItemDelete(query as CFDictionary) }
}
#endif
