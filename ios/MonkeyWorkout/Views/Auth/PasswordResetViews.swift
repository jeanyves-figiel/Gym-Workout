import SwiftUI

struct ForgotPasswordView: View {
    @Binding var path: [AuthRoute]
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var task = FormTask()

    var body: some View {
        AuthScreen(title: "Reset password") {
            AccountHeader(symbol: "lock.rotation", title: "Forgot password?",
                          subtitle: "We'll email you a 6-digit code to set a new password.",
                          gradient: AccountTint.password)
            AccountField(label: "Email") {
                TextField("you@example.com", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Email")
            }
            ErrorText(message: task.error)
            LimeActionButton(title: "Send code", busy: task.busy, disabled: !email.contains("@")) {
                let email = email.trimmingCharacters(in: .whitespaces)
                task.run {
                    try await model.api.forgotPassword(email: email)
                    path.append(.reset(email: email))
                }
            }
            .padding(.top, 6)
        }
    }
}

struct ResetPasswordView: View {
    let email: String
    @Binding var path: [AuthRoute]
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @State private var password = ""
    @State private var task = FormTask()
    @State private var done = false

    var body: some View {
        AuthScreen(title: "New password") {
            if done {
                AccountHeader(symbol: "checkmark.seal.fill", title: "Password updated",
                              subtitle: "All devices were signed out. Sign in with your new password.",
                              gradient: AccountTint.export)
                LimeActionButton(title: "Sign in") { path = [.signIn] }
                    .padding(.top, 6)
            } else {
                AccountHeader(symbol: "key.fill", title: "New password",
                              subtitle: "Code sent to \(email).", gradient: AccountTint.password)
                AccountField(label: "6-digit code") {
                    TextField("123456", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .font(Theme.display(28).monospacedDigit())
                        .tracking(6)
                        .accessibilityLabel("6-digit code")
                        .onChange(of: code) { _, new in code = String(new.filter(\.isNumber).prefix(6)) }
                }
                AccountField(label: "New password") {
                    SecureField("At least 10 characters", text: $password)
                        .textContentType(.newPassword)
                        .accessibilityLabel("New password")
                }
                PasswordHint(password: password)
                ErrorText(message: task.error)
                LimeActionButton(title: "Set new password", busy: task.busy,
                                 disabled: code.count != 6 || password.isEmpty || PasswordRules.problem(password) != nil) {
                    task.run {
                        try await model.api.resetPassword(email: email, code: code, newPassword: password)
                        done = true
                    }
                }
                .padding(.top, 6)
            }
        }
    }
}

struct PrivacyNoticeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AccountHeader(symbol: "hand.raised.fill", title: "Privacy notice",
                              subtitle: "Only what the app needs to work.", gradient: AccountTint.export)
                    .padding(.bottom, 4)
                Text("MonkeyWorkout is a personal app. It stores only what it needs to work:")
                Text("• **Account** — email, optional name, password hash (never the password), Sign in with Apple identifier.")
                Text("• **Training** — your training profile and the weights you log, so they sync across devices.")
                Text("• **Body** — height, weight and birth year you enter, for calorie estimates and progress. Gender and sex are optional, inclusive and never required.")
                Text("• **History** — completed sessions (exercises, sets, weights, duration, heart rate) so you can see progress.")
                Text("• **Security** — signed-in devices (device name, dates) so you can sign them out.")
                Text("**Apple Health** data you allow is read and written on this iPhone only and never sent to the server.")
                Text("No tracking, no ads, no third-party analytics. Data is stored on the app's own server and encrypted in transit.")
                Text("You can export everything or permanently delete your account at any time from **Account**.")
            }
            .padding()
        }
        .themedForm()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
