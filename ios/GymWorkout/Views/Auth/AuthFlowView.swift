import APIClient
import AuthenticationServices
import SwiftUI

enum AuthRoute: Hashable {
    case signIn, signUp, verify(email: String), forgot, reset(email: String), privacy
}

struct AuthFlowView: View {
    @State private var path: [AuthRoute] = []

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

struct WelcomeView: View {
    @Binding var path: [AuthRoute]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "figure.climbing")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Gym-Workout").font(.largeTitle.bold())
                Text("Strength, power, mobility and cardio — planned for your week and your gym.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AppleSignInButton()
            Button { path.append(.signUp) } label: {
                Text("Create account with email").bold().frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("I already have an account") { path.append(.signIn) }
        }
        .padding(24)
    }
}

/// Sign in with Apple → backend verifies the identity token and creates/links the account.
struct AppleSignInButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
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
                    task.run {
                        let user = try await model.api.signInWithApple(identityToken: token, name: name)
                        await model.didAuthenticate(user)
                    }
                case let .failure(error):
                    if (error as? ASAuthorizationError)?.code != .canceled { task.error = error.localizedDescription }
                }
            }
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(height: 50)
            .disabled(task.busy)
            ErrorText(message: task.error)
        }
    }
}
