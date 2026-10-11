import SwiftUI
import WorkoutEngine

struct SignUpView: View {
    @Binding var path: [AuthRoute]
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var accepted = false
    @State private var task = FormTask()

    private var mismatch: Bool { !confirm.isEmpty && confirm != password }
    private var valid: Bool {
        email.contains("@") && PasswordRules.problem(password) == nil && !password.isEmpty && password == confirm && accepted
    }

    var body: some View {
        AuthScreen(title: "Create account") {
            AccountHeader(symbol: "figure.climbing", title: "Create account",
                          subtitle: "Your plan, sessions and climbs, synced across your devices.",
                          gradient: WorkoutEngine.Category.power.gradient)

            VStack(alignment: .leading, spacing: 14) {
                AccountField(label: "Name (optional)") {
                    TextField("What should we call you?", text: $name)
                        .textContentType(.name)
                        .accessibilityLabel("Name (optional)")
                }
                AccountField(label: "Email") {
                    TextField("you@example.com", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Email")
                }
                AccountField(label: "Password") {
                    SecureField("At least 10 characters", text: $password)
                        .textContentType(.newPassword)
                        .accessibilityLabel("Password")
                }
                AccountField(label: "Confirm password") {
                    SecureField("Same again", text: $confirm)
                        .textContentType(.newPassword)
                        .accessibilityLabel("Confirm password")
                }
                if password.isEmpty {
                    AccountNote(text: "At least 10 characters. A passphrase works well.")
                } else {
                    PasswordHint(password: password)
                }
                if mismatch {
                    Label("Passwords don't match.", systemImage: "xmark.circle.fill")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.red).padding(.leading, 4)
                }
            }

            Button { path.append(.privacy) } label: {
                AccountCard(symbol: "hand.raised.fill", title: "Privacy notice",
                            subtitle: "What's stored and why. No tracking, no ads.", gradient: AccountTint.export)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Read privacy notice")
            .padding(.top, 6)
            Toggle(isOn: $accepted) {
                Text("I accept the privacy notice").font(.body.weight(.semibold))
            }
            .tint(Theme.lime)
            .card(padding: 16)

            ErrorText(message: task.error)
            LimeActionButton(title: "Create account", busy: task.busy, disabled: !valid) {
                let email = email.trimmingCharacters(in: .whitespaces)
                let name = name.trimmingCharacters(in: .whitespaces)
                task.run {
                    try await model.api.register(email: email, password: password, name: name.isEmpty ? nil : name, acceptedTerms: accepted)
                    path.append(.verify(email: email))
                }
            }
            .padding(.top, 6)
        }
    }
}
