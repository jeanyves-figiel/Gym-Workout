import APIClient
import SwiftUI
import WorkoutEngine

struct SignInView: View {
    @Binding var path: [AuthRoute]
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @State private var task = FormTask()

    var body: some View {
        AuthScreen(title: "Sign in") {
            AccountHeader(symbol: "person.crop.circle.fill", title: "Welcome back",
                          subtitle: "Sign in to sync your plan, sessions and climbs.",
                          gradient: WorkoutEngine.Category.strength.gradient)
            AccountField(label: "Email") {
                TextField("you@example.com", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Email")
            }
            AccountField(label: "Password") {
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .onSubmit(submit)
            }
            ErrorText(message: task.error)
            LimeActionButton(title: "Sign in", busy: task.busy, disabled: email.isEmpty || password.isEmpty, action: submit)
                .padding(.top, 6)
            HStack(spacing: 10) {
                AccountPillButton(title: "Forgot password?") { path.append(.forgot) }
                AccountPillButton(title: "Create an account") { path.append(.signUp) }
            }
        }
    }

    private func submit() {
        let email = email.trimmingCharacters(in: .whitespaces)
        task.run {
            do {
                let user = try await model.api.login(email: email, password: password)
                await model.didAuthenticate(user)
            } catch let e as APIError where e.code == "email_not_verified" {
                path.append(.verify(email: email))
            }
        }
    }
}
