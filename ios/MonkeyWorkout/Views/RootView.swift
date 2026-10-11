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
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            NavigationStack { WeekView() }
                .tabItem { Label("Train", systemImage: "bolt.heart.fill") }
            NavigationStack { LibraryView() }
                .tabItem { Label("Explore", systemImage: "figure.arms.open") }
            NavigationStack { ProgressTabView() }
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            NavigationStack { CommunityView() }
                .tabItem { Label("Community", systemImage: "person.3.fill") }
            NavigationStack { AccountView() }
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .toolbarBackground(Theme.bg, for: .tabBar)
        // Community profile early so auto-share works for the first workout of the session.
        .task(id: model.user?.id) { await Community.shared.load(api: model.api, userId: model.user?.id) }
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
        case "player-rest": WorkoutPlayerView(sessionId: second, demoRest: true)
        case "example": NavigationStack { SessionView(sessionId: WorkoutTemplate.all[1].sessionId) }
        case "explore": NavigationStack { LibraryView() }
        case "monkeygrade": NavigationStack { MonkeyGradeView() }
        case "climb-settings": ClimbSettingsView()
        case "climb": LogClimbView(initial: ClimbLog(start: Date().addingTimeInterval(-90 * 60), effort: 8, topGrade: "6C"))
        case "muscle": NavigationStack { MuscleDetailView(muscle: .lats) }
        case "exercise": NavigationStack { ExerciseDetailView(exerciseId: "pull-up") }
        case "pr": NavigationStack { ScrollView { PRCard(exerciseId: "bench-press").padding(16) }.background(Theme.bg.ignoresSafeArea()) }
        case "pr-attempt": PRAttemptView(exerciseId: "bench-press")
        case "pr-result": PRAttemptView(exerciseId: "bench-press", showing: Demo.prResult)
        case "technique": FormSheet(exercise: Exercise.get("leg-press"))
        case "progress", "progress-empty": NavigationStack { ProgressTabView() }
        case "history": DemoPushedHistory(recordId: model.history.first?.id ?? UUID())
        case "body": NavigationStack { BodyHealthView() }
        case "account": NavigationStack { AccountView() }
        case "account-password": NavigationStack { ChangePasswordView(hasPassword: true) }
        case "account-email": NavigationStack { ChangeEmailView(currentEmail: Demo.user?.email, hasPassword: true) }
        case "community", "community-join": NavigationStack { CommunityView() }
        case "community-share": ShareWinView()
        case "community-profile": NavigationStack { CommunityProfileView() }
        case "picker": ExercisePickerView(limit: 12, selected: ["back-extension", "ab-wheel", Demo.customExercise.exerciseId]) { _ in }
        case "builder": CustomExerciseBuilderView(existing: Demo.customExercise)
        case "onboarding", "onboarding-climbing":
            NavigationStack {
                ProfileFormView(initial: Demo.screen == "onboarding" ? nil : Demo.climbingProfile) { _ in }
                    .navigationTitle("Your training")
            }
        case "variety":
            NavigationStack {
                ProfileFormView(initial: nil, scrollTo: "variety") { _ in }
                    .navigationTitle("Your training")
            }
        case "readiness":
            ReadinessSheet(snapshot: Demo.health, readiness: Readiness.assess(Demo.health)?.0 ?? .normal, flags: Readiness.assess(Demo.health)?.1 ?? [])
        case "cycle": WeekPhaseSheet(week: model.plan?.week ?? 1)
        case "library": NavigationStack { WorkoutLibraryView().navigationDestination(for: String.self) { SessionView(sessionId: $0) } }
        case "library-plan": AddToPlanSheet(workout: model.libraryWorkout(for: WorkoutTemplate.all[0].session) ?? Demo.customWorkouts[0])
        case "calendar": NavigationStack { CalendarView() }
        case "gyms": GymFinderView(place: "Zürich")
        case "away": AwayEditorView(initial: AwayPeriod(kind: .travel, start: Demo.away()[1].start, end: Demo.away()[1].end, note: "Berlin", setup: .hotelGym), isNew: true) { _ in }
        case "notifications": NavigationStack { NotificationSettingsView() }
        case "reschedule":
            MissedSessionSheet(sessionId: second, day: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        default: MainTabView()
        }
    }
}

/// History detail pushed from Progress, as in the app (title and back button).
private struct DemoPushedHistory: View {
    @State private var path: [UUID]

    init(recordId: UUID) { _path = State(initialValue: [recordId]) }

    var body: some View {
        NavigationStack(path: $path) { ProgressTabView() }
    }
}
#endif
