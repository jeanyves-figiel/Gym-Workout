import AuthenticationServices
import SwiftUI
import WorkoutEngine

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
                .environment(\.bodyFigure, model.bodyFigure)
                // Dynamic Type (#540): grows up to the third accessibility size, where the layouts still hold.
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .task {
                    model.health = health
                    FuelStore.shared.health = health
                    FuelStore.shared.planFor = { [model] in model.fuelPlan(on: $0) }
                    // Screens reopened by Undo (#285) live outside this tree: give them the same environment.
                    UndoCloseCenter.shared.environment = { [model, lock, health] view in
                        AnyView(view.environment(model).environment(lock).environment(health)
                            .environment(\.bodyFigure, model.bodyFigure).preferredColorScheme(.dark).tint(Theme.lime)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility3))
                    }
                    await model.bootstrap()
                    FuelStore.shared.applyWidgetGlasses()
                    GarminSync.shared.attach(model)
                    WatchSync.shared.start(model: model, health: health)
                    HomeWidgetSync.shared.start(model: model, health: health)
                    await AppleCredentialCheck.verify(model)
                    await GarminSync.shared.pull()
                }
                .task {
                    // Health reads in parallel with sign-in and sync (cached values already shown, #202).
                    #if DEBUG
                    if Demo.enabled {
                        health.snapshot = Demo.health
                        MoveStore.shared.demo()
                        FuelStore.shared.demo(layout: Demo.screen == "fuel-timeline" ? .timeline : Demo.screen == "fuel-portions" ? .portions : .dashboard)
                        return
                    }
                    #endif
                    await health.refresh()
                    WatchSync.shared.push()
                }
                .task(id: model.bodyFigure) {
                    // 3D body map (#225): build the figure early so Explore shows it at once.
                    var wants3D = UserDefaults.standard.string(forKey: BodyMapMode.storageKey) == BodyMapMode.solid.rawValue
                    #if DEBUG
                    if Demo.enabled { wants3D = Demo.screen.hasPrefix("explore-3d") }
                    #endif
                    guard wants3D else { return }
                    let figure = model.bodyFigure
                    _ = await Task.detached(priority: .utility) { BodyMesh.of(figure) }.value
                }
                .task {
                    // Apple ID stopped using Sign in with Apple for this app while it was running.
                    for await _ in NotificationCenter.default.notifications(named: ASAuthorizationAppleIDProvider.credentialRevokedNotification) {
                        await AppleCredentialCheck.verify(model)
                    }
                }
                // Plan, completion, history or custom workouts changed: refresh the Watch.
                .onChange(of: WatchSync.changeKey(model)) { WatchSync.shared.schedulePush() }
                // Home Screen widget taps (#297).
                .onOpenURL { HomeWidgetRouter.open($0, model: model) }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        model.flushPersist()
                        lock.didEnterBackground()
                        HomeWidgetSync.shared.push()
                    case .inactive:
                        // App switcher snapshot: hide content when the lock is on.
                        lock.didResignActive()
                    case .active:
                        lock.didBecomeActive()
                        // A new programme week (#255), or a new calendar week for the plan (#266).
                        model.syncProgramme()
                        model.rollWeekIfNeeded()
                        // Glasses tapped on the water widget (#520).
                        FuelStore.shared.applyWidgetGlasses()
                        Task {
                            await AppleCredentialCheck.verify(model)
                            await model.sync()
                            await health.refresh()
                            WatchSync.shared.push()
                        }
                    case .inactive:
                        model.flushPersist()
                    default: break
                    }
                }
        }
    }
}
