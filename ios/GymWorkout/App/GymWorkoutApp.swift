import SwiftUI

@main
struct GymWorkoutApp: App {
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
                    #if DEBUG
                    if Demo.enabled { health.snapshot = Demo.health; return }
                    #endif
                    await health.refresh()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background: lock.didEnterBackground()
                    case .active:
                        lock.didBecomeActive()
                        Task {
                            await model.sync()
                            await health.refresh()
                        }
                    default: break
                    }
                }
        }
    }
}
