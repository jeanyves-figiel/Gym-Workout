import SwiftUI
import WorkoutEngine

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
                    #if DEBUG
                    if model.demo { DemoScreen() } else { MainTabView() }
                    #else
                    MainTabView()
                    #endif
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
            NavigationStack { ProgressTabView() }
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            NavigationStack { AccountView() }
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .toolbarBackground(Theme.bg, for: .tabBar)
        .modifier(NotificationsHost())
    }
}

private struct LockScreen: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.system(size: 44))
            Text("MonkeyWorkout is locked").font(.headline)
            if let e = lock.error { Text(e).font(.footnote).foregroundStyle(.secondary) }
            Button("Unlock with \(lock.biometryName)") { Task { await lock.unlock() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

#if DEBUG
/// Jumps straight to one screen for CI screenshots.
private struct DemoScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let second = model.plan?.sessions.dropFirst().first?.id ?? ""
        switch Demo.screen {
        case "session": NavigationStack { SessionView(sessionId: second) }
        case "player": WorkoutPlayerView(sessionId: second)
        case "example": NavigationStack { SessionView(sessionId: WorkoutTemplate.all[1].sessionId) }
        case "explore": NavigationStack { LibraryView() }
        case "monkeygrade": NavigationStack { MonkeyGradeView() }
        case "climb-settings": ClimbSettingsView()
        case "climb": LogClimbView(initial: ClimbLog(start: Date().addingTimeInterval(-90 * 60), effort: 8, topGrade: "6C"))
        case "muscle": NavigationStack { MuscleDetailView(muscle: .lats) }
        case "exercise": NavigationStack { ExerciseDetailView(exerciseId: "pull-up") }
        case "technique": FormSheet(exercise: Exercise.get("leg-press"))
        case "progress": NavigationStack { ProgressTabView() }
        case "history": NavigationStack { HistoryDetailView(recordId: model.history.first?.id ?? UUID()) }
        case "body": NavigationStack { BodyHealthView() }
        case "picker": ExercisePickerView(limit: 12, selected: ["back-extension", "ab-wheel", "breathing"]) { _ in }
        case "onboarding", "onboarding-climbing":
            NavigationStack {
                ProfileFormView(initial: Demo.screen == "onboarding" ? nil : Demo.climbingProfile) { _ in }
                    .navigationTitle("Your training")
            }
        case "readiness":
            ReadinessSheet(snapshot: Demo.health, readiness: Readiness.assess(Demo.health)?.0 ?? .normal, flags: Readiness.assess(Demo.health)?.1 ?? [])
        case "cycle": WeekPhaseSheet(week: 1)
        case "notifications": NavigationStack { NotificationSettingsView() }
        case "reschedule":
            MissedSessionSheet(sessionId: second, day: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        default: MainTabView()
        }
    }
}
#endif
