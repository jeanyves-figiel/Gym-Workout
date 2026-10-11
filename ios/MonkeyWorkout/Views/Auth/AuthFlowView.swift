import APIClient
import AuthenticationServices
import SwiftUI
import WorkoutEngine

enum AuthRoute: Hashable {
    case signIn, signUp, verify(email: String), forgot, reset(email: String), privacy
}

struct AuthFlowView: View {
    @State private var path: [AuthRoute] = {
        #if DEBUG
        // CI screenshots (-demoScreen signin|signup|verify) open straight on that step.
        if Demo.enabled {
            switch Demo.screen {
            case "signin": return [.signIn]
            case "signup": return [.signUp]
            case "verify": return [.verify(email: Demo.user?.email ?? "climber@example.com")]
            default: break
            }
        }
        #endif
        return []
    }()

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(path: $path)
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .signIn: SignInView(path: $path)
                    case .signUp: SignUpView(path: $path)
                    case let .verify(email): VerifyEmailView(email: email)
                    case .forgot: ForgotPasswordView(path: $path)
                    case let .reset(email): ResetPasswordView(email: email, path: $path)
                    case .privacy: PrivacyNoticeView()
                    }
                }
        }
    }
}

/// Scaffold for auth steps (#88): Explore-style gradient header, dark rounded fields, lime action —
/// the same parts as Account sub-screens instead of a grey Form.
struct AuthScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .themedForm()
        .navigationTitle(title)
        .toolbarTitleDisplayMode(.inline)
    }
}

struct WelcomeView: View {
    @Binding var path: [AuthRoute]
    @State private var appear = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            RadialGradient(colors: [WorkoutEngine.Category.strength.colors[1].opacity(0.55), .clear], center: .topTrailing, startRadius: 20, endRadius: 420)
                .ignoresSafeArea()
            RadialGradient(colors: [WorkoutEngine.Category.power.colors[0].opacity(0.35), .clear], center: .bottomLeading, startRadius: 20, endRadius: 380)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                Spacer()
                VStack(alignment: .leading, spacing: -8) {
                    ForEach(Array(["LIFT.", "LEAP.", "CLIMB.", "RECOVER."].enumerated()), id: \.offset) { i, word in
                        Text(word)
                            .font(Theme.display(58))
                            .foregroundStyle(i == 2 ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white))
                            .opacity(appear ? 1 : 0)
                            .offset(x: appear ? 0 : -40)
                            .animation(.spring(duration: 0.6).delay(Double(i) * 0.08), value: appear)
                    }
                }
                Text("Sessions built for your week, your gym and your climbing — with every muscle mapped.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.muted)
                Spacer()
                AppleSignInButton()
                Button { path.append(.signUp) } label: { Text("CREATE ACCOUNT") }
                    .buttonStyle(LimeButtonStyle())
                Button("I already have an account") { path.append(.signIn) }
                    .font(Theme.label(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .onAppear { appear = true }
    }
}

/// Sign in with Apple → backend verifies the identity token and creates/links the account.
struct AppleSignInButton: View {
    @Environment(AppModel.self) private var model
    @State private var task = FormTask()

    var body: some View {
        VStack(spacing: 6) {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case let .success(auth):
                    guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                          let tokenData = cred.identityToken,
                          let token = String(data: tokenData, encoding: .utf8)
                    else {
                        task.error = "Apple did not return an identity token."
                        return
                    }
                    let name = cred.fullName.flatMap { PersonNameComponentsFormatter().string(from: $0) }.flatMap { $0.isEmpty ? nil : $0 }
                    // Server exchanges it for an Apple refresh token so account deletion can revoke Sign in with Apple.
                    let code = cred.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
                    let appleUserID = cred.user
                    task.run {
                        let user = try await model.api.signInWithApple(identityToken: token, name: name, authorizationCode: code)
                        AppleCredentialCheck.remember(appleUserID: appleUserID, accountId: user.id)
                        await model.didAuthenticate(user)
                    }
                case let .failure(error):
                    if (error as? ASAuthorizationError)?.code != .canceled { task.error = error.localizedDescription }
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 56)
            .clipShape(Capsule())
            .disabled(task.busy)
            ErrorText(message: task.error)
        }
    }
}
