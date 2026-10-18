import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Security)
import Security
#endif

#if canImport(CryptoKit)
/// Sign in with Apple nonce (#432): Apple signs `hashed` into the identity token; the server gets `raw`,
/// checks the hash and refuses a nonce it has seen, so a captured identity token can't be replayed.
public struct AppleNonce: Sendable, Equatable {
    /// Sent to the server (`nonce` in the body): 64 lowercase hex characters.
    public let raw: String
    /// Set on `ASAuthorizationAppleIDRequest.nonce`: lowercase hex SHA-256 of `raw`.
    public var hashed: String { Self.sha256Hex(raw) }

    public init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        var filled = false
        #if canImport(Security)
        filled = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess
        #endif
        if !filled {
            var rng = SystemRandomNumberGenerator()
            bytes = bytes.map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        }
        raw = Self.hex(bytes)
    }

    public init(raw: String) { self.raw = raw }

    static func sha256Hex(_ s: String) -> String { hex(Array(SHA256.hash(data: Data(s.utf8)))) }

    private static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
}
#endif
