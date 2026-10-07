import APIClient
import SwiftUI

struct SignInView: View {
    @Binding var path: [AuthRoute]
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @State private var task = FormTask()

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .onSubmit(submit)
            } footer: {
                ErrorText(message: task.error)
            }
            Section {
                BusyButton(title: "Sign in", busy: task.busy, disabled: email.isEmpty || password.isEmpty, action: submit)
            }
            Section {
                Button("Forgot password?") { path.append(.forgot) }
                Button("Create an account") { path.append(.signUp) }
            }
        }
        .navigationTitle("Sign in")
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
