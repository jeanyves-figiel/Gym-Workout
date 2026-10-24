import APIClient
import SwiftUI
import WorkoutEngine

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLock.self) private var lock
    @Environment(HealthManager.self) private var health
    @State private var exportURL: URL?
    @State private var exportTask = FormTask()
    @State private var confirmSignOutAll = false
    @AppStorage(AutoNextPref.key) private var autoNextSec = AutoNextPref.fallback
    @AppStorage(CoachPref.onKey) private var coachOn = true
    @AppStorage(ReportPref.shakeKey) private var shakeToReport = true
    @AppStorage(CoachPref.styleKey) private var coachStyle = CoachStyle.hype.rawValue
    @AppStorage(CoachPref.voiceKey) private var coachVoice = CoachVoiceLevel.keyMoments.rawValue
    private var coachSummary: String {
        _ = (coachOn, coachStyle, coachVoice)  // re-render when any of them changes
        return CoachPref.summary
    }
    @State private var signOutAllTask = FormTask()
    @State private var deviceCount: Int?
    /// The device count didn't load (#539): an error card with Retry instead of an empty value.
    @State private var deviceCountError: String?
    @State private var climbSettings = false
    @State private var webPage: WebPage?

    // Settings layout (#394, design B + C): search, sticky chapter bar, one gradient card per chapter.
    @State private var query = ""
    @State private var chapter: SettingsChapter? = .you
    @FocusState private var searchFocused: Bool
    private var search: SettingsSearch { SettingsSearch(query: query) }

    // Row search texts: title first, then the words a member might type.
    private enum Find {
        static let pro = "MonkeyWorkout Pro membership subscription trial lifetime"
        static let profile = "Your profile name nickname photo about avatar community social gym buddies live sharing blocked gender pronouns coach calls you how we talk to you"
        static let gym = "Your gym equipment trip travel"
        static let body = "Body & Health height weight sex figure apple health"
        static let onboarding = "Onboarding set up setup guide tour show me round gym machines map first plan programme start again"
        static let method = "Training method block dup rir volume minimal"
        static let flow = "After last set workout flow next exercise countdown auto"
        static let coach = "Workout coach voice monkey hype chill drill haptics ask coach bubble microphone talk mic hands-free"
        static let reminders = "Reminders alerts notifications quiet hours check-in achievements alarm ring silent focus rest timer"
        static let climbing = "Around sport days climbing wall session before after run snowboard bike rest light"
        static let fuel = "Fuel nutrition food diet meals protein water allergies vegan vegetarian halal recipes no numbers"
        static let watchStart = "Start from iPhone apple watch ask auto"
        static let action = "Action button apple watch ultra"
        static let lift = "Lift sensor beta apple watch reps bar speed velocity"
        static let garmin = "Garmin watch connect iq fenix forerunner venu epix pair code"
        static let bike = "Bike sensors power meter cadence heart rate strap ftp zones cycling watts"
        static let style = "Style look theme monkey coach watch face home"
        static let widgets = "Home Screen widgets"
        static let monkeyGrade = "MonkeyGrade climbing connected apps"
        static let password = "Password sign in"
        static let email = "Email sign in"
        static let security = "Security 2-step two factor passkeys mfa"
        static let devices = "Signed-in devices sessions"
        static let lock = "Lock face id touch id biometric"
        static let export = "Export my data json download"
        static let signOut = "Sign out everywhere session"
        static let delete = "Delete account"
        static let whatsNew = "What's new updates release notes"
        static let privacy = "Privacy policy legal"
        static let terms = "Terms of use legal eula"
        static let support = "Support help contact"
        static let report = "Report a problem bug feedback broken idea shake screenshot"

        static let you = [pro, profile, gym, body, onboarding]
        static let training = [method, flow, coach, reminders, climbing, fuel]
        static let watch = [watchStart, action, lift, garmin, bike]
        static let look = [style, widgets, monkeyGrade]
        static let account = [password, email, security, devices, lock, export, signOut, delete]
        static let help = [whatsNew, report, privacy, terms, support]
        static let all = you + training + watch + look + account + help
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                    if let user = model.user {
                        profileHero(user).padding(.horizontal, 16).padding(.top, 16)
                    }
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            if let user = model.user {
                                groups(user)
                            } else {
                                ProgressView().frame(maxWidth: .infinity).padding(40).task { await model.refreshUser() }
                            }
                            helpGroup
                            if search.active && !search.any(Find.all) {
                                Text("No setting matches “\(query)”.")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                                    .frame(maxWidth: .infinity).padding(.vertical, 30)
                            }
                            Text("MonkeyWorkout · Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                                .font(.caption).foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 6)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    } header: {
                        searchHeader { c in
                            searchFocused = false
                            withAnimation { proxy.scrollTo(c, anchor: .top) }
                        }
                    }
                }
            }
            .coordinateSpace(name: "settings")
            .onPreferenceChange(ChapterTopKey.self) { tops in
                // The chapter whose card reaches under the sticky bar is the current one.
                guard !search.active else { return }
                let passed = SettingsChapter.allCases.filter { (tops[$0] ?? .infinity) < 170 }
                chapter = passed.last ?? .you
            }
        }
        .readableWidth()
        .themedForm()
        .navigationTitle("Settings")
        .task { await loadDeviceCount() }
        .sheet(isPresented: $climbSettings) { AroundSportView() }
        .sheet(item: $webPage) { SafariView(url: $0.url).ignoresSafeArea() }
        .confirmationDialog("Sign out everywhere?", isPresented: $confirmSignOutAll, titleVisibility: .visible) {
            Button("Sign out all devices", role: .destructive) {
                signOutAllTask.run { try await model.signOutEverywhere() }
            }
        } message: {
            Text("Every device, including this one, will need to sign in again.")
        }
    }

    private func loadDeviceCount() async {
        deviceCountError = nil
        #if DEBUG
        if model.demo { return }
        #endif
        do { deviceCount = try await model.api.sessions().count } catch is CancellationError {
            // Left the screen: nothing to report.
        } catch { deviceCountError = error.localizedDescription }
    }

    private func searchHeader(jump: @escaping (SettingsChapter) -> Void) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.subheadline.weight(.bold)).foregroundStyle(Theme.muted)
                TextField("Search settings", text: $query, prompt: Text("Search settings").foregroundStyle(Theme.muted))
                    .font(.body.weight(.semibold))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .accessibilityIdentifier("settings.search")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.09)))
            .padding(.horizontal, 16).padding(.top, 8)
            if !search.active {
                SettingsChapterBar(chapters: SettingsChapter.allCases, current: chapter, jump: jump)
            } else {
                Color.clear.frame(height: 8)
            }
        }
        .background(Theme.bg.opacity(0.96))
    }

    @ViewBuilder
    private func groups(_ user: User) -> some View {
        if search.any(Find.you) {
            SettingsGroup(chapter: .you) {
                if ProStore.shared.visible && search.matches(Find.pro) {
                    NavigationLink { ProView() } label: {
                        let e = ProStore.shared.entitlement
                        SettingsRow(symbol: "crown.fill", title: "MonkeyWorkout Pro",
                                    value: e.pro ? (e.lifetime == true ? "Lifetime" : e.source == .grant ? "Free access" : e.trial == true ? "Free week" : "Active")
                                        : ProStore.shared.testing ? "Test · \(ProStore.shared.testEffect)" : "1 week free") {
                            Text(e.pro ? "PRO" : "TRY").font(Theme.label(11)).tracking(1)
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Theme.lime))
                        }
                    }
                    .buttonStyle(.plain)
                }
                // The header card opens Your profile (#438); this row only shows up for a search.
                if search.active && search.matches(Find.profile) {
                    NavigationLink { ProfileView() } label: {
                        let me = Community.shared.me
                        SettingsRow(symbol: "person.crop.circle.fill", title: "Your profile", value: profileValue(me)) {
                            if let url = model.api.resolve(me.avatarUrl) {
                                AvatarView(url: url, nickname: me.nickname ?? "?", size: 30, ring: .white)
                            } else {
                                AccountChevron()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                // Current gym (#160): home gym, or the trip's while away.
                if search.matches(Find.gym) { YourGymCard(compact: true) }
                if search.matches(Find.body) {
                    NavigationLink { BodyHealthView() } label: {
                        let kg = health.snapshot.weightKg ?? model.body.weightKg
                        SettingsRow(symbol: "heart.text.square.fill", title: "Body & Health",
                                    value: kg.map { Format.kg(($0 * 10).rounded() / 10) + " kg" } ?? (health.connected ? "Health on" : nil))
                    }
                    .buttonStyle(.plain)
                }
                // Onboarding again (#664): every step or one, and the app tour.
                if search.matches(Find.onboarding) {
                    NavigationLink { OnboardingHubView() } label: {
                        let left = model.onboarding?.later.count
                        SettingsRow(symbol: "flag.checkered", title: "Onboarding",
                                    value: left.map { $0 == 0 ? "Done" : "\($0) to do" })
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.onboarding")
                }
            }
        }

        if search.any(Find.training) {
            SettingsGroup(chapter: .training) {
                if let method = model.profile?.trainingMethod, search.matches(Find.method) {
                    // Training method (#156): same editor as Training profile → Training method.
                    NavigationLink { ProfileSectionView(section: .method) } label: {
                        SettingsRow(symbol: method.symbol, title: "Training method", value: method.label)
                    }
                    .buttonStyle(.plain)
                }
                // Workout flow (#357): what happens after an exercise's last set.
                if search.matches(Find.flow) {
                    NavigationLink { WorkoutFlowView() } label: {
                        SettingsRow(symbol: "forward.fill", title: "After last set", value: AutoNextPref.short(autoNextSec))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.flow")
                }
                // Workout coach (#379): Coach Monkey's voice and big moments in the player.
                if search.matches(Find.coach) {
                    NavigationLink { CoachSettingsView() } label: {
                        SettingsRow(symbol: "megaphone.fill", title: "Coach & Ask Coach", value: coachSummary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.coach")
                }
                if search.matches(Find.reminders) {
                    NavigationLink { NotificationSettingsView() } label: {
                        SettingsRow(symbol: "bell.badge.fill", title: "Reminders & alerts")
                    }
                    .buttonStyle(.plain)
                }
                // Fuel (#496): goal, diet, avoid list, meals, day times, No numbers.
                if search.matches(Find.fuel) {
                    NavigationLink { FuelSetupView() } label: {
                        SettingsRow(symbol: "fork.knife", title: "Fuel")
                    }
                    .buttonStyle(.plain)
                }
                // Around sport days (#390, any sport #658): also on the Wall session and Sport prep pages. Members with a sport.
                if let p = model.profile, Generator.isClimber(p) || !p.otherSports.isEmpty, search.matches(Find.climbing) {
                    Button { climbSettings = true } label: {
                        SettingsRow(symbol: "figure.mixed.cardio", title: "Around sport days") { AccountChevron() }
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        // Watches (#347, #349, #383, #550): Apple Watch options on one page, each row opens it at its card; Garmin.
        if search.any(Find.watch) {
            SettingsGroup(chapter: .watch) {
                if search.matches(Find.watchStart) {
                    NavigationLink { WatchOptionsView(focus: .start) } label: {
                        SettingsRow(symbol: "applewatch.radiowaves.left.and.right", title: "Start from iPhone", value: WatchStartPref.shared.mode.short)
                    }
                    .buttonStyle(.plain)
                }
                if search.matches(Find.action) {
                    NavigationLink { WatchOptionsView(focus: .action) } label: {
                        SettingsRow(symbol: "button.horizontal.top.press.fill", title: "Action button", value: WatchActionPref.shared.mode.title)
                    }
                    .buttonStyle(.plain)
                }
                if search.matches(Find.lift) {
                    NavigationLink { WatchOptionsView(focus: .lift) } label: {
                        SettingsRow(symbol: "waveform.path.ecg", title: "Lift sensor β", value: WatchLiftPref.shared.mode.short)
                    }
                    .buttonStyle(.plain)
                }
                // Garmin watches (#550): pair with the code the watch shows.
                if search.matches(Find.garmin) {
                    NavigationLink { GarminView() } label: {
                        SettingsRow(symbol: "watch.analog", title: "Garmin watch",
                                    value: GarminSync.shared.paired ? "Paired" : "Pair")
                    }
                    .buttonStyle(.plain)
                }
                // Bike sensors and FTP (#623).
                if search.matches(Find.bike) {
                    NavigationLink { BikeSensorsView() } label: {
                        SettingsRow(symbol: "bicycle", title: "Bike sensors", value: model.bikeFTP.map { "FTP \($0) W" } ?? "Set up")
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if search.any(Find.look) {
            SettingsGroup(chapter: .look) {
                // App style (#219, #227): one pick for the iPhone game look and the Watch.
                if search.matches(Find.style) {
                    NavigationLink { WatchHomeView() } label: {
                        SettingsRow(symbol: WatchHomePref.shared.style.phoneSymbol, title: "Style", value: WatchHomePref.shared.style.phoneTitle)
                    }
                    .buttonStyle(.plain)
                }
                // Home Screen widgets (#297): presets, look and topic per size.
                if search.matches(Find.widgets) {
                    NavigationLink { HomeWidgetsView() } label: {
                        let w = HomeWidgetSync.shared.settings
                        SettingsRow(symbol: "square.grid.2x2.fill", title: "Home Screen widgets", value: "\(w.preset?.title ?? "Custom") · \(w.look.title)")
                    }
                    .buttonStyle(.plain)
                }
                if search.matches(Find.monkeyGrade) { monkeyGradeRow(user) }
            }
        }

        if search.any(Find.account) {
            SettingsGroup(chapter: .account) {
                if search.matches(Find.password) {
                    NavigationLink { ChangePasswordView(hasPassword: user.hasPassword) } label: {
                        SettingsRow(symbol: "key.fill", title: "Password", value: user.hasPassword ? "Set" : "Add")
                    }
                    .buttonStyle(.plain)
                }
                if search.matches(Find.email) {
                    NavigationLink { ChangeEmailView(currentEmail: user.email) } label: {
                        SettingsRow(symbol: "envelope.fill", title: "Email", value: user.email == nil ? "Add" : "Change")
                    }
                    .buttonStyle(.plain)
                }
                // 2-step sign-in, recovery codes, passkeys (#257).
                if search.matches(Find.security) {
                    NavigationLink { SecurityView() } label: {
                        SettingsRow(symbol: "lock.shield.fill", title: "2-step & passkeys")
                    }
                    .buttonStyle(.plain)
                }
                if search.matches(Find.devices) {
                    NavigationLink { DevicesView() } label: {
                        SettingsRow(symbol: "iphone.gen3", title: "Signed-in devices", value: deviceCount.map { "\($0)" })
                    }
                    .buttonStyle(.plain)
                    if let deviceCountError {
                        InlineErrorCard(title: "Couldn't load your devices", message: deviceCountError) {
                            Task { await loadDeviceCount() }
                        }
                    }
                }
                if search.matches(Find.lock) {
                    SettingsRow(symbol: lock.biometryName == "Touch ID" ? "touchid" : "faceid", title: "Lock with \(lock.biometryName)") {
                        Toggle("Lock with \(lock.biometryName)", isOn: Binding(
                            get: { lock.enabled },
                            set: { on in Task { await lock.setEnabled(on) } }))
                            .labelsHidden()
                            .tint(Theme.lime)
                    }
                }
                if search.matches(Find.export) {
                    Button { export() } label: {
                        SettingsRow(symbol: "square.and.arrow.down.fill", title: "Export my data") {
                            if exportTask.busy { ProgressView().tint(.white) } else { Text("JSON").font(Theme.label(13)) }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(exportTask.busy)
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share export", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(LimeButtonStyle())
                    }
                    ErrorText(message: exportTask.error)
                }
                if search.matches(Find.signOut) {
                    HStack(spacing: 6) {
                        AccountPillButton(title: "Sign out") { Task { await model.signOut() } }
                        AccountPillButton(title: "Sign out everywhere") { confirmSignOutAll = true }
                    }
                    ErrorText(message: signOutAllTask.error)
                }
            }
            if search.matches(Find.delete) {
                NavigationLink { DeleteAccountView() } label: {
                    AccountCard(symbol: "trash.fill", title: "Delete account", subtitle: "Permanent. Export your data first.", gradient: nil, textColor: .red) {
                        AccountChevron()
                    }
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.red.opacity(0.45)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var helpGroup: some View {
        if search.any(Find.help) {
            SettingsGroup(chapter: .help) {
                if (WhatsNew.current != nil || !WhatsNew.history.isEmpty) && search.matches(Find.whatsNew) {
                    // Every update, newest first (#245).
                    NavigationLink { WhatsNewHistoryView(latest: WhatsNew.current, history: WhatsNew.history) } label: {
                        SettingsRow(symbol: "sparkles", title: "What's new",
                                    value: "\(WhatsNew.history.count + (WhatsNew.current == nil ? 0 : 1)) updates")
                    }
                    .buttonStyle(.plain)
                }
                if search.matches(Find.report) {
                    // Report a problem (#467 A); shake to report (B) can be turned off here.
                    NavigationLink { ReportProblemView(draft: ReportDraft(via: .settings, area: "Train")) } label: {
                        SettingsRow(symbol: "ladybug.fill", title: "Report a problem")
                    }
                    .buttonStyle(.plain)
                    SettingsRow(symbol: "iphone.radiowaves.left.and.right", title: "Shake to report") {
                        Toggle("Shake to report", isOn: $shakeToReport).labelsHidden().tint(Theme.lime)
                    }
                }
                if search.matches(Find.privacy) { legalRow(symbol: "hand.raised.fill", title: "Privacy policy", url: AppConfig.privacyURL) }
                if search.matches(Find.terms) { legalRow(symbol: "doc.text.fill", title: "Terms of use", url: AppConfig.termsURL) }
                if search.matches(Find.support) { legalRow(symbol: "questionmark.bubble.fill", title: "Support", url: AppConfig.supportURL) }
            }
        }
    }

    @ViewBuilder
    private func monkeyGradeRow(_ user: User) -> some View {
        let link = MonkeyGradeLink.shared
        let connected = link.isConnected(for: user.id)
        NavigationLink { MonkeyGradeView() } label: {
            SettingsRow(symbol: "figure.climbing", title: "MonkeyGrade",
                        value: connected ? (link.sessions.isEmpty ? "On" : "\(link.sessions.count) sessions") : "Connect")
        }
        .buttonStyle(.plain)
    }

    private func legalRow(symbol: String, title: String, url: URL) -> some View {
        Button { webPage = WebPage(url: url) } label: {
            SettingsRow(symbol: symbol, title: title) {
                Image(systemName: "arrow.up.right").font(.footnote.weight(.heavy)).opacity(0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(title.lowercased())")
    }

    private func profileValue(_ me: PublicProfile) -> String? {
        if me.nickname == nil { return "Set up" }
        return me.member ? "Shown" : "Ready"
    }

    private func profileHero(_ user: User) -> some View {
        // Badges get their own full-width row and the sessions count is a lime pill (#211),
        // so neither squeezes the chips into letter-by-letter wrapping.
        VStack(alignment: .leading, spacing: 12) {
            // Photo, name and @nickname open one profile page for every "about me" field (#438).
            NavigationLink { ProfileView() } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Text(initials(user))
                            .font(Theme.display(24))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 64, height: 64)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lime))
                        // Profile photo (#108), same as in Community.
                        if let url = model.api.resolve(Community.shared.me.avatarUrl) {
                            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                        }
                    }
                    .overlay(Circle().strokeBorder(Theme.lime, lineWidth: 2.5))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(user.name?.isEmpty == false ? user.name! : "Add your name")
                                .font(Theme.display(22))
                                .opacity(user.name?.isEmpty == false ? 1 : 0.6)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Image(systemName: "pencil").font(.footnote.weight(.bold)).opacity(0.7)
                            Spacer(minLength: 0)
                            sessionsPill
                        }
                        Text(Community.shared.me.nickname.map { "@\($0)" } ?? "@ add a nickname")
                            .font(Theme.label(15))
                            .foregroundStyle(Theme.lime.opacity(Community.shared.me.nickname == nil ? 0.6 : 1))
                        Text(user.email ?? "Hidden (Apple)").font(.footnote.weight(.medium)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit your profile")
            let pro = ProStore.shared.entitlement.pro
            if user.appleLinked || (user.emailVerified && user.email != nil) || pro {
                HStack(spacing: 6) {
                    if user.appleLinked { chip("Apple", symbol: "apple.logo") }
                    if user.emailVerified && user.email != nil { chip("Verified", symbol: "checkmark.seal.fill") }
                    if pro { chip("PRO", symbol: "crown.fill", highlighted: true) }
                }
            }
            // What the app learned from the member's choices (#299), moved here from Training profile (#305).
            TasteProfileStrip()
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(AccountTint.profile))
    }

    private var sessionsPill: some View {
        let count = model.history.count
        return Text("\(count) \(count == 1 ? "SESSION" : "SESSIONS")")
            .font(Theme.label(11))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.lime))
    }

    private func chip(_ title: String, symbol: String, highlighted: Bool = false) -> some View {
        Label(title, systemImage: symbol)
            .font(Theme.label(10))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(highlighted ? Theme.ink : .white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(highlighted ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(.white.opacity(0.22))))
    }

    private func initials(_ user: User) -> String {
        let named = user.name?.trimmingCharacters(in: .whitespaces).isEmpty == false
        let words = ((named ? user.name : user.email) ?? "?").split(whereSeparator: { " @.".contains($0) })
        if named && words.count >= 2 { return String(words.prefix(2).compactMap(\.first)).uppercased() }
        return String((words.first ?? "?").prefix(named ? 2 : 1)).uppercased()
    }

    private func export() {
        exportTask.run {
            let data = try await model.api.exportData()
            let url = AppModel.exportFileURL
            // Encrypted while the device is locked; removed again on sign-out / account deletion.
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            exportURL = url
        }
    }
}

struct ChangePasswordView: View {
    let hasPassword: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var new = ""
    @State private var task = FormTask()
    @State private var gate = ReauthGate()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AccountHeader(symbol: "key.fill", title: hasPassword ? "Change password" : "Set a password",
                              subtitle: hasPassword ? "Other devices will be signed out." : "Sign in with your email too. Other devices will be signed out.",
                              gradient: AccountTint.password)
                AccountField(label: "New password") {
                    SecureField("At least 10 characters", text: $new).textContentType(.newPassword)
                }
                PasswordHint(password: new)
                ErrorText(message: task.error)
                AccountNote(text: "We'll ask you to confirm it's you first.")
                LimeActionButton(title: "Save", busy: task.busy,
                                 disabled: new.isEmpty || PasswordRules.problem(new) != nil) {
                    let password = new
                    task.run {
                        // Confirm it's you (#257): passkey, Apple, current password, 2-step or email code.
                        try await gate.run(model.api) { try await model.api.changePassword(new: password) }
                        await model.refreshUser()
                        dismiss()
                    }
                }
                .padding(.top, 6)
            }
            .padding(16)
        }
        .readableWidth()
        .themedForm()
        .navigationTitle(hasPassword ? "Change password" : "Set password")
        .toolbarTitleDisplayMode(.inline)
        .reauthSheet(gate)
    }
}

struct DevicesView: View {
    @Environment(AppModel.self) private var model
    @State private var sessions: [ActiveSession] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                AccountHeader(symbol: "iphone.gen3", title: "Signed-in devices",
                              subtitle: "Every place your account is signed in.", gradient: AccountTint.devices) {
                    if !loading { AccountValue(value: "\(sessions.count)", unit: "active") }
                }
                if loading { ProgressView().frame(maxWidth: .infinity).padding(24) }
                ForEach(sessions, id: \.createdAt) { s in
                    AccountCard(symbol: symbol(for: s.device), title: s.device ?? "Unknown device",
                                subtitle: "Signed in " + String(s.createdAt.prefix(10)), gradient: nil) { EmptyView() }
                }
                ErrorText(message: error)
                AccountNote(text: "To sign out everywhere, use Sign out everywhere in Settings.")
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .readableWidth()
        .themedForm()
        .navigationTitle("Devices")
        .toolbarTitleDisplayMode(.inline)
        .task {
            defer { loading = false }
            do { sessions = try await model.api.sessions() } catch { self.error = error.localizedDescription }
        }
    }

    private func symbol(for device: String?) -> String {
        let d = (device ?? "").lowercased()
        if d.contains("ipad") { return "ipad" }
        if d.contains("mac") { return "laptopcomputer" }
        if d.contains("watch") { return "applewatch" }
        return "iphone"
    }
}

struct DeleteAccountView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmText = ""
    @State private var task = FormTask()
    @State private var gate = ReauthGate()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AccountHeader(symbol: "trash.fill", title: "Delete account",
                              subtitle: "Permanently deletes your account, training profile and all logged weights from the server and this device. It cannot be undone.",
                              gradient: AccountTint.danger)
                AccountNote(text: "Tip: export your data first.")
                if ProStore.shared.entitlement.source == .subscription && ProStore.shared.entitlement.lifetime != true {
                    // App Store 5.1.1(v): deleting the account doesn't stop Apple billing.
                    AccountNote(text: "Deleting your account doesn't cancel your MonkeyWorkout Pro subscription. Cancel it in Settings → Apple ID → Subscriptions.")
                }
                AccountField(label: "Type DELETE to confirm") {
                    TextField("DELETE", text: $confirmText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                ErrorText(message: task.error)
                LimeActionButton(title: "Delete my account", busy: task.busy,
                                 disabled: confirmText != "DELETE", destructive: true) {
                    // Confirm it's you first (#257).
                    task.run { try await gate.run(model.api) { try await model.deleteAccount() } }
                }
                .padding(.top, 6)
            }
            .padding(16)
        }
        .readableWidth()
        .themedForm()
        .navigationTitle("Delete account")
        .toolbarTitleDisplayMode(.inline)
        .reauthSheet(gate)
    }
}

/// Top of each Settings chapter in the scroll view, for the sticky chapter bar (#394).
struct ChapterTopKey: PreferenceKey {
    static let defaultValue: [SettingsChapter: CGFloat] = [:]
    static func reduce(value: inout [SettingsChapter: CGFloat], nextValue: () -> [SettingsChapter: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}
