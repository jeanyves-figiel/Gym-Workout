import APIClient
import AuthenticationServices
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// Account security (#257, designs A + A from `account-security/proposals.png`):
// a "Confirm it's you" sheet before sign-in changes, and the Security page (2-step sign-in, recovery codes, passkeys).

enum SecurityTint {
    static let confirm = LinearGradient(colors: [Color(red: 1, green: 0.24, blue: 0.67), Color(red: 0.47, green: 0.29, blue: 0.63)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let passkey = LinearGradient(colors: [Color(red: 0, green: 0.79, blue: 0.65), Color(red: 0.18, green: 0.5, blue: 0.93)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let twoStep = LinearGradient(colors: [Color(red: 0.97, green: 0.59, blue: 0.12), Color(red: 1, green: 0.82, blue: 0)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let codes = LinearGradient(colors: [Color(red: 0.23, green: 0.42, blue: 1), Color(red: 0.54, green: 0.3, blue: 1)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
    static let apple = LinearGradient(colors: [.black, Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - ASAuthorization (passkeys, Sign in with Apple) with async/await

private enum AuthorizationResult {
    case registration(PasskeyRegistration)
    case assertion(PasskeyAssertion)
    case apple(identityToken: String, authorizationCode: String?, user: String)
    case unsupported
}

@MainActor
final class AuthorizationRunner: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AuthorizationResult, Error>?
    private var controller: ASAuthorizationController?

    private func perform(_ request: ASAuthorizationRequest) async throws -> AuthorizationResult {
        // One request at a time (double tap): a second one would take the first's continuation, which then never
        // resumes, and the first controller's answer would reach the second.
        guard continuation == nil else { throw CancellationError() }
        return try await withCheckedThrowingContinuation { c in
            continuation = c
            let ctl = ASAuthorizationController(authorizationRequests: [request])
            ctl.delegate = self
            ctl.presentationContextProvider = self
            controller = ctl
            ctl.performRequests()
        }
    }

    /// Creates a passkey for this app (Face ID / Touch ID).
    func createPasskey(_ o: PasskeyRegistrationOptions) async throws -> PasskeyRegistration {
        guard let challenge = Base64URL.decode(o.options.challenge), let userID = Base64URL.decode(o.options.user.id) else {
            throw PasskeyError.badOptions
        }
        let request = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: o.options.rp.id)
            .createCredentialRegistrationRequest(challenge: challenge, name: o.options.user.name, userID: userID)
        request.userVerificationPreference = .required
        guard case let .registration(r) = try await perform(request) else { throw PasskeyError.badResponse }
        return r
    }

    /// Uses a passkey: `allowCredentials` empty → any passkey saved for this app (sign-in without email).
    func usePasskey(_ o: PasskeyAssertionOptions) async throws -> PasskeyAssertion {
        guard let challenge = Base64URL.decode(o.options.challenge) else { throw PasskeyError.badOptions }
        let request = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: o.options.rpId)
            .createCredentialAssertionRequest(challenge: challenge)
        request.userVerificationPreference = .required
        request.allowedCredentials = (o.options.allowCredentials ?? []).compactMap { Base64URL.decode($0.id) }
            .map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0) }
        guard case let .assertion(a) = try await perform(request) else { throw PasskeyError.badResponse }
        return a
    }

    /// Fresh Sign in with Apple (Face ID), for "confirm it's you". Returns the identity token and the raw nonce
    /// whose hash Apple signed into it (#432).
    func appleIdentityToken() async throws -> (token: String, nonce: String) {
        let nonce = AppleNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.nonce = nonce.hashed
        guard case let .apple(token, _, _) = try await perform(request) else {
            throw PasskeyError.badResponse
        }
        return (token, nonce.raw)
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let result: AuthorizationResult
        switch authorization.credential {
        case let c as ASAuthorizationPlatformPublicKeyCredentialRegistration:
            result = c.rawAttestationObject.map {
                .registration(PasskeyRegistration(credentialId: c.credentialID, clientDataJSON: c.rawClientDataJSON, attestationObject: $0))
            } ?? .unsupported
        case let c as ASAuthorizationPlatformPublicKeyCredentialAssertion:
            result = .assertion(PasskeyAssertion(credentialId: c.credentialID, clientDataJSON: c.rawClientDataJSON,
                                                 authenticatorData: c.rawAuthenticatorData, signature: c.signature, userHandle: c.userID))
        case let c as ASAuthorizationAppleIDCredential:
            if let t = c.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) {
                result = .apple(identityToken: t, authorizationCode: c.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }, user: c.user)
            } else {
                result = .unsupported
            }
        default:
            result = .unsupported
        }
        MainActor.assumeIsolated { finish(.success(result)) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let cancelled = (error as? ASAuthorizationError)?.code == .canceled
        let message = error.localizedDescription
        MainActor.assumeIsolated { finish(.failure(cancelled ? CancellationError() : PasskeyError.failed(message))) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
                ?? ASPresentationAnchor()
        }
    }

    private func finish(_ r: Result<AuthorizationResult, Error>) {
        continuation?.resume(with: r)
        continuation = nil
        controller = nil
    }
}

enum PasskeyError: LocalizedError {
    case badOptions, badResponse, failed(String)
    var errorDescription: String? {
        switch self {
        case .badOptions, .badResponse: "Passkeys aren't available right now. Try another way."
        case let .failed(m): m
        }
    }
}

// MARK: - Confirm it's you

/// Runs an account change; when the server asks to confirm it's you, shows the sheet and retries once.
/// One confirmation is valid 5 minutes for every change (`APIClient` keeps the grant).
@MainActor @Observable
final class ReauthGate {
    var methods: [ReauthMethod]?
    private var waiter: CheckedContinuation<Bool, Never>?

    func run(_ api: APIClient, _ op: @escaping @MainActor () async throws -> Void) async throws {
        do {
            try await op()
        } catch let e as APIError where e.code == "reauth_required" {
            let m = (try? await api.security().reauthMethods) ?? [.emailCode]
            let ok = await withCheckedContinuation { c in
                // Another change already waiting on the sheet: it is cancelled, this one takes the sheet.
                waiter?.resume(returning: false)
                waiter = c
                methods = m
            }
            guard ok else { throw CancellationError() }
            try await op()
        }
    }

    func finish(_ ok: Bool) {
        methods = nil
        waiter?.resume(returning: ok)
        waiter = nil
    }
}

extension View {
    func reauthSheet(_ gate: ReauthGate) -> some View {
        sheet(isPresented: Binding(get: { gate.methods != nil }, set: { if !$0 { gate.finish(false) } })) {
            ReauthSheet(methods: gate.methods ?? []) { gate.finish($0) }
        }
    }
}

struct ReauthSheet: View {
    let methods: [ReauthMethod]
    let done: (Bool) -> Void
    @Environment(AppModel.self) private var model
    @State private var runner = AuthorizationRunner()
    @State private var entry: ReauthMethod?
    @State private var text = ""
    @State private var codeSent = false
    @State private var task = FormTask()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    AccountHeader(symbol: "checkmark.shield.fill", title: "Confirm it's you",
                                  subtitle: "Needed before changing how you sign in. Valid 5 minutes.", gradient: SecurityTint.confirm)
                    if let entry {
                        entryForm(entry)
                    } else {
                        ForEach(methods, id: \.self) { m in
                            Button { pick(m) } label: { row(m) }
                                .buttonStyle(.plain)
                                .disabled(task.busy)
                        }
                        if methods.isEmpty {
                            AccountNote(text: "No way to confirm on this account. Contact support from Settings → Support.")
                        }
                    }
                    ErrorText(message: task.error)
                }
                .padding(16)
            }
            .readableWidth()
            .themedForm()
            .navigationTitle("Security check")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { done(false) } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ m: ReauthMethod) -> some View {
        switch m {
        case .passkey: AccountCard(symbol: "person.badge.key.fill", title: "Passkey", subtitle: "Face ID or Touch ID", gradient: SecurityTint.passkey)
        case .apple: AccountCard(symbol: "apple.logo", title: "Continue with Apple", subtitle: "Your Apple Account", gradient: SecurityTint.apple)
        case .emailCode: AccountCard(symbol: "envelope.fill", title: "Email me a code", subtitle: model.user?.email,
                                     gradient: SecurityTint.twoStep, ink: true)
        case .password: AccountCard(symbol: "key.fill", title: "Current password", gradient: SecurityTint.codes)
        case .totp: AccountCard(symbol: "number.square.fill", title: "2-step code", subtitle: "From your authenticator app",
                                gradient: AccountTint.notifications)
        }
    }

    @ViewBuilder
    private func entryForm(_ m: ReauthMethod) -> some View {
        switch m {
        case .password:
            AccountField(label: "Current password") {
                SecureField("Password", text: $text).textContentType(.password).onSubmit(confirm)
            }
        default:
            AccountField(label: m == .totp ? "Code from your authenticator" : "Code sent to \(model.user?.email ?? "your email")") {
                TextField("123456", text: $text)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .font(Theme.display(28))
                    .tracking(6)
                    .onChange(of: text) { _, new in text = String(new.filter(\.isNumber).prefix(6)) }
            }
        }
        LimeActionButton(title: "Confirm", busy: task.busy, disabled: m == .password ? text.isEmpty : text.count != 6, action: confirm)
        HStack(spacing: 10) {
            if m == .emailCode {
                AccountPillButton(title: "Resend code") { task.run { try await model.api.sendReauthCode() } }
            }
            AccountPillButton(title: "Another way") {
                entry = nil
                text = ""
                task.error = nil
            }
        }
    }

    private func pick(_ m: ReauthMethod) {
        switch m {
        case .passkey:
            task.run {
                let options = try await model.api.passkeyReauthOptions()
                let assertion = try await runner.usePasskey(options)
                try await model.api.reauth(passkey: assertion, challengeId: options.challengeId)
                done(true)
            }
        case .apple:
            task.run {
                let apple = try await runner.appleIdentityToken()
                try await model.api.reauth(appleIdentityToken: apple.token, nonce: apple.nonce)
                done(true)
            }
        case .emailCode:
            task.run {
                try await model.api.sendReauthCode()
                entry = .emailCode
            }
        case .password, .totp:
            entry = m
        }
    }

    private func confirm() {
        guard let entry else { return }
        let value = text
        task.run {
            if entry == .password { try await model.api.reauth(password: value) } else { try await model.api.reauth(code: value, method: entry) }
            done(true)
        }
    }
}

// MARK: - Security page

struct SecurityView: View {
    @Environment(AppModel.self) private var model
    @State private var overview: SecurityOverview?
    @State private var error: String?

    init(preview: SecurityOverview? = nil) {
        _overview = State(initialValue: preview)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                AccountHeader(symbol: "lock.shield.fill", title: "Security", subtitle: "2-step sign-in and passkeys", gradient: SecurityTint.confirm)
                if let o = overview {
                    NavigationLink { PasskeysView(passkeys: o.passkeys) { overview?.passkeys = $0 } } label: {
                        AccountCard(symbol: "person.badge.key.fill", title: "Passkeys", subtitle: "Sign in with Face ID, no password",
                                    gradient: SecurityTint.passkey) {
                            AccountValue(value: "\(o.passkeys.count)", unit: o.passkeys.count == 1 ? "passkey" : "passkeys")
                        }
                    }
                    .buttonStyle(.plain)
                    NavigationLink { TwoStepView(enabled: o.mfaEnabled, codesLeft: o.recoveryCodesLeft) { Task { await load() } } } label: {
                        AccountCard(symbol: "number.square.fill", title: "2-step sign-in", subtitle: "Authenticator app code after your password",
                                    gradient: SecurityTint.twoStep, ink: true) {
                            Text(o.mfaEnabled ? "ON" : "OFF").font(Theme.label(13)).tracking(1)
                        }
                    }
                    .buttonStyle(.plain)
                    if o.mfaEnabled {
                        NavigationLink { RecoveryCodesView(codes: nil) } label: {
                            AccountCard(symbol: "list.number", title: "Recovery codes", subtitle: "If you lose your phone",
                                        gradient: SecurityTint.codes) {
                                AccountValue(value: "\(o.recoveryCodesLeft)", unit: "left")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    AccountCard(symbol: "apple.logo", title: "Sign in with Apple",
                                subtitle: o.appleLinked ? "Skips 2-step: Apple already checks it's you" : "Not linked", gradient: nil) {
                        Text(o.appleLinked ? "LINKED" : "OFF").font(Theme.label(12)).tracking(1)
                    }
                    NavigationLink { DevicesView() } label: {
                        AccountCard(symbol: "iphone.gen3", title: "Signed-in devices", subtitle: "Where you're signed in", gradient: nil)
                    }
                    .buttonStyle(.plain)
                    AccountNote(text: "Changing your password, email, 2-step or passkeys, or deleting your account, asks you to confirm it's you first. We email you after every change.")
                        .padding(.top, 4)
                } else if error == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(24)
                }
                ErrorText(message: error)
            }
            .padding(16)
        }
        .readableWidth()
        .themedForm()
        .navigationTitle("Security")
        .toolbarTitleDisplayMode(.inline)
        .task { if overview == nil { await load() } }
    }

    private func load() async {
        #if DEBUG
        if Demo.enabled { return }
        #endif
        do { overview = try await model.api.security() } catch { self.error = error.localizedDescription }
    }
}

// MARK: - 2-step

struct TwoStepView: View {
    let enabled: Bool
    let codesLeft: Int
    let changed: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var gate = ReauthGate()
    @State private var setup: TotpSetup?
    @State private var code = ""
    @State private var recovery: [String]?
    @State private var confirmOff = false
    @State private var task = FormTask()
    @State private var closeGuard = CloseGuard()

    /// Setup or new codes on screen, kept for Undo (#285).
    struct Draft: Equatable {
        var setup: TotpSetup?
        var code: String
        var recovery: [String]?
    }

    /// `restoring`: the setup or recovery codes brought back by Undo (#285).
    init(enabled: Bool, codesLeft: Int, setup: TotpSetup? = nil, restoring: Draft? = nil, changed: @escaping () -> Void = {}) {
        self.enabled = enabled
        self.codesLeft = codesLeft
        self.changed = changed
        _setup = State(initialValue: restoring?.setup ?? setup)
        _code = State(initialValue: restoring?.code ?? "")
        _recovery = State(initialValue: restoring?.recovery)
    }

    /// Undo bar while recovery codes (never shown again) or a setup key are on screen (#285).
    private var undoOffer: UndoOffer? {
        guard recovery != nil || (!enabled && setup != nil) else { return nil }
        let kept = Draft(setup: setup, code: code, recovery: recovery)
        let on = self.enabled, left = self.codesLeft, done = self.changed
        return UndoOffer(title: "2-step sign-in closed",
                         detail: kept.recovery != nil ? "Recovery codes not shown again" : "Setup not finished",
                         symbol: kept.recovery != nil ? "list.number" : "number.square.fill",
                         colors: [Color(red: 0.97, green: 0.59, blue: 0.12), Color(red: 1, green: 0.82, blue: 0)]) {
            AnyView(UndoReopenedPush { TwoStepView(enabled: on, codesLeft: left, restoring: kept, changed: done) })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let recovery {
                    RecoveryCodesList(codes: recovery)
                    LimeActionButton(title: "I saved them") {
                        closeGuard.done()
                        changed()
                        dismiss()
                    }
                } else if enabled {
                    AccountHeader(symbol: "checkmark.shield.fill", title: "2-step is on",
                                  subtitle: "After your password we ask for the code from your authenticator app. Apple and passkeys skip it.",
                                  gradient: SecurityTint.twoStep)
                    AccountCard(symbol: "list.number", title: "Recovery codes", subtitle: "One-time codes if you lose your phone",
                                gradient: SecurityTint.codes) {
                        AccountValue(value: "\(codesLeft)", unit: "left")
                    }
                    ErrorText(message: task.error)
                    LimeActionButton(title: "New recovery codes", symbol: "arrow.clockwise", busy: task.busy) {
                        task.run { try await gate.run(model.api) { recovery = try await model.api.newRecoveryCodes() } }
                    }
                    AccountPillButton(title: "Turn off 2-step", role: .destructive) { confirmOff = true }
                } else if let setup {
                    setupSteps(setup)
                } else {
                    AccountHeader(symbol: "number.square.fill", title: "2-step sign-in",
                                  subtitle: "Protect your password with a 6-digit code from an authenticator app (Passwords, Google Authenticator, 1Password…).",
                                  gradient: SecurityTint.twoStep)
                    AccountNote(text: "Optional. Asked only when you sign in with email and password. Sign in with Apple and passkeys skip it.")
                    ErrorText(message: task.error)
                    LimeActionButton(title: "Turn on 2-step", busy: task.busy) {
                        task.run { try await gate.run(model.api) { setup = try await model.api.startTwoStepSetup() } }
                    }
                }
            }
            .padding(16)
        }
        .readableWidth()
        .themedForm()
        .navigationTitle("2-step sign-in")
        .toolbarTitleDisplayMode(.inline)
        .reauthSheet(gate)
        .confirmationDialog("Turn off 2-step?", isPresented: $confirmOff, titleVisibility: .visible) {
            Button("Turn off", role: .destructive) {
                task.run {
                    try await gate.run(model.api) { try await model.api.disableTwoStep() }
                    closeGuard.done()
                    changed()
                    dismiss()
                }
            }
        } message: {
            Text("Your recovery codes stop working too.")
        }
        .undoableClose(closeGuard, offer: undoOffer)
    }

    @ViewBuilder
    private func setupSteps(_ s: TotpSetup) -> some View {
        Text("1  ADD TO YOUR AUTHENTICATOR").eyebrow().padding(.leading, 4)
        HStack(alignment: .top, spacing: 14) {
            if let qr = Self.qr(s.otpauthUrl) {
                Image(uiImage: qr).interpolation(.none).resizable().frame(width: 120, height: 120)
                    .padding(8).background(RoundedRectangle(cornerRadius: 14).fill(.white))
                    .accessibilityLabel("QR code for your authenticator app")
            }
            VStack(alignment: .leading, spacing: 8) {
                if let url = URL(string: s.otpauthUrl) {
                    Link(destination: url) {
                        Label("Open in authenticator", systemImage: "arrow.up.forward.app.fill")
                            .font(Theme.label(13)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(Capsule().fill(Theme.lime))
                    }
                }
                Text("Or scan the code, or type this key:").font(.footnote).foregroundStyle(Theme.muted)
                Text(s.secret.chunked(4)).font(.footnote.monospaced().weight(.semibold)).textSelection(.enabled)
            }
        }
        .card(padding: 14)
        Text("2  ENTER THE 6-DIGIT CODE").eyebrow().padding(.leading, 4).padding(.top, 6)
        AccountField(label: "Code") {
            TextField("123456", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .font(Theme.display(28))
                .tracking(6)
                .onChange(of: code) { _, new in code = String(new.filter(\.isNumber).prefix(6)) }
        }
        ErrorText(message: task.error)
        LimeActionButton(title: "Turn on", busy: task.busy, disabled: code.count != 6) {
            let c = code
            task.run { try await gate.run(model.api) { recovery = try await model.api.enableTwoStep(code: c) } }
        }
    }

    static func qr(_ text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let img = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(img, from: img.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// New codes (gated); shown once.
struct RecoveryCodesView: View {
    @Environment(AppModel.self) private var model
    @State private var codes: [String]?
    @State private var gate = ReauthGate()
    @State private var task = FormTask()
    @State private var closeGuard = CloseGuard()

    init(codes: [String]?) {
        _codes = State(initialValue: codes)
    }

    /// Undo bar whenever new codes are on screen: they can't be shown again (#285). Reopens with the same codes.
    private var undoOffer: UndoOffer? {
        guard let kept = codes else { return nil }
        return UndoOffer(title: "Recovery codes closed", detail: "Recovery codes not shown again", symbol: "list.number",
                         colors: [Color(red: 0.23, green: 0.42, blue: 1), Color(red: 0.54, green: 0.3, blue: 1)]) {
            AnyView(UndoReopenedPush { RecoveryCodesView(codes: kept) })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let codes {
                    RecoveryCodesList(codes: codes)
                } else {
                    AccountHeader(symbol: "list.number", title: "Recovery codes",
                                  subtitle: "Each code signs you in once instead of the 2-step code. We can't show your old codes again.",
                                  gradient: SecurityTint.codes)
                    ErrorText(message: task.error)
                    LimeActionButton(title: "Make new codes", symbol: "arrow.clockwise", busy: task.busy) {
                        task.run { try await gate.run(model.api) { codes = try await model.api.newRecoveryCodes() } }
                    }
                    AccountNote(text: "Old codes stop working.")
                }
            }
            .padding(16)
        }
        .readableWidth()
        .themedForm()
        .navigationTitle("Recovery codes")
        .toolbarTitleDisplayMode(.inline)
        .reauthSheet(gate)
        .undoableClose(closeGuard, offer: undoOffer)
    }
}

struct RecoveryCodesList: View {
    let codes: [String]

    var body: some View {
        AccountHeader(symbol: "list.number", title: "Save your recovery codes",
                      subtitle: "Each one signs you in once if you lose your authenticator. Shown only now.", gradient: SecurityTint.codes)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(codes, id: \.self) { c in
                Text(c).font(.body.monospaced().weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardStrong))
            }
        }
        .textSelection(.enabled)
        HStack(spacing: 10) {
            AccountPillButton(title: "Copy all") { UIPasteboard.general.string = codes.joined(separator: "\n") }
            ShareLink(item: "MonkeyWorkout recovery codes\n" + codes.joined(separator: "\n")) {
                Text("Share").font(Theme.label(14)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Capsule().fill(Theme.cardStrong))
            }
        }
    }
}

// MARK: - Passkeys

struct PasskeysView: View {
    @State private var passkeys: [Passkey]
    private let changed: ([Passkey]) -> Void
    @Environment(AppModel.self) private var model
    @State private var gate = ReauthGate()
    @State private var runner = AuthorizationRunner()
    @State private var task = FormTask()
    @State private var renaming: Passkey?
    @State private var newName = ""
    @State private var removing: Passkey?

    init(passkeys: [Passkey], changed: @escaping ([Passkey]) -> Void = { _ in }) {
        _passkeys = State(initialValue: passkeys)
        self.changed = changed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                AccountHeader(symbol: "person.badge.key.fill", title: "Passkeys",
                              subtitle: "Sign in with Face ID or Touch ID. Saved in your iCloud Keychain, nothing to type or forget.",
                              gradient: SecurityTint.passkey) {
                    AccountValue(value: "\(passkeys.count)", unit: "saved")
                }
                ForEach(passkeys) { p in
                    AccountCard(symbol: "key.horizontal.fill", title: p.name,
                                subtitle: "Added \(p.createdAt.prefix(10))" + (p.lastUsedAt.map { " · used \($0.prefix(10))" } ?? ""), gradient: nil) {
                        Menu {
                            Button("Rename", systemImage: "pencil") {
                                newName = p.name
                                renaming = p
                            }
                            Button("Remove", systemImage: "trash", role: .destructive) { removing = p }
                        } label: {
                            Image(systemName: "ellipsis.circle.fill").font(.title2).foregroundStyle(Theme.lime)
                        }
                        .accessibilityLabel("Options for \(p.name)")
                    }
                }
                ErrorText(message: task.error)
                LimeActionButton(title: "Add a passkey", symbol: "plus", busy: task.busy) { add() }
                    .padding(.top, 4)
                AccountNote(text: "Passkey sign-in skips 2-step: it already needs your device and Face ID.")
            }
            .padding(16)
        }
        .readableWidth()
        .themedForm()
        .navigationTitle("Passkeys")
        .toolbarTitleDisplayMode(.inline)
        .reauthSheet(gate)
        .alert("Rename passkey", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") {
                guard let p = renaming else { return }
                let name = newName.trimmingCharacters(in: .whitespaces)
                renaming = nil
                guard !name.isEmpty else { return }
                task.run { update(try await model.api.renamePasskey(id: p.id, name: name)) }
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Remove \(removing?.name ?? "passkey")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                guard let p = removing else { return }
                removing = nil
                task.run { try await gate.run(model.api) { update(try await model.api.deletePasskey(id: p.id)) } }
            }
        } message: {
            Text("Also delete it from Settings → Passwords so it stops showing up.")
        }
    }

    private func add() {
        task.run {
            try await gate.run(model.api) {
                let options = try await model.api.passkeyRegistrationOptions()
                let reg = try await runner.createPasskey(options)
                update(try await model.api.addPasskey(reg, challengeId: options.challengeId, name: UIDevice.current.model))
            }
        }
    }

    private func update(_ list: [Passkey]) {
        passkeys = list
        changed(list)
    }
}

// MARK: - Sign-in additions

/// "Sign in with passkey" on the sign-in screens: any passkey saved for this app, no email needed.
struct PasskeySignInButton: View {
    @Environment(AppModel.self) private var model
    @State private var runner = AuthorizationRunner()
    @State private var task = FormTask()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                task.run {
                    let options = try await model.api.passkeySignInOptions()
                    let assertion = try await runner.usePasskey(options)
                    await model.didAuthenticate(try await model.api.signInWithPasskey(assertion, challengeId: options.challengeId))
                }
            } label: {
                AccountCard(symbol: "person.badge.key.fill", title: "Sign in with passkey", subtitle: "Face ID, no password",
                            gradient: SecurityTint.passkey) {
                    if task.busy { ProgressView().tint(.white) } else { AccountChevron() }
                }
            }
            .buttonStyle(.plain)
            .disabled(task.busy)
            ErrorText(message: task.error)
        }
    }
}

/// After a correct password when 2-step is on.
struct TwoStepSignInView: View {
    let token: String
    /// Set when the code finishes a Sign in with Apple: remembered for the account like a direct Apple sign-in.
    let appleUserID: String?
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @State private var useRecovery = false
    @State private var task = FormTask()

    init(token: String, appleUserID: String? = nil) {
        self.token = token
        self.appleUserID = appleUserID
    }

    var body: some View {
        AuthScreen(title: "2-step code") {
            AccountHeader(symbol: "number.square.fill", title: useRecovery ? "Recovery code" : "2-step code",
                          subtitle: useRecovery ? "One of the codes you saved when you turned on 2-step." : "From your authenticator app.",
                          gradient: SecurityTint.twoStep)
            AccountField(label: useRecovery ? "Recovery code" : "6-digit code") {
                if useRecovery {
                    TextField("xxxxx-xxxxx", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.title3.monospaced().weight(.bold))
                } else {
                    TextField("123456", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .font(Theme.display(28))
                        .tracking(6)
                        .onChange(of: code) { _, new in code = String(new.filter(\.isNumber).prefix(6)) }
                }
            }
            ErrorText(message: task.error)
            LimeActionButton(title: "Sign in", busy: task.busy, disabled: useRecovery ? code.count < 10 : code.count != 6) {
                let value = code
                task.run {
                    let user = useRecovery
                        ? try await model.api.completeTwoStep(token: token, recoveryCode: value)
                        : try await model.api.completeTwoStep(token: token, code: value)
                    if let appleUserID { AppleCredentialCheck.remember(appleUserID: appleUserID, accountId: user.id) }
                    await model.didAuthenticate(user)
                }
            }
            AccountPillButton(title: useRecovery ? "Use authenticator code" : "Lost your phone? Use a recovery code") {
                useRecovery.toggle()
                code = ""
                task.error = nil
            }
            Text("OR").eyebrow().frame(maxWidth: .infinity).padding(.top, 10)
            PasskeySignInButton()
            AppleSignInButton()
        }
    }
}

private extension String {
    func chunked(_ n: Int) -> String {
        stride(from: 0, to: count, by: n).map { i -> String in
            let s = index(startIndex, offsetBy: i)
            return String(self[s..<(index(s, offsetBy: n, limitedBy: endIndex) ?? endIndex)])
        }.joined(separator: " ")
    }
}
