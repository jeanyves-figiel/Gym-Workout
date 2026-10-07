import SwiftUI

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
        Form {
            Section("Account") {
                TextField("Name (optional)", text: $name)
                    .textContentType(.name)
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
                SecureField("Confirm password", text: $confirm)
                    .textContentType(.newPassword)
            } header: {
                Text("Password")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("At least 10 characters. A passphrase works well.")
                    if let p = PasswordRules.problem(password) { Text(p).foregroundStyle(.red) }
                    if mismatch { Text("Passwords don't match.").foregroundStyle(.red) }
                }
            }
            Section {
                Toggle(isOn: $accepted) {
                    Text("I accept the privacy notice")
                }
                Button("Read privacy notice") { path.append(.privacy) }
            } footer: {
                ErrorText(message: task.error)
            }
            Section {
                BusyButton(title: "Create account", busy: task.busy, disabled: !valid) {
                    let email = email.trimmingCharacters(in: .whitespaces)
                    let name = name.trimmingCharacters(in: .whitespaces)
                    task.run {
                        try await model.api.register(email: email, password: password, name: name.isEmpty ? nil : name, acceptedTerms: accepted)
                        path.append(.verify(email: email))
                    }
                }
            }
        }
        .navigationTitle("Create account")
    }
}
