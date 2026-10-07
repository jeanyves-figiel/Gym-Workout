import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLock.self) private var lock

    var body: some View {
        ZStack {
            switch model.phase {
            case .launching:
                ProgressView()
            case .signedOut:
                AuthFlowView()
            case .signedIn:
                if model.profile == nil {
                    NavigationStack {
                        ProfileFormView(initial: nil) { model.applyProfile($0) }
                            .navigationTitle("Your training")
                    }
                } else {
                    MainTabView()
                }
            }
            if lock.locked && lock.enabled {
                LockScreen()
            }
        }
        .animation(.default, value: model.phase)
        .preferredColorScheme(.dark)
        .tint(Theme.lime)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { WeekView() }
                .tabItem { Label("Train", systemImage: "bolt.heart.fill") }
            NavigationStack { LibraryView() }
                .tabItem { Label("Explore", systemImage: "figure.arms.open") }
            NavigationStack { AccountView() }
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .toolbarBackground(Theme.bg, for: .tabBar)
    }
}

private struct LockScreen: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.system(size: 44))
            Text("Gym-Workout is locked").font(.headline)
            if let e = lock.error { Text(e).font(.footnote).foregroundStyle(.secondary) }
            Button("Unlock with \(lock.biometryName)") { Task { await lock.unlock() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
