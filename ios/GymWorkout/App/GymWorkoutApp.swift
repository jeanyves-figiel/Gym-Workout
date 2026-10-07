import SwiftUI

@main
struct GymWorkoutApp: App {
    @State private var model = AppModel.live()
    @State private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(lock)
                .task { await model.bootstrap() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background: lock.didEnterBackground()
                    case .active:
                        lock.didBecomeActive()
                        Task { await model.sync() }
                    default: break
                    }
                }
        }
    }
}
