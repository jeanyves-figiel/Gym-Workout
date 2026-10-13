import APIClient
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
                        ProfileFormView(initial: nil) { p in
                            model.applyProfile(p)
                            // New accounts start on this release: no "What's new" for them (#183).
                            WhatsNew.markSeen()
                            // Pro (#126): one offer, right after the first plan, skippable. Never shown again at launch.
                            model.offerPro = ProStore.shared.badged
                        }
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
    @State private var whatsNew = WhatsNew.pending

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
        .sidebarAdaptableTabs()
        // Community profile early so auto-share works for the first workout of the session.
        .task(id: model.user?.id) { await Community.shared.load(api: model.api, userId: model.user?.id) }
        .modifier(NotificationsHost())
        .fullScreenCover(isPresented: Binding(get: { model.offerPro }, set: { model.offerPro = $0 })) {
            NavigationStack { ProView(context: .onboarding) { model.offerPro = false } }
        }
        // First open after an update (#183); seen once dismissed, either way.
        .sheet(item: Binding(get: { model.offerPro ? nil : whatsNew }, set: { whatsNew = $0 }), onDismiss: WhatsNew.markSeen) {
            WhatsNewView(notes: $0)
        }
    }
}

private extension View {
    /// iPad and unfolded iPhone Duo: tab bar that can become a sidebar (iOS 18+). iPhone keeps the bottom tab bar.
    @ViewBuilder func sidebarAdaptableTabs() -> some View {
        if #available(iOS 18, *) { tabViewStyle(.sidebarAdaptable) } else { self }
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
        case "workout-style": if let s = model.session(second) { WorkoutStyleSheet(session: s) }
        case "swap":
            if let item = model.plan?.sessions.dropFirst().first?.blocks.first(where: { $0.kind == .strength })?.items.first {
                SwapExerciseSheet(exerciseId: item.exerciseId, uid: item.uid)
            }
        case "player": WorkoutPlayerView(sessionId: second)
        case "player-rest": WorkoutPlayerView(sessionId: second, demoRest: true)
        case "player-timed": WorkoutPlayerView(sessionId: second, demoMode: "timed")
        case "player-logged": WorkoutPlayerView(sessionId: second, demoMode: "logged")
        case "example": NavigationStack { SessionView(sessionId: WorkoutTemplate.all[1].sessionId) }
        case "explore": NavigationStack { LibraryView() }
        case "explore-female": NavigationStack { LibraryView() }.environment(\.bodyFigure, .female)
        case "explore-3d":
            NavigationStack { LibraryView() }.environment(\.bodyMapDemo, BodyMapDemo(mode: .solid, picked: .chest))
        case "explore-3d-back":
            NavigationStack { LibraryView() }.environment(\.bodyMapDemo, BodyMapDemo(mode: .solid, picked: .glutes, facing: .back))
                .environment(\.bodyFigure, .female)
        case "explore-3d-side":
            NavigationStack { LibraryView() }.environment(\.bodyMapDemo, BodyMapDemo(mode: .solid, picked: .quads, facing: .side))
        case "explore-list": NavigationStack { LibraryView(scrollTo: .back) }
        case "explore-volume": NavigationStack { LibraryView(scrollTo: .shoulders) }
        case "explore-workouts": NavigationStack { LibraryView(mode: .workouts) }
        case "monkeygrade": NavigationStack { MonkeyGradeView() }
        case "climb-settings": ClimbSettingsView()
        case "climb": LogClimbView(initial: ClimbLog(start: Date().addingTimeInterval(-90 * 60), effort: 8, topGrade: "6C"))
        case "muscle": NavigationStack { MuscleDetailView(muscle: .lats) }
        case "muscle-female": NavigationStack { MuscleDetailView(muscle: .glutes) }.environment(\.bodyFigure, .female)
        case "exercise": NavigationStack { ExerciseDetailView(exerciseId: "pull-up") }
        case "pr": NavigationStack { ScrollView { PRCard(exerciseId: "bench-press").padding(16) }.readableWidth().background(Theme.bg.ignoresSafeArea()) }
        case "pr-attempt": PRAttemptView(exerciseId: "bench-press")
        case "pr-result": PRAttemptView(exerciseId: "bench-press", showing: Demo.prResult)
        case "technique": FormSheet(exercise: Exercise.get("leg-press"))
        case "progress", "progress-empty": NavigationStack { ProgressTabView() }
        case "progress-flipped": NavigationStack { ProgressTabView(demoFlipped: .volume) }
        case "progress-records": NavigationStack { ProgressTabView(demoSection: .records) }
        case "history": DemoPushedHistory(recordId: model.history.first?.id ?? UUID())
        case "body": NavigationStack { BodyHealthView() }
        case "measurements": NavigationStack { MeasurementsView() }
        case "measurement-log": MeasurementLogSheet(initial: model.measurements.last ?? BodyMeasurement(date: Date()), isNew: false)
        case "measurement-detail": NavigationStack { MeasurementDetailView(metric: .girth(.upperArm)) }
        case "measurement-howto": MeasurementHowToSheet(metric: .girth(.waist))
        case "measurement-guide":
            let last = model.measurements.last
            MeasureGuideView(steps: ([.weight, .bodyFat] + GirthSite.allCases.map { BodyMetric.girth($0) }).map { metric in
                let value: Double? = switch metric {
                case .weight: last?.weightKg
                case .bodyFat: last?.bodyFatPct
                case let .girth(p): last?.girth(p)
                case .leanMass: nil
                }
                return MeasureGuideView.Step(key: metric.id, metric: metric, last: value)
            }, text: .constant(["waist": "78.5"]), index: 5)
        case "account": NavigationStack { AccountView() }
        case "paywall", "pro": NavigationStack { ProView() }
        case "pro-offer": NavigationStack { ProView(context: .onboarding) {} }
        case "pro-gate": ProPaywallSheet(gate: .variation)
        case "account-profile": NavigationStack { PublicProfileView() }
        case "account-password": NavigationStack { ChangePasswordView(hasPassword: true) }
        case "account-email": NavigationStack { ChangeEmailView(currentEmail: Demo.user?.email, hasPassword: true) }
        case "community", "community-join": NavigationStack { CommunityView() }
        case "community-share": ShareWinView()
        case "community-profile": NavigationStack { CommunityProfileView() }
        case "community-members":
            NavigationStack { FindMembersView().navigationDestination(for: CommunityAuthor.self) { MemberView(author: $0) } }
        case "picker": ExercisePickerView(limit: 12, selected: ["back-extension", "ab-wheel", Demo.customExercise.exerciseId]) { _ in }
        case "builder": CustomExerciseBuilderView(existing: Demo.customExercise)
        case "muscle-picker": MusclePickerScreen(primary: [.glutes], secondary: [.hamstrings], heat: [.glutes: 1, .hamstrings: 0.35]) { _ in }
        case "generate":
            MuscleWorkoutGeneratorSheet(profile: model.profile ?? Profile(),
                                        options: MuscleWorkoutOptions(profile: model.profile ?? Profile(), groups: [.chest, .back]),
                                        replacing: false) { _, _ in }
        case "generated":
            let options = MuscleWorkoutOptions(groups: [.chest, .back], minutes: 60, rest: .short, grouping: .supersets)
            CustomWorkoutEditor(initial: CustomWorkout.generate(options, profile: model.profile ?? Profile(), seed: 7), generated: options)
        case "onboarding", "onboarding-climbing":
            NavigationStack {
                ProfileFormView(initial: Demo.screen == "onboarding" ? nil : Demo.climbingProfile) { _ in }
                    .navigationTitle("Your training")
            }
        case "profile": NavigationStack { TrainingProfileView().navigationTitle("Training profile") }
        case "profile-gym": NavigationStack { ProfileSectionView(section: .gym) }
        case "profile-goal", "profile-goal-focus":
            NavigationStack {
                ProfileFormView(initial: Demo.splitProfile(model.profile), section: .goal,
                                scrollTo: Demo.screen == "profile-goal-focus" ? "split" : nil) { _ in }
                    .navigationTitle("Goal")
                    .navigationBarTitleDisplayMode(.inline)
            }
        case "day-focus": DayFocusSheet(weekday: 4, index: 2, current: .legs) { _ in }
        case "profile-method": NavigationStack { ProfileSectionView(section: .method) }
        case "profile-flow": NavigationStack { ProfileSectionView(section: .flow) }
        case "flow-session": if let s = model.plan?.sessions.first { SessionFlowSheet(session: s) }
        case "flow-builder":
            CustomWorkoutEditor(initial: Demo.customWorkouts[0].withFlow([.warmup: 6, .mobility: 6, .cooldown: 5], profile: model.profile ?? Profile()))
        case "flow-picks":
            BlockPicksSheet(kind: .warmup, picks: .constant(BlockPicks(items: [BlockPick(exerciseId: "treadmill-run", minutes: 7),
                                                                                BlockPick(exerciseId: "cat-cow", minutes: 2)])))
        case "equipment": EquipmentSheet(equipment: .constant(GymKind.budget.equipment))
        case "gym-setup": GymSetupView(ref: Demo.holmes, actionTitle: "USE THIS GYM") { _ in }
        case "gym-swipe": GymSetupView(ref: nil, actionTitle: "USE THIS GYM", startStep: .swipe, startKind: .budget) { _ in }
        case "gym-result": GymSetupView(ref: nil, name: "Hotel Adlon", actionTitle: "USE FOR THIS TRIP", startStep: .result, startKind: .hotel) { _ in }
        case "not-here":
            if let item = model.plan?.sessions.dropFirst().first?.blocks.first(where: { $0.kind == .strength })?.items
                .first(where: { Exercise.get($0.exerciseId).equipment.count >= 2 }) {
                NotHereSheet(exerciseId: item.exerciseId, uid: item.uid)
            }
        case "onboarding-figure":
            NavigationStack {
                ProfileFormView(initial: nil, scrollTo: "figure") { _ in }
                    .navigationTitle("Your training")
            }
        case "variation": VariationSheet(days: Set(model.variableSessions.map(\.id)), keep: model.keptSwapUids)
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
        case "move": MoveSessionSheet(sessionId: second)
        case "whats-new": if let n = WhatsNew.current { WhatsNewView(notes: n) }
        case "whats-new-history": NavigationStack { WhatsNewHistoryView(latest: WhatsNew.current, history: WhatsNew.history) }
        case "add-workout": AddWorkoutSheet()
        case "add-workout-quick": AddWorkoutSheet(quick: .fullUpper)
        case "day":
            if let w = model.calendarWeeks(count: 1).first, let wd = w.plan.sessions.first(where: { $0.id == second })?.weekday {
                DaySheet(selection: DaySelection(week: w, weekday: wd, current: true)) { _, _ in } onEdit: { _ in }
            }
        case "away": AwayEditorView(initial: AwayPeriod(kind: .travel, start: Demo.away()[1].start, end: Demo.away()[1].end, note: "Berlin", setup: .hotelGym), isNew: true) { _ in }
        case "notifications": NavigationStack { NotificationSettingsView() }
        case "watch-home": NavigationStack { WatchHomeView() }
        // Game looks (#227): game-{week|session|done|progress}-{coach|deck|rings}; week is the Train tab.
        case let g where g.hasPrefix("game-session"): NavigationStack { SessionView(sessionId: second) }
        case let g where g.hasPrefix("game-done"): WorkoutPlayerView(sessionId: second, demoMode: "done")
        case let g where g.hasPrefix("game-progress"): NavigationStack { ProgressTabView() }
        case "game-quest-deck":
            NavigationStack {
                ScrollView {
                    if let plan = model.plan {
                        QuestMap(sessions: plan.sessions, days: [:]) { _, _ in EmptyView() }.padding(16)
                    }
                }
                .background(Theme.bg.ignoresSafeArea())
                .navigationTitle("Week quest")
            }
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
