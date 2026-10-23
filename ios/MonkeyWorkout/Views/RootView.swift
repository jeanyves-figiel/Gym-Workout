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
                // Guided onboarding (#664): stays up after its plan step made the profile, until the tour step.
                if model.profile == nil || model.onboardingOpen {
                    OnboardingFlowView(mode: .newMember, profile: nil)
                } else {
                    #if DEBUG
                    if model.demo { DemoScreen() } else { MainTabView() }
                    #else
                    MainTabView()
                    #endif
                }
            }
            // This build can't keep working (#583, design B): over everything but the lock.
            if Remote.shared.updateNeed == .required {
                RequiredUpdateView()
            }
            if lock.enabled && (lock.locked || lock.covered) {
                LockScreen()
            }
        }
        .animation(.default, value: model.phase)
        .preferredColorScheme(.dark)
        .tint(Theme.lime)
    }
}

/// Settings left the tab bar for the avatar (#496): iOS shows 5 tabs, Fuel took its place.
enum MainTab: Hashable { case train, explore, progress, fuel, community }

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.scenePhase) private var scenePhase
    @State private var whatsNew = WhatsNew.pending
    @State private var ask = CoachAsk.shared
    /// Exercise page opened by Visual Intelligence or Shortcuts (#617).
    @State private var exerciseLaunch = ExerciseLaunch.shared
    @AppStorage(AskCoachPref.bubbleKey) private var coachBubble = true

    /// What's new with the X top right (#556); its own function keeps `body` quick to type-check.
    private func whatsNewSheet(_ notes: WhatsNew) -> some View {
        NavigationStack { WhatsNewView(notes: notes) }
    }

    var body: some View {
        TabView(selection: Bindable(model).tab) {
            NavigationStack { WeekView() }
                .tabItem { Label("Train", systemImage: "bolt.heart.fill") }
                .tag(MainTab.train)
            NavigationStack { LibraryView() }
                .tabItem { Label("Explore", systemImage: "figure.arms.open") }
                .tag(MainTab.explore)
            NavigationStack { ProgressTabView() }
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(MainTab.progress)
            NavigationStack { FuelView() }
                .tabItem { Label("Fuel", systemImage: "fork.knife") }
                .tag(MainTab.fuel)
            NavigationStack { CommunityView() }
                .tabItem { Label("Community", systemImage: "person.3.fill") }
                .tag(MainTab.community)
        }
        // Liquid Glass tab bar on iOS 26 (#616 A).
        .glassTabBar()
        .sidebarAdaptableTabs()
        // Ask Coach everywhere (#412 A): the floating 🐵 and its chat, which knows the screen on top.
        .overlay { if coachBubble { AskCoachBubble() } }
        // App tour (#664): over everything on the tabs, the bubble for the tab showing.
        .overlay { if model.tourStep != nil { AppTourOverlay() } }
        .sheet(item: $ask.request) { r in CoachChatView(ask: r).remotePaused(.askCoach) }
        .sheet(item: $exerciseLaunch.item) { i in NavigationStack { ExerciseDetailView(exerciseId: i.id) } }
        // Me sheet (#560): the Me pill at the top right of every tab.
        .sheet(isPresented: Bindable(model).meOpen) {
            NavigationStack {
                MeSheet().toolbar { CloseToolbarItem { model.meOpen = false } }
            }
        }
        // Settings straight (#496), e.g. from Coach chat.
        .sheet(isPresented: Bindable(model).settingsOpen) {
            NavigationStack {
                AccountView().toolbar { CloseToolbarItem { model.settingsOpen = false } }
            }
        }
        // Community profile early so auto-share works for the first workout of the session.
        .task(id: model.user?.id) {
            await Community.shared.load(api: model.api, userId: model.user?.id)
            await autoShare()
        }
        // Auto-share catch-up (#479): a workout finished on the Watch while the app was closed, a failed post or
        // a sport the Watch tracked (it reaches the iPhone through Health) is posted when the app opens.
        .onChange(of: scenePhase) { _, p in
            guard p == .active else { return }
            Task { await autoShare() }
            // Workouts and sets from a Garmin watch (#550).
            Task { await GarminSync.shared.pull() }
        }
        .onChange(of: health.snapshot.recentSports.count) { Task { await autoShare() } }
        // Style picked here or on the Watch (#681): an edited Train layout follows it too.
        .onChange(of: WatchHomePref.shared.style) { model.restyleTrainLayout() }
        // Coach voice (#402, C): the best matching studio voice, downloaded once in the background.
        .task(id: model.user?.id) { await CoachVoiceStore.shared.prepare(model: model) }
        .task(id: "\(Community.shared.profile?.userId ?? "")-\(model.game.level)") { await Community.shared.reportLevel(model.game.level, api: model.api) }
        .task(id: "\(Community.shared.profile?.userId ?? "")-\(model.communityPronouns ?? "")") {
            await Community.shared.setPronouns(model.communityPronouns, api: model.api)
        }
        .modifier(NotificationsHost())
        // Shake to report and Report on errors (#467) present over any screen.
        .onAppear { ProblemReporter.shared.model = model }
        // Workout run on the Watch (#603): its twin player.
        .fullScreenCover(isPresented: Binding(get: { MirroredWorkout.shared.presented && !model.offerPro },
                                              set: { MirroredWorkout.shared.presented = $0 })) {
            TwinPlayerView()
        }
        .fullScreenCover(isPresented: Binding(get: { model.offerPro }, set: { model.offerPro = $0 })) {
            NavigationStack { ProView(context: .onboarding) { model.offerPro = false } }
        }
        // First open after an update (#183); seen once dismissed, either way.
        .sheet(item: Binding(get: { model.offerPro ? nil : whatsNew }, set: { whatsNew = $0 }), onDismiss: WhatsNew.markSeen) {
            whatsNewSheet($0)
        }
    }
}

private extension View {
    /// iPad and unfolded iPhone Duo: tab bar that can become a sidebar. iPhone keeps the bottom tab bar.
    func sidebarAdaptableTabs() -> some View {
        tabViewStyle(.sidebarAdaptable)
    }
}

private struct LockScreen: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.system(size: 44))
            // Only covered (app switcher): no prompt to unlock.
            if lock.locked {
                Text("MonkeyWorkout is locked").font(.headline)
                if let e = lock.error { Text(e).font(.footnote).foregroundStyle(.secondary) }
                Button("Unlock with \(lock.biometryName)") { Task { await lock.unlock() } }
                    .buttonStyle(.borderedProminent)
            }
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
        case "session", "session-zones": NavigationStack { SessionView(sessionId: second) }
        case "edit-exercises":
            if let s = model.uneditedSession(second) { EditExercisesSheet(sessionId: second, base: s, blocks: Demo.editedBlocks(s)) }
        case "session-edited":
            NavigationStack { SessionView(sessionId: second) }
                .onAppear { if let s = model.uneditedSession(second), !model.isEdited(second) { model.saveSessionEdit(second, blocks: Demo.editedBlocks(s)) } }
        case "workout-style": if let s = model.session(second) { WorkoutStyleSheet(session: s) }
        case "swap":
            if let item = model.plan?.sessions.dropFirst().first?.blocks.first(where: { $0.kind == .strength })?.items.first {
                SwapExerciseSheet(exerciseId: item.exerciseId, uid: item.uid)
            }
        case "swap-zones":
            // A superset member (#274): swap options near its partner first.
            if let item = model.plan?.sessions.dropFirst().first?.blocks.first(where: { $0.kind == .strength })?.items.first(where: { $0.group != nil }) {
                SwapExerciseSheet(exerciseId: item.exerciseId, uid: item.uid)
            }
        case "player", "player-zones": WorkoutPlayerView(sessionId: second)
        case "player-rest": WorkoutPlayerView(sessionId: second, demoRest: true)
        case "player-timed": WorkoutPlayerView(sessionId: second, demoMode: "timed")
        case "player-logged": WorkoutPlayerView(sessionId: second, demoMode: "logged")
        case "player-next": WorkoutPlayerView(sessionId: second, demoMode: "next")
        case "player-coach": WorkoutPlayerView(sessionId: second, demoMode: "coach")
        case "player-record": WorkoutPlayerView(sessionId: second, demoMode: "coach-record")
        case "coach-settings": NavigationStack { CoachSettingsView() }
        case "watch-options": NavigationStack { WatchOptionsView() }
        case "watch-lift": NavigationStack { WatchOptionsView(focus: .lift) }
        case "lift-practice":
            LiftPracticeView(demo: .demo)
        case "workout-flow": NavigationStack { WorkoutFlowView() }
        case "finish-early": WorkoutPlayerView(sessionId: second, demoMode: "finish")
        case "player-fitted": WorkoutPlayerView(sessionId: second, demoMode: "fitted")
        // Machine setups (#355).
        case "player-setup": WorkoutPlayerView(sessionId: second, demoMode: "setup")
        case "machine-setup": MachineNoteSheet(exerciseId: "leg-press", gym: model.homeGym.ref)
        case "exercise-setups": NavigationStack { ExerciseDetailView(exerciseId: "leg-press") }
        // Position guide (#402).
        case "position", "position-mistake", "position-press":
            let e = Exercise.get(Demo.screen == "position-press" ? "bench-press" : "back-squat")
            if let p = e.position {
                NavigationStack { PositionGuideView(exercise: e, position: p, demoMistake: Demo.screen == "position-mistake") }
            }
        case "player-superset": WorkoutPlayerView(sessionId: second, demoMode: "superset")
        case "player-superset-fix": WorkoutPlayerView(sessionId: second, demoMode: "superset-fix")
        case "player-split": WorkoutPlayerView(sessionId: second, demoMode: "superset-split")
        case "player-map": WorkoutPlayerView(sessionId: second, demoMode: "map")
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
        // Explore by machine (#456).
        case "explore-machines": NavigationStack { LibraryView(mode: .machines) }
        case "explore-machine-chips":
            NavigationStack { LibraryView(scrollTo: .arms) }
                .onAppear { UserDefaults.standard.set(MachineFilter.area(.cables).key, forKey: MachineFilterStore.key) }
        // Current gym in Explore (#662): pinned My gym tile and its sheet.
        case "explore-gym-chip":
            NavigationStack { LibraryView(scrollTo: .arms) }
                .onAppear { UserDefaults.standard.set(MachineFilter.gym.key, forKey: MachineFilterStore.key) }
        case "explore-gym": ExploreGymSheet()
        case "machine": NavigationStack { MachineDetailView(item: .cable) }
        // Training programmes (#255); train-programme and programme-test are the Train tab.
        case "explore-programmes": NavigationStack { LibraryView(mode: .programmes) }
        case "explore-routines": NavigationStack { LibraryView(mode: .routines) }
        case "programme", "programme-running": NavigationStack { ProgrammeDetailView(programme: Programme.all[0]) }
        case "programme-length": NavigationStack { ProgrammeDetailView(programme: Programme.all[0], demoLength: true) }
        case "programme-grid", "programme-grid-running":
            NavigationStack { ProgrammeDetailView(programme: Programme.all[0], demoGrid: true) }
        case "programme-mine": NavigationStack { ProgrammeDetailView(programme: Programme.all[0], demoEdit: true) }
        case "programme-builder", "programme-builder-week": ProgrammeBuilderView()
        case "snow-ready": NavigationStack { ProgrammeDetailView(programme: Programme.snowReady(.snowboard)) }
        case "hyrox-ready": NavigationStack { ProgrammeDetailView(programme: Programme.find(Programme.hyroxId)!) }
        case "progress-programmes": NavigationStack { ProgressTabView(demoSection: .programmes) }
        case "profile-programme": NavigationStack { TrainingProfileView().navigationTitle("Training profile") }
        case "calendar-programme": NavigationStack { CalendarView() }
        // Missed sessions (#266); train-missed is the Train tab.
        case "calendar-missed": NavigationStack { CalendarView() }
        case "missed-catchup":
            if let wd = model.missedToHandle.first?.weekday { MissedCatchUpSheet(weekday: wd) }
        case "missed-log":
            if let s = model.missedSessions.first { MissedLogSheet(session: s) }
        case "programme-finished":
            if let r = model.programmeHistory.last { ProgrammeFinishedSheet(record: r) }
        case "monkeygrade": NavigationStack { MonkeyGradeView() }
        case "climb-settings", "around-sport": AroundSportView()
        // Climbing gym (#366): Wall session card, Explore → Climbing, the hangboard session, a hangboard drill.
        case "wall-session":
            NavigationStack {
                WallSessionPage(today: true, climbedToday: false)
                    .navigationDestination(for: String.self) { SessionView(sessionId: $0) }
            }
        case "explore-climbing": NavigationStack { ClimbingCategoryView() }
        case "wall-hangboard": NavigationStack { SessionView(sessionId: WallSession.templates[3].sessionId) }
        case "exercise-climbing": NavigationStack { ExerciseDetailView(exerciseId: "hang-ramp") }
        case "climb": LogClimbView(initial: ClimbLog(start: Date().addingTimeInterval(-90 * 60), effort: 8, topGrade: "6C"))
        case "muscle": NavigationStack { MuscleDetailView(muscle: .lats) }
        case "muscle-female": NavigationStack { MuscleDetailView(muscle: .glutes) }.environment(\.bodyFigure, .female)
        case "exercise": NavigationStack { ExerciseDetailView(exerciseId: "pull-up") }
        case "pr": NavigationStack { ScrollView { PRCard(exerciseId: "bench-press").padding(16) }.readableWidth().background(Theme.bg.ignoresSafeArea()) }
        case "pr-attempt": PRAttemptView(exerciseId: "bench-press")
        case "pr-result": PRAttemptView(exerciseId: "bench-press", showing: Demo.prResult)
        case "technique": FormSheet(exercise: Exercise.get("leg-press"))
        case "progress", "progress-empty": NavigationStack { ProgressTabView() }
        case "progress-flipped": NavigationStack { ProgressTabView(demoFlipped: .volume, demoSection: .training) }
        case "progress-records": NavigationStack { ProgressTabView(demoSection: .records) }
        case "progress-edit": NavigationStack { ProgressTabView(demoEditing: true) }
        case "progress-sports": NavigationStack { ProgressTabView() }
        case "history": DemoPushedHistory(recordId: model.history.first?.id ?? UUID())
        case "history-page": NavigationStack { HistoryView() }
        case "body": NavigationStack { BodyHealthView() }
        case "body-talk": NavigationStack { TalkToYouDemo() }
        case "measurements": NavigationStack { MeasurementsView() }
        case "measurement-log": MeasurementLogSheet(initial: model.measurements.last ?? BodyMeasurement(date: Date()), isNew: false)
        // Close + Undo bar (#285) over Train, as after closing a half-filled measurements sheet.
        case "undo-bar":
            NavigationStack { WeekView() }
                .overlay(alignment: .bottom) {
                    UndoBar(offer: UndoOffer(title: "Measurements closed", detail: "Weight, body fat · 6 girths", symbol: "ruler.fill",
                                             colors: WorkoutEngine.Category.mobility.colors) { AnyView(EmptyView()) },
                            undo: {})
                        .padding(.horizontal, 12).padding(.bottom, 60)
                }
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
        // Report a problem (#467): the page, after a shake (screenshot attached), after Report on an error, and sent.
        case "report": NavigationStack { ReportProblemView(draft: ReportDraft(via: .settings, area: "Workout player")) }
        case "report-shake": NavigationStack {
            ReportProblemView(draft: ReportDraft(via: .shake, area: "Workout player", screen: "Bench press",
                                                 shots: [UIImage(systemName: "photo")!.withTintColor(.gray)]), modal: true)
        }
        case "report-error": NavigationStack {
            ReportProblemView(draft: ReportDraft(via: .error, kind: .broken, area: "Sync & account", screen: "Train",
                                                 error: "Some changes haven't synced yet. We'll keep trying."), modal: true)
        }
        case "report-sent": NavigationStack { ReportProblemView(draft: ReportDraft(via: .settings, area: "Train"), demoSent: true) }
        case "paywall", "pro": NavigationStack { ProView() }
        case "pro-offer": NavigationStack { ProView(context: .onboarding) {} }
        case "pro-gate": ProPaywallSheet(gate: .variation)
        case "account-profile": NavigationStack { ProfileView() }
        case "account-password": NavigationStack { ChangePasswordView(hasPassword: true) }
        case "account-email": NavigationStack { ChangeEmailView(currentEmail: Demo.user?.email) }
        // Account security (#257).
        case "account-security": NavigationStack { SecurityView(preview: Demo.security) }
        case "account-reauth": ChangePasswordView(hasPassword: true).sheet(isPresented: .constant(true)) {
            ReauthSheet(methods: [.passkey, .password, .totp, .emailCode]) { _ in }
        }
        case "account-2step": NavigationStack {
            TwoStepView(enabled: false, codesLeft: 0, setup: TotpSetup(secret: "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP",
                                                                       otpauthUrl: "otpauth://totp/MonkeyWorkout:climber%40example.com?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=MonkeyWorkout"))
        }
        case "account-recovery": NavigationStack { RecoveryCodesView(codes: Demo.recoveryCodes) }
        case "account-passkeys": NavigationStack { PasskeysView(passkeys: Demo.security.passkeys) }
        case "community", "community-join", "community-plans", "community-fuel", "community-mine": NavigationStack { CommunityView() }
        case "community-plan":
            NavigationStack { SharedPlanView(plan: SharedPlans.shared.plans[0]).navigationDestination(for: CommunityAuthor.self) { MemberView(author: $0) } }
        case "community-share-plan": SharePlanSheet()
        case "community-tip": PostTipSheet()
        case "community-share": ShareWinView()
        case "community-profile": NavigationStack { ProfileView() }
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
        case "coach-chat", "coach-chat-empty":
            CoachChatView()
                .onAppear { if Demo.screen == "coach-chat" { Demo.fillCoachChat(profile: model.profile ?? Profile()) } }
        case "ask-coach":
            CoachChatView(ask: AskCoachRequest(focus: CoachFocus(screen: "exercise", title: "Barbell bench press"),
                                               question: "My shoulder clicks on this one"))
        case "ask-coach-bubble":
            NavigationStack { ExerciseDetailView(exerciseId: "bench-press") }.overlay { AskCoachBubble() }
        // Guided onboarding (#664): each step, the app tour, the set-up card and Settings → Onboarding.
        case "onboarding-gym", "onboarding-machines", "onboarding-map", "onboarding-plan", "onboarding-tour":
            OnboardingFlowView(mode: .newMember, profile: nil,
                               startAt: OnboardingStep(rawValue: String(Demo.screen.dropFirst("onboarding-".count))) ?? .gym)
        case "app-tour": MainTabView()
        case "train-setup": NavigationStack { WeekView() }
        case "onboarding-hub": NavigationStack { OnboardingHubView() }
        case "onboarding", "onboarding-climbing":
            NavigationStack {
                ProfileFormView(initial: Demo.screen == "onboarding" ? nil : Demo.climbingProfile) { _ in }
                    .navigationTitle("Your training")
            }
        case "profile": NavigationStack { TrainingProfileView().navigationTitle("Training profile") }
        case "fresh-start": FreshStartSheet()
        case "lift-lab": NavigationStack { LiftLabView(exerciseId: "bench-press") }
        case "lift-focus": NavigationStack { LiftFocusView() }
        case "lift-focus-setup": LiftFocusSheet(exerciseId: "bench-press")
        case "set-style": SetStyleSheet(exercise: Exercise.get("bench-press"))
        case "taste": NavigationStack { TasteView() }
        case "profile-gym", "profile-gym-add": NavigationStack { ProfileSectionView(section: .gym) }
        case "profile-goal", "profile-goal-focus":
            NavigationStack {
                ProfileFormView(initial: Demo.splitProfile(model.profile), section: .goal,
                                scrollTo: Demo.screen == "profile-goal-focus" ? "split" : nil) { _ in }
                    .navigationTitle("Goal")
                    .navigationBarTitleDisplayMode(.inline)
            }
        case "day-focus": DayFocusSheet(weekday: 4, index: 2, current: .legs) { _ in }
        case "focus-sheet": if let s = model.session(second) { NavigationStack { FocusPickView(session: s) } }
        case "swap-day": if let s = model.session(second) { SwapDaySheet(session: s) }
        case "profile-method": NavigationStack { ProfileSectionView(section: .method) }
        case "profile-flow": NavigationStack { ProfileSectionView(section: .flow) }
        case "flow-session": if let s = model.plan?.sessions.first { SessionFlowSheet(session: s) }
        case "flow-builder":
            CustomWorkoutEditor(initial: Demo.customWorkouts[0].withFlow([.warmup: 6, .mobility: 6, .cooldown: 5], profile: model.profile ?? Profile()))
        case "flow-picks":
            BlockPicksSheet(kind: .warmup, picks: .constant(BlockPicks(items: [BlockPick(exerciseId: "treadmill-run", minutes: 7),
                                                                                BlockPick(exerciseId: "cat-cow", minutes: 2)])))
        case "flow-warmup", "flow-cooldown":
            let k: BlockKind = Demo.screen == "flow-warmup" ? .warmup : .cooldown
            let t = k == .warmup ? FlowTweaks(warmupStyle: .pulse)
                : FlowTweaks(cooldownMoves: [BlockPick(exerciseId: "foam-roll-glutes", minutes: 2), BlockPick(exerciseId: "childs-pose-reach", minutes: 2),
                                             BlockPick(exerciseId: "breathing", minutes: 2)])
            FlowTweakSheet(kind: k, tweaks: .constant(t), preview: { tw in
                let ex = Demo.customWorkouts[0].playableItems.compactMap(\.exercise)
                return Generator.flowBlocks((model.profile ?? Profile()).applying(tw), around: ex, minutes: [k: 6], seed: 1).first?.items ?? []
            }) {}
        case "quick-flow":
            NavigationStack { QuickSessionOptionsView(focus: .push, day: "Thursday") { _, _, _ in true } }
        case "equipment": EquipmentSheet(equipment: .constant(GymKind.budget.equipment))
        case "equipment-zones", "equipment-by-zone": EquipmentSheet(equipment: .constant(Gym.puls5.equipment), layout: .constant(Demo.layout))
        case "floor-plan": FloorPlanSheet(layout: .constant(Demo.layout), equipment: Gym.puls5.equipment)
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
        // Growing with the member (#495).
        case "train-smart": NavigationStack { WeekView() }
        case "block-tweak": if let r = model.makeBlockReview() { BlockReviewSheet(review: r) }
        case "auto-tune": AutoTuneSheet()
        case "growth-path": NavigationStack { GrowthPathView() }
        case "coach-memory": NavigationStack { CoachMemoryView() }
        case "cycle": WeekPhaseSheet(week: model.plan?.week ?? 1)
        case "library": NavigationStack { WorkoutLibraryView().navigationDestination(for: String.self) { SessionView(sessionId: $0) } }
        case "library-plan": AddToPlanSheet(workout: model.libraryWorkout(for: WorkoutTemplate.all[0].session) ?? Demo.customWorkouts[0])
        case "calendar": NavigationStack { CalendarView() }
        case "train-edit": NavigationStack { WeekView(demoEditing: true) }
        case "train-day-picked": NavigationStack { WeekView(demoPick: .planned) }
        case "train-rest-day", "train-sport-day": NavigationStack { WeekView(demoPick: .rest) }
        case "train-skipped": NavigationStack { WeekView() }
        case "train-past-day": NavigationStack { WeekView(demoPick: .past) }
        case "train-run", "train-hybrid": NavigationStack { WeekView() }
        case "run-session", "run-start":
            if let day = model.runWeek.first(where: { $0.workout.kind == .intervals }) ?? model.runWeek.first {
                RunSessionSheet(day: day, demoChoosing: Demo.screen == "run-start")
            }
        case "run-goal": RunGoalEditor(initial: model.runGoal)
        case "zone-week": ZoneWeekCard(time: ZoneTime(seconds: [1_380, 6_720, 2_160, 900, 180]), fromApple: true).padding(16)
        case "train-gallery": TrainWidgetGallery()
        case "train-customise": TrainCustomiseSheet()
        case "gyms": GymFinderView(place: "Zürich")
        case "own-gym": OwnGymSheet(name: "Kraftwerk Garage Gym") { _ in }
        case "move": MoveSessionSheet(sessionId: second)
        // Fuel (#496).
        case "fuel", "fuel-timeline", "fuel-portions", "fuel-setup-card": NavigationStack { FuelView() }
        case "fuel-recipes": NavigationStack { RecipeBrowserView().navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }.fuelDestinations() }
        case "recipe": NavigationStack { RecipeDetailView(recipe: RecipeBook.catalog[0]) }
        case "cook-mode": CookModeView(recipe: RecipeBook.catalog[0], servings: RecipeBook.catalog[0].servings)
        case "fuel-pantry": NavigationStack { PantryView().navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }.fuelDestinations() }
        case "meal-plan":
            NavigationStack { MealPlanView().navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }.fuelDestinations() }
                .onAppear { if FuelStore.shared.saved.plan.isEmpty { model.planMeals() } }
        case "groceries":
            NavigationStack { GroceriesView().navigationDestination(for: Recipe.self) { RecipeDetailView(recipe: $0) }.fuelDestinations() }
                .onAppear { if FuelStore.shared.saved.plan.isEmpty { model.planMeals() } }
        case "fuel-week": NavigationStack { FuelWeekView() }
        case "fuel-learn": NavigationStack { FuelLearnView() }
        case "fuel-supplements": NavigationStack { SupplementsView() }
        case "fuel-water": WaterSheet(plan: model.fuelPlan(on: Date()), glasses: FuelStore.shared.log(Date()).glasses, day: Date())
        case "fuel-setup": NavigationStack { FuelSetupView(sheet: true) }
        case "share-recipe": ShareRecipeSheet(recipe: RecipeBook.catalog[0])
        case "whats-new": if let n = WhatsNew.current { WhatsNewView(notes: n) }
        // Over-the-air prompts (#583): remote-banner and remote-required are Train with the banner / update screen.
        case "remote-paused": PausedCard(message: "Food scan is paused while we fix it. Search and barcode still work.")
        case "whats-new-history": NavigationStack { WhatsNewHistoryView(latest: WhatsNew.current, history: WhatsNew.history) }
        case "add-workout": AddWorkoutSheet()
        case "add-workout-quick": AddWorkoutSheet(quick: .upper)
        case "day":
            if let w = model.calendarWeeks(count: 1).first, let wd = w.plan.sessions.first(where: { $0.id == second })?.weekday {
                DaySheet(selection: DaySelection(week: w, weekday: wd, current: true)) { _, _ in } onEdit: { _ in }
            }
        case "your-week-sports":
            NavigationStack {
                ProfileFormView(initial: model.profile, section: .week) { _ in }
                    .navigationTitle("Your week")
                    .navigationBarTitleDisplayMode(.inline)
            }
        case "add-sport": SportPlanEditor(plan: SportPlan(sport: .snowboard, weekdays: [6], seasonMonths: [12, 1, 2, 3]), isNew: true) { _, _ in }
        case "plan-sport": PlanSportSheet(day: model.sportTrips.first?.start ?? PlanCalendar.key(Date(), model.planCalendar), sport: .snowboard)
        case "calendar-trip": NavigationStack { CalendarView() }
        case "day-trip":
            if let w = model.calendarWeeks(count: 3).first(where: { !$0.trips.isEmpty }), let wd = w.trips.keys.min() {
                DaySheet(selection: DaySelection(week: w, weekday: wd, current: false)) { _, _ in } onEdit: { _ in }
            }
        case "away": AwayEditorView(initial: AwayPeriod(kind: .travel, start: Demo.away()[1].start, end: Demo.away()[1].end, note: "Berlin", setup: .hotelGym), isNew: true) { _ in }
        case "notifications": NavigationStack { NotificationSettingsView() }
        case "watch-home": NavigationStack { WatchHomeView() }
        // Home Screen widgets (#297): Account screens and every look × topic × size as the widgets draw them.
        case "home-widgets": NavigationStack { HomeWidgetsView() }
        case "home-widgets-custom": NavigationStack { HomeWidgetsCustomView() }
        case "home-widgets-gradient": HomeWidgetGallery(look: .gradient)
        case "home-widgets-coach": HomeWidgetGallery(look: .coach)
        case "home-widgets-data": HomeWidgetGallery(look: .data)
        // Game looks (#227): game-{week|session|done|progress}-{coach|deck|rings}; week is the Train tab.
        case let g where g.hasPrefix("game-session"): NavigationStack { SessionView(sessionId: second) }
        case let g where g.hasPrefix("game-done"): WorkoutPlayerView(sessionId: second, demoMode: "done")
        case let g where g.hasPrefix("game-progress"): NavigationStack { ProgressTabView() }
        // Level ladder (#242): the sheet, and level-up celebrations (confetti / fireworks / crown rain).
        case "game-ladder": LevelLadderSheet()
        case "game-levelup": LevelUpCelebration(level: 8)
        case "game-levelup-legend": LevelUpCelebration(level: 40)
        case "game-chest": ChestReveal(sessions: 4)
        case "game-level-row":
            NavigationStack {
                ScrollView { GameProgressCard(badges: model.badges).padding(16) }
                    .background(Theme.bg.ignoresSafeArea())
                    .navigationTitle("Progress")
            }
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

#if DEBUG
/// Demo screen for How we talk to you (#415).
private struct TalkToYouDemo: View {
    @State private var gender: BodyMetrics.Gender? = .nonBinary
    @State private var pronouns: Pronouns?
    @State private var custom = ""
    @State private var call: CoachCall? = .name
    @State private var show = true

    var body: some View {
        ScrollView {
            TalkToYouCard(gender: $gender, pronouns: $pronouns, pronounsCustom: $custom, call: $call, showPronouns: $show,
                          name: "Alex", nickname: "alex_lifts", avatar: nil)
                .padding(16)
        }
        .readableWidth()
        .themedForm()
        .navigationTitle("Body & Health")
        .toolbarTitleDisplayMode(.inline)
    }
}
#endif

extension MainTabView {
    fileprivate func autoShare() async {
        await Community.shared.autoShare(model.autoShareWins(healthSports: health.snapshot.recentSports), api: model.api,
                                         userId: model.user?.id)
    }
}
