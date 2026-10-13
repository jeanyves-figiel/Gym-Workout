import APIClient
import SwiftUI

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLock.self) private var lock
    @Environment(HealthManager.self) private var health
    @State private var name = ""
    @State private var nameTask = FormTask()
    @FocusState private var nameFocused: Bool
    @State private var exportURL: URL?
    @State private var exportTask = FormTask()
    @State private var confirmSignOutAll = false
    @State private var signOutAllTask = FormTask()
    @State private var deviceCount: Int?
    @State private var gate: ProGate?
    @State private var webPage: WebPage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let user = model.user {
                    profileHero(user)
                    ErrorText(message: nameTask.error)

                    if ProStore.shared.visible {
                        section("Membership")
                        NavigationLink { ProView() } label: {
                            let e = ProStore.shared.entitlement
                            AccountCard(symbol: "crown.fill", title: "MonkeyWorkout Pro",
                                        subtitle: e.pro ? (e.lifetime == true ? "Lifetime · all updates included" : e.source == .grant ? "Free access" : e.trial == true ? "Free week running" : "Active")
                                            : ProStore.shared.testing ? "Staging test · \(ProStore.shared.testEffect)" : "1 week free, then from CHF 2 / week",
                                        gradient: AccountTint.pro, ink: true) {
                                Text(e.pro ? "PRO" : "TRY").font(Theme.label(12)).tracking(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Other features add their Account rows here as AccountCard (Community profile, Notifications, Training calendar).
                    section("You")
                    NavigationLink { PublicProfileView() } label: {
                        let me = Community.shared.me
                        AccountCard(symbol: "person.crop.circle.fill", title: me.nickname.map { "@\($0)" } ?? "Profile",
                                    subtitle: profileSubtitle(me), gradient: AccountTint.publicProfile) {
                            if let url = model.api.resolve(me.avatarUrl) {
                                AvatarView(url: url, nickname: me.nickname ?? "?", size: 44, ring: .white)
                            } else {
                                AccountChevron()
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // Current gym (#160): home gym, or the trip's while away.
                    YourGymCard()

                    NavigationLink { BodyHealthView() } label: {
                        AccountCard(symbol: "heart.text.square.fill", title: "Body & Health",
                                    subtitle: health.connected ? "Apple Health connected" : "Height, weight, Apple Health",
                                    gradient: AccountTint.body) {
                            if let kg = health.snapshot.weightKg ?? model.body.weightKg {
                                AccountValue(value: Format.kg((kg * 10).rounded() / 10), unit: "kg")
                            } else {
                                AccountChevron()
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if let method = model.profile?.trainingMethod {
                        // Training method (#156): same editor as Training profile → Training method.
                        NavigationLink { ProfileSectionView(section: .method) } label: {
                            AccountCard(symbol: method.symbol, title: "Training method", subtitle: method.label,
                                        gradient: method.gradient) {
                                AccountChevron()
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    NavigationLink { NotificationSettingsView() } label: {
                        AccountCard(symbol: "bell.badge.fill", title: "Reminders & alerts",
                                    subtitle: "Session reminders, check-ins, cheers",
                                    gradient: AccountTint.notifications)
                    }
                    .buttonStyle(.plain)

                    section("Connected apps")
                    // Watch home style (#219).
                    NavigationLink { WatchHomeView() } label: {
                        AccountCard(symbol: "applewatch", title: "Apple Watch",
                                    subtitle: "Home: \(WatchHomePref.shared.style.title)",
                                    gradient: AccountTint.watch)
                    }
                    .buttonStyle(.plain)
                    let mgConnected = MonkeyGradeLink.shared.isConnected(for: user.id)
                    if ProStore.shared.locked && !mgConnected {
                        Button { gate = .monkeyGrade } label: {
                            AccountCard(symbol: "figure.climbing", title: "MonkeyGrade", subtitle: "Connect your climbing app",
                                        gradient: ClimbKind.lead.gradient) { ProBadge() }
                        }
                        .buttonStyle(.plain)
                    } else {
                    NavigationLink { MonkeyGradeView() } label: {
                        let link = MonkeyGradeLink.shared
                        let connected = link.isConnected(for: user.id)
                        AccountCard(symbol: "figure.climbing", title: "MonkeyGrade",
                                    subtitle: connected ? "Climbing sessions, read-only" : "Connect your climbing app",
                                    gradient: ClimbKind.lead.gradient) {
                            if connected && !link.sessions.isEmpty {
                                AccountValue(value: "\(link.sessions.count)", unit: "sessions")
                            } else {
                                Text(connected ? "ON" : "CONNECT").font(Theme.label(12)).tracking(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    }

                    section("Security")
                    NavigationLink { ChangePasswordView(hasPassword: user.hasPassword) } label: {
                        AccountCard(symbol: "key.fill", title: user.hasPassword ? "Password" : "Set a password",
                                    subtitle: user.hasPassword ? "Change your password" : "Also sign in with email",
                                    gradient: AccountTint.password)
                    }
                    .buttonStyle(.plain)
                    NavigationLink { ChangeEmailView(currentEmail: user.email, hasPassword: user.hasPassword) } label: {
                        AccountCard(symbol: "envelope.fill", title: user.email == nil ? "Add email" : "Email",
                                    subtitle: user.email == nil ? "Sign in without Apple" : "Change sign-in email",
                                    gradient: AccountTint.email)
                    }
                    .buttonStyle(.plain)
                    NavigationLink { DevicesView() } label: {
                        AccountCard(symbol: "iphone.gen3", title: "Signed-in devices", subtitle: "Where you're signed in",
                                    gradient: AccountTint.devices) {
                            if let deviceCount { AccountValue(value: "\(deviceCount)", unit: "active") } else { AccountChevron() }
                        }
                    }
                    .buttonStyle(.plain)
                    AccountCard(symbol: lock.biometryName == "Touch ID" ? "touchid" : "faceid",
                                title: "Lock with \(lock.biometryName)", subtitle: "Ask when the app opens", gradient: nil) {
                        Toggle("Lock with \(lock.biometryName)", isOn: Binding(
                            get: { lock.enabled },
                            set: { on in Task { await lock.setEnabled(on) } }))
                            .labelsHidden()
                            .tint(Theme.lime)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40).task { await model.refreshUser() }
                }

                section("Your data")
                Button { export() } label: {
                    AccountCard(symbol: "square.and.arrow.down.fill", title: "Export my data",
                                subtitle: "Account, training profile and all logged weights", gradient: AccountTint.export, ink: true) {
                        if exportTask.busy { ProgressView().tint(Theme.ink) } else { Text("JSON").font(Theme.display(18)) }
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

                section("Legal & support")
                if let notes = WhatsNew.current {
                    NavigationLink { WhatsNewView(notes: notes) } label: {
                        AccountCard(symbol: "sparkles", title: "What's new", subtitle: "Latest improvements in this version",
                                    gradient: AccountTint.whatsNew)
                    }
                    .buttonStyle(.plain)
                }
                legalCard(symbol: "hand.raised.fill", title: "Privacy policy",
                          subtitle: "What's stored, why, your rights", url: AppConfig.privacyURL, gradient: AccountTint.privacy)
                legalCard(symbol: "doc.text.fill", title: "Terms of use",
                          subtitle: "EULA, subscriptions, community rules", url: AppConfig.termsURL, gradient: AccountTint.terms)
                legalCard(symbol: "questionmark.bubble.fill", title: "Support",
                          subtitle: "Contact and common questions", url: AppConfig.supportURL, gradient: AccountTint.support)

                section("Session")
                HStack(spacing: 10) {
                    AccountPillButton(title: "Sign out") { Task { await model.signOut() } }
                    AccountPillButton(title: "Sign out everywhere") { confirmSignOutAll = true }
                }
                ErrorText(message: signOutAllTask.error)

                NavigationLink {
                    DeleteAccountView(hasPassword: model.user?.hasPassword ?? false)
                } label: {
                    AccountCard(symbol: "trash.fill", title: "Delete account", subtitle: "Permanent. Export your data first.", gradient: nil, textColor: .red) {
                        AccountChevron()
                    }
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.red.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

                Text("MonkeyWorkout · Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                    .font(.caption).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .readableWidth()
        .themedForm()
        .navigationTitle("Account")
        .onAppear { name = model.user?.name ?? "" }
        .onChange(of: model.user?.name) { _, new in name = new ?? "" }
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

    private func legalCard(symbol: String, title: String, subtitle: String, url: URL, gradient: LinearGradient) -> some View {
        Button { webPage = WebPage(url: url) } label: {
            AccountCard(symbol: symbol, title: title, subtitle: subtitle, gradient: gradient) {
                Image(systemName: "arrow.up.right").font(.footnote.weight(.heavy)).opacity(0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(title.lowercased())")
    }

    private func section(_ title: String) -> some View {
        Text(title).eyebrow().padding(.leading, 4).padding(.top, 12)
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

    private func profileSubtitle(_ me: PublicProfile) -> String {
        if me.nickname == nil { return "Nickname, photo, about you" }
        if let bio = me.bio, !bio.isEmpty { return bio }
        return me.member ? "Shown in Community" : "Ready for Community"
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

    private func export() {
        exportTask.run {
            let data = try await model.api.exportData()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("gym-workout-export.json")
            try data.write(to: url, options: .atomic)
            exportURL = url
        }
    }
}

struct ChangePasswordView: View {
    let hasPassword: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var task = FormTask()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AccountHeader(symbol: "key.fill", title: hasPassword ? "Change password" : "Set a password",
                              subtitle: hasPassword ? "Other devices will be signed out." : "Sign in with your email too. Other devices will be signed out.",
                              gradient: AccountTint.password)
                if hasPassword {
                    AccountField(label: "Current password") {
                        SecureField("Current password", text: $current).textContentType(.password)
                    }
                }
                AccountField(label: "New password") {
                    SecureField("At least 10 characters", text: $new).textContentType(.newPassword)
                }
                PasswordHint(password: new)
                ErrorText(message: task.error)
                LimeActionButton(title: "Save", busy: task.busy,
                                 disabled: new.isEmpty || PasswordRules.problem(new) != nil || (hasPassword && current.isEmpty)) {
                    task.run {
                        try await model.api.changePassword(current: hasPassword ? current : nil, new: new)
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
                AccountNote(text: "To sign out everywhere, use Sign out everywhere on Account.")
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
    let hasPassword: Bool
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @State private var confirmText = ""
    @State private var task = FormTask()

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
                if hasPassword {
                    AccountField(label: "Password") {
                        SecureField("Password", text: $password).textContentType(.password)
                    }
                }
                AccountField(label: "Type DELETE to confirm") {
                    TextField("DELETE", text: $confirmText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                ErrorText(message: task.error)
                LimeActionButton(title: "Delete my account", busy: task.busy,
                                 disabled: confirmText != "DELETE" || (hasPassword && password.isEmpty), destructive: true) {
                    task.run { try await model.deleteAccount(password: hasPassword ? password : nil) }
                }
                .padding(.top, 6)
            }
            .padding(16)
        }
        .readableWidth()
        .themedForm()
        .navigationTitle("Delete account")
        .toolbarTitleDisplayMode(.inline)
    }
}
