import LocalAuthentication
import SwiftUI

/// Optional Face ID / passcode lock when returning to the app.
@MainActor @Observable
final class AppLock {
    private static let key = "appLockEnabled"
    private(set) var enabled: Bool
    var locked: Bool
    var error: String?

    init() {
        let on = UserDefaults.standard.bool(forKey: AppLock.key)
        enabled = on
        locked = on
    }

    private func store(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: AppLock.key)
    }

    var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    func didEnterBackground() { if enabled { locked = true } }

    func didBecomeActive() { if locked { Task { await unlock() } } }

    func unlock() async {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // No passcode set on device — lock cannot be enforced.
            locked = false
            return
        }
        do {
            if try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock MonkeyWorkout") {
                locked = false
                error = nil
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Confirms with biometrics before turning the lock on.
    func setEnabled(_ on: Bool) async {
        guard on else { store(false); return }
        let ctx = LAContext()
        if (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Enable app lock")) == true {
            store(true)
        }
    }
}
