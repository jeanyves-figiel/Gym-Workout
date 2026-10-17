import APIClient
import SwiftUI
import WorkoutEngine

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLock.self) private var lock
    @Environment(HealthManager.self) private var health
    @State private var name = ""
    @State private var nameTask = FormTask()
    @FocusState private var nameFocused: Bool
    /// Community @handle, edited here next to the name (#335); same record as Community.
    @State private var handle = ""
    @State private var handleTask = FormTask()
    @FocusState private var handleFocused: Bool
    @State private var exportURL: URL?
    @State private var exportTask = FormTask()
    @State private var confirmSignOutAll = false
    @AppStorage(AutoNextPref.key) private var autoNextSec = AutoNextPref.fallback
    @AppStorage(CoachPref.onKey) private var coachOn = true
    @AppStorage(CoachPref.styleKey) private var coachStyle = CoachStyle.hype.rawValue
    @AppStorage(CoachPref.voiceKey) private var coachVoice = CoachVoiceLevel.keyMoments.rawValue
    private var coachSummary: String {
        _ = (coachOn, coachStyle, coachVoice)  // re-render when any of them changes
        return CoachPref.summary
    }
    @State private var signOutAllTask = FormTask()
    @State private var deviceCount: Int?
    @State private var gate: ProGate?
    @State private var webPage: WebPage?

    // Settings layout (#394, design B + C): search, sticky chapter bar, one gradient card per chapter.
    @State private var query = ""
    @State private var chapter: SettingsChapter? = .you
    @FocusState private var searchFocused: Bool
    private var search: SettingsSearch { SettingsSearch(query: query) }

    // Row search texts: title first, then the words a member might type.
    private enum Find {
        static let pro = "MonkeyWorkout Pro membership subscription trial lifetime"
        static let profile = "Community profile photo about nickname avatar"
        static let gym = "Your gym equipment trip travel"
        static let body = "Body & Health height weight apple health"
        static let method = "Training method block dup rir volume minimal"
        static let flow = "After last set workout flow next exercise countdown auto"
        static let coach = "Workout coach voice monkey hype chill drill haptics"
        static let reminders = "Reminders alerts notifications quiet hours check-in achievements"
        static let watchStart = "Start from iPhone apple watch ask auto"
        static let action = "Action button apple watch ultra"
        static let lift = "Lift sensor beta apple watch reps bar speed velocity"
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

        static let you = [pro, profile, gym, body]
        static let training = [method, flow, coach, reminders]
        static let watch = [watchStart, action, lift]
        static let look = [style, widgets, monkeyGrade]
        static let account = [password, email, security, devices, lock, export, signOut, delete]
        static let help = [whatsNew, privacy, terms, support]
        static let all = you + training + watch + look + account + help
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                    if let user = model.user {
                        profileHero(user).padding(.horizontal, 16).padding(.top, 16)
                        ErrorText(message: nameTask.error ?? handleTask.error).padding(.horizontal, 16)
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
        .onAppear { name = model.user?.name ?? "" }
        .onChange(of: model.user?.name) { _, new in name = new ?? "" }
        .onAppear { handle = Community.shared.me.nickname ?? "" }
        .onChange(of: Community.shared.me.nickname) { _, new in if !handleFocused { handle = new ?? "" } }
        .task { deviceCount = try? await model.api.sessions().count }
        .proPaywall($gate)
        .sheet(item: $webPage) { SafariView(url: $0.url).ignoresSafeArea() }
        .confirmationDialog("Sign out everywhere?", isPresented: $confirmSignOutAll, titleVisibility: .visible) {
            Button("Sign out all devices", role: .destructive) {
                signOutAllTask.run { try await model.signOutEverywhere() }
            }
        } message: {
            Text("Every device, including this one, will need to sign in again.")
        }
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
                // Name and @handle live on the header card (#335); this row is photo and about only.
                if search.matches(Find.profile) {
                    NavigationLink { PublicProfileView() } label: {
                        let me = Community.shared.me
                        SettingsRow(symbol: "person.2.fill", title: "Community profile", value: profileValue(me)) {
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
                        SettingsRow(symbol: "megaphone.fill", title: "Workout coach", value: coachSummary)
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
            }
        }

        // Apple Watch (#347, #349, #383): every option on one page, each row opens it at its card.
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
                        SettingsRow(symbol: "square.grid.2x2.fill", title: "Widgets", value: "\(w.preset?.title ?? "Custom") · \(w.look.title)")
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
        if ProStore.shared.locked && !connected {
            Button { gate = .monkeyGrade } label: {
                SettingsRow(symbol: "figure.climbing", title: "MonkeyGrade") { ProBadge() }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink { MonkeyGradeView() } label: {
                SettingsRow(symbol: "figure.climbing", title: "MonkeyGrade",
                            value: connected ? (link.sessions.isEmpty ? "On" : "\(link.sessions.count) sessions") : "Connect")
            }
            .buttonStyle(.plain)
        }
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
            HStack(spacing: 14) {
                ZStack {
                    Text(initials(user))
                        .font(Theme.display(24))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(Theme.lime))
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
                        TextField("Add your name", text: $name, prompt: Text("Add your name").foregroundStyle(.white.opacity(0.6)))
                            .font(Theme.display(22))
                            .textContentType(.name)
                            .submitLabel(.done)
                            .focused($nameFocused)
                            .onChange(of: nameFocused) { _, focused in if !focused { saveName() } }
                        if nameTask.busy { ProgressView().tint(.white) } else if !nameFocused {
                            Image(systemName: "pencil").font(.footnote.weight(.bold)).opacity(0.7)
                        }
                        sessionsPill
                    }
                    handleRow
                    Text(user.email ?? "Hidden (Apple)").font(.footnote.weight(.medium)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
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

    /// Public @handle under the name (#335): one field, the same nickname shown in Community.
    private var handleRow: some View {
        HStack(spacing: 1) {
            Text("@").font(Theme.label(15))
            TextField("nickname", text: $handle, prompt: Text("add a nickname").foregroundStyle(Theme.lime.opacity(0.6)))
                .font(Theme.label(15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .submitLabel(.done)
                .focused($handleFocused)
                .onChange(of: handleFocused) { _, focused in if !focused { saveHandle() } }
                .fixedSize()
            if handleTask.busy { ProgressView().tint(Theme.lime).scaleEffect(0.7) } else if !handleFocused {
                Image(systemName: "pencil").font(.caption2.weight(.bold)).opacity(0.8).padding(.leading, 4)
            }
        }
        .foregroundStyle(Theme.lime)
        .accessibilityLabel("Nickname")
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

    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard (trimmed.isEmpty ? nil : trimmed) != model.user?.name else { return }
        nameTask.run { model.user = try await model.api.updateName(trimmed.isEmpty ? nil : trimmed) }
    }

    private func saveHandle() {
        let me = Community.shared.me
        let t = handle.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        handle = t
        guard t != (me.nickname ?? "") else { return }
        if t.isEmpty && me.member {
            handleTask.error = "Community members need a nickname."
        } else if !t.isEmpty && t.range(of: "^[A-Za-z0-9_.]{3,20}$", options: .regularExpression) == nil {
            handleTask.error = "Nickname: 3–20 letters, digits, _ or ."
        } else {
            let api = model.api
            handleTask.run {
                #if DEBUG
                if model.demo { return }
                #endif
                do {
                    Community.shared.setPublic(try await api.savePublicProfile(nickname: t, bio: me.bio ?? ""))
                } catch {
                    handle = me.nickname ?? ""
                    throw error
                }
            }
            return
        }
        handle = me.nickname ?? ""
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
