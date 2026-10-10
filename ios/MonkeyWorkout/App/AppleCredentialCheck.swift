import AuthenticationServices
import Foundation

/// Sign in with Apple credential state (#12). Apple requires apps to check it on launch: when the user
/// stops using Apple ID with this app (Settings → Apple ID → Sign in with Apple), sign out locally.
enum AppleCredentialCheck {
    /// `[account id: Apple user identifier]` — only accounts that signed in with Apple on this device.
    private static let key = "appleUserIDs"

    static func remember(appleUserID: String, accountId: String) {
        var map = stored
        map[accountId] = appleUserID
        UserDefaults.standard.set(map, forKey: key)
    }

    static func forget(accountId: String) {
        var map = stored
        map[accountId] = nil
        UserDefaults.standard.set(map, forKey: key)
    }

    static func appleUserID(for accountId: String) -> String? { stored[accountId] }

    private static var stored: [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    /// nil when Apple could not answer (offline, simulator) — never treated as revoked.
    static func credentialState(for appleUserID: String) async -> ASAuthorizationAppleIDProvider.CredentialState? {
        await withCheckedContinuation { (cont: CheckedContinuation<ASAuthorizationAppleIDProvider.CredentialState?, Never>) in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: appleUserID) { state, error in
                cont.resume(returning: error == nil ? state : nil)
            }
        }
    }

    @MainActor private static var checking = false

    /// Call on launch and when returning to the foreground. Signs out when the Apple credential
    /// behind the current account is revoked or no longer known to this device.
    @MainActor
    static func verify(_ model: AppModel) async {
        guard !checking, model.phase == .signedIn, !model.demo,
              let accountId = model.user?.id ?? model.state.ownerId,
              let appleUserID = appleUserID(for: accountId)
        else { return }
        checking = true
        defer { checking = false }
        switch await credentialState(for: appleUserID) {
        case .revoked?, .notFound?:
            forget(accountId: accountId)
            await model.sync() // push unsynced logs while the API session is still valid
            await model.signOut()
        default:
            break
        }
    }
}
