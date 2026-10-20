import LocalAuthentication
import SwiftUI

/// Optional Face ID / passcode lock when returning to the app.
@MainActor @Observable
final class AppLock {
    private static let key = "appLockEnabled"
    private(set) var enabled: Bool
    var locked: Bool
    /// Inactive (app switcher, Control Center): content hidden so the app switcher snapshot shows nothing.
    private(set) var covered = false
    var error: String?
    /// The Face ID / passcode sheet is up (it makes the app inactive, then active again).
    @ObservationIgnored private var prompting = false
    /// The member cancelled the prompt: wait for the Unlock button instead of asking again on every activation.
    @ObservationIgnored private var cancelled = false

    init() {
        let on = UserDefaults.standard.bool(forKey: AppLock.key)
        enabled = on
        locked = on
    }

    private func store(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: AppLock.key)
    }

    /// Asked once: `canEvaluatePolicy` is a synchronous call to the system and views read this on every render (#351).
    @ObservationIgnored private(set) lazy var biometryName: String = Self.currentBiometryName()

    private static func currentBiometryName() -> String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    func didEnterBackground() {
        if enabled { locked = true }
        // Back from the background later: ask again.
        cancelled = false
    }

    func didResignActive() { if enabled { covered = true } }

    func didBecomeActive() {
        covered = false
        if locked, !prompting, !cancelled { Task { await unlock() } }
    }

    func unlock() async {
        guard !prompting else { return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // No passcode set on device — lock cannot be enforced.
            locked = false
            return
        }
        prompting = true
        defer { prompting = false }
        do {
            if try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock MonkeyWorkout") {
                locked = false
                cancelled = false
                error = nil
            }
        } catch {
            if let code = (error as? LAError)?.code, [LAError.Code.userCancel, .appCancel, .systemCancel].contains(code) { cancelled = true }
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
