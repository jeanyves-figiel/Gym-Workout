import SwiftUI

struct ForgotPasswordView: View {
    @Binding var path: [AuthRoute]
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var task = FormTask()

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                VStack(alignment: .leading) {
                    Text("We'll email you a 6-digit code to set a new password.")
                    ErrorText(message: task.error)
                }
            }
            Section {
                BusyButton(title: "Send code", busy: task.busy, disabled: !email.contains("@")) {
                    let email = email.trimmingCharacters(in: .whitespaces)
                    task.run {
                        try await model.api.forgotPassword(email: email)
                        path.append(.reset(email: email))
                    }
                }
            }
        }
        .themedForm()
        .navigationTitle("Reset password")
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
        Form {
            if done {
                Section {
                    Label("Password updated. All devices were signed out.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Sign in") { path = [.signIn] }
                }
            } else {
                Section {
                    TextField("6-digit code", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .onChange(of: code) { _, new in code = String(new.filter(\.isNumber).prefix(6)) }
                    SecureField("New password", text: $password)
                        .textContentType(.newPassword)
                } header: {
                    Text("Code sent to \(email)")
                } footer: {
                    VStack(alignment: .leading) {
                        if let p = PasswordRules.problem(password) { Text(p).foregroundStyle(.red) }
                        ErrorText(message: task.error)
                    }
                }
                Section {
                    BusyButton(title: "Set new password", busy: task.busy,
                               disabled: code.count != 6 || password.isEmpty || PasswordRules.problem(password) != nil) {
                        task.run {
                            try await model.api.resetPassword(email: email, code: code, newPassword: password)
                            done = true
                        }
                    }
                }
            }
        }
        .themedForm()
        .navigationTitle("New password")
    }
}

struct PrivacyNoticeView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy notice").font(.title2.bold())
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
