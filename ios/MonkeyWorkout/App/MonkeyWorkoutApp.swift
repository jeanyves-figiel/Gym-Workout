import AuthenticationServices
import SwiftUI

@main
struct MonkeyWorkoutApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.live()
    @State private var lock = AppLock()
    @State private var health = HealthManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(lock)
                .environment(health)
                .task {
                    await model.bootstrap()
                    WatchSync.shared.start(model: model, health: health)
                    await AppleCredentialCheck.verify(model)
                    #if DEBUG
                    if Demo.enabled { health.snapshot = Demo.health; return }
                    #endif
                    await health.refresh()
                }
                .task {
                    // Apple ID stopped using Sign in with Apple for this app while it was running.
                    for await _ in NotificationCenter.default.notifications(named: ASAuthorizationAppleIDProvider.credentialRevokedNotification) {
                        await AppleCredentialCheck.verify(model)
                    }
                }
                // Plan, completion, history or custom workouts changed: refresh the Watch.
                .onChange(of: WatchSync.changeKey(model)) { WatchSync.shared.push() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background: lock.didEnterBackground()
                    case .active:
                        lock.didBecomeActive()
                        Task {
                            await AppleCredentialCheck.verify(model)
                            await model.sync()
                            await health.refresh()
                        }
                    default: break
                    }
                }
        }
    }
}
